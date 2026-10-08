---
name: cppmodel:parameter-sweep
description: Run a CppModel simulation many times over a range of parameter values and/or alternative input profiles (a parameter sweep, sensitivity study, or scenario matrix), without editing or rebuilding the simulation - each run's inputs/parameters are posted through the cppmodel MCP server's set_inputs right before it executes, and the whole batch is verified afterwards from the execution records in one get_binary_runs call. Designs the sweep with the user, runs it, and reports which combinations pass or fail, where the pass/fail boundary lies, and the metrics the user cares about. Use when asked to sweep, vary, or tune a parameter, test robustness across input scenarios, find the limit at which a simulation starts failing, or compare several input profiles.
---

## How a sweep works

This builds on `cppmodel:simulation-inputs`. Read that skill's "What this is" and step 3 (the rules
for authoring inputs) first; they apply to every run here. In short:

- A posted input document is **consumed by the next execution**.
- Every execution **records the inputs and parameters it actually read**.
- Every execution records the binary's **`CppModel.BinaryFingerprint`**, and the server numbers a
  build's runs by it: run i of an unchanged binary is index (runs before the batch) + i (see
  `cppmodel:simulations`' "Runs of one build").

So a sweep is sequential, and runs entirely through the `cppmodel` MCP server. Nothing has to be
built besides the simulation. For each run:

1. `set_inputs` posts that run's document;
2. the binary runs and submits its execution.

Then one `get_binary_runs` call fetches the whole batch by fingerprint and index, and its `expected`
argument checks every run's recorded values against the documents posted.

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

In CI or a script, without an AI assistant, `cppmodel-tool sweep` runs the same loop. See "In CI
or a script" at the end. Don't build it for a sweep run from here.

## 1. Preconditions

- `.env` has `CPPMODEL_USERNAME` and `CPPMODEL_PASSWORD` (see `cppmodel:simulation-testing`'s
  "Requirements"). If they're missing, stop and say so.
- The simulation binary is **built and up to date**. Build it as `cppmodel:simulation-testing`
  describes, before the sweep and not during it.
- **Nothing else runs this simulation on the same account during the sweep**: no `ctest`, no CI
  job with the same login, no second sweep, no run started from the web UI. Any of them would
  consume a posted document meant for a sweep run (other users' runs don't). Say this to the user
  before starting.
- **Check for a pending document** with `get_pending_inputs`. If one is pending, something on this
  account posted it for a run that hasn't happened. Save it as `<out>/pending.json` and tell the
  user: the sweep's first post replaces it, and step 6 re-posts it.

## 2. Find the names

Do `cppmodel:simulation-inputs` step 1, which uses the latest execution record plus the source, to
list every input and parameter the simulation reads, with exact names, types, and current values.
A misspelled name silently uses its fallback, and the server records it like any other.

## 3. Design the sweep with the user

Agree on:

- **What varies.** For parameters, give explicit values
  (`"Max Acceleration [m/s^2]": [2, 3, 4, 5, 6]`). Pick the range from the physics or the
  requirement, and include the current value so one run reproduces today's behaviour. For inputs,
  define named variants of a whole series (`"slow"`, `"fast"`, `"stop-and-go"`...), authored per
  `cppmodel:simulation-inputs` step 3. A varied input replaces the whole series with that label,
  not individual points.
- **Shape.**
  - **Grid**: every combination of the listed parameter values and input variants.
  - **Runs**: an explicit list, for one-at-a-time sensitivity, hand-picked corner cases, or one run
    per planned field run (`cppmodel:experiment-design`).
  - A grid's run count is the product of all the list lengths. State that number.
- **What stays fixed.** Every run's document starts from the latest execution's `inputs` and
  `parameters` (`get_latest_result`), with only the varied names changed. `set_inputs` needs a
  complete document, since a name left out uses its fallback. If that record consumed a posted
  document (step 2 shows its values differ from the fallbacks), the base carries those values. Say
  so, and offer a committed scenario file as the base instead.
- **What to measure.** Pass/fail is always recorded (exit code, `CppModel.StepResult`). Ask what
  else matters: peak or overshoot of an output, settling time, the final value, the time an event
  first happens. Knowing this up front decides which signals to fetch in step 6.
- **Size and time.** Every run is a real execution: it takes the binary's full runtime, adds an
  entry to the simulation's execution history, and costs a few API calls, which are rate-limited.
  Past roughly 50 runs, propose a coarse sweep first and then a refined one around the interesting
  region. Get the user's OK on the final run count.

## 4. Write the documents

Pick an output directory `<out>`. Use scratch for a one-off sweep, or a `.gitignore`d folder in
the project for one worth repeating after code changes (e.g. `simulations/sweeps/<name>/`). Ask the
user. It holds:

- `runs/NNN.json`: run NNN's document (`{inputs, parameters}`, exactly as it will be posted), from
  `000`. Validate every series (lengths, `x` strictly ascending from 0) before posting anything.
- `sweep.json`: the record of the sweep. It holds `simulation`, `binary`, and per run its `name`
  and the varied values. Step 5 adds `fingerprint`, `start`, and each run's `exitCode` and `log`.

Copied `CppModel.BinaryFingerprint` parameters can stay in the documents: `set_inputs` drops them
with a warning, and the `expected` check skips `CppModel.` names.

Then call `set_inputs` with `dry_run: true` on one document that contains every varied name. Treat
every `unrecognizedNames` entry as a typo until the source proves otherwise, and fix it in every
document. Show the user the run list before running anything.

## 5. Run

For each run, in order, post and run straight away:

1. `set_inputs` with `runs/NNN.json`.
2. Run the binary from the project root with `.env` sourced (as `cppmodel:simulation-testing`'s
   "Build and run" describes), with a time limit a few times its normal runtime, keeping the log:

   ```
   timeout 300 ./build/<path>/<SimulationBinary> > <out>/runs/NNN.log 2>&1; echo $?
   ```

   (On Windows, start it from PowerShell with `Start-Process -RedirectStandardOutput` and stop it
   after `Wait-Process -Timeout`.) Note the exit code in `sweep.json`: `0` passed, nonzero failed
   (255 on Linux/macOS, -1 on Windows), `124` timed out.

After the **first run**, read the fingerprint from the `CppModel.BinaryFingerprint: <n>` line of
its log. Call `get_binary_runs` with that fingerprint and `count: 0`: `total` includes the run just
made, so the batch's **start index is `total - 1`**. Save `fingerprint` and `start` in
`sweep.json`. Then check that first run with `get_binary_runs` (`start`, `count: 1`, `expected:
[runs/000.json]`, `summary: true`). If it isn't `applied`, every further run would just repeat the
default run, so stop.

**Stop the sweep** and go to step 6 with the runs made so far when:

- **A run submitted no execution.** Its log says `Could not reach API. Running offline.`, its
  fingerprint line ends in `(not submitted)`, or it has no fingerprint line at all (a timeout
  included).
- **The binary was rebuilt mid-sweep.** The log's fingerprint differs from the first run's. Later
  runs are indexed under the new build.
- **Anything else ran the simulation.** It may have consumed a document meant for a sweep run, or,
  for the same binary on the same account, shifted the indices. Stop as soon as you know of one.
  Otherwise the check in step 6 shows it.

Report the reason. Don't re-run blindly.

## 6. Check the batch, then clean up

Fetch the whole batch in one call: `get_binary_runs` with `simulation`, `fingerprint`, `start`,
`count` = the number of runs made, and `expected` = their documents in run order. Add `summary:
true`, or `signals` with just the series step 3 agreed to measure. Above 50 runs, page: the next
call starts at `start + 50` with the next 50 documents, and so on.

- **`allApplied: true`**: every run used what was posted. Go on to step 7.
- **A run with `applied: false`**: its `differences` list posted vs read values. Report them
  verbatim. If the recorded values are the fallbacks, the SDK isn't applying posted inputs at all
  (SDKs before 0.6.1). That isn't something to fix in the documents; offer
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
  with hold-last-value. Compute the metrics from these records; a short one-off computation over
  them is fine. They are the API's own data. Never search the project for other result files, or
  re-derive values some other way. For a sweep from an earlier session, `sweep.json`'s
  `fingerprint` and `start` fetch the runs again in order.
- **Refine where it matters.** If the boundary falls between two values, offer a second, finer
  sweep between them rather than guessing where it is.
- For a visual comparison, offer to plot the key signal across runs. Load the `dataviz` skill
  before drawing any chart.

Point the user at the web UI for any run they want to inspect:
`<uiUrl>/simulations/<name>` (`get_workspace` gives `uiUrl`), with the run's fingerprint and index.

## 8. Follow-ups worth offering

- **A failing combination should become a permanent test**, so it's covered without a sweep.
  Either commit it as a scenario file (`cppmodel:simulation-inputs`), or add an explicit scenario
  step to the simulation that sets those conditions in code (`cppmodel:simulation-testing`).
  Posted documents are one-shot, so a scenario that isn't in the repo isn't part of the test
  suite.
- **To find out why a combination fails**, fetch its execution with `get_binary_runs` (`start` =
  its index, `count: 1`). Then follow `cppmodel:simulation-testing`'s "Debugging a failure"
  section.
- **Re-run the same documents after code changes** to confirm the boundary moved the right way.
  Every run of both sweeps stays in the execution history, so compare the new sweep against the
  old one by the fingerprint and start index in each `sweep.json` (the rebuilt binary has a new
  fingerprint), not by re-running the old code.

Finish with where `sweep.json` and the documents are, and whether a previously pending document
was re-posted.

## In CI or a script

A pipeline or script that sweeps without an AI assistant uses `cppmodel-tool sweep` (SDK 0.6.3+),
which runs the same post-run-verify loop from a plan file. It ships as source with the SDK in
`<sdk>/share/cppmodel/tools`. `cppmodel:ci-pipeline` builds it in the pipeline. Locally, build it
with the project's toolchain:

```
cmake -S dependencies/share/cppmodel/tools -B build/cppmodel-tool
cmake --build build/cppmodel-tool
cppmodel-tool sweep <plan.json> <out-dir> [--dry-run] [--timeout <seconds>] [--workspace <id>] [--env <file>]
```

The plan lists `simulation`, `binary` (relative to the folder of the `.env` in use), `base`
(`"defaults"`, `"current"`, or an inline document), and either `parameters`/`inputs` for a grid or
`runs` for an explicit list:

```json
{
  "simulation": "<exact name from CMODEL_SIMULATE / CppModel_create>",
  "binary": "build/<path>/<SimulationBinary>",
  "base": "defaults",
  "parameters": { "Max Acceleration [m/s^2]": [2.0, 4.0, 6.0] },
  "inputs": {
    "Desired Velocity [mm/s]": {
      "slow": { "x": [0, 300], "y": [30, 60] },
      "fast": { "x": [0, 300], "y": [100, 200] }
    }
  }
}
```

It exits `0` when every run was verified (whether each passed or failed), `1` when it stopped
early, `2` for a usage error, and `130` after Ctrl-C. `<out>/summary.json` has one row per run
with its `fingerprint` and `index`, which `get_binary_runs` reads like a sweep from here.
`cppmodel-tool --help` lists the rest.
