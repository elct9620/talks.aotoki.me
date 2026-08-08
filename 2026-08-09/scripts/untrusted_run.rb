# frozen_string_literal: true

# Scenario: One Untrusted Run -- running one piece of AI-generated code and
# getting the result back, end to end.
#
# WHAT IS MEASURED
#   The whole path a request pays: construct a sandbox, evaluate a script
#   inside it, read the value out. Four payloads, from an empty program up to
#   a script that calls back into the host:
#     nil        the floor -- sandbox machinery with no guest work in it
#     value      a script that computes and returns something
#     text       string building, the shape LLM output usually takes
#     service    the same, plus a host call across the boundary
#
# HOW IT IS COMPUTED
#   Harness.measure calibrates each payload to ~0.1s per round and reports
#   the median of the per-round wall times. The value is read off the
#   Execution inside the timed block, so deserialising the result is part of
#   the number rather than left out of it.
#
# WHY THE MEASUREMENT IS VALID
#   * The floor is measured alongside the real payloads. Quoting only the nil
#     case would present sandbox overhead as the cost of doing work; quoting
#     only a real payload would hide how much of it is the guest program.
#     Both are reported so the split is visible.
#   * Sandbox construction is inside the timed block. This scenario is about
#     a run that owns its sandbox, which is what makes it comparable with
#     platform offerings that provision one per request.
#   * The process-wide caches are warmed first, so this measures a steady
#     state rather than a cold start -- cold start is its own scenario.
#
# READING THE RESULT
#   The platform-level competitors on the same slide (Docker, E2B, Lambda)
#   are measured at a different boundary: their figures include scheduling
#   and a network round trip, which this one does not. That difference is the
#   point of the slide, but it has to be stated rather than glossed over.

require "bundler/setup"
require "kobako"
require_relative "../lib/harness"

Harness.banner("One Untrusted Run: build a sandbox, run a script, read the value")

PAYLOADS = {
  "nil (floor)" => "nil",
  "value: sum to 100" => "total = 0; (1..100).each { |i| total += i }; total",
  # Single-quoted so the guest program reaches the sandbox verbatim instead of
  # being interpolated by the host.
  "text: build a report line" => 'rows = %w[a b c]; rows.map { |r| r + "=1" }.join(",")'
}.freeze

Kobako::Sandbox.new.eval("nil") # warm the process-wide caches

rows = []
PAYLOADS.each do |label, code|
  rows << Harness.measure(label) { Kobako::Sandbox.new.eval(code).value }
end

# The service case needs a binding, so the sandbox is configured inside the
# timed block too -- that configuration is part of what a real request pays.
rows << Harness.measure("service: one host call") do
  sandbox = Kobako::Sandbox.new
  sandbox.bind("Host::Rate", ->(n) { n * 2 })
  sandbox.eval("Host::Rate.call(21)").value
end

Harness.report("untrusted_run", rows)
