# frozen_string_literal: true

# Scenario: Low Cost Roundtrip -- kobako's per-call cost placed next to
# operations the audience already has a feel for.
#
# WHAT IS MEASURED
#   Two reference groups around the kobako rows:
#     isolation primitives  Thread.new + join, fork + waitpid
#     everyday Rails work   User.first, User.first.to_json, on two databases
#
# HOW IT IS COMPUTED
#   Every row goes through the same Harness.measure calibration, so a row is
#   a median of per-round wall times over rounds of equal duration. fork is
#   the one exception: its iteration count is pinned rather than calibrated.
#
# WHY THE MEASUREMENT IS VALID
#   * Thread and fork are measured on this machine rather than quoted from
#     elsewhere. An absolute microsecond figure only means something against
#     other figures from the same machine, runtime and load, so the reference
#     points have to be produced in the same session as the kobako rows.
#   * Only the joined Thread case is measured. Spawning without joining
#     leaves live threads accumulating, which measures the accumulation and
#     not the cost of creating one thread.
#   * fork gets a fixed iteration count. Calibration would drive it into tens
#     of thousands of processes, and its cost tracks the parent's page tables,
#     so a run that grows the process would measure its own footprint.
#   * fork is the one row where the wall-versus-CPU check does not apply: the
#     parent blocks in waitpid by design, so wall time is expected to exceed
#     CPU time. Its gate is the spread across rounds instead.
#   * The Rails rows are measured twice, against an in-memory database and
#     against a file on disk. In-memory isolates ORM and serialisation cost;
#     on disk is what a real application actually runs. Measuring only the
#     first would quietly pick the comparison kobako looks worst against, and
#     measuring only the second would blur ORM cost with page-cache luck.
#
# READING THE RESULT
#   Thread has no isolation, so it cannot support the claim that isolation is
#   expensive; fork is the primitive in kobako's own class, and it is the one
#   worth comparing against.

require "bundler/setup"
require "kobako"
require "active_record"
require "fileutils"
require_relative "../lib/harness"

Harness.banner("Low Cost Roundtrip: kobako against everyday operations")

DB_FILE = File.expand_path("../results/roundtrip.sqlite3", __dir__)
FileUtils.rm_f(DB_FILE)

ActiveRecord::Base.logger = nil
ActiveRecord::Schema.verbose = false

def connect(database)
  ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database)
  ActiveRecord::Schema.define do
    create_table :users, force: true do |t|
      t.string :name
      t.string :email
      t.integer :age
      t.timestamps
    end
  end
  100.times { |i| User.create!(name: "user#{i}", email: "user#{i}@example.com", age: 20 + (i % 40)) }
end

class User < ActiveRecord::Base; end

Kobako::Sandbox.new.eval("nil") # warm the process-wide caches
shared = Kobako::Sandbox.new.tap { |s| s.eval("nil") }

rows = []

puts "  -- isolation primitives on this machine"
rows << Harness.measure("Thread.new { nil }.join") { Thread.new { nil }.join }
rows << Harness.measure("fork + waitpid", iters: 200) do
  pid = fork { exit!(0) }
  Process.waitpid(pid)
end

puts "\n  -- kobako"
rows << Harness.measure("Sandbox.new") { Kobako::Sandbox.new }
rows << Harness.measure("Sandbox#eval (reused)") { shared.eval("nil") }
rows << Harness.measure("Sandbox.new + eval") { Kobako::Sandbox.new.eval("nil") }

# The connection is switched between the two arms rather than held open on
# both, so each arm is measured through the one connection pool a real
# application would have.
{ ":memory:" => "in-memory", DB_FILE => "on-disk" }.each do |database, name|
  connect(database)
  User.first # open the file and fill the schema cache outside the timed region
  puts "\n  -- everyday Rails operations (#{name} SQLite)"
  rows << Harness.measure("User.first (#{name})") { User.first }
  rows << Harness.measure("User.first.to_json (#{name})") { User.first.to_json }
end

FileUtils.rm_f(DB_FILE)
Harness.report("roundtrip", rows, activerecord: ActiveRecord::VERSION::STRING)
