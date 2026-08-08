# frozen_string_literal: true

require_relative "../lib/harness"
require "net/http"

# WHAT IS MEASURED
#   The cost of one untrusted run on Cloudflare's own sandbox primitive: a Worker
#   calls env.LOADER.get(id, ...) to load a dynamic Worker and invokes it. Two
#   cases, differing only in whether the loader's isolate cache is hit:
#     warm  a fixed id, so the isolate is reused    -> comparable to kobako's #eval
#     cold  a fresh uuid, so a new isolate is built -> comparable to Sandbox.new + eval
#   /baseline is the same Worker returning immediately, and is subtracted from both:
#   what is left is the loader's own cost, with the transport charged to neither.
#
# WHY IT IS MEASURED FROM OUTSIDE
#   Workers coarsens its own clock as a Spectre mitigation -- Date.now() and
#   performance.now() do not advance during synchronous execution -- so a timer
#   inside the Worker cannot see microseconds. The client's clock can, at the cost
#   of including one loopback HTTP round trip in every sample; that is exactly what
#   /baseline exists to remove.
#
# WHY THE COMPARISON IS FAIR, AND WHERE IT IS NOT
#   Fair: same machine, same session, same harness and calibration rule as every
#   kobako figure, and the transport is subtracted rather than ignored.
#   Not fair: kobako's numbers are an in-process call with no transport at all,
#   while this one cannot exist without a runtime process to talk to. The residual
#   is the honest comparison; the end-to-end figure is not.
#
# PREREQUISITE
#   The Worker under measurement must already be serving, under the workerd binary
#   directly -- not wrangler dev:
#     cd scripts/support/cf-bench && npm install
#     ./node_modules/workerd/bin/workerd serve --experimental config.capnp
#   The Worker Loader API works in plain workerd without the closed beta, which is
#   the whole reason this measurement is possible at all.
#
#   ! wrangler dev serves the same Worker but puts its own proxy in front: measured
#     side by side on 2026-08-04, its baseline was ~695us against workerd's ~77us.
#     That ~620us is wrangler's, and quoting it as Cloudflare's would be wrong.

PORT = Integer(ENV.fetch("CF_PORT", "8791"))
FLOOR_PORT = Integer(ENV.fetch("FLOOR_PORT", "8792"))

floor_pid = spawn(RbConfig.ruby, File.expand_path("support/floor_server.rb", __dir__), FLOOR_PORT.to_s)
sleep 0.5

http = Net::HTTP.new("127.0.0.1", PORT)
http.start
floor = Net::HTTP.new("127.0.0.1", FLOOR_PORT)
floor.start

versions = {
  wrangler: `cd #{File.expand_path("../../..", __dir__)} && npx wrangler --version 2>/dev/null`.strip,
  note: "worker_loaders binding, local mode"
}

# Raised deliberately: the layers only mean something if the machine was quiet, and
# the loadavg recorded next to them says whether it was.
STATUS = "2026-08-04 run is a feasibility check taken under load -- see env.loadavg. " \
         "The layers are the right shape but the figures are not quotable until re-run quiet."

Harness.banner("Cloudflare dynamic Worker (workerd, local)")

rows = [Harness.measure("floor") { floor.get("/") }]
rows += %w[baseline warm cold].map { |path| Harness.measure(path) { http.get("/#{path}") } }
Process.kill("TERM", floor_pid)

at = ->(label) { rows.find { |r| r[:label] == label }[:median_us] }
# Each layer is charged only for what it adds to the one below it.
layers = {
  "workerd request handling" => at.call("baseline") - at.call("floor"),
  "loader, isolate cached" => at.call("warm") - at.call("baseline"),
  "loader, new isolate" => at.call("cold") - at.call("baseline")
}

puts
layers.each { |label, us| puts format("  %-36s %s", label, Harness.approx_us(us)) }

Harness.report("cloudflare", rows, { versions: versions, layers: layers, status: STATUS })
