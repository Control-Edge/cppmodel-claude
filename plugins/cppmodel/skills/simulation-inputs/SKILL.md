---
name: cppmodel:simulation-inputs
description: Run a CppModel simulation with specific inputs (time series read by CppModel_getInput* / inputs["..."]) and parameters (constants read by CppModel_getParameter* / parameters["..."]) without editing or rebuilding it, by posting them to the Workspace API's /simulations/{id}/inputs endpoint right before a run. Finds the exact names the simulation reads, builds and validates the input document, posts it, runs the simulation, and confirms from the execution record that the values were really applied. Use when asked to run a simulation with given inputs/parameters or a named scenario, to try "what if <parameter> = X", or to see which inputs and parameters a simulation reads. For many runs over a range of values, use cppmodel:parameter-sweep instead.
---

## What this is

A simulation reads two kinds of external data:

- **Inputs**: time series, read each cycle with `CppModel_getInput{U8,...,F64}(self, "name",
  fallback)` in C, or `inputs.GetSafe("name", fallback)`/`inputs["name"]` in C++.
- **Parameters**: constants, read with `CppModel_getParameter{U8,...,F64}(self, "name", fallback)`
  in C, or the `parameters` JSON member in C++. `parameters` is `null` when nothing was posted,
  so read it with `parameters.value("name", fallback)` only after checking
  `parameters.is_object()`.

Before the simulation binary starts, you can post a document with values for them to
`/simulations/{id}/inputs`. Four facts, all confirmed against the live API, shape everything below:

1. **The document is one-shot.** The next execution consumes it; afterwards `GET .../inputs`
   returns 404 ("No input data found") until something is posted again. Post right before each
   run.
2. **A name that isn't posted silently uses the fallback** in the code. A misspelled name looks
   like a normal run with default values.
3. **Every execution records what the simulation actually read.** Its `inputs` and `parameters`
   list every name the binary read, with the value it got: posted values, or fallback values for
   names that weren't posted. This is how names are discovered (step 1) and how a run is verified
   (step 5).
4. **The server stores whatever it's sent without validating it.** A wrong shape or mismatched
   `x`/`y` lengths are accepted silently. Validate before posting (step 3).

Document format (`SimulationInputs` in `${CLAUDE_PLUGIN_ROOT}/api/workspace-api.yaml`):

```json
{
  "executionTime": "22-09-2026 05:33:47",
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

`.env` at the project root with `CPPMODEL_USERNAME` and `CPPMODEL_PASSWORD` (the client id
defaults to `cppmodel-frontend`); see `cppmodel:simulation-testing`. If they're missing, tell the
user and stop. The simulation doesn't need to have run before for a POST to be accepted.

All API access goes through the plugin's fetch script. Use `cppmodel-fetch.ps1` with the same
arguments from a plain PowerShell prompt:

```
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh inputs "<simulation name>"                  # pending document (404 = none)
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh set-inputs "<simulation name>" <file.json>   # post one
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh "<simulation name>"                         # latest execution record
```

## 1. Find every input and parameter name

Use two sources:

- **The latest execution record** (`cppmodel-fetch.sh "<simulation name>"`). Its `inputs[].label`
  and `parameters` keys are exactly the names the binary read on its last run, with the values it
  got. If the simulation has never run, build and run it once as `cppmodel:simulation-testing`
  describes, with nothing posted, so every value is a fallback, then read the record.
- **The source**, for what the record can't tell you:
  - Grep for `CppModel_getInput`/`CppModel_getParameter` (C), or `inputs[`,
    `inputs.GetSafe(`, and `parameters` (C++), including inside project wrappers and plant models.
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

```
cppmodel-fetch.sh inputs "<simulation name>"
```

The normal answer is 404, meaning nothing is pending. If a document comes back, someone (the web
UI, a teammate, an interrupted run) posted it for the next execution and it hasn't been consumed.
Save it to a scratch file and show it to the user before replacing it, since posting overwrites
it.

## 3. Author and validate the document

Start from the step-1 execution record's `inputs` and `parameters`, so everything the user didn't
ask to change keeps today's values explicitly. Then apply the user's changes.

Inputs:

- **`x` is simulation time in milliseconds**, ascending, starting at `0`. `y` has the same length.
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

Set `executionTime` to now, as `DD-MM-YYYY HH:MM:SS`.

The server won't catch mistakes, so check before posting:

- the top level is `{"inputs": [...], "parameters": {...}}`
- every input has `label`, `x`, and `y`, with equal lengths and `x` ascending
- every parameter value is a number
- names match step 1 exactly

Save the document as a file:

- a one-off experiment goes in the scratch area;
- a scenario worth repeating goes in the project, e.g.
  `simulations/scenarios/<simulation>/<scenario>.json` (match an existing convention).

Ask the user which.

## 4. Post, then run immediately

```
cppmodel-fetch.sh set-inputs "<simulation name>" <file.json>
```

Build and run the binary straight away, as `cppmodel:simulation-testing` describes ("Build and
run"), with `.env` sourced. Any other execution of this simulation in between would consume the
document instead: a `ctest` run, a CI job on the same account, or a run started from the web UI.
Check none is running.

If the binary's output says `Could not reach API. Running offline.`, it never fetched the document.
Say so and stop.

## 5. Confirm the values were applied, then report

Fetch the execution record:

```
cppmodel-fetch.sh "<simulation name>"
```

Compare its `parameters` and `inputs` with what you posted:

- **Posted parameters** should appear with the posted value.
- **Posted input series** should match when read with the hold rule. The recorded series are
  change-compressed: `x` holds only the times the value changed, plus the end time.
- **A posted name missing from the record** was never read by the simulation. It's a typo, or
  isn't used on this code path.
- **A recorded value equal to the fallback instead of the posted value** means the document
  wasn't applied. Stop and report it plainly, with posted vs recorded values. This run's results
  describe the default run, not the requested scenario. Don't present them as the scenario's
  outcome, and don't work around it by editing the simulation's fallback values, unless the user
  asks for that explicitly.

Once the values are confirmed, report:

- pass/fail: the exit code, and whether `CppModel.StepResult` in `results` ever dropped to 0
- what the scenario showed in the outputs the user cares about

If the run failed and the reason isn't obvious, continue with `cppmodel:simulation-testing`'s
"Debugging a failure" section.

## 6. Afterwards

The document was consumed, so nothing needs restoring and later runs (`ctest`, CI) are unaffected.
To run the same scenario again, post the saved file again before the run. If step 2 found someone
else's pending document that you replaced, tell the user it's gone, and offer to re-post the copy
saved in step 2.
