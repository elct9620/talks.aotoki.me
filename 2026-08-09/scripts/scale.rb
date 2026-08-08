# frozen_string_literal: true

# Scenario: Easy to Scale -- two independent claims about running many
# sandboxes on one machine.
#
# WHAT IS MEASURED
#   memory  the resident set added by COUNT live sandboxes, read before .new,
#           after .new, and again after every one of them has run once
#   gvl     wall time for the same guest work spread over N threads against
#           the same work run serially, as a speedup ratio
#
# HOW IT IS COMPUTED
#   Memory: RSS via `ps -o rss=`, in KB, with GC.start before each reading;
#   the per-sandbox figure is the delta over the baseline divided by COUNT.
#   Concurrency: the minimum of five rounds for each arm, then serial divided
#   by threaded. The minimum is used rather than the median because this arm
#   asks whether parallelism is possible at all, and the best observed run is
#   the one least contaminated by scheduling noise.
#
# WHY THE MEASUREMENT IS VALID
#   * The memory reading happens after every sandbox has actually run. A
#     Sandbox only materialises its guest instance on first invocation, so a
#     reading taken straight after .new would report a configuration object
#     and call it a sandbox.
#   * GC.start precedes each reading, so the delta is retained memory rather
#     than garbage not yet collected.
#   * The process-wide caches are warmed before the baseline is taken, which
#     keeps the engine and compiled module out of the per-sandbox figure.
#   * The concurrency arm uses a separate Sandbox per thread, never a shared
#     one. Sharing would measure a different and unsupported usage.
#   * The guest work is CPU-bound. If the GVL were held across the wasm call,
#     N threads would take N times as long as one and the speedup would sit
#     at 1.0 -- which makes this arm able to fail rather than merely confirm.

require "bundler/setup"
require "kobako"
require "etc"
require_relative "../lib/harness"

Harness.banner("Easy to Scale: memory density and thread parallelism")

COUNT = Integer(ENV.fetch("COUNT", "1000"))
CORES = Etc.nprocessors

# `ps` is the reader that works the same way on darwin and linux.
def rss_kb = `ps -o rss= -p #{Process.pid}`.to_i

Kobako::Sandbox.new.eval("nil") # warm the process-wide engine/module cache
GC.start
base = rss_kb

sandboxes = []
t0 = Harness.wall
COUNT.times { sandboxes << Kobako::Sandbox.new }
build_s = Harness.wall - t0

GC.start
after_new = rss_kb

t0 = Harness.wall
sandboxes.each { |s| s.eval("nil") }
first_eval_s = Harness.wall - t0
GC.start
after_eval = rss_kb

printf("\n  [memory] %d sandboxes\n", COUNT)
printf("    RSS baseline        %8.1f MB\n", base / 1024.0)
printf("    after .new          %8.1f MB   (+%.1f MB, %.2f KB/sandbox)\n",
       after_new / 1024.0, (after_new - base) / 1024.0, (after_new - base).to_f / COUNT)
printf("    after first eval    %8.1f MB   (+%.1f MB, %.2f KB/sandbox)\n",
       after_eval / 1024.0, (after_eval - base) / 1024.0, (after_eval - base).to_f / COUNT)
printf("    build time          %8.1f ms   (%.1f us/sandbox)\n",
       build_s * 1000, build_s / COUNT * 1_000_000)
printf("    first-eval sweep    %8.1f ms   (%.1f us/sandbox)\n",
       first_eval_s * 1000, first_eval_s / COUNT * 1_000_000)

memory = {
  count: COUNT, base_kb: base, after_new_kb: after_new, after_eval_kb: after_eval,
  per_sandbox_new_kb: (after_new - base).to_f / COUNT,
  per_sandbox_eval_kb: (after_eval - base).to_f / COUNT,
  build_us_per_sandbox: build_s / COUNT * 1_000_000,
  first_eval_us_per_sandbox: first_eval_s / COUNT * 1_000_000
}

sandboxes.clear
GC.start

WORK = "i = 0; while i < 300_000; i += 1; end; i"
PER_WORKER = 8

def run_serial(count)
  boxes = Array.new(count) { Kobako::Sandbox.new }
  boxes.each { |s| s.eval("nil") }
  t0 = Harness.wall
  boxes.each { |s| PER_WORKER.times { s.eval(WORK) } }
  Harness.wall - t0
end

def run_threaded(count)
  boxes = Array.new(count) { Kobako::Sandbox.new }
  boxes.each { |s| s.eval("nil") }
  t0 = Harness.wall
  boxes.map { |s| Thread.new { PER_WORKER.times { s.eval(WORK) } } }.each(&:join)
  Harness.wall - t0
end

puts "\n  [gvl] #{PER_WORKER} evals of a CPU-bound guest loop per worker, best of 5"
gvl = [1, 2, 4, CORES].uniq.map do |workers|
  serial = Array.new(5) { run_serial(workers) }.min
  threaded = Array.new(5) { run_threaded(workers) }.min
  printf("    workers=%-3d serial %7.1f ms   threaded %7.1f ms   speedup %.2fx\n",
         workers, serial * 1000, threaded * 1000, serial / threaded)
  { workers: workers, serial_ms: serial * 1000, threaded_ms: threaded * 1000,
    speedup: serial / threaded }
end

Harness.report("scale", [], memory: memory, gvl: gvl)
