# frozen_string_literal: true

# Scenario: Warm Start / Bootstrap -- once the process is warm, what each
# further sandbox operation costs.
#
# WHAT IS MEASURED
#   Sandbox.new (construction only)  a reusable configuration, no wasm instance
#   Sandbox.new + eval               the full cost of a per-request sandbox
#   Pool checkout + eval             the same request, served from a pool
#   shared #eval                     marginal cost of the Nth call on one sandbox
#   shared #run                      preload once, dispatch many
#
# HOW IT IS COMPUTED
#   Harness.measure calibrates each case to ~0.1s per round, discards the
#   warmup rounds and reports the median of the per-round wall times. The
#   guest program is "nil" throughout, so what is left after subtracting the
#   interpreter's own work is the sandbox machinery itself.
#
# WHY THE MEASUREMENT IS VALID
#   * One sandbox is created and evaluated before timing starts. That moves
#     the process-wide engine and module caches out of the measured region;
#     without it the first round would carry the cold start and the median
#     would drift with the round count.
#   * The shared cases reuse an already-evaluated sandbox, so they measure a
#     marginal call rather than a first call.
#   * Each case reports wall against CPU. These are microsecond-scale figures
#     where a single scheduler preemption would dominate, so a row whose wall
#     time exceeds its CPU time is not attributable to the code under test.
#
# READING THE RESULT
#   Sandbox.new does not create a wasm instance. The instance is created per
#   invocation and thrown away -- that discard is where the isolation
#   guarantee comes from. So a cheap Sandbox.new is the cost of a reusable
#   configuration, not the cost of a sandbox; the sandbox instance is paid
#   for in the eval rows.

require "bundler/setup"
require "kobako"
require_relative "../lib/harness"

Harness.banner("Warm Start: marginal cost of a sandbox operation in a warm process")

ENTRY = "module Worker; def self.call; nil; end; end"

Kobako::Sandbox.new.eval("nil") # warm the process-wide engine/module caches

shared_eval = Kobako::Sandbox.new.tap { |s| s.eval("nil") }
shared_run = Kobako::Sandbox.new.tap do |s|
  s.preload(code: ENTRY, name: :Worker)
  s.run(:Worker)
end
pool = Kobako::Pool.new(slots: 4)
pool.with { |s| s.eval("nil") }

rows = []

puts "  -- a new sandbox per request"
rows << Harness.measure("Sandbox.new (construction only)") { Kobako::Sandbox.new }
rows << Harness.measure("Sandbox.new + eval('nil')") { Kobako::Sandbox.new.eval("nil") }
rows << Harness.measure("Pool checkout + eval('nil')") { pool.with { |s| s.eval("nil") } }

puts "\n  -- a shared sandbox: cost of the Nth call"
rows << Harness.measure("eval('nil')") { shared_eval.eval("nil") }
rows << Harness.measure("run(:Worker)") { shared_run.run(:Worker) }

Harness.report("warm_start", rows)
