---
name: cppmodel:simulations
description: Query CppModel Workspace API results - list simulations (by name, or sorted by latest run or execution count), fetch the latest results for one, list its execution history, see what changed between two executions (code, parameters, signals), or compare executions with each other, with links into the workspace web UI. Exports chosen signals of one execution as a chart image to look at, or as a CSV, with a link for the user. Every simulation run is submitted to the workspace, and its execution history is how runs are compared. Use when asked about CppModel simulation results, executions, how a run compares with an earlier one or what changed since it, the Workspace API, "show me / plot / chart the signals", "look at the trace", "what did I run last", or a pasted `/snapshots/` link, in a project that uses the CppModel libraries.
---

## The tools: the `cppmodel` MCP server

All Workspace API access goes through the plugin's `cppmodel` MCP server
(`https://mcp.cppmodel.com/mcp`, declared in the plugin's `.mcp.json`). It signs in with the
user's CppModel account (free or licensed, both work the same) over OAuth, so querying results
needs no `.env` and no local tool. Running a simulation with chosen values, or a whole
parameter sweep, also needs nothing built besides the simulation: `set_inputs`, then run the
binary, then check the run with `get_binary_runs` and `expected`. The SDK's `cppmodel-tool` (prebuilt
in `dependencies/bin/` from SDK 0.8) does the same for CI jobs and scripts only
(`cppmodel:ci-pipeline`). Don't use it for work done here.

The server's instructions name the account and workspace the session is signed in as. Before the
first `cppmodel` tool call in a conversation, tell the user that account and workspace in one short
line, so they can stop you if it's the wrong one (e.g. a free account when they expected their
licensed workspace).

If the `cppmodel` tools aren't available, or fail with an authentication error, tell the user to
authenticate the server with `/mcp` and stop. Never re-implement API calls with curl, a script, or
an ad-hoc program instead, and never search the project for result files in their place.

| Tool | Use |
|------|-----|
| `list_simulations` | list simulations with execution counts and `lastExecutionAt` (`scope: "team"` for the whole team; `sort` by `name`, `executions` or `lastExecution`; `order`) |
| `get_latest_result` | the latest execution: inputs, parameters, results |
| `list_executions` | execution history, newest first, with id, time, status (up to 1000 per page) |
| `get_execution` | one past execution by id, same shape as `get_latest_result` |
| `what_changed` | what differs between two executions: code, parameters, signal names (see "Comparing runs") |
| `export_signals` | a chart (PNG, returned as an image), CSV or JSON of up to 8 signals of one execution, with a `/snapshots/<id>` link for the user (see "Looking at signals") |
| `get_export` | an export again, by id or `/snapshots/<id>` link, in any format |
| `get_binary_runs` | the runs of one build, by run index, each with `passed` (see "Runs of one build") |
| `get_pending_inputs` | the document waiting for this account's next execution (usually none) |
| `set_inputs` | post this account's next execution's inputs/parameters (see below) |
| `submit_execution` | record an execution no binary ran, such as measured data (see below) |
| `delete_simulation` | IRREVERSIBLE (see below) |
| `get_workspace` | which workspace the server is connected to, with UI and API URLs |
| `get_api_version` | the Workspace API version |

The simulation name is exactly the string passed to `CMODEL_SIMULATE(...)` in the source; case
and spaces matter. `list_simulations` shows the names.

Results can be large. Call `get_latest_result`/`get_execution`/`get_binary_runs` with
`summary: true` first to see which signals exist and their ranges, then with `signals: [...]` to
fetch only the series you need.

Execution ids are keys from `list_executions`, not positions: the first execution isn't `"0"` or
`"1"`. On a simulation others run too (`scope: "team"`), the latest execution may not be yours.

Results carry `uiUrl`, a link into the workspace web UI, which plots the signals: each simulation in
`list_simulations`, each execution in `list_executions`, the execution `get_execution` read (plus
`whatChangedUiUrl`, its comparison with the run before it), a `what_changed` comparison, and a
`submit_execution`, and an `export_signals`/`get_export` export (its snapshot page, which expires
after 7 days; see "Looking at signals"). `get_latest_result` and `get_binary_runs` link the
simulation's page, which shows its latest execution. Whenever you tell the user about a simulation, a run or a comparison,
give them the matching link so they can look at it themselves.

`set_inputs` posts a document the account's next execution of that simulation consumes; other
users' runs neither read nor consume it. Don't call it directly from here. Use
`cppmodel:simulation-inputs` for one scenario or `cppmodel:parameter-sweep` for many; both verify
the document was applied.

`get_latest_result`, `get_execution` and `get_binary_runs` take `expected`, the document posted
before the run (for `get_binary_runs`, one per run in run order, the first for `start`). Each run
then reports `applied` and `differences` (each posted value the run didn't use), and
`get_binary_runs` also `allApplied`. This needs a server version that has `expected`.

`submit_execution` records an execution `{inputs, parameters, results}` that no binary ran, such
as field measurements or data imported from another tool, exactly as a binary's own submission
would: it becomes part of that simulation's history (creating the simulation if needed) and
consumes the account's pending document for it, which the tool reports. Only use it when the user
asks to record such data, never to fake, patch or replace a run's results. Call it with `dry_run`
first to validate, and prefer a simulation name of its own (e.g. `<name> (field)`) so measured and
simulated executions don't mix in one history. Pass `execution_time` (`DD-MM-YYYY HH:MM:SS`) when
the data has a real start time; it defaults to now. Its `CppModel.BinaryFingerprint`, if given,
must be a whole number; leave it out unless the data really came from that binary.

`delete_simulation` removes the simulation with its entire execution history and any pending
document, the same as deleting it in the UI. It can't be undone and affects everyone who uses that
simulation, so only call it when the user explicitly asks, after telling them what will be lost.

## Runs of one build: `CppModel.BinaryFingerprint`

From SDK 0.7.0, every execution records the parameter `CppModel.BinaryFingerprint`, a hash of the
executable that ran it: the same value means the same build, a new value means it was rebuilt. It
covers the executable only, not the CppModel shared library beside it (SDK 0.8+); a rebuild after
an SDK update relinks the executable, so its fingerprint changes as well.
From SDK 0.7.2 the simulation also prints it when it finishes (`CppModel.BinaryFingerprint: <n>`,
then `Execution: <id>` when the server returned one; `(not submitted)` when the execution never
reached the workspace). The
server indexes executions by it, so `get_binary_runs` (`simulation`, `fingerprint`, `start`,
`count` up to 50) returns that build's runs in run order: index 0 is its first execution, indices
never move as more runs arrive, and other builds' executions don't interleave. Each run comes with
`passed` (every cycle's `CppModel.StepResult` was 1; `null` when the simulation doesn't output
it, so pass/fail exists only as the run's exit code); `total` says how
many runs the build has (`count: 0` returns just that), and `nextStart` the next page.

Use it for a batch run by one unchanged binary, such as a parameter sweep (whose `sweep.json`
records its `fingerprint` and `start` index) or repeated runs of a test, instead of paging
`list_executions` and guessing which ids belong together. It counts runs of the same binary by
every user. Executions from older SDKs, or recorded before the server indexed fingerprints, aren't
found; use `list_executions` for those.

## Comparing runs: `what_changed`

`what_changed` (`simulation`, optional `current_id`, `previous_id`) says what differs between two
executions without fetching their data:

- `code_changed`: whether their `CppModel.BinaryFingerprint` differs (`null` unless both have one);
- the parameters that changed (`old`/`new`), were added or were removed;
- every input and output name with `in`: `both`, `current` or `previous`.

Without ids it compares the simulation's two latest executions; with only `current_id`, that
execution and the one submitted before it; with both, those two. It doesn't compare signal
values: fetch those with `get_execution` and `signals`, or give the user its `uiUrl`, which overlays
both runs' signals in the web UI. Each run in the result also has its own `uiUrl`.

Start with it whenever the question is why a run differs from an earlier one: it says at once
whether the code was rebuilt, which values were different, and which signals appeared or
disappeared, so you fetch only the series that matter. If the server has no `what_changed`, fetch
both executions with `get_execution` (`summary: true`) and compare their parameters and signal
names yourself.

## Looking at signals: `export_signals`

`export_signals` (`simulation`, `format`, optional `execution_id`, default the latest) makes an
export of up to 8 signals of one execution, plus chosen parameters, and returns it in `format`:

- `png`: the chart as an image you can look at: steps on one time axis in seconds, a legend that
  notes scales and offsets, and the parameters as a caption. Use it to look for relationships
  between signals (cause and effect, the lag between a command and its response, interlocks) or
  for features of a signal's shape: overshoot, oscillation, settling, delays, steps, saturation,
  chattering.
- `csv`: a `time_ms` column (the union of every signal's x) and one column per signal, empty
  outside that signal's own time span. Use it when only the values matter, such as comparing
  signals at given times or computing a metric. Above 256 KiB it is cut at a row boundary and
  `csvTruncated` says so; narrow the export.
- `json`: the series `{label, source, scale, xOffset, yOffset, x, y}` with the range and transforms
  applied, change-compressed, plus `parameters`. For the raw series, `get_execution` with `signals`
  works as well.
- `none`: only the link.

```
export_signals {simulation: "CPidSystemSim", format: "png",
  signals: ["Setpoint", "PlantOutput", "ToleranceMax", "ToleranceMin",
            {label: "Settled", scale: 0.5}],
  parameters: ["Kp", "Ki", "Kd"], from: 0, to: 6000}
```

- **Check names first.** Take the labels from `summary: true`. Names are exact, and an unknown one
  is rejected (`HTTP 400 VALIDATION_ERROR`), never ignored. A signal is a label or `{label,
  source?, scale?, yOffset?, xOffset?}`. `source` (`inputs`/`results`) is needed only when a label
  is both an input and an output. The same label may appear more than once.
- **Narrow it to what matters.** `from`/`to` (ms of simulation time, applied before `xOffset`)
  around the moment of interest, such as a failure or a step change, and only the signals that
  explain it. That keeps the chart readable and the CSV small. Verification `violations` are in
  seconds; multiply by 1000 for `from`/`to`.
- **Put signals on one axis.** The plotted value is `y * scale + yOffset`: a 0/1 flag scaled to 0.5
  sits readably next to a signal near 1. `xOffset` (ms) lines a response up with its command.
  `width`/`height` set the PNG size (200–3000 px, default 1000 × 600).
- **Give the user the export's `uiUrl`, every time** (`<uiUrl>/snapshots/<id>`), so they see the
  same chart you looked at. The page also offers PNG and CSV downloads. `executionUiUrl` is the
  execution's page.
- **Exports are temporary.** They last 7 days (`expiresAt`), and stop working earlier if the
  execution is deleted. Never put a snapshot link in anything meant to last: documentation, a
  requirements-coverage file, a plan, a commit message. Link the execution's `uiUrl` there.
- **One export covers one execution.** To compare two runs, give `what_changed`'s `uiUrl`, which
  overlays both, or make one export per run. Only an overlay across many runs, such as a sweep's
  key signal over all runs, needs a chart of your own (`dataviz`).
- **Don't fetch export links with curl or a script.** They need the user's login; the tools return
  the PNG and CSV themselves.
- **Open a pasted link with `get_export`.** When the user pastes a `/snapshots/<id>` link, read it
  with `get_export` (`export`: the id or the link, `format`: `png`, `csv` or `json`), usually as
  `png` first. An expired or unknown export gives `HTTP 404 NOT_FOUND`; fall back to the
  execution, if the user knows which.

## The workspace is part of the loop

Every simulation run is submitted to the workspace, and its execution history is the record of the
work: each execution keeps the inputs and parameters it read and every output series, retrievable
by id later. So:

- **Every result you report comes from a recorded execution.** Never set
  `CPPMODEL_DISCARD_RESULTS` (removed in SDK 0.10.0; before 0.8: `CPPMODEL_OFFLINE`) and never pass
  `runOffline`. A run whose output has a line starting with `CppModel workspace:` (SDK 0.9.1+;
  before it, `Could not reach API. Running offline.`) produced nothing anyone can look at or
  compare later. Treat it as a run that didn't happen: fix the cause (`.env`, network, login) and
  run again.
- **Local runs are for exploring, not for results** (SDK 0.10.0+; see "Local runs" below).
  `--inputs <file> --results <out.json>` runs without submitting, so you can try values or check a
  fix many times while iterating. Its fingerprint line ends in `(not submitted)`. Whatever you
  then report, whether a pass/fail, a metric, a conclusion or a before/after comparison, comes from
  a recorded run of the same binary. Every iteration ends with one.
- **Compare runs through the history.** Before vs after a change, one scenario against another, a
  sweep against an earlier sweep: `list_executions` finds them, `what_changed` says what differs
  between two of them, and `get_execution` fetches each by id, with `signals` for just the series
  being compared. A sweep or other batch of one build is
  fetched with `get_binary_runs` instead. Two records with different `CppModel.BinaryFingerprint`
  came from different builds. Don't rebuild an old version to regenerate
  results the history already holds. Don't write scripts, extra tests, or extra printf/logging to
  collect data an execution already recorded.
- **Look before running.** If the question is "what did the simulation do when...", check the
  history first. Run again only when no execution covers it (different code, inputs, or
  parameters). For "what did I run last" or "the simulation I was working on", call
  `list_simulations` with `sort: "lastExecution"` (newest first) instead of paging through every
  name. `lastExecutionAt` is UTC, and `null` for a simulation whose latest execution was stored
  before the server recorded the time.
- **Keep simulation names stable.** The history is per name. A renamed simulation starts with an
  empty history and can't be compared with the old one by id, so rename only on purpose and say
  that this is the consequence.
- **One executable, one name.** Each simulation executable has exactly one fixed simulation name,
  and no other executable uses it, so its executions can be followed as one history
  (`cppmodel:simulation-testing`, "New case: input document or new simulation").
- **Name executions when reporting.** When reporting a result, give its execution id, or for a run
  of a batch its fingerprint and index, and its `uiUrl` from the tool's result, so the user and
  later sessions can find exactly that run.
- **History isn't clutter.** Never delete a simulation to tidy up (see `delete_simulation` above).

## Local runs

From SDK 0.10.0 a built simulation takes two options. The library reads them itself, so any binary
built against 0.10.0+ has them, `CMODEL_SIMULATE` and custom `main()`s alike:

- `--inputs <file>` (`-` = stdin) takes the inputs and parameters from the file instead of the
  workspace. The file is a `set_inputs` document, `{inputs, parameters}`; an execution record
  also works. The run still submits.
- `--results <file>` (`-` = stdout) writes the execution to the file instead of submitting it. The
  file has an execution record's shape (`inputs`, `results`, `parameters`, change-compressed
  series), so read it like `get_execution`'s result. On its own it still fetches the pending
  `set_inputs` document, without consuming it.

Both together make a **local run**: nothing is fetched or submitted. It still logs in, through the
same environment variables as a recorded run: `get_run_token`'s values set for that one command
only, never passed as an argument or written to a file:

```
CPPMODEL_ACCESS_TOKEN=<access_token> CPPMODEL_WORKSPACE=<workspace> CPPMODEL_LOGIN_TIMEOUT=0 ./build/<path>/<SimulationBinary> --inputs <file> --results <out.json>
```

The library checks the token's signature and expiry against the login server's keys, so a
missing, expired or forged token fails the run. Without the tool, a run falls back to
`.cppmodeltoken` or `.env`. `--results` is refused when `CI` is set.

Use local runs while iterating: trying parameter values before settling on a scenario, checking
whether a fix makes a failing trace pass, or exploring a coarse region before a sweep. Read the
results file directly, without a tool call. Don't use them for a test, `ctest`, CI, or to avoid a
run showing up in the history.

**End every iteration with a recorded run.** When an iteration is done, run the same binary again
with the same `--inputs <file>` and without `--results`. It submits, consumes any pending
`set_inputs` document, and prints its `Execution:` id. Then check it with `get_execution` (that id,
`expected` = the document) and report that execution, not the local file. With the SDK's
`cppmodel-tool`, `cppmodel-tool promote <binary> <file> --compare <out.json>` does the same run and
check, and also confirms the recorded run reproduced the local one. If it didn't reproduce (e.g. the
simulation uses randomness or wall-clock time), say so and report the recorded run. The local
results were only a preview.

## Workspaces

CppModel is multi-tenant: licensed accounts get a dedicated `w<number>.cppmodel.com` workspace,
free accounts share `free-workspace.cppmodel.com` (results are still per user). The MCP server
picks the workspace from the login; `get_workspace` says which one, with its `uiUrl`. Prefer the
`uiUrl` links the tools return. To build one yourself (name and ids URL-encoded):
`<uiUrl>/results/<name>` (a simulation's latest execution), `<uiUrl>/results/<name>/executions/<id>`
(one execution), `<uiUrl>/what-changed/<name>?current=<id>&previous=<id>` (two compared),
`<uiUrl>/snapshots/<id>` (a signal export, for 7 days) and `<uiUrl>/team-simulations`. Don't assume a `w<number>` workspace when explaining a URL.

## Running simulations still needs `.env`

The MCP server only reads and records data; it never runs anything. The simulation binaries
themselves (and `ctest`, and `cppmodel-tool` in CI) log in with `.env` at the project root:

```
CPPMODEL_USERNAME=...
CPPMODEL_PASSWORD=...
```

If `.env` is missing these when something has to run, tell the user and stop - do not guess or
fabricate credentials. The binaries cache the login in a `.cppmodeltoken` file in the directory
they run from. It holds a live access token: check that the project's `.gitignore` covers
`.cppmodeltoken` (anywhere in the tree) and `.env`, and offer to add them if not. Never print,
copy, or commit either file.

## Interpreting input/output signals in the results

A result (latest, or one execution by id) is one JSON document:

- `inputs`: a list of `{label, x, y}`, with every posted input plus the fallback of each
  `CppModel_getInput*` the simulation read that wasn't posted;
- `parameters`: the same for parameters, name → value, plus the reserved
  `CppModel.SimulationTime`/`StepSize`, in seconds, and `CppModel.BinaryFingerprint` (SDK
  0.7.0+, see above). A posted name appears even if the code never reads it;
- `results`: a list of `{label, x, y}` output series, including `CppModel.StepResult` (1 for a
  cycle that passed, 0 for one that failed).

`x` is simulation time in ms. Series are change-compressed: `x` holds only the times the value
changed, plus the end time, so the value between two points is the earlier point's `y`.

A simulation with verification rules (SDK 0.11.0+, `cppmodel:verification`) also records, per
rule:

- under `verification`, keyed by rule name, its outcome: `kind`, `status` (`pass`/`fail`/`error`),
  `pass`, `margins` (> 0 headroom, < 0 missed by that much, in the signal's units or seconds),
  `metrics`, `violations` (time intervals in **seconds**, not ms) and `explanation`;
- the output series `CppModel.Verify.<name>`: 1 until the rule first fails, then 0.

SDK 0.11.0 stored each outcome as the parameter `CppModel.Verify.<name>` instead; the MCP server
moves those into `verification`, so every execution reads the same. A local `--results` file is
the binary's own: with 0.11.0, look in its `parameters`.

A simulation that names requirements (`VerifyRequirement`, SDK 0.12.0+) also has `requirements`:
requirement ID → `{whole_run, steps, from_s, to_s}`, how the run covered it. Naming an ID says the
run addresses it; whether it was met is the run's own pass/fail. With 0.11.0 the IDs are only
printed and written to a local `cppmodel-requirements.json` (see `cppmodel:verification`, step 6).
Both fields are left out when the run has no rules or names no requirement.

For "why did it fail", read `verification` before fetching any series.

Whose inputs the `inputs` are depends on what the simulation runs (see
`cppmodel:simulation-testing`'s "which side is being simulated" note). For a plant-alone
simulation they are the plant's inputs (actuator commands) and outputs are its sensor readings.
For a controller or complete-system simulation they are all of the controller's inputs, as the
controller saw them: operator commands and setpoints, and the sensor signals the plant supplied
as fallbacks (or a posted value that overrode the plant). Outputs are its actuator commands and
plant signals the controller doesn't observe. There are no separate plant input/output series:
the cross-linked plant signals are the controller's.
