# Bounded performance baseline

Run `tools/perf/run.sh > build/perf.log` from any directory (create `build/`
first). Set `GODOT=/absolute/path/to/godot` to bypass wrappers that override XDG.
Requires Godot 4.7.2 and GNU `timeout`. Each run creates and removes fresh XDG
user/config/cache directories and an explicit temporary solver cache, imports
once, and bounds each engine process to 120 seconds. Never uses normal saves
or `build/solver-cache`. The project import cache remains local to the checkout;
use a separate worktree when comparing branches. The runner prints the commit,
engine, CPU, OS and cgroup CPU quota. `PERF {…}` lines are JSON records; times
are microseconds except the explicitly named `timing_ms` field.

The two ASCII fixtures are sealed 32×18 and 64×18 floors with a spawn. Their
only generated edit adds a two-cell shelf. The quick run compares public report summary fields (errors, warnings, reached/total ledges, needs, pickups)
for uncached/cold/warm and edited cached/uncached solves. Mismatch or a supposedly
cold cache hit fails. The run doubles as its focused regression check. It does
not replace the gameplay tests or full validation gate.

The authored-world census parses but does **not** traverse the world. It counts
phase/body/ledge/start-position inputs and scheduled ground/air plans using a
standalone subclass that suppresses the simulation boundary. These are intact
geometry scheduling counts, not measured full-traversal simulation totals:
landings, progression rounds, wall variants and Imprint can add work. It also
measures 600 mover ticks, 20 `solver_variant().all_solids()` rebuilds, and 3000
worst-case missing-wall queries through the same `Room.wall_at` boundary Tongue
Lash uses. This excludes the tongue animation and other collision checks.
The bounded room-12 sample runs one real jump at each phase from the first
ledge; it is a reproducibility probe, not a representative runtime estimate.
Cache size is reported as ticks and body samples, not estimated heap bytes.

Full-world `tools/validate.sh --no-cache` remains a separate, intentionally
expensive task. Coordinate it with other workers. Do not infer equivalent world
answers or a speedup from the census or the tiny fixtures. No CI time budget is
introduced here.

## Baseline, 2026-11-02

Measured parent `ef06486acbd1504415d32596a53d1fd19f6e6f9d`, official Godot
4.7.2 `ed1daf0bf`, Linux x86_64, AMD EPYC 9V74, 3 visible processors, cgroup
quota `200000 100000` (2 CPU equivalents), shared with correctness workers.
Three isolated runs passed equivalence. Observed cold validation ranges were
124–285 ms (32 cells, 288 plans) and 241–680 ms (64 cells, 576 plans); warm
ranges were 1.315–1.335 ms and 2.442–9.672 ms, respectively. These are a small
shared-machine distribution, not thresholds. In the final run, edge simulation
took 123 of 124 ms and 235 of 241 ms cold: it dominates these fixtures.
Twenty parses took 32/99 ms, twenty scene builds 0.56/0.64 ms, and 3000 stationary
physics steps over four rectangles took 20/53 ms (32/64 widths). Timing noise
is material; counts are the useful stable comparison.

| Intact room | Ground scheduled plans | Ground + air scheduled plans | Phases | Bodies |
| --- | ---: | ---: | ---: | ---: |
| 7 | 15,700 | 47,200 | 25 | 1 |
| 12 | 33,808 | 99,376 | 40 | 23 |

Room 12 stores 13,800 body samples at 600 cached ticks. It has two breakable
walls (four possible subsets before reachability filtering); the solver caps
wall states at 16. Room 12's final-run geometry rebuild batch took 0.19 ms,
600 mover ticks 19 ms, and 3000 wall misses about 50 ms. Forty sampled real
plans took 4 ms, illustrating why multiplying a hand-picked plan time by the
scheduler count would be misleading.

The census identifies a concrete scaling mechanism behind the reported >600 s
world solve: tens of thousands of plans per moving-room geometry, multiplied
by phase sampling, air plans and reachable wall variants, with up to 23 bodies
queried each physics tick. It does **not** establish which room dominates that
full run or how much time Imprint consumes. Next instrumentation should count
actual simulated ticks and plans by room/variant/progression round, and preserve
existing Imprint timing/candidate counters in a coordinated full-world run.
Prioritize broad-phase/body-query costs and redundant plan/variant work after
that attribution; parse/build optimization is unsupported by this evidence.

Validation: three fresh-cache runs passed. A warm-answer corruption mutant
(appending a suffix before equivalence comparison) exited 1 with `PERF equivalence
FAIL`; the mutation was reverted. No runtime behavior or drawings changed.
The full `tools/check.sh` gate is delegated to coordinated integration, because
its world solve exceeds the bounded profiling workload. Raw observations for
all three runs are in `baseline.jsonl`; only run 3 includes the real-plan probe.
