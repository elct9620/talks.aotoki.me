# frozen_string_literal: true

# Scenario: burst -- what happens to per-sandbox cost when many are requested
# at once, so kobako can be read on the axis platform offerings are measured on.
#
# WHAT IS MEASURED
#   Cost per sandbox two ways: BURST sandboxes created one after another, and
#   BURST sandboxes created from BURST threads started together. The result
#   is the ratio between them -- the degradation factor.
#
# HOW IT IS COMPUTED
#   Each arm times the whole batch and divides by BURST, then takes the
#   minimum over ROUNDS batches. Minimum rather than median: the question is
#   whether concurrency degrades the cost at all, so the cleanest observation
#   of each arm is the fair one to compare.
#
# WHY THE MEASUREMENT IS VALID
#   * Both arms do identical work -- construct and evaluate -- and differ only
#     in whether the requests overlap. The ratio therefore isolates the effect
#     of concurrency rather than of the work.
#   * The process-wide caches are warmed first, so neither arm carries a cold
#     start into the ratio.
#   * The threaded arm joins every thread before stopping the clock, so the
#     batch time covers all of the work and not just the fastest threads.
#
# READING THE RESULT
#   This is not a parallel-speedup measurement: guest execution is serialised
#   by the GVL, so "at once" does not mean "in parallel". What it answers is
#   the question the platform benchmarks answer -- do concurrent requests make
#   each individual request slower? Platform offerings degrade because they
#   queue provisioning; an in-process design has no queue, and whatever
#   degradation shows up here comes from contention instead.

require "bundler/setup"
require "kobako"
require_relative "../lib/harness"

Harness.banner("Burst: per-sandbox cost when requests arrive together")

BURST = Integer(ENV.fetch("BURST", "100"))
ROUNDS = Integer(ENV.fetch("BURST_ROUNDS", "10"))

Kobako::Sandbox.new.eval("nil") # warm the process-wide caches

def sequential(count)
  t0 = Harness.wall
  count.times { Kobako::Sandbox.new.eval("nil") }
  (Harness.wall - t0) / count * 1e6
end

def burst(count)
  t0 = Harness.wall
  Array.new(count) { Thread.new { Kobako::Sandbox.new.eval("nil") } }.each(&:join)
  (Harness.wall - t0) / count * 1e6
end

sequential_us = Array.new(ROUNDS) { sequential(BURST) }.min
burst_us = Array.new(ROUNDS) { burst(BURST) }.min

printf("  %-36s %9.2fus / sandbox\n", "sequential", sequential_us)
printf("  %-36s %9.2fus / sandbox\n", "burst(#{BURST})", burst_us)
printf("  %-36s %9.2fx\n", "degradation", burst_us / sequential_us)

Harness.report("burst", [], burst: BURST, burst_rounds: ROUNDS,
                            sequential_us: sequential_us, burst_us: burst_us,
                            degradation: burst_us / sequential_us)
