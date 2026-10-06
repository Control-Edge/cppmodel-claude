---
name: cppmodel:simulation-inputs
description: Run a CppModel simulation with specific inputs (time series read by CppModel_getInput* / inputs["..."]) and parameters (constants read by CppModel_getParameter* / parameters["..."]) without editing or rebuilding it, by posting them through the cppmodel MCP server's set_inputs right before a run. Finds the exact names the simulation reads, builds and validates the input document, posts it, runs the simulation, and confirms from the execution record that the values were really applied. Use when asked to run a simulation with given inputs/parameters or a named scenario, to try "what if <parameter> = X", or to see which inputs and parameters a simulation reads. For many runs over a range of values, use cppmodel:parameter-sweep instead.
---

## What this is

A simulation reads two kinds of external data:

- **Inputs**: time series, read each cycle with `CppModel_getInput{U8,...,F64}(self, "name",
  fallback)` in C, or `inputs.GetSafe("name", fallback)`/`inputs["name"]` in C++.
- **Parameters**: constants, read with `CppModel_getParameter{U8,...,F64}(self, "name", fallback)`
  in C, or `GetParameter("name", fallback)` in a C++ `Simulation` subclass.

**Posted documents are applied from SDK 0.6.1 on.** SDK 0.6.0 fetches and consumes them without
applying them, so every run silently uses the fallbacks. Check the vendored version first: look
for `CppModel_resetData` in `dependencies/include/cppmodel/CModel.h`, which 0.6.1 added. If it's
older, offer `cppmodel:update-dependencies` before going further.

Before the simulation binary starts, you can post a document with values for them with the
`cppmodel` MCP server's `set_inputs` tool. Four facts, all confirmed against the live API, shape
everything below:

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
  `get_pending_inputs`, `set_inputs`, and `get_latest_result`, used below. The simulation doesn't
  need to have run before for a post to be accepted.
- `.env` at the project root with `CPPMODEL_USERNAME` and `CPPMODEL_PASSWORD`, to run the binary;
  see `cppmodel:simulation-testing`. If they're missing, tell the user and stop.

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

Show the user the table (name, input or parameter, type, current or fallback value) before
authoring anything.

## 2. Check nothing is already pending

Call `get_pending_inputs`. The normal answer is that nothing is pending. If a document comes back,
something on this account (the web UI, an interrupted run or sweep, another session) posted it for
the next execution and it hasn't been consumed. Save it to a scratch file and show it to the user before replacing it, since posting
overwrites it.

## 3. Author and validate the document

Start from the step-1 execution record's `inputs` and `parameters`, so everything the user didn't
ask to change keeps today's values explicitly. Then apply the user's changes.

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
name is meant to use its fallback, and show the user any `warnings`.

Save the document as a file:

- a one-off experiment goes in the scratch area;
- a scenario worth repeating goes in the project, e.g.
  `simulations/scenarios/<simulation>/<scenario>.json` (match an existing convention).

Ask the user which.

## 4. Post, then run immediately

Call `set_inputs` with the saved document (without `dry_run`). Build and run the binary straight
away, as `cppmodel:simulation-testing` describes ("Build and run"), with `.env` sourced. Any other
execution of this simulation in between would consume the document instead: a `ctest` run, a CI job
on the same account, or a run started from the web UI. Check none is running.

If the binary's output says `Could not reach API. Running offline.`, it never fetched the document.
Say so and stop.

## 5. Confirm the values were applied, then report

Fetch the execution record with `get_latest_result` (pass `signals` to limit it to the series
you posted and the outputs you need). On a simulation others run too, make sure it's your run:
with SDK 0.7.0+, its `CppModel.BinaryFingerprint` is your binary's (`cppmodel-tool fetch
fingerprint <binary>`, if the tool is built, prints it), and `get_binary_runs` with that
fingerprint fetches your run by index. Compare its `parameters` and `inputs` with what you posted:

- **Posted parameters** should appear with the posted value.
- **Posted input series** should match when read with the hold rule. The recorded series are
  change-compressed: `x` holds only the times the value changed, plus the end time.
- **A recorded value equal to the fallback instead of the posted value**, or a posted name
  missing from the record, means the document wasn't applied. The usual cause is an SDK older
  than 0.6.1. Stop and report it plainly, with posted vs recorded values. This run's results
  describe the default run, not the requested scenario. Don't present them as the scenario's
  outcome, and don't work around it by editing the simulation's fallback values, unless the user
  asks for that explicitly.

Once the values are confirmed, report:

- pass/fail: whether `CppModel.StepResult` in `results` ever dropped to 0. The exit code is 0
  for a pass and nonzero for a fail (255 on Linux/macOS, -1 on Windows).
- what the scenario showed in the outputs the user cares about
- the execution id (from `list_executions`) or the run's fingerprint and index, so this run can
  be found and compared later

To compare the scenario with the default run or an earlier scenario, fetch both executions by id
with `get_execution` (see `cppmodel:simulations`' "The workspace is part of the loop"), instead of
rerunning the other one.

If the run failed and the reason isn't obvious, continue with `cppmodel:simulation-testing`'s
"Debugging a failure" section.

## 6. Afterwards

The document was consumed, so nothing needs restoring and later runs (`ctest`, CI) are unaffected.
To run the same scenario again, post the saved file again before the run. If step 2 found a pending
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