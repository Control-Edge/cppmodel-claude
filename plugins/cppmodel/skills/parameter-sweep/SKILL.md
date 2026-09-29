---
name: cppmodel:parameter-sweep
description: Run a CppModel simulation many times over a range of parameter values and/or alternative input profiles (a parameter sweep, sensitivity study, or scenario matrix), without editing or rebuilding the simulation - each run's inputs/parameters are posted to the Workspace API right before it executes, and verified afterwards from the execution record. Designs the sweep with the user, runs it with the plugin's sweep runner, and reports which combinations pass or fail, where the pass/fail boundary lies, and the metrics the user cares about. Use when asked to sweep, vary, or tune a parameter, test robustness across input scenarios, find the limit at which a simulation starts failing, or compare several input profiles.
---

## How a sweep works

This builds on `cppmodel:simulation-inputs`. Read that skill's "What this is" and step 3 (the rules
for authoring inputs) first; they apply to every run here. In short:

- A posted input document is **consumed by the next execution**.
- Every execution **records the inputs and parameters it actually read**.

So a sweep is sequential. For each combination, the runner:

1. posts that combination's document;
2. runs the binary;
3. fetches exactly the execution that run created;
4. **checks the recorded values against the posted ones.**

If a run didn't use what was posted, the sweep stops immediately, because every further run would
just repeat the default run. If a document was already pending before the sweep started, the
runner saves it and re-posts it at the end. Posts made during the sweep are all consumed, so
nothing else is left behind.

The runner ships with the plugin and uses `cppmodel-fetch.sh`/`.ps1` for every API call. Don't
reimplement any of this by hand:

```
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-sweep.sh <plan.json> <out-dir> [--dry-run] [--timeout <s>] [--workspace <id>]
```

```powershell
& "${CLAUDE_PLUGIN_ROOT}\scripts\cppmodel-sweep.ps1" <plan.json> <out-dir> [-DryRun] [-TimeoutSeconds <s>] [-Workspace <id>]
```

## 1. Preconditions

- `.env` has `CPPMODEL_USERNAME` and `CPPMODEL_PASSWORD` (see `cppmodel:simulation-testing`'s
  "Requirements"). If they're missing, stop and say so.
- The simulation binary is **built and up to date**. Build it as `cppmodel:simulation-testing`
  describes; the runner doesn't build.
- **Nothing else runs this simulation during the sweep**: no `ctest`, no CI job on the same
  account, no second sweep, no one pressing run in the web UI. Any of them would consume a posted
  document meant for a sweep run. The runner then catches the mismatch and stops, but the sweep is
  wasted. Say this to the user before starting.

## 2. Find the names

Do `cppmodel:simulation-inputs` step 1, which uses the latest execution record plus the source, to
list every input and parameter the simulation reads, with exact names, types, and current values.
A misspelled name silently uses its fallback, and the server records it like any other. Before
posting anything, the runner warns about every varied name the latest execution didn't read.
Treat that warning as a probable typo until the source proves otherwise. Posted documents are only
applied from SDK 0.6.1 on; check the vendored version as `cppmodel:simulation-inputs` describes.

## 3. Design the sweep with the user

Agree on:

- **What varies.** For parameters, give explicit values
  (`"Max Acceleration [m/s^2]": [2, 3, 4, 5, 6]`). Pick the range from the physics or the
  requirement, and include the current value so one run reproduces today's behaviour. For inputs,
  define named variants of a whole series (`"slow"`, `"fast"`, `"stop-and-go"`...), authored per
  `cppmodel:simulation-inputs` step 3.
- **Shape.**
  - **Grid**: every combination of the listed parameter values and input variants.
  - **Runs**: an explicit list, for one-at-a-time sensitivity or hand-picked corner cases.
  - A grid's run count is the product of all the list lengths. State that number.
- **What stays fixed.** This is the plan's `base` (step 4). The default, `"defaults"`, leaves
  every name the sweep doesn't vary at its fallback in the code, which is reproducible. Suggest
  an inline base, such as a committed scenario file, when the sweep should vary around a specific
  scenario instead.
- **What to measure.** Pass/fail is always recorded (exit code, `CppModel.StepResult`). Ask what
  else matters: peak or overshoot of an output, settling time, the final value, the time an event
  first happens. Knowing this up front decides which signals to look at in step 6.
- **Size and time.** Every run is a real execution: it takes the binary's full runtime, adds an
  entry to the simulation's execution history, and costs a few API calls, which are rate-limited.
  Past roughly 50 runs, propose a coarse sweep first and then a refined one around the interesting
  region. Get the user's OK on the final run count.

## 4. Write the plan

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

Or, for an explicit list, replace `parameters`/`inputs` with:

```json
"runs": [
  { "name": "baseline" },
  { "name": "heavy load", "parameters": { "Load [kg]": 12 }, "inputs": { "Desired Velocity [mm/s]": { "x": [0], "y": [150] } } }
]
```

- `base` is what each run starts from, before its own values are applied:
  - `"defaults"`, the default, is an empty document;
  - `"current"` is the document pending now, or otherwise the latest execution's recorded values;
  - an inline document can be given instead.
- A varied input replaces the whole series with that label, not individual points.
- The runner validates every series (lengths, ordering) before posting anything, because the
  server doesn't.
- `binary` is relative to the repo root. On Windows, include the `.exe`.

Save the plan where it fits its lifetime:

- scratch, for a one-off;
- the project, for a sweep worth repeating after code changes, e.g.
  `simulations/sweeps/<name>.plan.json`. Ask the user.

The output directory holds downloaded API data. Keep it out of git: use scratch, or a
`.gitignore`d folder.

## 5. Dry run, then run

```
cppmodel-sweep.sh plan.json <out> --dry-run
```

This writes every run's document to `<out>/runs/NNN.json` and lists the runs, without posting or
executing anything. Show the user the list, and spot-check one run file against the plan. Then run
for real with a `--timeout` a few times the binary's normal runtime:

```
cppmodel-sweep.sh plan.json <out> --timeout 120
```

The runner stops, and re-posts any document that was pending before the sweep, in these cases:

- **The simulation didn't use the posted values.** The recorded values differ from the posted
  ones, and the message lists posted vs read values per name. Report that verbatim to the user.
  If the recorded values are the fallbacks, the SDK isn't applying posted inputs at all. That
  happens with SDKs before 0.6.1, and isn't something to fix in the plan; offer
  `cppmodel:update-dependencies`.
- **A run went offline** ("Running offline" in its log).
- **A run created no new execution** on the server.
- **Any API call failed.**

Report the reason from the output. Don't re-run blindly.

## 6. Analyse the results

`<out>/summary.json` has one row per verified run: its values, `exitCode`, `passed`,
`executionId`, `applied`, `results` (the
execution record from the API) and `log`.

- **Pass/fail map first.** Show a table with one row per run, or a 2-D grid when two things were
  varied. Then state the boundary in words, e.g. "passes up to 4.0 m/s², fails from 5.0 m/s²
  with the fast profile only".
- **Metrics from the execution records.** Each `results/NNN.json` holds `results`, a list of
  `{label, x, y}` output series, alongside the `inputs`/`parameters` that were read. Series are
  change-compressed (`x` = the times the value changed, plus the end), so read them with
  hold-last-value. Compute the metrics agreed in step 3 from these files; a short one-off
  computation over them is fine. They are the API's own data. Never search the project for other
  result files, or re-derive values some other way.
- **Refine where it matters.** If the boundary falls between two values, offer a second, finer
  sweep between them rather than guessing where it is.
- For a visual comparison, offer to plot the key signal across runs. Load the `dataviz` skill
  before drawing any chart.

Point the user at the web UI for any run they want to inspect:
`https://<workspace>.cppmodel.com/simulations/<name>`, with the execution id from the summary.

## 7. Follow-ups worth offering

- **A failing combination should become a permanent test**, so it's covered without a sweep.
  Either commit it as a scenario file (`cppmodel:simulation-inputs`), or add an explicit scenario
  step to the simulation that sets those conditions in code (`cppmodel:simulation-testing`).
  Posted documents are one-shot, so a scenario that isn't in the repo isn't part of the test
  suite.
- **To find out why a combination fails**, fetch its execution by id
  (`cppmodel-fetch.sh execution "<name>" <executionId>`). Then follow
  `cppmodel:simulation-testing`'s "Debugging a failure" section.
- **Re-run a saved plan after code changes** to confirm the boundary moved the right way.

Finish with where the plan and results are, and whether a previously pending document was
re-posted.
