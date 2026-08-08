# frozen_string_literal: true

# Scenario: Docker measured the same way kobako is, so the two can share a chart.
#
# WHAT IS MEASURED
#   `docker run --rm <image> <interpreter> -e <code>` end to end: the CLI call,
#   the daemon round trip, container create and start, the interpreter's own
#   startup, the program, and teardown. Three images:
#     alpine        the floor -- container lifecycle with no interpreter in it
#     ruby:alpine   the honest counterpart to kobako, which runs Ruby
#     python:alpine the image Monty's own benchmark uses, for cross-reference
#
# HOW IT IS COMPUTED
#   One `docker run` per round, ROUNDS rounds, median of the per-round wall
#   times. No calibration loop: a round already costs ~200ms, which is four
#   orders of magnitude above the clock's resolution, so batching would only
#   hide variance.
#
# WHY THE MEASUREMENT IS VALID
#   * The image is pulled before timing starts, so no round pays a registry
#     fetch. This is the same assumption every published Docker startup figure
#     makes, and it is the generous one for Docker.
#   * The program is the smallest thing that still returns a value, so what is
#     left is container startup plus interpreter startup -- the thing the chart
#     is comparing, not the workload.
#   * The output is asserted, so a round that silently failed cannot be timed
#     as if it had succeeded.
#   * This is the one scenario where the wall-versus-CPU check does not apply:
#     the work happens in the daemon and the container, not in this process,
#     so the parent's CPU time is meaningless here. Its gate is the spread
#     across rounds instead.
#
# WHY WE MEASURE A COMPETITOR HERE AT ALL
#   Docker publishes no startup-time claim anywhere in its documentation, so
#   there is no official figure to quote. Third-party figures for the same
#   command range from ~195ms to over 1500ms depending on host, storage and
#   image -- a spread wide enough that picking one is picking a conclusion.
#   Measuring it here, on the same machine and in the same session as kobako,
#   is the only way the chart compares like with like.

require "bundler/setup"
require "open3"
require_relative "../lib/harness"

Harness.banner("Docker: one container run, measured the way kobako is")

ROUNDS = Integer(ENV.fetch("ROUNDS", "15"))
WARMUP = Integer(ENV.fetch("WARMUP", "3"))

CASES = [
  { label: "alpine (floor)", image: "alpine", argv: %w[true], expect: "" },
  { label: "ruby:3.4-alpine", image: "ruby:3.4-alpine", argv: ["ruby", "-e", "puts 1 + 1"], expect: "2" },
  { label: "python:3.14-alpine", image: "python:3.14-alpine", argv: ["python", "-c", "print(1 + 1)"], expect: "2" }
].freeze

def docker_run(image, argv)
  out, status = Open3.capture2e("docker", "run", "--rm", image, *argv)
  [out.strip, status]
end

rows = CASES.map do |kase|
  # Pull outside the timed region; a round must never pay a registry fetch.
  system("docker", "image", "inspect", kase[:image], out: File::NULL, err: File::NULL) ||
    system("docker", "pull", "--quiet", kase[:image], out: File::NULL)

  samples = []
  (ROUNDS + WARMUP).times do |round|
    t0 = Harness.wall
    out, status = docker_run(kase[:image], kase[:argv])
    elapsed = (Harness.wall - t0) * 1e3
    raise "docker run failed: #{out}" unless status.success? && out == kase[:expect]

    samples << elapsed if round >= WARMUP
  end

  median = Harness.median(samples)
  mean = samples.sum / samples.size
  sd = Math.sqrt(samples.sum { |v| (v - mean)**2 } / (samples.size - 1))
  slide = Harness.approx_ms(median)
  printf("  %-36s median %9.2fms  -> %-7s rsd %4.1f%%  min %8.2f  max %8.2f  [n=%d]\n",
         kase[:label], median, slide, sd / mean * 100, samples.min, samples.max, samples.size)
  { label: kase[:label], image: kase[:image], median_ms: median, slide: slide,
    mean_ms: mean, sd_ms: sd, rsd_pct: sd / mean * 100,
    min_ms: samples.min, max_ms: samples.max, rounds: samples.size }
end

runtime = `docker info --format '{{.OperatingSystem}} / {{.ServerVersion}}'`.strip
puts "\n  runtime: #{runtime}"
Harness.report("docker", rows, docker_runtime: runtime)
