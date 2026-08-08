# frozen_string_literal: true

# Scenario: workloads -- how kobako's cost splits between the sandbox itself
# and the guest program, across programs of very different weight.
#
# WHAT IS MEASURED
#   Four workloads under two verbs:
#     #eval  parses on every call
#     #run   parses once via #preload, then dispatches
#   The workloads are empty, a 300k-iteration loop, a 10k accumulation and 2k
#   string concatenations. Plus a whole-sandbox-per-run baseline and a host
#   round trip driven 100 times.
#
# HOW IT IS COMPUTED
#   Harness.measure calibrates each case to ~0.1s per round and reports the
#   median of the per-round wall times.
#
# WHY THE MEASUREMENT IS VALID
#   * The empty workload is measured under both verbs, which fixes the
#     per-call overhead. Every heavier workload can then be read as overhead
#     plus guest work rather than as one opaque figure.
#   * The host round trip runs the boundary crossing 100 times inside one
#     invocation, so the per-crossing cost comes out of the slope rather than
#     out of a single crossing that the clock could not resolve.
#   * The process-wide caches are warmed before timing, so no case carries a
#     cold start.
#
# READING THE RESULT
#   These figures describe kobako only. Competitor figures on the slides come
#   from each vendor's own published claim, not from this harness -- quoting
#   our own measurement of someone else's product would put a number they
#   never agreed to in their mouth.

require "bundler/setup"
require "kobako"
require_relative "../lib/harness"

Harness.banner("Workloads: where kobako's cost goes as the guest program grows")

WORKLOADS = {
  "empty" => "nil",
  "loop-300k" => "i = 0\nwhile i < 300000\n  i += 1\nend\ni",
  "sum-10k" => "total = 0\n(0...10000).each { |x| total += x * 2 }\ntotal",
  "str-2k" => "s = ''\n2000.times { s += 'x' }\ns.length"
}.freeze

sandbox = Kobako::Sandbox.new
sandbox.eval("nil") # move the process-wide caches out of the timed region

rows = []

puts "  -- parsed on every call"
WORKLOADS.each { |name, code| rows << Harness.measure("eval #{name}") { sandbox.eval(code) } }

puts "\n  -- parsed once, run many"
preloaded = Kobako::Sandbox.new
WORKLOADS.each_with_index do |(_, code), i|
  preloaded.preload(code: "class W#{i}\n  def self.call\n#{code}\n  end\nend", name: :"W#{i}")
end
WORKLOADS.each_with_index { |(name, _), i| rows << Harness.measure("run #{name}") { preloaded.run(:"W#{i}") } }

puts "\n  -- a whole sandbox per run (baseline)"
rows << Harness.measure("new + eval empty") { Kobako::Sandbox.new.eval("nil") }

puts "\n  -- host round trips"
host = Kobako::Sandbox.new
host.bind("H::Bump", ->(i) { i + 1 })
host.preload(
  code: "class HostCall\n  def self.call\n    total = 0\n    100.times { |i| total += H::Bump.call(i) }\n    total\n  end\nend",
  name: :HostCall
)
rows << Harness.measure("host-call x100") { host.run(:HostCall) }

Harness.report("workloads", rows)
