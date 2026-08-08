# /// script
# requires-python = ">=3.13"
# dependencies = ["pydantic-monty==0.0.19"]
# ///
"""Monty measured the same way kobako is, so the two can share a chart.

Run with `uv run scripts/monty.py`; the version is pinned above the way the
Gemfile pins kobako, so the competitor's build is part of the record.

WHAT IS MEASURED
    The same two shapes scripts/untrusted_run.rb and scripts/cold_start.rb
    measure for kobako, mapped onto Monty's own API:

      per run   pool.checkout() + feed_run(code)   <-> Sandbox.new + eval(code)
                a fresh isolated execution context, process-level setup already
                paid, running one snippet and returning its value
      cold      first Monty() in a fresh process   <-> first Sandbox.new in a
                                                       fresh process

    The payloads are the same four as untrusted_run.rb, written to be
    semantically equivalent in Python rather than idiomatic in it.

HOW IT IS COMPUTED
    A line-for-line mirror of lib/harness.rb: calibrate the iteration count
    until one round costs about ROUND_BUDGET seconds, discard WARMUP_ROUNDS,
    time ROUNDS further rounds, and report the median of the per-round wall
    times, rounded to two significant digits for the slide.
    The cold figure is sampled once per process and repeated across fresh
    processes, because a cold start happens once by definition.

WHY THE MEASUREMENT IS VALID
    * The calibration rule, round budget, round count and summary statistic
      are identical to the Ruby side. Two medians from two different harnesses
      would not be comparable even on one machine; these are.
    * time.perf_counter is Python's monotonic high-resolution clock, the same
      role CLOCK_MONOTONIC plays on the Ruby side, and only the standard
      library times anything, so no benchmark framework's overhead enters.
    * Batch-then-divide keeps the clock's resolution out of the result.
    * The pool is warmed before the per-run arm, matching the Ruby side's
      warm-up of the process-wide caches. Without it the first round would
      carry the 200ms+ pool spawn and the median would drift with round count.
    * Run in the same session as the kobako scripts. Absolute microsecond
      figures drift between sessions, so a cross-session pairing would compare
      drift as much as design.

WHY WE MEASURE A COMPETITOR HERE AT ALL
    Monty publishes two startup figures that disagree by 60x: "<1us to go from
    code to execution result" in prose, and 0.06ms in its comparison table.
    Neither is reproducible through the shipped Python API -- since 0.0.19
    execution happens in a pool of subprocess workers, and their own benchmark
    script notes the cold start "now includes spawning a worker subprocess and
    the protocol handshake", which cannot happen in 60us. Quoting either would
    put a number on the slide that the audience cannot reproduce. Measuring
    both sides the same way is the only way the chart means anything.
"""

import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

import pydantic_monty
from pydantic_monty import Monty

ROUNDS = int(os.environ.get('ROUNDS', 15))
WARMUP_ROUNDS = int(os.environ.get('WARMUP', 3))
ROUND_BUDGET = float(os.environ.get('BUDGET', 0.1))
REPEATS = int(os.environ.get('REPEATS', 5))

PAYLOADS = {
    'nil (floor)': 'None',
    'value: sum to 100': 'total = 0\nfor i in range(1, 101):\n    total += i\ntotal',
    'text: build a report line': "rows = ['a', 'b', 'c']\nout = []\nfor r in rows:\n    out.append(r + '=1')\n','.join(out)",
}
SERVICE_CODE = 'rate(21)'
SERVICE_LOOKUP = {'rate': lambda n: n * 2}


def approx(value):
    """Two significant digits -- the figure that goes on a slide.

    Same rule as Harness.approx in lib/harness.rb, so both sides of the chart
    are rounded identically.
    """
    if value == 0:
        return 0.0
    magnitude = 10 ** (math.floor(math.log10(abs(value))) - 1)
    return round(value / magnitude) * magnitude


def approx_us(us):
    return f'{approx(us):g}us' if us < 1000 else f'{approx(us / 1000.0):g}ms'


def approx_ms(ms):
    return f'{approx(ms * 1000.0):g}us' if ms < 1 else f'{approx(ms):g}ms'


def calibrate(fn):
    iters = 1
    while True:
        t0 = time.perf_counter()
        for _ in range(iters):
            fn()
        elapsed = time.perf_counter() - t0
        if elapsed >= ROUND_BUDGET or iters >= 1_000_000:
            return iters
        iters = min(int(iters * (ROUND_BUDGET / elapsed) * 1.2) + 1, iters * 8)


def measure(label, fn):
    iters = calibrate(fn)
    per_iter = []
    for r in range(ROUNDS + WARMUP_ROUNDS):
        t0 = time.perf_counter()
        for _ in range(iters):
            fn()
        elapsed = time.perf_counter() - t0
        if r >= WARMUP_ROUNDS:
            per_iter.append((elapsed / iters) * 1_000_000)

    per_iter.sort()
    median = (per_iter[(len(per_iter) - 1) // 2] + per_iter[len(per_iter) // 2]) / 2
    mean = sum(per_iter) / len(per_iter)
    sd = (sum((v - mean) ** 2 for v in per_iter) / (len(per_iter) - 1)) ** 0.5
    slide = approx_us(median)
    print(f'  {label:<36} median {median:9.2f}us  -> {slide:<7} rsd {sd / mean * 100:4.1f}%  [n={ROUNDS} x {iters}]')
    return dict(label=label, median_us=median, slide=slide, mean_us=mean, sd_us=sd,
                rsd_pct=sd / mean * 100, min_us=per_iter[0], max_us=per_iter[-1],
                iters_per_round=iters, rounds=ROUNDS)


# --- child role: time this process's own cold start, report on stdout -------
if os.environ.get('MONTY_COLD_CHILD'):
    t0 = time.perf_counter()
    with Monty() as pool:
        t1 = time.perf_counter()
        with pool.checkout() as session:
            session.feed_run('None')
    t2 = time.perf_counter()
    print(json.dumps({
        'pool_ms': (t1 - t0) * 1e3,
        'first_run_ms': (t2 - t1) * 1e3,
        'total_ms': (t2 - t0) * 1e3,
    }))
    sys.exit()

print(f'== Monty, measured the way kobako is (pydantic-monty {pydantic_monty.__version__})\n')

results = []

# --- cold: one sample per process, repeated ---------------------------------
print('  -- cold start (fresh process, first pool)')
env = dict(os.environ, MONTY_COLD_CHILD='1')
samples = [json.loads(subprocess.run([sys.executable, __file__], env=env,
                                     capture_output=True, text=True).stdout)
           for _ in range(REPEATS)]
for label, keys in (('cold: Monty() pool', ('pool_ms',)),
                    ('cold: pool + first run', ('pool_ms', 'first_run_ms'))):
    values = sorted(sum(s[k] for k in keys) for s in samples)
    median = (values[(len(values) - 1) // 2] + values[len(values) // 2]) / 2
    slide = approx_ms(median)
    print(f'  {label:<36} median {median:9.2f}ms  -> {slide:<7} min {values[0]:8.2f}   max {values[-1]:8.2f}   [n={len(values)}]')
    results.append(dict(label=label, median_ms=median, slide=slide,
                        min_ms=values[0], max_ms=values[-1], samples_ms=values))

# --- per run: pool already up, a fresh session each time --------------------
with Monty() as pool:
    with pool.checkout() as session:  # warm the pool out of the timed region
        session.feed_run('None')

    def run(code, lookup=None):
        with pool.checkout() as s:
            return s.feed_run(code, external_lookup=lookup)

    print('\n  -- per run (pool warm, fresh session each time)')
    for label, code in PAYLOADS.items():
        results.append(measure(label, lambda c=code: run(c)))
    results.append(measure('service: one host call',
                           lambda: run(SERVICE_CODE, SERVICE_LOOKUP)))

out = Path(__file__).resolve().parent.parent / 'results' / 'monty.json'
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps({
    'env': {
        'monty': pydantic_monty.__version__,
        'python': sys.version,
        'clock': 'time.perf_counter (wall)',
        'rounds': ROUNDS,
        'warmup': WARMUP_ROUNDS,
        'round_budget_s': ROUND_BUDGET,
        'repeats': REPEATS,
    },
    'results': results,
}, indent=2))
print(f'\nwrote {out.parent.name}/{out.name}')
