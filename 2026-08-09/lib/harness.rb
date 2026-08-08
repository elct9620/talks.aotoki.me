# frozen_string_literal: true

require "json"
require "etc"

# Shared measurement basis for every number that appears on the slides.
#
# WHAT IS MEASURED
#   Elapsed time of one operation, in microseconds, as a median over repeated
#   rounds. Every scenario script builds its rows out of Harness.measure.
#
# HOW IT IS COMPUTED
#   1. Calibrate: grow the iteration count until one round costs ~BUDGET
#      seconds. A round is timed as a whole and divided by the iteration
#      count; a single operation is never timed on its own.
#   2. Discard the first WARMUP rounds.
#   3. Time ROUNDS further rounds, recording wall and CPU time for each.
#   4. Report the median of the per-round wall times, plus the relative
#      standard deviation (sd / mean) as the spread.
#
# WHY THE MEASUREMENT IS VALID
#   * Batch-then-divide beats the clock's resolution. This machine resolves
#     CLOCK_PROCESS_CPUTIME_ID to 1000ns, so timing a single ~3us operation
#     leaves three ticks of signal and 25-50% quantisation error. A round of
#     ~0.1s reduces that error to noise.
#   * The median resists the scheduler. One preempted round shifts a mean but
#     not a median, and the reported RSD says whether that assumption held --
#     an RSD above a few percent means the machine was not quiet enough.
#   * Wall and CPU are reported side by side as an independent quietness
#     check. Wall time is what a user feels, but it absorbs machine load;
#     CPU time does not. When the two agree the work was CPU-bound and the
#     number is attributable to the code. A wall time visibly above CPU time
#     means the process waited on something, and that row must not be quoted.
#   * Only the standard library is used. The competitor side (Monty) runs in
#     Python, where Ruby's benchmark gems do not exist; the one basis both
#     languages share is a monotonic clock plus an identical calibration
#     rule, so the two result sets are comparable rather than merely adjacent.
module Harness
  ROUNDS = Integer(ENV.fetch("ROUNDS", "15"))
  WARMUP = Integer(ENV.fetch("WARMUP", "3"))
  BUDGET = Float(ENV.fetch("BUDGET", "0.1")) # target seconds per round
  RESULTS_DIR = File.expand_path("../results", __dir__)

  module_function

  # CLOCK_MONOTONIC never steps backwards over NTP adjustments, which a
  # wall-clock reading of Time.now would.
  def wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  def cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)

  # Grows the iteration count geometrically until one round costs about
  # BUDGET seconds, so every case -- whether it takes 3us or 3ms -- is timed
  # over a comparable slice of wall clock. The 1.2 factor overshoots slightly
  # so the loop converges from below instead of oscillating; the x8 cap keeps
  # a single step from exploding when the first round measures near zero.
  def calibrate(&block)
    iters = 1
    loop do
      t0 = wall
      iters.times(&block)
      elapsed = wall - t0
      return iters if elapsed >= BUDGET || iters >= 1_000_000

      iters = elapsed <= 0 ? iters * 8 : [(iters * (BUDGET / elapsed) * 1.2).ceil, iters * 8].min
    end
  end

  # iters: is passed explicitly only where calibration would be destructive --
  # fork, for instance, would be driven to thousands of processes.
  def measure(label, iters: nil, &block)
    iters ||= calibrate(&block)
    walls = []
    cpus = []
    (ROUNDS + WARMUP).times do |round|
      w0 = wall
      c0 = cpu
      iters.times(&block)
      w = (wall - w0) / iters * 1e6
      c = (cpu - c0) / iters * 1e6
      next if round < WARMUP # JIT, GC and page faults are still settling

      walls << w
      cpus << c
    end
    row = summarize(label, walls, cpus, iters)
    puts format("  %-36s median %9.2fus  -> %-7s rsd %4.1f%%  wall-cpu %5.1f%%  [n=%d x %d]",
                label, row[:median_us], row[:slide], row[:rsd_pct], row[:wall_minus_cpu_pct],
                ROUNDS, iters)
    row
  end

  # Spread is reported as RSD rather than raw sd so cases of different
  # magnitude can be judged against one threshold.
  def summarize(label, walls, cpus, iters)
    mean = walls.sum / walls.size
    sd = walls.size > 1 ? Math.sqrt(walls.sum { |v| (v - mean)**2 } / (walls.size - 1)) : 0.0
    median_wall = median(walls)
    median_cpu = median(cpus)
    {
      label: label,
      median_us: median_wall,
      slide: approx_us(median_wall),
      cpu_median_us: median_cpu,
      wall_minus_cpu_pct: median_wall.zero? ? 0.0 : (median_wall - median_cpu) / median_wall * 100,
      mean_us: mean,
      sd_us: sd,
      rsd_pct: mean.zero? ? 0.0 : sd / mean * 100,
      min_us: walls.min,
      max_us: walls.max,
      iters_per_round: iters,
      rounds: walls.size
    }
  end

  # Averages the two middle samples on an even count, so the median of a
  # 15-round run and of a 16-round run mean the same thing.
  def median(values)
    s = values.sort
    (s[(s.length - 1) / 2] + s[s.length / 2]) / 2.0
  end

  # The figure that goes on a slide, rounded to two significant digits.
  #
  # Two digits sits inside every case's own round-to-round spread, so the
  # rounding cannot move a claim the measurement supports -- 74.75us and 75us
  # are the same finding. What it buys is a number an audience can hold in
  # their head while the next slide is being talked through. The raw median
  # stays in the JSON, so the exact figure is one file away when someone asks.
  def approx(value)
    return 0.0 if value.zero?

    magnitude = 10**(Math.log10(value.abs).floor - 1)
    (value / magnitude).round * magnitude
  end

  # Microseconds carry past 1000 badly on a slide, so the unit follows the
  # magnitude and the rounding is applied in whichever unit is displayed.
  def approx_us(us)
    us < 1000 ? format("%gus", approx(us)) : format("%gms", approx(us / 1000.0))
  end

  def approx_ms(ms)
    ms < 1 ? format("%gus", approx(ms * 1000.0)) : format("%gms", approx(ms))
  end

  # Recorded next to every result set: absolute microsecond figures are only
  # comparable within one machine, one runtime build and one load level.
  def env
    {
      ruby: RUBY_DESCRIPTION,
      kobako: defined?(Kobako::VERSION) ? Kobako::VERSION : nil,
      cores: Etc.nprocessors,
      loadavg: begin
        `sysctl -n vm.loadavg`.strip
      rescue StandardError
        nil
      end,
      clock: "CLOCK_MONOTONIC (wall) + CLOCK_PROCESS_CPUTIME_ID (cpu)",
      rounds: ROUNDS,
      warmup: WARMUP,
      round_budget_s: BUDGET
    }.compact
  end

  def banner(title)
    puts "== #{title}"
    e = env
    puts "   ruby=#{e[:ruby]}"
    puts "   kobako=#{e[:kobako]}  cores=#{e[:cores]}  loadavg=#{e[:loadavg]}"
    puts
  end

  def report(name, rows, extra = {})
    Dir.mkdir(RESULTS_DIR) unless Dir.exist?(RESULTS_DIR)
    path = File.join(RESULTS_DIR, "#{name}.json")
    File.write(path, JSON.pretty_generate({ env: env, results: rows }.merge(extra)))
    puts "\nwrote #{path.sub("#{File.expand_path("..", __dir__)}/", "")}"
  end
end
