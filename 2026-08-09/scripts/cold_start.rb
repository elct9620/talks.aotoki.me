# frozen_string_literal: true

# Scenario: Cold Start -- how long a brand-new process takes to obtain its
# first usable sandbox.
#
# WHAT IS MEASURED
#   Three tiers that differ only in the state of the .cwasm AOT cache:
#     A  no .cwasm      wasmtime must run Cranelift over the guest module
#     B  .cwasm on disk a new process mmaps it and skips the compiler
#     C  same process   every cache is already resident; only construction left
#   Each tier reports: require "kobako", Sandbox.new, the first eval, and a
#   second sandbox built in the same process.
#
# HOW IT IS COMPUTED
#   The measurement has to cross a process boundary -- inside one process the
#   module cache makes A and B indistinguishable after the first sandbox. So
#   this script re-executes itself as a child (KOBAKO_COLD_CHILD), the child
#   stamps CLOCK_MONOTONIC around each step and prints them as JSON, and the
#   parent takes the median over REPEATS children.
#   "Sandbox.new + first eval" is summed per sample before taking the median,
#   because taking two medians and adding them would mix different rounds.
#
# WHY THE MEASUREMENT IS VALID
#   * XDG_CACHE_HOME points at a throwaway directory, which is where the gem
#     resolves its .cwasm store. Tier A therefore starts from a genuinely
#     empty cache instead of silently reading the developer's ~/.cache/kobako,
#     and the run cannot pollute that store either.
#   * Tier A uses a fresh directory per repeat. Reusing one would let the
#     first child write the cache the rest would read, turning A into B.
#   * A cold start happens once per process by definition, so it is sampled
#     once per process and repeated, never looped -- a loop would only ever
#     measure the warm path.
#   * Millisecond-scale steps are far above the clock's 1000ns resolution, so
#     one-shot timing is sound here in a way it would not be for the
#     microsecond scenarios.

require "bundler/setup"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../lib/harness"

# --- child role: time this process's own cold start, report on stdout -------
if ENV["KOBAKO_COLD_CHILD"]
  t0 = Harness.wall
  require "kobako"
  t1 = Harness.wall
  sandbox = Kobako::Sandbox.new
  t2 = Harness.wall
  sandbox.eval("nil")
  t3 = Harness.wall
  Kobako::Sandbox.new.eval("nil")
  t4 = Harness.wall

  puts JSON.generate(
    require_ms: (t1 - t0) * 1e3,
    sandbox_new_ms: (t2 - t1) * 1e3,
    first_eval_ms: (t3 - t2) * 1e3,
    second_sandbox_ms: (t4 - t3) * 1e3,
    total_ms: (t4 - t0) * 1e3
  )
  exit
end

# --- parent role ------------------------------------------------------------
require "kobako"
Harness.banner("Cold Start: first usable sandbox in a fresh process")

REPEATS = Integer(ENV.fetch("REPEATS", "5"))

def child(cache_dir)
  out = IO.popen({ "KOBAKO_COLD_CHILD" => "1", "XDG_CACHE_HOME" => cache_dir },
                 [RbConfig.ruby, __FILE__], &:read)
  JSON.parse(out, symbolize_names: true)
end

# Several keys sum within one sample, so a composite step stays attributable
# to the single child process that produced it.
def summarize(label, samples, *keys)
  values = samples.map { |s| keys.sum { |k| s[k] } }
  median = Harness.median(values)
  slide = Harness.approx_ms(median)
  printf("  %-36s median %9.2fms  -> %-7s min %8.2f   max %8.2f   [n=%d]\n",
         label, median, slide, values.min, values.max, values.size)
  { label: label, median_ms: median, slide: slide,
    min_ms: values.min, max_ms: values.max, samples_ms: values }
end

rows = []

Dir.mktmpdir("kobako-coldstart") do |root|
  # Tier A: every process recompiles. A fresh cache directory per repeat is
  # what makes Cranelift unavoidable.
  puts "  -- no AOT cache (every process recompiles)"
  cold = Array.new(REPEATS) do |i|
    dir = File.join(root, "cold-#{i}")
    FileUtils.mkdir_p(dir)
    child(dir)
  end
  rows << summarize("recompile: Sandbox.new", cold, :sandbox_new_ms)
  rows << summarize("recompile: Sandbox.new + first eval", cold, :sandbox_new_ms, :first_eval_ms)

  # Tier B: the cache is already on disk; a new process reads it. The first
  # child is the one that writes it and is discarded.
  warm_dir = File.join(root, "warm")
  FileUtils.mkdir_p(warm_dir)
  child(warm_dir)
  puts "\n  -- AOT cache on disk (.cwasm, new process mmaps it)"
  warm = Array.new(REPEATS) { child(warm_dir) }
  rows << summarize("cached: Sandbox.new", warm, :sandbox_new_ms)
  rows << summarize("cached: Sandbox.new + first eval", warm, :sandbox_new_ms, :first_eval_ms)
  rows << summarize("same process: second sandbox + eval", warm, :second_sandbox_ms)
  rows << summarize("require \"kobako\" (native extension)", warm, :require_ms)
end

puts
puts "  The gap between the first two rows and the next two is Cranelift"
puts "  compilation -- the two bars on the Cold Start slide."

Harness.report("cold_start", rows, repeats: REPEATS)
