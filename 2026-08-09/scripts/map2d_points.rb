# frozen_string_literal: true

# Computes the Map2D coordinates for the two comparison slides, so the points are
# derived rather than eyeballed. Prints the audits and the Point elements, ready to
# paste into src/slides.md. The speed data is shared by both charts, which is why
# they live in one script: the X axis must not drift between them.
#
# X -- SPEED (both charts)
#   Positions come from log10 of the measured median, because the field spans three
#   orders of magnitude and a linear axis would collapse every microsecond figure
#   onto the right edge. A pure log placement then has the opposite problem: the
#   three in-process options sit within 8% of each other and read as "the same
#   speed" when one is in fact 2.3x another. SPREAD applies a power curve to the
#   normalised position, widening the fast end at the cost of compressing the slow
#   end -- where the three container options really are within 20% of each other
#   and their order carries no argument. SPREAD=1.0 restores the plain log axis.
#
# Y -- CAPABILITY (chart 1) and ISOLATION (chart 2)
#   Each is the sum of an audit whose columns are scored against the same yardstick
#   across all six options, added rather than weighted so no judgement is smuggled
#   in through a multiplier. The reasoning for each column sits with its table.

SPREAD = Float(ENV.fetch("SPREAD", "0.5"))
X_RANGE = [8.0, 92.0].freeze
Y_RANGE = [12.0, 90.0].freeze
MIN_GAP = 12.0      # 12 units of a 40rem stage is ~76px, clearing a Focus frame
SAME_COLUMN = 12.0  # labels run to the right of their point, so a near x is an overlap

# median microseconds for one untrusted run; see results/*.json
SPEED = {
  "Docker" => { us: 220_000, source: "self-measured" },
  "E2B" => { us: 200_000, source: "vendor" },
  "Lambda" => { us: 259_000, source: "third-party" },
  "Cloudflare" => { us: 120, source: "self-measured, provisional" },
  "kobako" => { us: 60, source: "self-measured", tone: "gunJyo" },
  "Monty" => { us: 26, source: "self-measured" }
}.freeze

# CAPABILITY -- what the guest can do at all.
#
# The four system columns (files/net/proc/conc) stay in even though every in-process
# option scores zero on them: they are what the audience is picturing when it uses
# Docker as its yardstick, and dropping them for "no discriminating power" leaves the
# anchors barely above kobako, which reads as wrong to anyone watching.
#
# host = can the guest call the host's existing objects directly. The container
# options score 0 not because they are weak but because they are a different process:
# you have to build and serialise an API yourself. This is the only column here that
# does not correlate with speed.
CAPABILITY_COLUMNS = %i[language klass stdlib import files net proc conc time memory host].freeze
CAPABILITY = {
  "Docker" => { language: 1, klass: 1, stdlib: 1, import: 1, files: 1, net: 1, proc: 1, conc: 1,
                time: 1, memory: 1, host: 0 },
  # Hosted, so the sandbox lifetime is capped by the plan rather than by the embedder.
  "E2B" => { language: 1, klass: 1, stdlib: 1, import: 1, files: 1, net: 1, proc: 1, conc: 1,
             time: 0.5, memory: 1, host: 0 },
  "Lambda" => { language: 1, klass: 1, stdlib: 1, import: 1, files: 0.5, net: 1, proc: 1, conc: 1,
                time: 0.5, memory: 1, host: 0 },
  # 5 min CPU and 128 MB per isolate are platform constants, hence 0 on both limits.
  "Cloudflare" => { language: 1, klass: 1, stdlib: 0.5, import: 0.5, files: 0, net: 0.5, proc: 0,
                    conc: 0, time: 0, memory: 0, host: 0.75 },
  # timeout and memory_limit are host-set with no platform ceiling, hence 1 on both.
  # kobako's stdlib 0.5 against Monty's 0.25 is one yardstick -- how much of a working
  # standard library the guest actually has. A first pass scored Monty against CPython
  # and kobako against CRuby, which flattered Monty.
  "kobako" => { language: 0.5, klass: 1, stdlib: 0.5, import: 0, files: 0, net: 0, proc: 0,
                conc: 0, time: 1, memory: 1, host: 1 },
  "Monty" => { language: 0, klass: 0, stdlib: 0.25, import: 0, files: 0, net: 0, proc: 0,
               conc: 0, time: 1, memory: 1, host: 0.5 }
}.freeze

# ISOLATION -- four axes borrowed from the 2026 AI-code-sandbox comparative study
# (arXiv 2606.08433), keeping the ones decidable from architecture. Its other two --
# escape CVE history and fuzzing posture -- need a per-runtime audit we have not done,
# so they are absent rather than guessed.
#
#   klass    engine class. The paper's own finding is that classes "separate cleanly
#            on every architectural axis, but products within a class do not", so this
#            is the column that carries the real difference and it is weighted x3:
#            microVM 1 (guest kernel + hypervisor to escape) > OCI container 0.5
#            (shared kernel) > in-process memory boundary 0.25 (Wasm, V8 isolate --
#            an escape lands inside the host process) > 0 (no memory boundary).
#   surface  host attack surface: how much host interface the boundary exposes.
#            microVM is virtio plus KVM; a container is the entire syscall table.
#   stack    defense-in-depth stackability: whether further layers (seccomp, userns,
#            cap-drop, or an outer VM) can sit under or over this engine. Scored
#            regardless of who adds them, so a hosted service gets credit for the
#            layers its vendor already runs.
#   ambient  ambient authority, from the object-capability literature: what the guest
#            can reach without being granted anything.
#
# ⚠ The paper explicitly declines to combine its axes into one ranking, because
#   operators weight them differently. A slide needs one Y, so this sum IS that
#   forbidden combination -- the per-column scores above are the honest artefact and
#   the total is a presentation device.
#
# Cloudflare is scored as the hosted service, which is what the audience pictures.
# Self-hosted workerd is weaker: its own README says it "does not contain suitable
# defense-in-depth against the possibility of implementation bugs" and tells you to
# add a VM.
#
# kobako's klass = 0.25 is the honest weak spot: it runs inside your process, so a
# wasmtime escape lands directly in your Ruby application, whereas escaping a
# container still leaves an attacker facing the kernel.
ISOLATION_COLUMNS = %i[klass surface stack ambient].freeze
# The only weighting in either audit, and it is here because the paper's finding is
# that the class boundary is the one that actually separates: without it, an engine
# with no memory boundary at all outscores a container on the three softer columns.
ISOLATION_WEIGHTS = { klass: 3 }.freeze
ISOLATION = {
  # Default docker run has the network up, a full filesystem and the environment in
  # place; the isolation has to be configured on (--network none, --cap-drop, ...).
  # It is not zero, though: there is a default seccomp profile and some caps dropped.
  "Docker" => { klass: 0.5, surface: 0.25, stack: 1, ambient: 0.25 },
  "E2B" => { klass: 1, surface: 1, stack: 1, ambient: 0 },
  # Ambient authority includes the IAM credentials handed to every invocation.
  "Lambda" => { klass: 1, surface: 1, stack: 1, ambient: 0 },
  # A sandboxed Worker has fetch/connect denied outright, but V8 is a large JIT.
  "Cloudflare" => { klass: 0.25, surface: 0.5, stack: 1, ambient: 1 },
  # hermetic profile denies even ambient clock and entropy; the guest reaches nothing
  # that was not bound. Surface is wasmtime plus a Transport wire, not a syscall table.
  "kobako" => { klass: 0.25, surface: 0.75, stack: 1, ambient: 1 },
  # No memory boundary at all: third-party review states it cannot be the sole sandbox
  # because it has no OS-level isolation or memory boundary.
  "Monty" => { klass: 0, surface: 0.75, stack: 1, ambient: 1 }
}.freeze

# Every mark carries a name so that a slide's `steps` can point at it without repeating
# the label, which is free to be reworded.
def slug(label) = label.downcase.gsub(/[^a-z0-9]+/, "-")

def totals_for(table, columns, weights = {})
  table.to_h { |label, scores| [label, columns.sum { |c| scores[c] * weights.fetch(c, 1) }] }
end

def coordinates(totals)
  logs = SPEED.to_h { |label, d| [label, Math.log10(d[:us])] }
  slowest = logs.values.max
  fastest = logs.values.min
  best = totals.values.max
  worst = totals.values.min

  raw = SPEED.map do |label, data|
    u = (slowest - logs[label]) / (slowest - fastest) # 0 at the slowest, 1 at the fastest
    {
      label: label,
      x: X_RANGE[0] + (1 - ((1 - u)**SPREAD)) * (X_RANGE[1] - X_RANGE[0]),
      y: Y_RANGE[0] + ((totals[label] - worst) / (best - worst)) * (Y_RANGE[1] - Y_RANGE[0]),
      tone: data[:tone]
    }.compact
  end

  # Options that are genuinely alike land on top of each other -- the container three
  # are within 20% on speed and within one point on capability, which is the finding,
  # not a defect. Their labels still have to be legible, so points sharing a column
  # are spread to MIN_GAP around their own centre. Order and grouping survive; only
  # the spacing inside a cluster stops being proportional. Ties break towards the
  # smaller attack surface, so the ordering is stated rather than left to sort order.
  raw.sort_by { |p| p[:x] }.slice_when { |a, b| (b[:x] - a[:x]) > SAME_COLUMN }.each do |cluster|
    next if cluster.size < 2

    ordered = cluster.sort_by { |p| [-p[:y], -ISOLATION[p[:label]][:surface]] }
    ordered.each_cons(2) { |above, below| below[:y] = [below[:y], above[:y] - MIN_GAP].min }

    # Pushing down can run off the bottom; lift the whole cluster back inside, which
    # only moves points that were already displaced.
    underflow = Y_RANGE[0] - ordered.last[:y]
    if underflow.positive?
      headroom = Y_RANGE[1] - ordered.first[:y]
      ordered.each { |p| p[:y] += [underflow, headroom].min }
    end
  end

  raw.map { |p| p.merge(x: p[:x].round, y: p[:y].round) }
end

def report(title, table, columns, weights = {})
  totals = totals_for(table, columns, weights)
  points = coordinates(totals)

  puts "== #{title}"
  puts format("%-11s %s  total   x    y    source", "",
              columns.map { |c| "#{c.to_s[0, 4]}#{weights[c] ? "x#{weights[c]}" : ""}".rjust(7) }.join)
  SPEED.each_key do |label|
    point = points.find { |q| q[:label] == label }
    puts format("%-11s %s %6.2f  %-4d %-4d %s",
                label, columns.map { |c| format("%7g", table[label][c]) }.join,
                totals[label], point[:x], point[:y], SPEED[label][:source])
  end
  puts
  points.each do |p|
    tone = p[:tone] ? " tone=\"#{p[:tone]}\"" : ""
    puts %(  <Point name="#{slug(p[:label])}" :x="#{p[:x]}" :y="#{p[:y]}"#{tone}>#{p[:label]}</Point>)
  end
  puts
end

puts "SPREAD=#{SPREAD} (1.0 = plain log axis)\n\n"
report("The Balance -- Y = capability", CAPABILITY, CAPABILITY_COLUMNS)
report("Isolation -- Y = what the boundary is made of", ISOLATION, ISOLATION_COLUMNS, ISOLATION_WEIGHTS)
