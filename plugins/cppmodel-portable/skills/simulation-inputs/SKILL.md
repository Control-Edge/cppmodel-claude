---
name: simulation-inputs
description: "Run a CppModel simulation with specific inputs (time series read by CppModel_getInput* / inputs[\"...\"]) and parameters (constants read by CppModel_getParameter* / parameters[\"...\"]) without editing or rebuilding it: passed to the binary with --inputs <file> (SDK 0.10.0+), or posted through the cppmodel MCP server's set_inputs right before a run with older SDKs. Finds the exact names the simulation reads, builds and validates the input document, runs the simulation with it (exploring locally first if useful), and confirms from the execution record that the values were really applied. Use when asked to run a simulation with given inputs/parameters or a named scenario, to try \"what if <parameter> = X\", to compare input profiles, or to see which inputs and parameters a simulation reads. For many runs over a range of values, use cppmodel:parameter-sweep instead. For a case needing its own logic (sequences, faults, its own checks), not just values, write a new simulation (cppmodel:simulation-testing)."
---

## Reading notes

- This is the cppmodel plugin's `simulation-inputs` skill. It was written for Claude Code, but applies to any
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

## What this is

This runs an existing simulation with different *values*. Whenever a case can be expressed by
inputs and/or parameters alone, this is the way to run it: write no new C/C++ file and don't
edit the simulation. If the request needs logic the
simulation doesn't already describe (stimuli that react to state, a sequence, a fault, a different
variant, its own assertions), don't encode it in an input document: offer a new simulation in
C/C++ instead (`cppmodel:simulation-testing`, "New case: input document or new simulation").

A simulation reads two kinds of external data:

- **Inputs**: time series, read each cycle with `CppModel_getInput{U8,...,F64}(self, "name",
  fallback)` in C, or `inputs.GetSafe("name", fallback)`/`inputs["name"]` in C++.
- **Parameters**: constants, read with `CppModel_getParameter{U8,...,F64}(self, "name", fallback)`
  in C, or `GetParameter("name", fallback)` in a C++ `Simulation` subclass.

**Posted documents are applied from SDK 0.6.1 on.** SDK 0.6.0 fetches and consumes them without
applying them, so every run silently uses the fallbacks. Check the vendored version first: from
0.8 it's `PACKAGE_VERSION` in `dependencies/lib/cmake/cppmodel/cppmodelConfigVersion.cmake`;
without that file, look for `CppModel_resetData` in `dependencies/include/cppmodel/CModel.h`,
which 0.6.1 added. If it's older, offer `cppmodel:update-dependencies` before going further.

**From SDK 0.10.0, pass the document to the binary instead of posting it:** `<binary> --inputs
<file>` reads it from the file and submits as usual, so no other run can consume it first. The
same file with `--results <out.json>` added is a local run, which doesn't submit (see
`cppmodel:simulations`' "Local runs"). With an older SDK, post the document with the `cppmodel`
MCP server's `set_inputs` tool before the binary starts. Four facts, all confirmed against the live
API, shape everything below. The first applies to posted documents only:

1. **The document is one-shot and per account.** The account's next execution of the simulation
   consumes it; afterwards `get_pending_inputs` finds nothing until something is posted again.
   Other users' runs neither read nor consume it, but every run on the same account does (`ctest`,
   CI with the same login, the web UI). Post right before each run.
2. **A name that isn't posted silently uses the fallback** in the code. A misspelled name looks
   like a normal run with default values.
3. **Every execution records the values it ran with.** Its `inputs` and `parameters` hold every
   posted value, plus the fallback for each name the binary read that wasn't posted. A posted
   value always wins over the fallback. This is how a run is verified (step 5). A posted name the
   code never reads is recorded too, so the record can't reveal a typo; check names against the
   source before posting (step 1).
4. **The document replaces any pending one, and must be complete.** `set_inputs` checks its
   shape and compares its names with the latest execution: `unrecognizedNames` were never
   recorded there (likely typos), `notPosted` will use their fallbacks. Use `dry_run: true` to get
   that check without posting (step 3).

Document format (the `set_inputs` arguments besides `simulation`):

```json
{
  "inputs": [
    { "label": "Desired Velocity [mm/s]", "x": [0, 300, 600], "y": [50.0, 150.0, 30.0] }
  ],
  "parameters": {
    "Max Acceleration [m/s^2]": 4.0,
    "CppModel.SimulationTime": 1.2,
    "CppModel.SimulationStepSize": 0.001
  }
}
```

## Requirements

- The `cppmodel` MCP server, authenticated (see `cppmodel:simulations`). It provides
  `get_pending_inputs`, `set_inputs`, `get_latest_result` and `get_binary_runs`, used below. The
  check in step 5 needs a server version whose execution tools take `expected`. The simulation
  doesn't need to have run before for a post to be accepted.
- A login to run the binary as the account the MCP server is connected as: `get_run_token` (SDK
  0.9.0+), else `.cppmodeltoken` or `.env` at the project root with `CPPMODEL_USERNAME` and
  `CPPMODEL_PASSWORD`; see `cppmodel:simulation-testing`'s "Requirements". If there's none, tell the
  user and stop.

## 1. Find every input and parameter name

Use two sources:

- **An execution record from a run with nothing posted.** Its `inputs[].label` and `parameters`
  keys are exactly the names the binary read, each with its fallback value. A record from a run
  that consumed a posted document also contains that document's names, whether the code reads
  them or not. So if the latest execution consumed one (its values differ from the fallbacks), or
  the simulation has never run, build and run it once with nothing pending, as
  `cppmodel:simulation-testing` describes, then read the record.
- **The source**, which is authoritative and also gives what the record can't:
  - Grep for `CppModel_getInput`/`CppModel_getParameter` (C), or `inputs[`,
    `inputs.GetSafe(`, and `GetParameter(`/`parameters` (C++), including inside project wrappers
    and plant models.
  - Record each name's C type suffix (`U8`, `I32`, `F64`...), which gives its range and whether
    it's integral.
  - Note any name read only on some code paths; it's missing from a record whose run never
    reached that path.

Each name goes where the code reads it: `getInput` names under `inputs`, `getParameter` names
under `parameters`. Posting a name in the wrong section is the same as not posting it. Keys
starting with `CppModel.` are reserved (see step 3).

Then settle whose inputs they are (`cppmodel:simulation-testing`'s "which side is being
simulated"):

- **Plant alone** (no controller in the binary): the inputs are the plant's, its actuator commands
  and environment. Author them from the plant's point of view.
- **Controller or complete system**: the inputs are the controller's, under its own names. The
  plant is feedback: it is evaluated first and supplies the fallback of each input it models
  (sensors), so with nothing posted those inputs follow the plant. Author the document as what
  reaches the controller from outside (operator commands, setpoints, other units' signals). Post
  a plant-fed input only to force it on purpose (a stuck switch, a failed sensor): the posted
  series replaces the plant's value for the whole run. Never write a plant actuator command into
  it: the controller produces those.

For each input, note in the table whether its fallback comes from the plant or is a constant (from
the source: what the `getInput` call passes). Show the user the table (name, input or parameter, type, current or fallback value)
before authoring anything.

## 2. Check nothing is already pending

Call `get_pending_inputs`. The normal answer is that nothing is pending. If a document comes back,
something on this account (the web UI, an interrupted run or sweep, another session) posted it for
the next execution and it hasn't been consumed. Save it to a scratch file and show it to the user
before running: posting overwrites it, and a recorded run with `--inputs` consumes it without using
it.

## 3. Author and validate the document

Start from the step-1 execution record's `inputs` and `parameters`, so everything the user didn't
ask to change keeps today's values explicitly. Then apply the user's changes. **In a closed-loop
simulation, first drop every plant-fed input** from that base: the record holds the plant's trace
from that run, and posting it back would replace the plant with a fixed replay and open the loop.
Keep one only if the user asked to force it.

Inputs:

- **`x` is simulation time in milliseconds**, strictly ascending, starting at `0`. `y` has the
  same length.
- **Values are held between points** (zero-order hold). At time t the input reads the `y` of the
  latest `x` <= t, and the last point holds to the end.
  - A step needs one point at the step time: `x: [0, 300], y: [50, 150]`. Paired points like
    `[..., 299, 300, ...]` from the UI are equivalent.
  - A ramp has to be written as a staircase of points. Going finer than the simulation step size
    gains nothing, because the binary only reads at step boundaries.
- **Integral types get whole numbers within the type's range.** Booleans are `0`/`1`.
- **Several cases can share one document.** Inputs are time series, so cases can be
  chained along the time axis (nominal, then a load step, then stop-and-go), each starting once
  the system is back in a known state, and one run covers them all. That's the benefit, not a
  compromise: the one trace shows every failure across the sequence, so the user explores them
  all from a single run instead of rerunning case by case. Lengthen the run to fit if
  the simulation honours `CppModel.SimulationTime` (see Parameters below). Parameters can't be
  chained: they're constant for the whole run, so a different parameter set is another run
  (`cppmodel:parameter-sweep`).
- **Write the scenario from the perspective step 1 settled.** In a closed-loop simulation a
  scenario is what the operator or the surrounding system does to the controller ("press start at
  1 s, raise the setpoint at 5 s"), not what the actuators do; the plant produces the rest. A
  request phrased as plant behaviour ("the motor runs up for 2 s") is translated into the
  controller inputs that cause it, or, if none do, raised with the user.

Parameters:

- One number per name.
- `CppModel.SimulationTime` and `CppModel.SimulationStepSize` are reserved. They're **in
  seconds** (input `x` is in milliseconds), and the execution record shows the values from
  `CMODEL_SIMULATE(...)`/`CppModel_create(...)`, which take milliseconds. Keep them as recorded.
  Don't use them to change the run length unless a run confirms the binary honours them: check
  that the recorded time axis actually changed.
- `CppModel.BinaryFingerprint`, copied along with a record's parameters, is left out by
  `set_inputs` with a warning: each binary records its own. That warning is expected.

Check the document before posting:

- every input has `label`, `x`, and `y`, with equal lengths and `x` strictly ascending from `0`
- every parameter value is a number
- names match step 1 exactly

Then call `set_inputs` with `dry_run: true`. A broken document comes back as an error listing
every problem ("The document wasn't posted: ..."); fix them all. A valid one returns `posted:
false` with `unrecognizedNames`, `notPosted` (`{inputs, parameters}`) and `warnings`. Treat every
`unrecognizedNames` entry as a typo until the source proves otherwise, confirm every `notPosted`
name is meant to use its fallback (plant-fed inputs in a closed loop are expected there), and show
the user any `warnings`.

Save the document as a file:

- a one-off experiment goes in the scratch area;
- a value variant worth repeating goes in the project, e.g.
  `simulations/inputs/<simulation>/<case>.json` (match an existing convention).

Ask the user which. A case worth keeping that turned out to be more than values (it needed a
particular order of events or its own check) belongs in code: offer a new simulation or step
instead of the file. With SDK 0.13.0+ the document itself can be one step of such a simulation
(an inputs step, `cppmodel:simulation-testing`), so it isn't rewritten as code.

## 4. Run with the document

### SDK 0.10.0+: pass the file

Build the binary, call `get_run_token`, and run it with the saved file, with the token set for that
one command only, as `cppmodel:simulation-testing` describes ("Build and run"):

```
CPPMODEL_ACCESS_TOKEN=<access_token> CPPMODEL_WORKSPACE=<workspace> CPPMODEL_LOGIN_TIMEOUT=0 ./build/<path>/<SimulationBinary> --inputs <file>
```

Nothing else can consume the file, so other runs of the simulation meanwhile don't matter. The run
still consumes a document pending from `set_inputs` when it submits. Step 2 saved that document, if
there was one.

**When the user wants to try several values first**, e.g. to find the one that meets a requirement,
explore with local runs: the same command with `--results <scratch>/out-<n>.json` added, one
document file per try. Read each results file directly, change the document, and run again.
Nothing reaches the workspace. When the values are settled, run the chosen file once more without
`--results`. That recorded run is the result. Never report a local run's numbers as the
scenario's outcome (`cppmodel:simulations`' "Local runs").

### Older SDKs: post, then run immediately

Call `set_inputs` with the saved document (without `dry_run`). Build the binary, then call
`get_run_token` and run it straight away with `CPPMODEL_ACCESS_TOKEN=<access_token>
CPPMODEL_WORKSPACE=<workspace>` set for that one command only, as `cppmodel:simulation-testing`
describes ("Build and run"). Never store the token in a file. Without the tool, run it with `.env`
sourced. The token makes the run belong to the account `set_inputs` posted for; a run as another
account doesn't consume the document. Any other
execution of this simulation in between would consume the document instead: a `ctest` run, a CI job
on the same account, or a run started from the web UI. Check none is running.

Either way, if the binary's output has a line starting with `CppModel workspace:` (SDK 0.9.1+;
before it, `Could not reach API. Running offline.`), it couldn't log in to or reach the workspace
and submitted nothing. Say so, with that line, and stop. A line starting with `CppModel: --inputs`
means the file is unusable. It names the problem, so fix the file and run again.

## 5. Confirm the values were applied, then report

Read the fingerprint from the run's output. From SDK 0.7.2 on, the simulation prints
`CppModel.BinaryFingerprint: <n>` when it finishes, followed by `Execution: <id>` when the server
returned the new execution's id. `(not submitted)` after the fingerprint means the execution never
reached the workspace: there's nothing to check, so say so and stop. An SDK from 0.7.0 to 0.7.1
records the fingerprint without printing it. Take it from `CppModel.BinaryFingerprint` in
`get_latest_result`'s `parameters` instead.

Fetch the run and check it in one call, passing the document (`{inputs, parameters}`, as posted or
as in the `--inputs` file) as `expected`, and `signals` to limit the record to the series you posted and the outputs you
need:

- `get_binary_runs` with `simulation`, `fingerprint`, `start: total - 1`, `count: 1` and
  `expected: [document]`, where `total` comes from a first call with `count: 0`. This finds your run
  even when other people run the same simulation, as long as nobody else ran this same binary in
  between.
- `get_execution` with the printed `Execution:` id and `expected: document` is the same check, and
  the simplest one for a run with `--inputs`.
- `get_latest_result` with `expected: document` is enough when nobody else runs this simulation.
  It also works with SDK 0.6.1 to 0.6.4, which record no fingerprint.

The result gets `applied` and `differences`:

- **`applied: true`**: every posted parameter was recorded with the posted value, and every posted
  input series matches the record under the hold rule. A posted name the code never reads is
  recorded too, so this doesn't rule out a typo. Step 1's check against the source does that.
- **`applied: false`**: `differences` has one line per posted value the run didn't use, with
  posted and recorded values. The document wasn't applied, and the usual cause is an SDK older
  than 0.6.1. Stop and report it plainly, quoting the `differences`. This run's results describe
  the default run, not the requested scenario. Don't present them as the scenario's outcome, and
  don't work around it by editing the simulation's fallback values, unless the user asks for that
  explicitly.

Once the values are confirmed, report:

- pass/fail: whether `CppModel.StepResult` in `results` ever dropped to 0. The exit code is 0
  for a pass and nonzero for a fail, but the nonzero value depends on the shell (255 on
  Linux/macOS and in Git Bash, -1 or 4294967295 in PowerShell, 127 through Git Bash's `timeout`,
  which is also "command not found"). Go by `StepResult`, not by the code.
- what the scenario showed in the outputs the user cares about; optionally a `png` export of
  those outputs (`export_signals`, see `cppmodel:simulations`' "Looking at signals") with its
  link. The link expires after 7 days, so the execution id and `uiUrl` stay the durable reference
- the execution id (from `list_executions`) or the run's fingerprint and index, so this run can
  be found and compared later, and its `uiUrl`

To compare the scenario with the default run or an earlier scenario, use `what_changed` with both
execution ids for the parameters that differ and the comparison's `uiUrl`, then fetch both with
`get_execution` for the signals you report (see `cppmodel:simulations`' "Comparing runs"), instead
of rerunning the other one.

If the run failed and the reason isn't obvious, continue with `cppmodel:simulation-testing`'s
"Debugging a failure" section.

## 6. Afterwards

Nothing is left pending, so later runs (`ctest`, CI) are unaffected. To run the same scenario
again, pass the saved file with `--inputs` again (or post it again with an older SDK). If step 2 found a pending
document that you replaced, tell the user it's gone, and offer to re-post the copy
saved in step 2.

## Starting over: deleting a simulation's data

To wipe a simulation's executions, stored parameters, and any pending document (the same as deleting
it in the UI), use the `delete_simulation` tool. The code can do the same itself with
`CppModel_resetData(sim)` (C) or `ResetData()` (C++), called before
`CppModel_Simulate`/`Simulate()`. Both are irreversible and remove the execution history other
people may rely on. Only do it when the user asks, after saying exactly what will be lost. A
simulation that has never executed can't be deleted, and a document posted for it stays pending
until its first run consumes it.