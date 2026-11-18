# Faster room iteration and solver execution

Status: implementation specification; no gameplay or solver changes implemented.

Prepared 2026-11-16 against commit `b2bf4c1d7e11dbcabb87f2774e4dacb1bc0cc05e`.
Reconcile this specification with the current branch before implementation. The
README, AGENTS.md, and current game design remain authoritative for behavior.

## 1. Objective and approved direction

The author draws a room on graph paper, gives an agent a photograph, reviews the
translated render, requests adjustments, and eventually approves the room. New
large rooms currently take tens of minutes or longer to validate. Optimize this
workflow without asking the author to draw smaller rooms or simplifying mechanics.

Implement these improvements in order:

1. Geometry-only previews and an explicit path to local play before validation.
2. Measured performance baselines and stronger equivalence checks.
3. Exact, deterministic simulation batches shared by serial and parallel execution.
4. Resumable, bounded, multiprocess execution of those batches.
5. Profile-guided removal of duplicate work and expensive hot spots.

Prepare the work boundaries for possible tongue attachment to moving and spinning
platforms. Do not implement that mechanic in this project. Its gameplay rules are
not yet decided, and current content must not depend on it.

The final validation gate remains mandatory before a room PR is ready. A preview,
successful web export, completed batch, and validated world are different outcomes.
Never report one as another.

## 2. Findings that motivate the design

These observations are from repository code and existing logs, not a fresh timed
benchmark. Historical logs can reflect different room versions and machine load.

- `tests/render.gd::_initialize` calls `graph.solve(data.start_room)` before
  filtering the requested room IDs. It reads the committed cache but does not
  save newly computed answers. Rendering a changed room can therefore perform a
  full solve and leave validation to repeat expensive work.
- `tools/validate.sh` defaults to `jobs=1`. Only an explicit `--jobs` enables the
  current process-based warm-up. `tools/check.sh` does pass the machine's cores.
- `tools/check.sh --quick` does not reduce search work. It changes stale-cache
  enforcement, not the solver's coverage.
- `tests/lib/cache_warm.gd` has four part types: `jumps0`, `jumps1`, `climb0`, and
  `climb1`. Jump pieces cover a room and its wall variants. Climb pieces cover one
  room variant and one ability signature. These pieces are still very large.
- `build/rewarm.log` records room 19 `jumps1` at 4549.0 seconds, room 18 `climb1`
  at 5885.6 seconds, and room 19 `climb1` at 6029.4 seconds. These are individual
  durations during parallel execution, not additive wall-clock measurements.
- The same log records a subsequent solve at 512.5 seconds with some uncached
  work. `build/final2.log` records a later solve at 50.3 seconds with no ground
  edge rooms recomputed. Do not label either number a current baseline.
- `ReachGraph` already reuses mover-free trajectories across phases and some
  trajectories across static broken-wall variants. `Movers` already caches tick
  geometry and indexes spinner scanlines by row. Do not propose these existing
  optimizations as new work.
- Fingerprints invalidate an entire room's results when its solver inputs
  change. The committed cache makes unchanged rooms cheap, but does not solve
  the first-build problem.
- `CacheWarm.plan` currently treats the existence of a climb signature as enough
  to omit that piece. This is not a safe completeness rule for new partial
  checkpoints. Explicit completion accounting is required.
- `ClimbMoves.Store.sampled` and ceiling hang positions use first encounter
  semantics. `Ledge.add_touch` also retains the first touch for its rounded key.
  Completion-order merging can change the graph even if all physics runs match.

## 3. Scope, non-goals, and rules that cannot change

### In scope

- Preview CLI, render outputs, validation CLI, scheduling, diagnostics, checkpoints.
- Refactoring solver plan generation and result application without changing the
  sampled plans, their order, their simulation, or their semantic outputs.
- Cache integrity and equivalence tests needed for partial and parallel work.
- Targeted optimizations demonstrated by profiles and parity checks.
- README, AGENTS.md, design implementation reference/decision log, and testing
  checklist updates in the PR that changes the corresponding workflow.

### Explicitly deferred

- Moving/spinning tongue attachment gameplay and its runtime/dev controls.
- Reusing results across arbitrary edits within a room.
- Coarser search, adaptive sample density, budgeted approximate validation.
- Native/C++/Rust physics rewrites, new engine builds, distributed/cloud workers.
- Threaded GDScript simulation, automatic publishing, changing room geometry.
- Reducing required ledge, progression, trap, pickup, or door validation.

### Invariants

1. `MovementSim` remains the sole movement implementation. Solver orchestration
   cannot copy movement equations or depend on scene/autoload state.
2. Preserve `HOLDS`, air-jump samples, climb phases, sample intervals, frame limits,
   collision order, hazard handling, and existing conservative limitations.
3. A door still enters the destination room with its ordinary unbroken state.
   Preserve broken-wall and broken-spinner-arm semantics and stable entity IDs.
4. Preserve progression and ability signatures, including Tongue Climb's `also`
   upgrade values. Never substitute a dev loadout for world progression.
5. No result may be used for different room geometry, abilities, solver code,
   plan semantics, or input snapshot. Stale work is discarded, not blessed.
6. Preview/build/solver tooling must never read or modify the player's normal save.
7. The release web game remains a single-threaded static-hostable export. Python
   and worker processes are authoring tools, not browser runtime dependencies.
8. Fully completed results are independent of worker count, scheduling, restarts,
   and whether the cache started cold or warm.

## 4. Author-facing command contract

Flags in this section are proposed new interfaces, not commands that exist today.
Implement and document their parsing; do not silently pass unknown options through.

### Preview

`tools/render.sh --preview 18`

- Import as required, load the real world using the existing loader, and perform
  its structural checks. Do not construct a ReachGraph or SolverCache in this mode.
- Render the selected room geometry, entities, tracks, door alignment, and existing
  structural markings. Do not draw unreachable/trap/needs overlays.
- Output `build/renders/room_18_preview.png`, with a visible label
  `PREVIEW - REACHABILITY NOT CHECKED`. Use a small tool-only label renderer with
  the existing font if needed; `DIGITS` currently cannot render that sentence.
- Print the output path, selected room, loader errors, and validation status.
- No IDs means all room previews and `world_preview.png`. Unknown room IDs and
  unknown flags exit 2. Loader errors exit 1; they must not say preview passed.
- Valid geometry preview exits 0, meaning only structural loading/rendering passed.
- Do not read, write, refresh, or invalidate committed solver cache files.
- Preserve the existing default analyzed-render behavior initially for compatibility.
  Warn before its solve that it can be expensive and advertise `--preview`.
  Make existing analyzed mode save successfully computed cache entries via the
  same checked persistence boundary as validation; never save partial worker data
  as complete. Until that boundary exists, use explicit validation before an
  analyzed render rather than adding a second cache writer implementation.

Extract argument handling and rendering entry points sufficiently to test that
preview never invokes analysis. Preserve the existing geometry drawing; the
status strip and output filename distinguish preview from analyzed output.

### Local play before validation

Existing `tools/build_web.sh` followed by `tools/serve.sh` produces a local build
without invoking validation. Document the URL `?dev=1&room=18` for isolated tests.
Do not have the agent play the game or record video unless requested. The author
can play while the validation job is pending. Build success is not room approval.

### Validation and warm-up

- `tools/validate.sh`: full world validation, using cache and a bounded automatic
  worker count for missing work, then the normal progression/reporting pass.
- `tools/validate.sh --jobs N`: explicit positive worker limit. CLI takes
  precedence over `JOBS`; `JOBS` takes precedence over the automatic default.
- Initial automatic default: `min(4, detected logical cores)`, at least 1.
  Keep this conservative until measured worker memory justifies raising it.
  Report detected cores, chosen workers, and override instructions.
- `tools/validate.sh --jobs 1`: same job path and output semantics, one worker.
- `tools/validate.sh --warm-only --rooms 18,19`: prepare those rooms' required
  local cache pieces, including wall variants; no claim of world validity.
  This is for debugging/benchmarks. Ordinary validation still checks the world.
- `--fresh`: use an isolated new completed-cache directory and ignore completed
  cache and checkpoints from prior runs. Print its location. Never delete another
  active run's directory. This is a clean benchmark/correctness run.
- `--resume RUN_DIR`: explicitly resume a prior compatible run. Reject pairing
  with `--fresh`. Ordinary runs may automatically reuse compatible checkpoints.
- `--no-cache`: preserve a serial reference mode that reads/writes neither
  committed cache nor resumable results. It is intentionally slow and useful for
  parity. Do not quietly turn it into cached parallel warm-up.
- `--strict-ledges` and `--dump=PATH` keep their existing meaning.
- Provide `--help`, reject invalid values before launching Godot, and handle paths
  with spaces. Use Python argument arrays for subprocesses, never `shell=True`.

Do not add a room filter that calls a partial world solve and labels it full
validation. Cross-room doors, resources, progression, and traps still need the
world pass.

### Build gate

`tools/check.sh` keeps import, tests, strict validation, export, and integrity
checks. Its `JOBS` limit must also govern validation; the current script uses
`CORES` there instead. Do not run a test pool and solver pool simultaneously.
Keep `--quick` backward compatible but describe it accurately. Fix the final
message that currently says "uncached" even for cached validation.

### Required room-authoring sequence

Update root AGENTS.md's drawing workflow to explicitly allow this order:

1. Translate photograph, document scale/rounding/assumptions, load structurally.
2. Produce geometry preview and translation report immediately.
3. Let the author approve or revise geometry; mark validation pending.
4. Optionally build a local isolated playtest for the author.
5. Validate approved geometry. Preserve the existing at-most-two-cell nudge rule;
   larger changes remain a question. Re-render/report every changed judgment.
6. Run final gates and provide analyzed renders/validation results.
7. Commit room content only after the user's approval, one room per commit.

Preview approval does not authorize silently changing the drawing to satisfy the
solver. An edit while validation runs makes the old run stale for the edited input.

## 5. Baseline and observability before optimization

Create a benchmark runner under `tools/` using Python's standard library and a
small GDScript entry under `tests/lib/`. Keep machine-readable reports in
`build/solver-bench/<run-id>/`; never overwrite the previous measurements.

Record commit, dirty-input hashes, Godot version, OS, CPU/core count, worker count,
cache mode, room fingerprints, solver fingerprint, elapsed wall time, sum of
worker CPU time where available, peak memory with units/source, and output hashes.
Unsupported resource measurements should be `unavailable`, not a made-up zero.

Measure these separate cases:

- Structurally valid room preview after import.
- Fully warm whole-world validation.
- Room 18 cold preparation with every variant and required ability signature.
- Room 19 cold preparation with every variant and required ability signature.
- Both rooms cold together; remaining rooms may have valid completed cache.
- A small synthetic world containing a mover, ceiling hang, wall hang, air jump,
  pickup, door, and breakable. Run this frequently during implementation.

Collect old and new results on the same machine, same room version, and same
engine. Do not compare a lone serial run to historical jobs contending with many
other processes. Run expensive baselines once initially; repeat only where needed
to resolve noise or compare a final candidate. Archive baseline dumps and logs.

Instrument by room variant, ability signature, and stage:

- Ground/air plan enumeration; actual simulation calls and frames.
- Static and rider entry discovery; wall/ceiling departure simulation.
- Breakable follow-up simulation and variant preparation.
- Graph aggregation, door landing, progression, and `needs` reporting.
- Completed-cache hits, checkpoint hits, mover-free reuse, wall-state reuse.
- Worker startup, work, idle time, serialization, and coordinator application.
- Maximum batch duration, outstanding result bytes, and checkpoint bytes.

Do not time every physics tick in the production path. Use counters or sampled
profiling; report instrumentation overhead. Existing `_room_plans` counts attempts,
not necessarily actual `MovementSim.run` calls, so keep these metrics distinct.
Do not overwrite cold-cost scheduling history with warm-cache milliseconds as the
current `build/room-times.json` approach can do. Store cold costs by compatible
signature, with sample counts and separate cache-hit measurements.

## 6. Architecture: deterministic control, parallel physics

### Responsibilities

- `ReachGraph` and `ClimbMoves` retain graph construction, progression, discovery,
  ordering, and interpretation of results.
- A small pure batch layer describes exact simulation requests, runs them using
  `MovementSim.run`, and returns raw results. It supports an in-process executor
  by default, so pure tests need no worker infrastructure.
- A tool-only GDScript controller supplies an external executor during warm-up.
  Pure solver classes receive an interface/callable; they do not read files,
  spawn processes, poll a directory, or reference autoloads themselves.
- A Python supervisor manages persistent headless Godot workers, bounded queues,
  process failures, run locks, checkpoints, and progress.
- Only the deterministic controller applies results to ledges/hangs and creates
  complete cache entries. Workers never mutate the shared graph or committed cache.

Suggested files, to be adjusted only when existing structure clearly fits better:

- `src/world/solver/simulation_request.gd`: typed request fields and identity.
- `src/world/solver/simulation_batch.gd`: pure enumeration/result contract and
  in-process execution; no operating-system dependencies.
- `tests/lib/solver_worker.gd`: persistent headless physics worker.
- `tests/lib/solver_controller.gd`: tool adapter for external batch execution.
- `tools/solver_jobs.py`: standard-library supervisor and checkpoint handling.
- `tests/solver_batch_test.gd`, `tests/solver_checkpoint_test.gd`: semantic tests.
- `tests/tools/solver_jobs_test.py`: supervisor lifecycle tests, explicitly wired
  into `tools/check.sh` because `tests/*_test.gd` discovery will not run Python.

Do not create a general task framework, network service, database, or second
progression solver. These modules serve this solver's current plan execution.

### Safe unit of parallelism

Use batches of independent trajectory requests, not whole transitive climb
searches. Long ledges and individual moving ledges must be splittable; a single
ledge must not recreate the hour-long-job problem.

Each request has an ordinal within its current ordered scope. Workers may finish
in any order; the controller applies results in the original ordinal order.
Batch boundaries and worker count cannot alter ordinals or final first winners.

Start with 64 simulation requests per batch and at most two pending batches per
worker. Profile and adjust the default to target roughly 0.25–2 seconds of work
per ordinary batch without unbounded buffers. These are tuning targets, not
claims about current performance. Group requests that share geometry to amortize
setup and preserve per-worker mover geometry caches.

Keep dependencies between semantic scopes. Ground preparation must precede a
climb scope that requires it. A room's climb scopes may begin when that room's
prerequisites are complete; do not wait for all rooms to finish ground work.
Limit the total number of active physics workers globally. Controller processes
must not spawn private pools that multiply the configured worker budget.

### Extract plan generation without changing plans

Refactor in small steps, first using only the in-process executor:

1. Separate `ReachGraph.try_plan` into request construction, simulation/reuse, and
   result application. Preserve the public wrapper while callers migrate.
2. Preserve every `JumpPlan` field, exact start coordinates, selected solid rects
   and their order, collection/trigger rects, start tick, rider body, and frame cap.
3. Make `_ensure_edges`, `_ensure_air_edges`, `_ride`, `_ride_air`, and walk-off
   helpers enumerate the same requests in their current nested-loop order.
4. The ordered reducer continues calling the existing ledge methods. Do not
   pre-deduplicate touches independently in each worker and union them later.
5. Preserve `_free_runs`, `_records`, `_reusing`, and `reuse_margin` semantics.
   Reuse decisions may be controller-owned. Do not discard existing wall-state
   reuse just because requests now run in other processes.
6. Keep broken spinner arms excluded from static-wall plan reuse.

### Climb discovery is an ordered, incremental process

The earlier recommendation to separate discovery from departures does NOT mean
that all hangs can be discovered up front without simulation. Ceiling paths and
rider trajectories discover more hangs. Implement an incremental separation:

1. Controller visits ledges in the existing order and obtains entry hangs.
2. For a rider, workers simulate the ordered rider trajectories. Return raw
   positions/results; controller applies the existing rising-only sampling,
   hazard cutoff, `seen` handling, `_unsafe`, and `_stick` in reference order.
3. Controller follows the existing `pop_back` depth-first expansion order.
4. For the next hang, controller constructs its departure trajectory batches.
   Workers run those independent physics requests concurrently.
5. Controller replays results/samples in the exact order used by `_from_ceiling`,
   `_sample`, `_jump_from`, and `_break_from`; it alone mutates `Store.sampled`,
   `Store.sticks`, `Store.hangs`, links, and ledge result collections.
6. Newly discovered hangs enter the existing ordered traversal. Repeat to closure.

This preserves the first position chosen for a ceiling cell, including failed
first samples cached as `[]`. A later successful point cannot replace an earlier
failed representative merely because a worker returned first.

When a scope is too small to amortize IPC, run it in-process. When multiple room
or ability scopes are ready, the supervisor can interleave their independent
batches. Do not speculatively expand uncommitted hangs with worker-local stores.

Do not serialize a complete `Store` or cyclic `Hang.links` graph. Journal pure
requests/results and replay discovery deterministically on restart. Restart can
redo inexpensive traversal while reusing expensive completed simulations.

## 7. Request identity, serialization, and worker lifecycle

### Identity

A work identity covers:

- Work protocol version and algorithm version.
- Solver fingerprint, immutable input snapshot digest, room variant fingerprint.
- Room ID and explicit ordered broken IDs; ability values/signature.
- Stage and semantic origin (ledge geometry/ID or hang key plus exact position).
- Full simulation settings, start tick, rider identity, and geometry selection.
- Ordered request range and digest of its contents.

Use stable content identity, not `get_instance_id`, PID, timestamps, or worker
number. A ledge index is valid only within its matching fingerprinted geometry;
verify its geometric descriptor when decoding it. Mover body indexes must be
checked against the stable mover/entity ID and local body number.

Represent optional values explicitly. Current APIs use NAN and INF sentinels;
JSON cannot reliably round-trip them. Encode `top: null` for default top and an
explicit boolean/value pair for optional input switching, then reconstruct the
original values. Do not round physics coordinates for keys. Test numeric
round-tripping to the precision of the project's Godot build.

### Immutable inputs

At run start, create a manifest of all solver-consumed code/configuration and the
loaded world inputs, including world layout, room files and upgrades. The scope
digest must cover anything used by the controller, even if an existing room cache
fingerprint intentionally omits it. Cache-independent worker requests still need
the complete relevant simulation configuration.

Workers must evaluate one immutable input version. Prefer an isolated tool input
snapshot or immutable serialized room/config payloads plus a fixed code snapshot;
do not start later workers against newly edited source while earlier workers use
old loaded scripts. Do not copy the entire `.git`, build, saves, or export tree.
Import a copied project once before launching workers if a code snapshot is used.
Validate snapshot export excludes and tests; it is not a shipped game asset.

Before promoting results to the live completed cache, recheck live fingerprints.
If the author edited relevant inputs, retain the old run for diagnostics/reuse
only under its old identity and report `stale input; rerun required`. Do not
silently validate a mixture of old/new files or overwrite the new room's cache.

### Transport and process management

Use a local file-spool protocol initially; no network ports or browser APIs.
The supervisor is the sole dispatcher. It writes atomically renamed request
files into per-worker inboxes. Workers poll only their inbox and atomically write
result envelopes to their outboxes. Poll at a modest interval (e.g. 25 ms), with
long-lived processes to avoid importing/starting Godot per batch.

Workers load immutable geometry once per bounded set of room contexts and retain
mover geometry caches. Evict contexts rather than retaining the whole world per
worker indefinitely. Confirm no mutable simulation state leaks between requests;
in particular inspect `Movers._broken` and replacement/cache invalidation. Each
run must begin with the same semantic mover state as the reference execution.

Every result includes request ID, content digest, status, ordered result count,
timings, and output checksum. Missing, truncated, mismatched, duplicate-conflicting,
or nonfinite data is rejected before application. A duplicate identical result
is harmless. Conflicting results for the same identity are an error, never
"first writer wins".

The supervisor tracks child PIDs directly. On Ctrl-C/SIGTERM, stop dispatching,
preserve completed valid work, request worker shutdown, then terminate/kill only
owned workers after a bounded grace period. Never `pkill godot`.
Detect worker exit immediately and detect a stalled batch by heartbeat/deadline;
retry at most once in a fresh worker, then exit nonzero with the batch ID and log.
Do not turn an internal error into an unreachable ledge or successful validation.

Use unique run directories and a lock for each run. Concurrent independent runs
may coexist. Completed-cache publication must use a lock too; a second publisher
waits with a visible message or exits with a clear conflict. Never delete shared
`build/warm-*` directories while another run is active.

## 8. Checkpoints and completed cache

Keep two different stores:

- `build/solver-work/<input-digest>/<run-id>/`: local resumable requests, results,
  journal, timing data, logs. Gitignored and excluded from the web export.
- `data/solver-cache/`: verified completed semantic results, committed with content
  or solver changes as today. No raw paths, process state, or partial job files.

Write each checkpoint to a temporary sibling, close it, and atomically rename.
Include checksums and protocol version. Ignore abandoned temporary files. The
controller can regenerate requests and load matching completed results on resume;
checkpoint identity must not depend solely on a previous batch size.

Cache publication requirements:

1. Explicit completeness for every required movement/climb signature, including
   the valid case of zero hangs. A nonempty signature dictionary is not proof.
2. Every expected result was received and applied in canonical order.
3. All dynamically discovered climb work reached closure; no pending hang/batch.
4. Output refers only to existing ledges, entities, room variants, and valid data.
5. Source fingerprints still match the snapshot before promotion.
6. Write files atomically; publication failure must fail validation visibly.
7. Existing valid completed pieces must survive an unrelated interrupted piece.

Bump `SolverCache.FORMAT` when adding completeness metadata or changing its schema.
Do not migrate partial legacy climb dictionaries into "complete" by assumption.
Regenerate affected caches. Centralize what makes a piece complete so the planner,
reader, writer, merge, and tests agree. Runtime graph code may still calculate a
missing entry normally, but warm-up must not claim completion while anything it
promised is missing.

Keep the current conservative fingerprints. New pure code that influences results
belongs in `SOLVER_FILES` and its closure tests. Tool-only scheduling code does not
need to invalidate completed semantic results when scheduling changes, but its
protocol/semantic request interpretation must invalidate incompatible checkpoints.
Never remove an existing fingerprint dependency merely to avoid an expensive run.

When the final world solve computes missing work for an unexpected signature,
report it with the signature and count. Continue correctly; do not suppress it.
Extend preparation coverage using the real upgrade application semantics, not a
hard-coded list of guessed tongue lengths. Retain a test for the current
`tongue_climb` upgrade's `also` values and both air-jump states.

## 9. Profile-guided optimizations after exact batching

Implement only measured candidates, one at a time, retaining old/new results.
Do not claim the project complete just because CPU utilization increased.

### Candidate A: share genuinely identical trajectories

`_from_ceiling` calls `try_plan` and `_sample` for related trajectories. They are
NOT automatically the same request: `try_plan` supplies door triggers and pickup
collection; `_sample` currently does not. A door may terminate one sooner.

First add a regression with a door intersecting the sampled path. Reuse only when
all termination and simulation inputs match. Otherwise keep both or design a
separately tested richer run-result contract that exactly reconstructs both old
outcomes. Do not let a "single run" optimization silently truncate tongue samples.
Reuse mover-free probes across phases where existing semantics allow it. Include
recording mode, hang direction/time, frame caps, and geometry in reuse identity.

### Candidate B: reduce collision/allocation overhead

Profile `MovementSim.run/step`, `Movers.rects_near/hazards_near`, spinner geometry,
and static collision filtering. Existing spinner row indexing stays. Candidate
improvements are cheaper reusable buffers or a safe broad phase for plain/static
rects, only if measured. Any filtered candidate list must preserve collision
iteration order and all corner-correction/probe margins. Include high speeds,
scraping, spinner slopes, pushing, crushing, and breakable transitions in parity.

### Candidate C: reuse trajectory prefixes

Treat this as later optional work. A prefix snapshot needs complete simulator
state, accumulated bounds/collection/hazard/airborne state, tick, and relevant
mover state—not just position and velocity. Only proceed if profiles show enough
benefit to justify a new resumable simulation contract. Keep existing `run` as a
reference and verify every existing termination rule. Do not implement it merely
because it sounds faster.

Defer cross-edit room-local invalidation and narrower solver fingerprints. Their
proof burden is larger and moving attachments will change the dependency model.

## 10. Future moving/spinning tongue attachments

This section is an extension contract, not authorization to implement gameplay.

The batch layer must accept explicit initial state and an evolving versioned
request payload. It must not assume that every launch is from a stationary ledge,
that every hang is determined solely by world position, or that all departure
phases are interchangeable. Preserve absolute start ticks in current requests.
Do not persist process-local `Hang` objects as the long-term identity format.

Document the fields a future attachment state will need, without adding unused
ability flags or fake implemented powers today:

- Stable target entity ID and body/subshape identity where needed.
- Attachment point in the target's local coordinates and its face/normal.
- Attachment time, current time, and remaining hold/re-stick/cooldown state.
- Player position, velocity, jump resources, and wall/breakable state.
- Target lifecycle state: emitter instance, despawn, broken arm, hazard exposure.
- Whether release transfers velocity, after the author chooses that behavior.

Important temporal constraint: a route that attaches at tick A and one that
departs at tick B may be joined only if staying attached from A to B is legal.
The current static graph abstracts away some timing. Do not extend that
abstraction unchanged to moving attachments or simply key by `tick % max_period`.
If periodic equivalence is later used, prove it against the joint relevant mover
period and every hold/resource/lifecycle constraint; emitter cycles can distinguish
apparently equal geometric phases.

The future feature should be its own design/PR sequence: author chooses carry and
rotation behavior, upside-down attachment, hold duration, obstruction/crush rules,
release velocity, eligible/spiked surfaces, and target disappearance behavior;
then implement shared simulation and runtime; then explicit solver state/edges;
then permit content to depend on it. Include the full dev catalog, removal/reset,
retry, named-loadout, save-isolation, browser, and parity requirements from AGENTS.md.

For the current work, tests should show that different explicit start ticks and
different rider/target identities cannot collide in request/checkpoint identity.
Do not write tests that claim moving tongue attachment already works.

## 11. Implementation sequence and reviewable PR boundaries

### PR 1 — Preview before solve

Change `tools/render.sh`, `tests/render.gd`, workflow docs, and focused render
tests. Add explicit preview status, separate filenames, strict CLI parsing, and
the revised drawing workflow. Keep solver code/fingerprint unchanged if possible.
Inspect a large-room preview and test cache bytes/mtime remain untouched. Verify
an ordinary local release web build is possible before validation.

Exit criteria: preview does no solve, works with missing/stale cache, preserves
geometry, reports loader failures, and cannot be confused with analyzed results.

### PR 2 — Baselines, diagnostics, and equivalence oracle

Add the benchmark harness and stage counters. Capture old whole-world outputs
before changing algorithm boundaries. Add richer solver dumps for climb behavior,
exact retained door-touch coordinates/velocities, and full report outcomes.
Keep old-checkout compatibility in `solver_diff.sh`: it currently copies current
`tests/validate.gd` into the old tree. New test-runner dependencies could break
that. Use a version-compatible standalone dump adapter or preserve the baseline
runner; do not copy a new worker-dependent runner into an old checkout.

Exit criteria: repeatable baseline artifacts for rooms 18/19, readable timing
breakdown, and comparison that catches changed climb representatives and touches.

### PR 3 — Pure requests and ordered serial batches

Refactor ground, air, and mover trajectories first; then rider/climb/breakable
trajectories. Use an in-process executor only. Keep all discovery order and physics
unchanged. Add typed codecs and round-trip tests. Preserve existing reuse caches.

Exit criteria: semantic dumps match the pre-refactor baseline; serial cache/no-cache
results agree; focused movement/provider tests and required solver diff pass.
Do not introduce worker processes while parity is still failing.

### PR 4 — Persistent workers, replay, and transactional cache completion

Implement supervisor, external executor, bounded batch queues, input snapshot,
checkpoints, cancellation, and explicit completed-piece metadata. Add fine-grained
work for a single large room, not just many rooms. Replace the current copy-an-entire-
cache-per-piece warm-up after equivalence is demonstrated. Retain serial execution.
Wire default workers and correct `JOBS` precedence into validation/check scripts.

Exit criteria: cold serial and parallel semantic dumps match; reversed/shuffled
completion and interrupted/resumed runs match; stale/partial data cannot pass;
an isolated room 19 uses multiple workers; memory/queue limits are measured.

For a smaller implementing model, split this milestone into three dependent PRs
if necessary: 4a worker transport and lifecycle (opt-in, no default change), 4b
checkpoint replay and completion-aware cache schema, 4c default scheduler/CLI
integration and resource tuning. Each must preserve the serial fallback and pass
its own tests; do not enable the new default before 4b's integrity tests pass.

### PR 5 — Measured optimizations and final performance report

Select candidates from section 9 using the profiles. Make each change separable
and reversible. Re-run focused correctness/performance checks after each change.
Record final benchmark comparisons, remaining serial bottlenecks, and recommended
worker count. Complete all documentation and rebuild committed solver cache.

Exit criteria: final exact gates pass, preview and solve targets are measured,
and the PR reports actual gains and any unmet targets. Do not weaken coverage to
hit a timing target. If a candidate offers negligible benefit, omit/revert it and
document the measurement rather than keeping complexity.

All implementation PRs follow repository instructions: branches, no direct main
pushes, required tests/validation, coherent updated docs, and relevant committed
cache files. Never mark an unrun long gate passed. Do not create PR bodies or
commit messages with shell heredoc substitution; use files or short `-m` flags.

## 12. Regression and verification matrix

### Preview and command behavior

- Preview with absent cache and a large room; assert zero simulation calls.
- Stale/corrupt cache does not affect preview, and preview writes no cache files.
- Output label/filename differs; no reachability coloring; geometry matches the
  same renderer with overlays disabled. Inspect produced images, not just exits.
- Unknown ID, malformed room, unknown flag, missing `--jobs` value, zero/negative/
  noninteger worker counts, conflicting flags, paths containing spaces.
- `--warm-only` never emits `validate pass`; `--quick` still runs the full gate.

### Semantic parity

- Cold no-cache reference vs serial batch vs parallel with 1, 2, and 4 workers.
- Reverse and shuffled completion; multiple batch sizes; cache hit/miss mixtures.
- Long ledge, moving ledge, scrape-separated segments, spinner bar and broken arm.
- Static wall hangs, ceiling hangs, ceiling-to-ceiling links, rising rider lashes.
- Both air-jump states, the upgraded tongue length, no lash, no climb, ceiling
  disabled, breakable climbing disabled, and distinct nondefault signatures.
- Same ceiling cell discovered at distinct positions; first failed sample followed
  by a successful sample; discovery of the same hang through two ledges.
- Two door touches with the same rounded key but different exact velocities;
  preserve the winning representative and resulting destination landing.
- Spike/death cutoff and pickup-before-later-death semantics; door termination
  differs from sample-only path; release/drop and maximum supported frame bounds.
- Breakable-wall follow-up into the right variant; doors restore ordinary walls.
- Multi-room progression, optional pickups, token/3TM rules, trap/strict ledges.

Compare complete outputs, not just `validate pass`, counts, or rounded touch keys.
Extend `solver_dump` to include climb stores/representatives where available,
provider-derived transitions and exact retained touch values as well as existing
report/graph fields. Keep a separate ordered event trace for small fixtures where
final set equality would conceal a traversal change. Sort sets for presentation,
but do not hide semantic first-winner values.

### Worker/checkpoint failure injection

- Terminate during computation and during temporary-file write; resume reuses
  completed work and recomputes incomplete work only.
- Worker exits, times out, returns wrong ID/count/checksum or malformed payload.
- Duplicate identical batch accepted once; conflicting duplicate fails.
- Change room, neighbor door, movement values, upgrades, solver code, or protocol
  between runs; stale checkpoint rejected appropriately.
- Source changes while workers run; live cache is not promoted for old inputs.
- Valid zero-hang completion vs partial signature with one hang; planner must
  distinguish both. Missing a dynamically discovered batch prevents completion.
- Two invocations, same run resume lock, different runs, conflicting publication.
- Read-only/full output location; cache publication failure is visible/nonzero.
- Normal save/loadout files untouched; no orphan worker after cancellation.

Use tiny fixture worlds for failure tests so CI does not launch an hour-long solve
to exercise interruption. Isolate each test's files and connect Python tests to
the gate explicitly. Keep tests of the real Godot worker protocol, not only mocks.

### Required project gates

- Relevant individual tests during iteration, especially cache, solver, reach,
  mover, platform, spinner, scrape, tongue climb, tongue reach, and parity.
- `tools/check.sh` before an implementation PR: every test, strict world
  validation, release web build and export integrity.
- `tools/check.sh --fresh` after solver changes, with its actual completion
  recorded. Run the required uncached exact comparison using
  `tools/solver_diff.sh <baseline-ref>` after making its adapter old-version safe.
  An empty diff is required for these exact optimizations. Also compare the new
  parallel dump against the serial reference; existing solver_diff is serial.
- `tools/pixel_check.sh` for drawing changes, including preview changes as required
  by project guidance; do not update gameplay baselines for a tool status label.
- Serve the release export in an ordinary browser window; verify load, keyboard
  focus/input, resize/scaling, dev entry, pause/overlays and static assets. The
  automated export/headless pass alone is not browser verification. Let the author
  do manual playtesting unless explicitly requested otherwise.
- Inspect export contents to ensure worker artifacts and checkpoints are excluded.
- Regenerate and commit the correct `data/solver-cache` for any solver changes.

## 13. Performance acceptance and reporting

Correctness gates are mandatory. Timing goals are explicit engineering targets,
not guaranteed outcomes from the current inspection.

- Preview after import: target at most 5 seconds for rooms 18 and 19 on the
  recorded development machine, with zero solver calls. Report import separately.
- Parallel cold-room preparation: target at least 2x faster than the same revised
  serial engine at 4 workers, and a material reduction against the old baseline.
  Report both comparisons: a slower serial refactor must not be hidden by parallelism.
- Product goal: bring a large-room validation cycle toward 10 minutes or less.
  Treat this as a stretch goal pending baseline/profile evidence, not a permission
  to reduce samples. Report actual end-to-end time including the final world pass.
- Fully warm validation: avoid more than 10% repeatable regression versus the
  same-machine baseline. Do not spawn a full idle worker pool when nothing is missing.
- Checkpoint recovery: expensive completed compatible batches are not simulated
  again; demonstrate with counters. Replaying cheap graph traversal is acceptable.
- Bounded memory and disk: report peak RSS for all processes, not just the parent;
  avoid swapping at the default worker count. Bound queued path results, evict
  geometry contexts, and clean completed-run raw data only after verified cache
  promotion, retaining compact benchmark summaries.
- Show worker utilization and longest batch, so a residual serial bottleneck is
  visible. Unknown dynamic work gets counts and elapsed time, not a fabricated ETA.

Emit progress every 5–10 seconds while work is active: current room/stage,
completed/pending batches, active workers, reused results, elapsed time, and output
log path. Progress is diagnostic only and must not affect result order or cache keys.

## 14. Instructions for the implementing agent

1. Read root AGENTS.md, README, design implementation reference and decision log,
   then this plan. Inspect current Git status and preserve unrelated work. The
   planning session had an unrelated untracked `.claude/` directory; do not add it.
2. Treat this as implementation work, not permission to redesign movement or rooms.
   Start with PR 1; do not implement all five PRs as one unreviewable rewrite.
3. Verify current function names and source behavior before editing. If code has
   moved, follow the shared boundaries rather than blindly using stale line numbers.
4. Capture a reference before changing solver semantics. Add a failing meaningful
   regression for each correctness-sensitive refactor, then fix it.
5. First prove serial equivalence, then parallel equivalence, then speed. Do not
   debug ordering, caching, and physics changes simultaneously.
6. If exact equivalence fails, reduce to a small fixture and fix the divergence.
   Do not regenerate expected results to conceal it. Any intentional change to
   solver coverage requires a separate explicit design decision.
7. A difficult optimization may be deferred with evidence, but preview-only work
   is not completion of the solver performance project. Report remaining work.
8. Update current documentation when behavior changes; this plan records intent
   and is not a substitute for updating README/design/checklist instructions.
9. In each PR report what changed, observed speed/memory results, exact checks run,
   incomplete checks, cache changes, and browser verification. Include the required
   before/after slowest-room tables for exact solver changes.
10. At final handoff, provide commands for preview, local play, ordinary validation,
    serial diagnosis and resume; measured old/new times; known limits; and the
    remaining design decisions for moving tongue attachment. Do not claim that
    moving attachment has been implemented by this performance project.

## 15. Implementation contracts and common mistakes

### Minimum request/result records

Use typed GDScript classes internally and versioned plain data at the process
boundary. The following is a field checklist, not a replacement for `JumpPlan`:

- Request envelope: `protocol`, `input_digest`, `request_id`, `scope_id`,
  `ordinal`, `room_variant`, `geometry_digest`, `ability_signature`, `purpose`.
- Initial conditions: exact position/velocity, grounded start, start tick,
  rider mover ID/local body, hang direction and hang time.
- Controls: input, hold frames, jump boolean, optional later input/switch frame,
  air-jump count/frame/hold, simulation limit, path-recording boolean.
- Geometry: stable references to the ordered rect arrays used for solids,
  triggers, hazards, collections, and bounds. Load these once per geometry context;
  do not serialize every rect again for each trajectory if a digest/reference works.
- Result: the exact `MovementSim.run` result fields consumed by that purpose,
  plus request identity, simulation count/frame count, status and checksum.
  Path points are needed for sampling requests; omit them from other requests.

Keep graph interpretation outside this record. The worker returns physical outcomes,
not a verdict such as "room reachable" or a set of globally merged hang links.
Never pass arbitrary function names or executable code from JSON to workers.

The ordered `try_plan` reducer must preserve its current sequence: collect the
run's reported pickups, then discard further transition handling for a hazardous
result, then handle a door touch, else handle a successful landing. Preserve the
special classification where a ceiling hang's spare jump does not require double
jump. Do not reimplement this classification differently in the worker.

### Reference-order replay pseudocode

For an independent scope such as one ledge's ordinary jump enumeration:

1. Enumerate requests in the existing nested-loop order and assign ordinals.
2. Resolve existing safe reuse in that same logical order; submit remaining work.
3. Store finished results by identity without mutating the graph.
4. Apply the next ordinal only when its result exists. Buffer later ordinals within
   the configured bound; pause submission if the bound is full.
5. Apply through the original interpretation helpers, update reuse records, and
   move to the next ordinal. Only declare the scope complete at its end.

For a climb expansion, distinguish raw physics from ordered discovery. A worker
can compute a path while another computes another path, but `_stick`, ceiling
representative selection, `seen`, link insertion, and depth-first traversal happen
only during controller replay. If discovering the next scope depends on applying
the current one, wait. Preserve correctness first and measure this serial portion
before considering a separate algorithm change.

### Baseline limitations to handle explicitly

Existing warm-up and uncached traversal may expose order-sensitive behavior
differently. Test that comparison before refactoring; do not assume the committed
cache is the oracle merely because CI currently accepts it. If the baseline
already differs, retain both dumps, reduce the issue to a fixture, and report the
specific divergence. Fix that existing correctness problem in a separate change
with an explicit documented expected behavior before claiming exact speedup parity.

The existing `solver_diff.sh` waits for both processes with `|| true` and then
checks for dump files. Strengthen its runner to detect process errors and partial
dumps, while allowing intentional validator error cases in fixture comparisons.
A successful comparison means both analyses completed and their declared outputs
match; matching truncated dumps are not success. Clean output paths per run to
avoid accidentally reading yesterday's dump after a failed process.

The normal validation report is not the same as warmed cache coverage. Warm-up
may intentionally calculate unused variants/signatures for future progression;
benchmark that work separately from final world traversal. Do not delete variants
from the warm-up just to improve numbers unless the planner proves they are not
required and the change has independent coverage.

### CI and rollback

Review `.github/workflows/check.yml` and `deploy.yml` when integrating the new
runner. Both currently run `tools/check.sh` with a 90-minute job timeout. Keep the
normal committed-cache path practical on that runner; do not solve missing caches
in a scheduled background service or extend timeouts as the main performance fix.
CI must run the supervisor tests and still refuse stale committed caches.

Retain an explicit serial fallback during rollout. A user selecting one worker
must exercise the same deterministic batch semantics; `--no-cache` remains the
diagnostic in-process reference. If parallel execution fails, exit with a clear
error and resume instructions rather than silently starting an unannounced
hour-long fallback. Reverting an optimization must not destroy completed cache
files or normal saves; incompatible checkpoints may be ignored safely.
