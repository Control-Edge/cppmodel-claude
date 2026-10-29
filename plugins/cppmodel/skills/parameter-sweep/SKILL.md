---
name: cppmodel:parameter-sweep
description: Run a CppModel simulation many times over a range of parameter values (a parameter sweep or sensitivity study; each parameter set is a restart, while input profiles are chained in time within each run), without editing or rebuilding the simulation - each run's inputs/parameters are passed to the binary with --inputs (SDK 0.10.0+) or posted through the cppmodel MCP server's set_inputs right before it executes, and the whole batch is verified afterwards from the execution records in one get_binary_runs call. Designs the sweep with the user, runs it, and reports which combinations pass or fail, where the pass/fail boundary lies, and the metrics the user cares about. Use when asked to sweep, vary, or tune a parameter, test robustness across parameter ranges, or find the limit at which a simulation starts failing. Cases that differ in logic rather than values are separate simulations (cppmodel:simulation-testing), not sweep variants.
---

## How a sweep works

A sweep varies the values of one behaviour the simulation already describes. Cases that differ in
logic (different sequences, faults, variants or checks) are separate simulations written in C/C++,
not sweep variants (`cppmodel:simulation-testing`, "New case: input document or new simulation").

This builds on `cppmodel:simulation-inputs`. Read that skill's "What this is" and step 3 (the rules
for authoring inputs) first; they apply to every run here. In short:

- A posted input document is **consumed by the next execution**.
- Every execution **records the inputs and parameters it actually read**.
- Every execution records the binary's **`CppModel.BinaryFingerprint`**, and the server numbers a
  build's runs by it: run i of an unchanged binary is index (runs before the batch) + i (see
  `cppmodel:simulations`' "Runs of one build").

So a sweep is sequential, and needs nothing built besides the simulation. For each run, the binary
runs with that run's document and submits its execution:

- **SDK 0.10.0+:** the binary takes the document as `--inputs runs/NNN.json`. Nothing is posted, so
  other runs of the simulation meanwhile (`ctest`, CI, a colleague) can't take a sweep run's values.
- **Older SDKs:** `set_inputs` posts the document right before the run, and the run consumes it.

Then one `get_binary_runs` call fetches the whole batch by fingerprint and index, and its `expected`
argument checks every run's recorded values against the documents.

Requirements:

- The `cppmodel` MCP server, authenticated (see `cppmodel:simulations`), in a version whose
  `get_binary_runs` takes `expected`.
- **SDK 0.7.2+** prints `CppModel.BinaryFingerprint: <n>` when the simulation finishes, so the
  sweep reads the fingerprint from the first run's output. With **0.7.0 to 0.7.1**, take it from
  `CppModel.BinaryFingerprint` in `get_latest_result`'s `parameters` after the first run. **Before
  0.7.0** there's no fingerprint and no run index. Offer `cppmodel:update-dependencies`.
  Otherwise, check each run right after it with `get_latest_result` and `expected`, and note its
  execution id from `list_executions`.
- Posted documents are applied only from SDK 0.6.1 on. Check the vendored version as
  `cppmodel:simulation-inputs` describes.

To keep a sweep running in CI, turn its run documents into tests. See "In CI" at the end.

## 1. Preconditions

- A login to run the binary as the MCP server's account: `get_run_token` (SDK 0.9.0+), else
  `.cppmodeltoken` or `.env` with `CPPMODEL_USERNAME` and `CPPMODEL_PASSWORD` (see
  `cppmodel:simulation-testing`'s "Requirements"). If there's none, stop and say so.
- The simulation binary is **built and up to date**. Build it as `cppmodel:simulation-testing`
  describes, before the sweep and not during it.
- **With an SDK before 0.10.0, nothing else runs this simulation on the same account during the
  sweep**: no `ctest`, no CI job with the same login, no second sweep, no run started from the web
  UI. Any of them would consume a posted document meant for a sweep run (other users' runs don't).
  Say this to the user before starting. With `--inputs` only one thing matters: nobody else runs
  this same build meanwhile, since that would shift the run indices.
- **Check for a pending document** with `get_pending_inputs`. If one is pending, something on this
  account posted it for a run that hasn't happened. Save it as `<out>/pending.json` and tell the
  user: the sweep's first run consumes it (with `--inputs` too, when it submits), and step 6
  re-posts it.

## 2. Find the names

Do `cppmodel:simulation-inputs` step 1, which uses the latest execution record plus the source, to
list every input and parameter the simulation reads, with exact names, types, and current values.
A misspelled name silently uses its fallback, and the server records it like any other.

## 3. Design the sweep with the user

Agree on:

- **What varies: parameters.** Give explicit values
  (`"Max Acceleration [m/s^2]": [2, 3, 4, 5, 6]`). Pick the range from the physics or the
  requirement, and include the current value so one run reproduces today's behaviour. Parameters
  are constants for a whole run, so each parameter set is a restart of the simulation: one run.
- **Input profiles are chained, not swept.** Inputs are time series, so several profiles
  (`"slow"`, `"fast"`, `"stop-and-go"`...) go one after another along the time axis of the same
  document, each starting once the system is back in a known state (at rest, setpoint reached),
  authored per `cppmodel:simulation-inputs` step 3. Every run then covers all of them, its trace
  shows every failure across them, and the run count doesn't multiply. Make a profile a separate run only if it can't start from a state the
  run can return to. In a controller or complete-system simulation the profiles are controller
  inputs (operator command profiles, setpoint steps), never plant actuator commands: the plant is
  feedback and reacts to whatever the controller does.
- **Shape.**
  - **Grid**: every combination of the listed parameter values.
  - **Runs**: an explicit list, for one-at-a-time sensitivity, hand-picked corner cases, or one run
    per planned field run (`cppmodel:experiment-design`).
  - A grid's run count is the product of the parameter list lengths. State that number.
- **What stays fixed.** Every run's document starts from the latest execution's `inputs` and
  `parameters` (`get_latest_result`), with only the varied names changed. `set_inputs` needs a
  complete document, since a name left out uses its fallback. If that record consumed a posted
  document (step 2 shows its values differ from the fallbacks), the base carries those values. Say
  so, and offer a committed input document as the base instead. In a closed-loop simulation, drop
  the plant-fed inputs from the base (`cppmodel:simulation-inputs` step 3): posting the recorded
  plant trace back would override the plant in every run.
- **What to measure.** Pass/fail is always recorded (exit code, `CppModel.StepResult`). Ask what
  else matters: peak or overshoot of an output, settling time, the final value, the time an event
  first happens. Knowing this up front decides which signals to fetch in step 6. If the simulation
  has verification rules (SDK 0.11.0+), each rule's margin (`margins` in its outcome under the
  execution's `verification`) is a ready-made metric. Its sign flips at the pass/fail
  boundary, so it shows how close each passing run came.
- **Size and time.** Every run is a real execution: it takes the binary's full runtime, adds an
  entry to the simulation's execution history, and costs a few API calls, which are rate-limited.
  Past roughly 50 runs, propose a coarse sweep first and then a refined one around the interesting
  region. Get the user's OK on the final run count.
- **Whether a coarse pass runs locally** (SDK 0.10.0+). A coarse pass that only locates the
  interesting region can run as local runs: the step-5 command with `--results
  <out>/local/NNN.json` added. It adds nothing to the history and needs no API calls besides the
  token, and you read its results files directly. Its pass/fail map is a guide for designing the
  refined sweep and is never reported as the outcome. The sweep the user gets results from is
  always recorded (`cppmodel:simulations`' "Local runs"). Offer this only for a pass that is
  exploratory by design, and say so.

## 4. Write the documents

Pick an output directory `<out>`. Use scratch for a one-off sweep, or a `.gitignore`d folder in
the project for one worth repeating after code changes (e.g. `simulations/sweeps/<name>/`). Ask the
user. It holds:

- `runs/NNN.json`: run NNN's document (`{inputs, parameters}`, exactly as the run gets it), from
  `000`. Validate every series (lengths, `x` strictly ascending from 0) before running anything.
- `sweep.json`: the record of the sweep. It holds `simulation`, `binary`, and per run its `name`
  and the varied values. Step 5 adds `fingerprint`, `start`, and each run's `exitCode`, `log` and
  printed `Execution:` id.

Copied `CppModel.BinaryFingerprint` parameters can stay in the documents: `set_inputs` drops them
with a warning, and the `expected` check skips `CppModel.` names.

Then call `set_inputs` with `dry_run: true` on one document that contains every varied name. Treat
every `unrecognizedNames` entry as a typo until the source proves otherwise, and fix it in every
document. Show the user the run list before running anything.

## 5. Run

For each run, in order:

1. With an SDK before 0.10.0 only: `set_inputs` with `runs/NNN.json`, straight before the run.
2. Run the binary from the project root with the run token set for that one command (as
   `cppmodel:simulation-testing`'s "Build and run" describes), with a time limit a few times its
   normal runtime, keeping the log. From SDK 0.10.0 it takes the document itself:

   ```
   CPPMODEL_ACCESS_TOKEN=<access_token> CPPMODEL_WORKSPACE=<workspace> CPPMODEL_LOGIN_TIMEOUT=0 timeout 300 ./build/<path>/<SimulationBinary> --inputs <out>/runs/NNN.json > <out>/runs/NNN.log 2>&1; echo $?
   ```

   With an older SDK, leave out `--inputs`: the run reads the posted document. Without
   `get_run_token`, source `.env` instead.

A token lives only about 5 minutes, so fetch a fresh one per batch of runs: call `get_run_token`
before the first run, note when it expires (`date +%s` plus `expires_in`), and reuse it only while
it has more than a minute plus one run's normal runtime left. Then call it again; if its
`expires_in` is still under 60, wait until it has expired first. The tool allows about 10 calls a
minute, so don't call it per run when runs are short. Never put the token in `sweep.json`, a run
document, a log or a script. A log with `CPPMODEL_ACCESS_TOKEN is expired or invalid` means the run
used another login and may not have consumed its document: stop as for a run that submitted
nothing.

   (On Windows, start it from PowerShell with `Start-Process -RedirectStandardOutput` and stop it
   after `Wait-Process -Timeout`.) Note the exit code in `sweep.json`: `0` passed, `124` timed
   out, anything else failed. A failed run's code depends on the shell (255 on Linux/macOS and in
   Git Bash, -1 in PowerShell, 127 through Git Bash's `timeout`, the same code as "command not
   found"), so the log and step 6 decide what happened, not the code.

After the **first run**, read the fingerprint from the `CppModel.BinaryFingerprint: <n>` line of
its log. Call `get_binary_runs` with that fingerprint and `count: 0`: `total` includes the run just
made, so the batch's **start index is `total - 1`**. Save `fingerprint` and `start` in
`sweep.json`. Then check that first run with `get_binary_runs` (`start`, `count: 1`, `expected:
[runs/000.json]`, `summary: true`). If it isn't `applied`, every further run would just repeat the
default run, so stop.

**Stop the sweep** and go to step 6 with the runs made so far when:

- **A run submitted no execution.** Its log has a line starting with `CppModel workspace:` (SDK
  0.9.1+; before it, `Could not reach API. Running offline.`), its
  fingerprint line ends in `(not submitted)`, or it has no fingerprint line at all (a timeout
  included). One exception: a run whose only problem is `submitting the execution failed (HTTP
  401 ...)` at the end hit a transient login failure (seen with SDK 0.9.4). It isn't indexed, so
  the indices stay right. Re-run it once with a fresh token (re-post its document first with an
  SDK before 0.10.0) and go on if that run submits. Stop if it fails again.
- **The binary was rebuilt mid-sweep.** The log's fingerprint differs from the first run's. Later
  runs are indexed under the new build.
- **A run's log has a line starting with `CppModel: --inputs`.** The document is unusable; the line
  says why. Fix it (in every document that shares the problem) before going on.
- **Anything else ran the simulation.** Before SDK 0.10.0 it may have consumed a document meant for
  a sweep run. A run of the same binary shifts the indices with any SDK. Stop as soon as you know
  of one. Otherwise the check in step 6 shows it.

Report the reason. Don't re-run blindly.

## 6. Check the batch, then clean up

Fetch the whole batch in one call: `get_binary_runs` with `simulation`, `fingerprint`, `start`,
`count` = the number of runs made, and `expected` = their documents in run order. Add `summary:
true`, or `signals` with just the series step 3 agreed to measure. Above 50 runs, page: the next
call starts at `start + 50` with the next 50 documents, and so on.

- **`allApplied: true`**: every run used what was posted. Go on to step 7.
- **A run with `applied: false`**: its `differences` list the document's vs read values. Report them
  verbatim. If the recorded values are the fallbacks, the SDK isn't applying the documents at all:
  an SDK before 0.10.0 run with `--inputs` ignores the option, and one before 0.6.1 ignores posted
  inputs. That isn't something to fix in the documents; offer
  `cppmodel:update-dependencies`. If only some runs differ, something else consumed their
  documents. Leave those runs out of the analysis and say which.
- **`notRunYet`**: fewer runs are indexed than were made. A run didn't submit, or the start index
  is wrong because something else ran this binary. Say which runs are affected.

If step 1 saved a pending document, re-post it with `set_inputs` now, including when the sweep
stopped early, and tell the user.

## 7. Analyse the results

Each run in `get_binary_runs` has its `index`, `passed` (every cycle's `CppModel.StepResult` was
1), and the execution record: `results`, a list of `{label, x, y}` output series, alongside the
`inputs`/`parameters` that were read. A failing run's exit code is platform-dependent, so go by
`passed`.

- **Pass/fail map first.** Show a table with one row per run, or a 2-D grid when two things were
  varied. Then state the boundary in words, e.g. "passes up to 4.0 m/s², fails from 5.0 m/s²
  with the fast profile only".
- **Metrics from the execution records.** Fetch the series agreed in step 3 with `signals`.
  Series are change-compressed (`x` = the times the value changed, plus the end), so read them
  with hold-last-value. With chained input profiles, compute each metric per profile over its
  time window in the document. Compute the metrics from these records; a short one-off computation over
  them is fine. They are the API's own data. Never search the project for other result files, or
  re-derive values some other way. For a sweep from an earlier session, `sweep.json`'s
  `fingerprint` and `start` fetch the runs again in order.
- **Refine where it matters.** If the boundary falls between two values, offer a second, finer
  sweep between them rather than guessing where it is. With verification rules, the margins on
  both sides show roughly where to aim it. Still confirm the boundary with runs.
- For a visual comparison, offer to plot the key signal across runs. An export covers one
  execution only, so a cross-run overlay needs a chart of your own: load the `dataviz` skill
  before drawing it.

Point the user at the web UI for any run they want to inspect: `get_binary_runs` gives the
simulation's page as `uiUrl`, so name the run's fingerprint and index with it. For a link to one
run, find its id with `list_executions`, whose items each have their own `uiUrl`. To show how two
runs differ, `what_changed` with their ids gives the parameters that differ and a `uiUrl` that
overlays both. For one run the user wants to see, such as the run at the boundary, export it as a
`png` (`export_signals` with that run's execution id, see `cppmodel:simulations`' "Looking at
signals"), look at it, and give its link.

## 8. Follow-ups worth offering

- **A failing combination should become a permanent test**, so it's covered without a sweep.
  The point is inputs and parameters only, so commit its run document as an input document with its
  own `ctest` test (`cppmodel:simulation-inputs`, "In CI" below); no new C/C++ file. Only if
  covering it needs different logic or flow is it another simulation (`cppmodel:simulation-testing`,
  "New case: input document or new simulation"). Posted documents are one-shot, so a document
  that isn't in the repo isn't part of the test suite.
- **To find out why a combination fails**, fetch its execution with `get_binary_runs` (`start` =
  its index, `count: 1`). Then follow `cppmodel:simulation-testing`'s "Debugging a failure"
  section.
- **Re-run the same documents after code changes** to confirm the boundary moved the right way.
  Every run of both sweeps stays in the execution history, so compare the new sweep against the
  old one by the fingerprint and start index in each `sweep.json` (the rebuilt binary has a new
  fingerprint), not by re-running the old code. For one point of each, `what_changed` with the two
  execution ids confirms only the code changed (`code_changed`, no parameter differences).

Finish with where `sweep.json` and the documents are, and whether a previously pending document
was re-posted.

## In CI

A sweep that should keep running in CI needs no tool (SDK 0.10.0+). Copy the run documents worth
keeping (`<out>/runs/NNN.json`, renamed after what they test) into the project. Then add one
`ctest` test per document that runs the binary with `--inputs <document>`. Mark a point meant to
fail with `WILL_FAIL`. `cppmodel:ci-pipeline`'s "Sweeps" shows the CMake. Every test
submits its execution, and the exit code is the result. With an SDK before 0.10.0, recommend
updating it (`cppmodel:update-dependencies`) first.
