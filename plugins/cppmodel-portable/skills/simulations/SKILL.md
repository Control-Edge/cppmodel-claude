---
name: simulations
description: "Query CppModel Workspace API results - list simulations (sorted by name, latest run, latest committed run or execution count; or only those whose latest run was, or wasn't, committed), fetch the latest results, list execution history, see what changed between two runs (code, parameters, signals), list the builds (fingerprint or commit) that ran, or get chosen signals' statistics, per-step values and pass/fail across many executions at once (a sweep, a commit), with web UI links. Exports signals of one execution, or several runs on one chart, as an image to look at or a CSV, with a link for the user. Every run is submitted to the workspace, and its history is how runs are compared. Use when asked about CppModel simulation results, executions, how a run compares with an earlier one or what changed, the Workspace API, \"show me / plot / chart the signals\", \"look at the trace\", \"what did I run last\", \"what isn't committed yet\", or a pasted `/snapshots/` link, in a project that uses the CppModel libraries."
---

## Reading notes

- This is the cppmodel plugin's `simulations` skill. It was written for Claude Code, but applies to any
  AI assistant; these notes translate what's specific to Claude Code.
- `cppmodel:<name>` ("the `cppmodel:<name>` skill") is this plugin's `<name>` skill, in
  `<plugin>/skills/<name>/SKILL.md`: when this one says to use it, load that skill and follow it.
- "The `cppmodel` MCP server" is the one this plugin installs (`https://mcp.cppmodel.com/mcp`).
- `<plugin>` is the root of this plugin: the directory two levels above this file.
- "Ask with `AskUserQuestion`": use your client's multiple-choice question tool if it has one,
  otherwise ask in a message that lists the options, and wait for the answer.
- "Authenticate with `/mcp`": sign in to the `cppmodel` MCP server the way your client does.
- Other remarks about Claude Code only apply there.

---

## The tools: the `cppmodel` MCP server

All Workspace API access goes through the plugin's `cppmodel` MCP server
(`https://mcp.cppmodel.com/mcp`, declared in the plugin's `.mcp.json`). It signs in with the
user's CppModel account (free or licensed, both work the same) over OAuth, so querying results
needs no `.env` and no local tool. Running a simulation with chosen values, or a whole
parameter sweep, also needs nothing built besides the simulation: `set_inputs`, then run the
binary, then check the run with `get_binary_runs` and `expected`.

The server's instructions name the account and workspace the session is signed in as. Before the
first `cppmodel` tool call in a conversation, tell the user that account and workspace in one short
line, so they can stop you if it's the wrong one (e.g. a free account when they expected their
licensed workspace).

If the `cppmodel` tools aren't available, or fail with an authentication error, tell the user to
authenticate the server with `/mcp` and stop. Never re-implement API calls with curl, a script, or
an ad-hoc program instead, and never search the project for result files in their place.

| Tool | Use |
|------|-----|
| `list_simulations` | list simulations with execution counts, `lastExecutionAt` and its `gitHash` and `fingerprint`, and the newest run from a clean commit (`lastCommittedExecutionAt`, `lastCommittedGitHash`) (`scope: "team"` for the whole team; `sort` by `name`, `executions`, `lastExecution` or `lastCommittedExecution`; `order`; `tracking`: `committed`/`uncommitted`, see "Committed and uncommitted runs") |
| `get_latest_result` | the latest execution: inputs, parameters, results |
| `list_executions` | execution history, newest first, with id, time, status (up to 1000 per page) |
| `get_execution` | one past execution by id, same shape as `get_latest_result` |
| `what_changed` | what differs between two executions: code, parameters, signal names (see "Comparing runs") |
| `export_signals` | a chart (PNG, returned as an image), CSV or JSON of up to 8 signals of one execution, or of several executions on one chart, with a `/snapshots/<id>` link for the user (see "Looking at signals") |
| `get_export` | an export again, by id or `/snapshots/<id>` link, in any format |
| `get_binary_runs` | the runs of one simulation by one build, by run index, each with `passed` (see "Runs of one build") |
| `list_builds` | the builds that ran simulations, newest first, grouped by fingerprint or by commit (see "Runs of one build") |
| `query_executions` | chosen signals (as statistics, per-step values or series) and parameters of many executions in one call, each with pass/fail (see "Many runs side by side") |
| `get_pending_inputs` | the document waiting for this account's next execution (usually none) |
| `set_inputs` | post this account's next execution's inputs/parameters (see below) |
| `submit_execution` | record an execution no binary ran, such as measured data (see below) |
| `delete_simulation` | IRREVERSIBLE (see below) |
| `list_docs`, `get_docs`, `upload_docs`, `delete_docs` | the workspace's published documentation (w##### workspaces only); see `cppmodel:documentation`, "Publishing to the workspace" |
| `get_workspace` | which workspace the server is connected to, with UI and API URLs |
| `get_api_version` | the Workspace API version and its request size limit (`limits.maxRequestBytes`) |

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
must be a whole number, and its `CppModel.GitHash` a commit string; leave both out unless the data
really came from that binary.

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
reached the workspace, which from SDK 0.17.0 includes an execution over the workspace's 100 MB
limit: the run fails, printing its size, series and point count, and the fix is fewer recorded
signals, a coarser step or a shorter run). The
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

`list_builds` finds the builds themselves, newest first: executions grouped by
`CppModel.BinaryFingerprint` (`by: "fingerprint"`, the default) or by `CppModel.GitHash`
(`by: "gitHash"`), across all simulations or only some (`simulations`, exact names, or
`simulationPrefix`). Each row has the build's execution and simulation counts, its first and last
execution ids and times, and `lastGitHash` (by fingerprint) or `lastFingerprint` (by commit).
Filter by `fingerprint` to see which commits one binary ran with (a VirtualPLC build can span
several), or by `gitHash` to see which builds ran one commit (a developer's machine and CI, say).
Use it for "what did that commit run", "which builds ran today" or to find the fingerprint for
`get_binary_runs` or `query_executions` without fetching an execution first.
`list_simulations` also gives each simulation's newest `fingerprint`.

From SDK 0.15.0, a run whose executable is inside a git repository also records
`CppModel.GitHash`, the commit checked out when it started (e.g. `d6ebfd2`, with `-dirty` when a
tracked file had uncommitted changes; untracked build output doesn't count), and prints it next to
the fingerprint. It's the only parameter that is a string, and it's missing outside a repository
or without git. It tells a run on a developer's machine from a CI run of the same commit at a
glance.

### Committed and uncommitted runs

A simulation's newest execution is **committed** when its `CppModel.GitHash` has no `-dirty`: it
ran from a clean checkout of that commit. One with `-dirty`, or with no git hash at all, is
uncommitted. `list_simulations` reports, per simulation, `gitHash` (its newest execution's, `null`
without one) and `lastCommittedExecutionAt`/`lastCommittedGitHash` (its newest execution from a
clean commit). It can:

- keep only the simulations whose newest run was committed (`tracking: "committed"`) or not
  (`tracking: "uncommitted"`), e.g. for "what am I working on that isn't committed yet" or "which
  simulations still need a run from a clean commit (or CI)";
- sort by the newest committed run (`sort: "lastCommittedExecution"`), e.g. for "what did CI run
  last".

Simulations from SDKs before 0.15.0, or run outside a git repository, have no git hash and count
as uncommitted.

A **VirtualPLC** simulation (SDK 0.15.0+, a controller in Structured Text, see
`cppmodel:simulation-testing`) loads its `.st` files when it starts, so the fingerprint covers the
executable but not the PLC code: a change to the `.st` files alone keeps the same fingerprint, and
one build's runs in `get_binary_runs` may have run different PLC code. Compare
`CppModel.GitHash` (and its `-dirty`) for those, and don't edit the `.st` files during a batch.

## Many runs side by side: `query_executions`

`query_executions` returns chosen signals and parameters of many executions in one call, to compare
them without fetching each execution: a sweep, every run of a commit across several simulations,
or a few runs picked by id. Select the executions with any of `executionIds`, `fingerprint`,
`gitHash` (`includeDirty: true` also matches `<hash>-dirty`), `simulations` (exact names) and
`simulationPrefix`; given several, an execution must match all of them. Items come in execution-id
order (`order: "asc"`, the order they were submitted, by default), paged with `limit` (up to 500)
and `offset`; `total` counts every match and `nextOffset` is where the next page starts.

- `signals` (up to 32): exact labels, or `{label, source}` for one that is both an input and an
  output. One an execution lacks is listed in its `missing` rather than failing the call.
- `reduce` says what each signal comes back as: `"summary"` (default: first, last, min, max and the
  time-weighted mean over `from`..`to`, in ms), `"steps"` (one value per step of `stepSignal`,
  `CppModel.StepNumber` by default: the value held just before the next step starts) or
  `"series"` (the change-compressed series cut to `from`..`to`; can be large).
- `parameters`: the names to return, or `"*"` for all; one an execution lacks is `null`.
- With `verification` (default `true`) each item has `passed` (every `CppModel.StepResult` was 1;
  `null` without one), `failedRules`, `rulesPassed` and `rulesTotal`. Each item has its `uiUrl`.
- A result too big for the context is cut, and `truncated` says so: narrow the signals, the
  `reduce` or the page.

Use it for a sweep's metric table (pass/fail, a peak, a final value, per parameter set) instead of
paging `get_binary_runs` and computing the statistics yourself, and for "how did every simulation
do at this commit". It doesn't check `expected`: that stays with `get_binary_runs`.

## Comparing runs: `what_changed`

`what_changed` (`simulation`, optional `current_id`, `previous_id`) says what differs between two
executions without fetching their data:

- `code_changed`: whether their `CppModel.BinaryFingerprint` differs (`null` unless both have one;
  `false` for a VirtualPLC simulation whose Structured Text alone changed);
- the parameters that changed (`old`/`new`), were added or were removed, `CppModel.GitHash` among
  them (SDK 0.15.0+): a changed commit, or a `-dirty` appearing, shows there;
- every input and output name with `in`: `both`, `current` or `previous`.

Without ids it compares the simulation's two latest executions; with only `current_id`, that
execution and the one submitted before it; with both, those two. It doesn't compare signal
values: fetch those with `get_execution` and `signals`, export the signals that differ from both
runs on one chart (`export_signals`, "Compare runs on one chart"), or give the user its `uiUrl`,
which overlays both runs' signals in the web UI. Each run in the result also has its own `uiUrl`.

Start with it whenever the question is why a run differs from an earlier one: it says at once
whether the code was rebuilt, which values were different, and which signals appeared or
disappeared, so you fetch only the series that matter. It's one small call that reads no series,
far cheaper than fetching both executions and diffing them. If the server has no `what_changed`, fetch
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
  signals at given times or computing a metric. The table is the result's `csv` field (CRLF line
  ends). Above 256 KiB it is cut at a row boundary and `csvTruncated` says so; narrow the export.
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
  execution is deleted. In anything meant to last (documentation, a requirements-coverage file,
  a plan, a commit message) link the execution's `uiUrl`. Documentation may also note a snapshot
  link beside it, marked temporary with its `expiresAt` date, and keeps the chart itself as a PNG
  file next to its pages: the export result names the PNG the client saved
  (`[Image: source: <path>]`), so copy that file (`cppmodel:documentation`).
- **Compare runs on one chart.** A signal may come from another execution: `{label, executionId}`
  for another run of this simulation, plus `simulationId` for a run of another simulation (a
  measured `(field)` execution, a planned prediction, another use case). The same label from two
  parameter variants, before and after a fix, or a prediction against a measurement, then share
  one time axis, narrowed to the signals and window that matter, which `what_changed`'s overlay
  can't do. The legend and CSV columns name each signal's execution (`Speed · #7568`), and
  `parameters` are reported per execution as `<name> (#<id>)`; they must exist in the export's own
  execution (`execution_id`). The 8-signal limit covers all of them, so one chart holds up to 8
  runs of one signal. Only a chart no export draws, such as more runs than that or a metric per
  run (a sweep's pass/fail map), needs a chart of your own (`dataviz`).

  ```
  export_signals {simulation: "CPidSystemSim", execution_id: "7568", format: "png",
    signals: ["PlantOutput", {label: "PlantOutput", executionId: "7566"}, "Setpoint"],
    parameters: ["Kp"], from: 0, to: 6000}
  ```
- **Don't fetch export links with curl or a script.** They need the user's login; the tools return
  the PNG and CSV themselves.
- **Open a pasted link with `get_export`.** When the user pastes a `/snapshots/<id>` link, read it
  with `get_export` (`export`: the id or the link, `format`: `png`, `csv` or `json`), usually as
  `png` first. An expired or unknown export gives `HTTP 404 NOT_FOUND`; fall back to the
  execution, if the user knows which.

## Ask the workspace instead of writing scripts

For an agent, the cheapest way to learn something about a run is to let it submit and then ask
for exactly what the question needs. A recorded run costs nothing extra: the platform stores every
input, parameter and output, and evaluates the verification rules while it runs. Each question
after that is one tool call whose answer is already cut to size. A temporary script costs much
more:

- writing it, fixing it when it doesn't run the first time, running it, and reading its output;
- reading a whole results file or execution into context, every series of it, to find a few
  values;
- leftover files to clean up, and numbers the user can't open or check later.

Every run is submitted (SDK 0.17.0 removed `--results`, which wrote the execution to a file), so
ask the workspace for a `png` or `csv` export of just the signals and time window you need.

So match the question to the tool:

| You need | Ask for |
|---|---|
| which signals exist, their ranges | `get_execution`/`get_latest_result` with `summary: true` |
| a few series | `get_execution` with `signals` |
| values at given times, or a table to compute a metric from | `export_signals` `csv`, cut with `from`/`to` |
| the shape: overshoot, lag, oscillation, an interlock | `export_signals` `png`, and look at it |
| whether it passed, where and why it failed, how close it came | the execution's `verification` (rules, `cppmodel:verification`): status, `violations`, `explanation`, margins |
| why this run differs from an earlier one | `what_changed`: rebuilt or not, which parameters, which signals, in one small call |
| a whole batch of one build, with each run's `expected` checked | `get_binary_runs` with `summary` or `signals` |
| a metric, pass/fail or parameters across many runs (a sweep, a commit, picked ids) | `query_executions` with `reduce: "summary"` or `"steps"` |
| which builds or commits ran | `list_builds` |

- **Verification rules do the checking during the run.** A rule is checked every cycle by the
  library, and its outcome is stored with the execution: pass/fail, every violation interval, an
  explanation, and a margin in physical units (how much headroom, or how far it missed). That
  replaces scanning a trace after the run for timings, ranges, settling or oscillation. The same
  rule then checks every later run, `ctest` and CI run, and sweep run at no extra cost, and the
  margins show where a sweep's boundary lies. Hand-written checks or scripts give none of that.
- **`what_changed` is the cheap first step of any comparison.** It reads no series, yet it tells
  you whether the code was rebuilt, which parameters differ and which signals came or went, so you
  then fetch only the series that matter. Fetching two whole executions to diff them yourself
  costs far more, and its `uiUrl` overlays both runs for the user anyway.
- **Arithmetic over what the tools returned is fine**, such as a sweep's metric from fetched
  series. A chart no export draws (more than 8 runs, or a metric per run) is the one case for a
  chart of your own (`dataviz`). Not fine: scripts that parse result files, resample, plot one execution, diff
  executions, or re-check timings a rule could check.

## The workspace is part of the loop

**The workspace is an integral part of CppModel, not an optional upload target.** A CppModel
simulation is a run *and* its recorded execution: the library fetches the run's inputs from the
workspace, submits every run there, and pass/fail, verification outcomes, requirement coverage,
comparisons, charts and documentation evidence are all read back from it. There is no supported
way to use CppModel without it, so never try to work around it:

- don't run without submitting (no `--results`, `CPPMODEL_DISCARD_RESULTS`, `runOffline`, or a
  patched/stubbed library or login);
- don't capture or parse a run's stdout, logs or files for signal values, and don't add printf
  logging or extra outputs to get data the execution already records;
- don't reimplement checks, plots or comparisons in scripts when a verification rule,
  `export_signals` or `what_changed` does it;
- don't swap in a hand-written harness without the library to "test faster".

When the workspace can't be reached or the login fails, the run fails (`CppModel workspace:`):
stop and fix the login or network with the user, rather than finding another way to get a result.

Every simulation run is submitted to the workspace, and its execution history is the record of the
work: each execution keeps the inputs and parameters it read and every output series, retrievable
by id later. So:

- **Every result you report comes from a recorded execution.** Never set
  `CPPMODEL_DISCARD_RESULTS` (removed in SDK 0.10.0; before 0.8: `CPPMODEL_OFFLINE`) and never pass
  `runOffline`. A run whose output has a line starting with `CppModel workspace:` (SDK 0.9.1+;
  before it, `Could not reach API. Running offline.`) produced nothing anyone can look at or
  compare later. Treat it as a run that didn't happen: fix the cause (`.env`, network, login) and
  run again.
- **There are no local runs.** Every try, however exploratory, is a recorded run: trying values,
  checking a fix, a coarse pass before a sweep. SDK 0.17.0 removed `--results`, and a run started
  with it fails before it runs. With an SDK from 0.10.0 to 0.16.x it still wrote the execution to
  a file instead of submitting it; don't use it there either. Whatever you report, whether a
  pass/fail, a metric, a conclusion or a before/after comparison, comes from a recorded execution,
  read by the id the run prints (`Execution: <id>`).
- **Compare runs through the history.** Before vs after a change, one scenario against another, a
  sweep against an earlier sweep: `list_executions` finds them, `what_changed` says what differs
  between two of them, and `get_execution` fetches each by id, with `signals` for just the series
  being compared. A sweep or other batch of one build is
  fetched with `get_binary_runs` instead, and many runs' metrics at once with `query_executions`. Two records with different `CppModel.BinaryFingerprint`
  came from different builds. Don't rebuild an old version to regenerate
  results the history already holds. Don't write scripts, extra tests, or extra printf/logging to
  collect data an execution already recorded.
- **Look before running.** If the question is "what did the simulation do when...", check the
  history first. Run again only when no execution covers it (different code, inputs, or
  parameters). For "what did I run last" or "the simulation I was working on", call
  `list_simulations` with `sort: "lastExecution"` (newest first) instead of paging through every
  name; for work not yet committed, add `tracking: "uncommitted"`. `lastExecutionAt` is UTC, and `null` for a simulation whose latest execution was stored
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

## Inputs from a file and exit codes

From SDK 0.10.0 a built simulation takes `--inputs <file>` (`-` = stdin). The library reads it
itself, so any binary built against 0.10.0+ has it, `CMODEL_SIMULATE` and custom `main()`s alike.
It takes the inputs and parameters from the file instead of the workspace. The file is a
`set_inputs` document, `{inputs, parameters}`; an execution record read from the workspace also
works. The run still submits, and consumes any pending `set_inputs` document, but the execution
records the values from the file. It logs in like any run: `get_run_token`'s values set for that
one command only, never passed as an argument or written to a file:

```
CPPMODEL_ACCESS_TOKEN=<access_token> CPPMODEL_WORKSPACE=<workspace> CPPMODEL_LOGIN_TIMEOUT=0 ./build/<path>/<SimulationBinary> --inputs <file>
```

Then check it with `get_execution` (the printed `Execution:` id, `expected` = the document) and
report that execution.

SDK 0.10.0 to 0.16.x also had `--results <file>`, which wrote the execution to a file instead of
submitting it (a "local run"). SDK 0.17.0 removed it: naming it fails the run before it runs. Don't
use it with an older SDK either, and if a project's scripts, `ctest` registrations or docs still
pass it, remove it (`cppmodel:update-dependencies`).

**Exit code.** From SDK 0.17.0 a `CMODEL_SIMULATE` run exits with 0 when every step passed and 1
when it failed (a failing step, a failed verification rule, or a run that couldn't start or
submit); a C++ `main()` returns `GetSimulationResult() == 0 ? 0 : 1`. The first failing step's
number is still the run's result (`GetSimulationResult()`, `CppModel_getSimulationResult()`), not
the exit code. Before 0.17.0 the exit code was that step number, cut by Linux/macOS shells to its
low 8 bits (a failure at step 256 exited 0) and shown as 255, 127 or 4294967295 for a failure
outside a step; with those SDKs judge a run by its recorded execution, not its exit code. Any
other code (e.g. 127, the binary or a DLL not found) means the program didn't run.

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
themselves (and `ctest`) log in with `.env` at the project root:

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
  `CppModel.SimulationTime`/`StepSize`, in seconds, `CppModel.BinaryFingerprint` (SDK
  0.7.0+, see above) and `CppModel.GitHash` (SDK 0.15.0+, a string, see above). A posted name
  appears even if the code never reads it;
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
moves those into `verification`, so every execution reads the same.

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
