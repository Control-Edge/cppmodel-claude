---
name: cppmodel:simulation-testing
description: Write, extend, or debug a CppModel-based simulation test, in C (the SDK's CModel.h API - CppModel_* functions and its CMODEL_CYCLIC/CMODEL_SIMULATE macros - directly or via a project's own helpers) or C++ (cppmodel::Simulation from cppmodel.hpp, CppModelBase::Simulation in older code, directly or via a project's own wrapper class). Use when asked to add test coverage to a CppModel simulation, to test a case that needs different logic or flow than an existing simulation (as another simulation; a case that only needs other inputs/parameters uses cppmodel:simulation-inputs, with no new file), when a simulation test fails and the reason isn't obvious from stdout, or when tightening timing-based assertions against real execution data.
---

## Requirements: check credentials before running or debugging anything

Running a simulation binary needs a CppModel account (free or licensed). The run belongs to the
account it logs in as, and only that account's runs consume what was posted with `set_inputs`. Use
the first of these that's available:

1. **The `cppmodel` MCP server's `get_run_token`** (SDK 0.9.0+). It returns `access_token`,
   `expires_in`, `workspace` and `account`: the account the MCP server is connected as, so the run
   reads that account's posted inputs. No credentials are stored in the project.
2. **`.cppmodeltoken` or `.env`** at the project root, the latter with:

   ```
   CPPMODEL_USERNAME=...
   CPPMODEL_PASSWORD=...
   ```

   Needed without the MCP server (CI, scripts) or with an SDK older than 0.9.0, which ignores the
   token variable.

Check this *before* running a binary, not after something fails. If neither is available, tell
the user and stop - do not guess, fabricate, or improvise a workaround (e.g.
searching the local filesystem for prior results, or writing new code to reconstruct what the API
would have returned). Writing or editing test/model code doesn't need credentials; running a
simulation does. Reading its outcome goes through the `cppmodel` MCP server (see
`cppmodel:simulations`); if its tools are unavailable or unauthenticated, tell the user to
authenticate it with `/mcp` and stop, for the same reason.

## Which side is being simulated: whose inputs they are

A simulation's inputs (`CppModel_getInput*` in C, `inputs["..."]`/`GetSafe` in C++) are always the
inputs of one component, named as that component sees them. Which component that is depends on
what the simulation runs:

- **The plant alone** (open loop, no controller in the binary; e.g. checking a new model from
  `cppmodel:plant-model` by itself): inputs are the **plant's** inputs - the actuator commands
  (`actuators` struct) plus any environment the plant takes (load, ambient). Outputs are its
  sensor readings and internal state.
- **The controller, or the complete system** (controller and plant together): inputs are the
  **controller's** inputs - its `inputs`/`in_signals` struct: sensor signals, operator commands,
  setpoints, signals from other units - under the controller's own names. The plant is there as
  feedback, not as the thing being driven by the document. Each cycle runs in this order:

  1. **Evaluate the plant**, its actuators set from the controller's previous outputs.
  2. **Read every controller input with `getInput`**. For an input the plant models (a limit
     switch, a position counter, a pressure), pass the plant's value as the fallback. For one the
     plant has nothing to do with (an operator button, a setpoint, a mode switch), pass a constant
     default.
  3. **Evaluate the controller.**
  4. **Publish with `setOutput`.**

  With nothing posted for an input, the controller gets the plant's value and the record shows
  exactly that, since an execution records the fallback it used. A posted value overrides the
  plant for that input, for the whole run (the last point holds to the end). That's intended: it
  is how a scenario forces a sensor (stuck switch, failed transducer). So post only the inputs the
  scenario sets; leaving a plant-fed input out keeps the loop closed.

  The focus is the controller, so its interface is the simulation's interface. Don't define the
  plant's inputs and outputs as signals of their own: where the two are cross-linked, plant inputs
  are the controller's outputs and plant outputs are the controller's inputs, under the
  controller's names. Outputs are the controller's outputs (the actuator commands), plus only those
  plant signals the controller doesn't observe (the true position when the controller only sees a
  limit switch, a pressure no sensor reports). Plant actuators are never inputs here. Without a
  plant model, every controller input comes straight from the document.

Pick the case before writing the per-cycle callback; it decides the input names. Don't mix them:
a closed-loop simulation never takes plant actuator commands as inputs, and a plant-alone one
never takes controller inputs. One cycle of a closed-loop simulation, in C:

```c
CMODEL_CYCLIC()
{
    /* 1. plant, driven by the previous cycle's controller outputs */
    plant.actuators.motor_up = ctrl.outputs.motor_up;
    plant.actuators.motor_down = ctrl.outputs.motor_down;
    plantModelCyclic(&plant, currentTime_ms);

    /* 2. controller inputs: the plant's value is the fallback, a posted value overrides it */
    ctrl.inputs.start_button = CppModel_getInputU8(self, "Start Button", 0);
    ctrl.inputs.upper_limit = CppModel_getInputU8(self, "Upper Limit", plant.sensors.upper_limit);
    ctrl.inputs.pressure_bar = CppModel_getInputF64(self, "Pressure [bar]", plant.sensors.pressure_bar);

    /* 3. controller */
    controller(&ctrl);

    /* 4. controller outputs */
    CppModel_setOutputU8(self, "Motor Up", ctrl.outputs.motor_up);
    CppModel_setOutputU8(self, "Motor Down", ctrl.outputs.motor_down);
    /* plant signal the controller doesn't observe */
    CppModel_setOutputF64(self, "Position [mm]", plant.position_mm);
    /* ... step schedule, CppModel.StepResult ... */
}
```

The C++ shape is the same: the plant is a member, evaluated first in `RunCyclic`, and each
controller input is read with `inputs.GetSafe("name", <plant value or default>)`.

## New case: input document or new simulation

Before writing any code for a new case, decide which of the two it is:

- **It can be expressed by inputs and/or parameters alone**: different values, time series or
  constants for what an existing simulation already does (a setpoint profile, another load, a
  tuned gain, an operator profile from a field log, a sweep). **Don't write another C/C++ file**
  and don't edit the simulation. Run the existing one with an input document (`--inputs`,
  `cppmodel:simulation-inputs`, or `cppmodel:parameter-sweep` for many), committed as an input
  document with its own `ctest` test if it should stay.
- **It needs different logic or flow**: anything inputs and parameters can't express, such as
  stimuli that react to the system's state ("press stop once the lift is half way"), a different
  sequence of steps, injected faults, a different controller or plant variant, or checks of its
  own. **Write another simulation** for it, in C/C++, rather than growing an existing one into a
  generic simulation driven by switches. CppModel is for C/C++ developers: code says this
  exactly, is checked by the compiler, and is reviewed like the rest of the project.

If unsure, try to write the input document first. If the case can't be stated in it without
pretending (a time series standing in for "when X happens"), it's another simulation.

- **Keep new simulations cheap.** Put the shared wiring (plant, controller, the per-cycle copy
  between them, common checks) in the project's own helper, header or base class, so each new
  simulation is mostly its step schedule and assertions. Reuse an existing one if the project has
  it.
- **Name each simulation after the behaviour it tests**, give it its own target, and register it
  with `ctest` (below). Each one gets its own execution history in the workspace and its own
  pass/fail in CI, so a failure points straight at the behaviour that broke.
- **One executable, exactly one simulation name.** A simulation is a single entity in the
  workspace, and its executions are followed by its name. Pass the name as a fixed literal
  (`CMODEL_SIMULATE("Name", ...)`, `CppModel_create("Name", ...)`, `name` in the C++
  constructor). Never derive it from a parameter, argument, environment variable or input
  document, and never run two simulations from one `main()`. No two executables share a name
  either, or their histories mix. Input-document variants of one executable run under its one
  name; each execution records the inputs it ran with, which tells them apart.

## Language: C or C++

Only relevant when creating a **brand-new** simulation file - skip this when extending or
debugging an existing one, whose language is already fixed by its file extension. Use the
`cppmodel:language` skill to decide, then jump to the matching subsection below.

## Anatomy of a simulation

Every CppModel simulation, in either language, does the same three things per cycle: runs one
callback per simulated `task_period_ms`/step, crosses the simulation boundary (read simulated
inputs, run one cycle of the code under test with the plant as feedback when the controller is in
the loop, publish outputs), and reports pass/fail for that
cycle via a `CppModel.StepResult` signal (1 = pass, 0 = fail - any single cycle returning 0 fails
the whole run, there's no "mostly passing"). How that's actually wired up is project-specific and
you must check what already exists before picking one - don't assume either shape below is what
this project uses without looking.

From SDK 0.11.0, verification rules can set `CppModel.StepResult` instead: objects created once
with a name and settings (`Always`, `Response`, `Settle`, `Mode`, `Oscillation`, ...) that the
library tracks over time, ANDed with whatever the simulation sets itself. When the pass/fail
criterion is about time or comes from a requirement (a range, an interlock, a deadline, settling,
a mode sequence, no oscillation), use rules and `VerifyRequirement` through
`cppmodel:verification` rather than hand-written step logic.

### C++

From SDK 0.13.0, the library schedules steps itself (its `documentation/Steps.md`):
`cppmodel::Scenario` and `RunScenario` here, `CMODEL_STEP`/`CppModel_runScenario` in C (below).

Check first whether this project has its own base class layered on top of
`cppmodel::Simulation` (or, in code written before SDK 0.8, `CppModelBase::Simulation` from
`cppmodel/Simulation.h` - the same class under its old names) - e.g. a project-specific wrapper might add a
`steps` map of `{time_ms, function}` chained through a `CallStep()`-like helper, a per-cycle entry
point override, and helpers for tracing which requirements each simulation exercises out to a
requirements file. If a wrapper like this exists anywhere in the project, subclass *that* and
follow its exact shape (populate its step container, override its per-cycle method, call its
requirement-tracing helper if the scenario covers a named requirement) - don't build a second,
competing mechanism alongside it. (From SDK 0.11.0 the library has its own `VerifyRequirement`; if
the project's helper predates it, ask before switching, see `cppmodel:verification`.)

If no such wrapper exists, `#include <cppmodel.hpp>` (C++17) and subclass `cppmodel::Simulation`
directly. Set `name`, `time_ms` and `stepSize_ms` in the constructor. Override `RunCyclic` as the
per-cycle callback, with the exact parameter type from the vendored `cppmodel.hpp`
(`unsigned long long simulationTime_ms` since SDK 0.6; before 0.8 it was in `cppmodel/Model.h`, and
releases before 0.6 used `double`). Use `inputs.GetSafe("name", fallback)` / `outputs["name"] = value`
to cross the boundary, and always set `outputs["CppModel.StepResult"]`. Read parameters with
`GetParameter("name", fallback)` (SDK 0.6.1+), which returns the posted value or else records and
returns the fallback; `.get<double>()` etc. converts it. `main()` constructs the simulation object,
calls `.Simulate()`, and returns `GetSimulationResult()`. The SDK's
`share/cppmodel/example/simulation.cpp` is a complete minimal one.

From SDK 0.8 a few semantics are worth knowing when writing or debugging C++ simulations:

- `inputs[...]`/`GetSafe()` return a value, not a reference: assigning to one does nothing.
- Inputs and outputs are numbers (`double`; `bool` converts to 0/1). Assigning a string or JSON
  object to an output throws. Parameters keep their JSON type.
- An exception thrown in `Init`/`RunCyclic`/`Finalize` aborts the run and is rethrown from
  `Simulate()`; library errors are `cppmodel::Error`. Uncaught, it ends the process with a
  nonzero exit and no submitted execution, so read the exception's message before looking for a
  trace.
- `Simulate()` throws when `stepSize_ms` is 0.

### C

C simulations `#include <CModel.h>`. Check first whether the project has its own helper header
(often `ModelHelpers.h`) with an `InternalStep_ts` step-schedule array run through
`RunInternalSteps`, or its own versions of the `CMODEL_*` macros. Grep for `CMODEL_SIMULATE`,
`InternalStep_ts` and `ModelHelpers.h` first - if present, use them exactly as existing C
simulations in the project do. Don't migrate such a project to the SDK's steps unasked; offer it
only when the user wants to.

Otherwise use `CModel.h` itself. Its macros are the shortest form: `CMODEL_CYCLIC() { ... }`
defines the per-cycle callback (`void RunCyclic(CModelSimulation_ts *self, unsigned long
currentTime_ms)`), and `CMODEL_SIMULATE("Name", totalTime_ms, task_period_ms)` expands to a `main()`
that creates, runs and destroys the simulation and returns its result. The SDK's
`share/cppmodel/example/simulation.c` is a complete minimal one. The same by hand:
`CppModel_create(name, totalTime_ms, task_period_ms)` (NULL on failure), `CppModel_setRunStepFunction(sim,
RunCyclic)`, `CppModel_Simulate(sim)`, `CppModel_getSimulationResult(sim)` as `main`'s return
value, then `CppModel_destroy(sim)`. Either way, cross the boundary with
`CppModel_getInput{U8,I32,...,F64}(self, "name", fallback)` / `CppModel_setOutput{U8,I32,...,F64}(self,
"name", value)` and `CppModel_getParameter{...}(self, "name", fallback)`, and call
`CppModel_setOutputU8(self, "CppModel.StepResult", result)` every cycle. Values cross as `double`
(from SDK 0.8), so an integer type round-trips exactly up to 2^53. A failing call prints
`CppModel: <function>(<name>) failed: ...` on stderr and returns the fallback.

### Either way

The simulation still needs a step schedule chaining the steps of its behaviour in one file, using
whatever mechanism the chosen path above provides (a project's own `steps` map/vector or
`InternalStep_ts` + `RunInternalSteps`, else the SDK's steps from 0.13.0, below). Keep the steps to that one behaviour; an unrelated behaviour gets its own
simulation ("New case: input document or new simulation" above). Give each distinct scenario a fresh `Init`-style reset function beforehand,
unless deliberately continuing from the previous scenario's end state (also a valid, commonly used
pattern - e.g. confirming a signal set in one step has the expected effect at the very start of
the next).

Assertion style: prefer "eventually true, with a grace window" over exact cycle-counting, e.g.
`return sawExpectedEvent || (localTime_ms < someGenerousMs);`. Real timing (motor ramps, debounce
timers, multi-state sequences) is easy to get wrong by hand - don't guess tight thresholds, derive
them from the actual physics/logic involved, then validate against a real trace (below) before
trusting them.

### The SDK's steps (SDK 0.13.0+)

Without a project mechanism, use the library's. Three words, one meaning each: an **input
document** is the JSON (`{"inputs": [...]}`), a **step** runs for a duration, and a **scenario**
is an ordered list of steps.

- **Step:** a function run every cycle for its duration. It gets the time since its step started
  (0 at its first cycle) and returns whether the cycle passed. C: `CMODEL_STEP(Fn, ms)`; C++:
  `{&Sim::Fn, this, ms}` or `{lambda, ms}`. No function (`NULL`/`nullptr`) only waits.
- **Nested scenario:** a short sequence that brings the system to a state ("start the motor"),
  written once and chained wherever a test needs that state. C: `CMODEL_STEP_SCENARIO(start)`;
  C++: the `Scenario` itself. Declare it before the scenario that uses it.
- **Inputs step:** an input document whose inputs are read during the step (`x` counts from the
  step's start), with an optional function checking each cycle. Use it for stimuli that are data,
  such as a field log or a profile, inside an ordered test. C: `CMODEL_STEP_INPUTS(path, CheckFn,
  0)`; C++: `cppmodel::Scenario::Inputs(path, &Sim::Check, this)`. Duration 0 is the document's
  length. Inputs passed with `--inputs` or posted still win, and the document's parameters are
  ignored. Pass the folder from CMake (`target_compile_definitions(... SIMULATIONS_DIR=...)`)
  rather than relying on the working directory.
- **Running it:** in the step function, call `CppModel_runScenario(self, &test, currentTime_ms)` /
  `RunScenario(test, simulationTime_ms)` **before reading inputs** (it loads the inputs steps'
  documents at time 0), and set `CppModel.StepResult` from its result. Create the simulation with
  the scenario's length: `CppModel_scenarioDuration(&test, stepMs)` / `test.Duration(stepSize_ms)`.
- **Timing:** each step lasts its duration rounded up to whole cycles, at least one; the last
  step continues to the end of the run. The step is found from the time, so a scenario needs no
  reset and can be reused anywhere.
- **Step numbers:** running a scenario records the running step's number, counted from 1 across
  the flattened schedule, as `CppModel.Step` and `CppModel.StepNumber`. A failed run's result and
  exit code are the first failing step's number.

The SDK's `simulations/MotorStarterC.c` and `MotorStarterCpp.cpp` are complete examples of all
three step kinds.

## Build and run

```
cmake --build build --target <SimulationName>
```

Then run the binary directly from the build folder, logged in as "Requirements" above describes.
With `get_run_token`, call it right before the run and set its values in the environment of that
one command only:

```
CPPMODEL_ACCESS_TOKEN=<access_token> CPPMODEL_WORKSPACE=<workspace> CPPMODEL_LOGIN_TIMEOUT=0 ./build/<path-to>/<SimulationName>
```

`CPPMODEL_LOGIN_TIMEOUT=0` (SDK 0.9.1+) makes a run that can't log in fail at once. Without it, the
run prints a sign-in link nobody will open and waits 60 seconds. Older SDKs ignore it, and their
browser sign-in waits indefinitely, so run those with a `timeout`.

Never write the token to a file, `.env`, a script or a log, and don't `export` it. A token lives
about 5 minutes, and the binary takes it once, at start: it must outlast the whole run, or the run
can't submit. If `expires_in` is under 60, or under the run's normal runtime plus a margin, wait
until it has expired and call `get_run_token` again. A run that prints `CPPMODEL_ACCESS_TOKEN is
expired or invalid; using the saved login instead.` ran as whatever `.cppmodeltoken`/`.env` logs in
as, possibly another account that didn't consume the posted inputs: say so and rerun with a fresh
token. A `ctest` run gets the token the same way, for the one command, and each simulation it
starts takes it again, so the whole `ctest` run must fit in `expires_in`. A run that can't fit in
one token's lifetime needs `.env`.

Without the tool, source `.env` instead (a saved login in `.cppmodeltoken` is used while it's
valid):

```
set -a && source .env && set +a && ./build/<path-to>/<SimulationName>
```

(With a Visual Studio generator the binary is under `build/<Config>/`.)

Exit code 0 means every cycle's `StepResult` was 1. Nonzero means at least one cycle failed, but
the binary itself gives no detail about which one - it only prints a `UI:` line, its
`CppModel.BinaryFingerprint`, and, once submitted, the new `Execution:` id. The `UI:` line's
`/simulations/<SimulationName>` path isn't a page of the current web UI; give the user the
`uiUrl` the `cppmodel` tools return for the execution instead (`cppmodel:simulations`). A binary that fails to start with a
missing `libcppmodel.so.1`/`libcppmodel.dylib`/`cppmodel.dll` was built without
`cppmodel_deploy_runtime(<target>)` (below). With MinGW, a binary that exits at once with no
output and code `0xc0000139` (-1073741511; 127 in Git Bash) loaded another program's
`libstdc++-6.dll` from PATH, often Git for Windows'. `cppmodel_deploy_runtime` copies only
`cppmodel.dll`, not the compiler's runtime, so link MinGW targets statically (below).

Every run is submitted to the workspace and stays in the simulation's execution history - see
`cppmodel:simulations`' "The workspace is part of the loop". Never set `CPPMODEL_DISCARD_RESULTS`
(removed in 0.10.0; before 0.8 `CPPMODEL_OFFLINE`) or `runOffline`. A run that can't log in to or
reach the workspace fails and prints a line starting with `CppModel workspace:` that says why (SDK
0.9.1+; before it, `Running offline.`, and it could still pass). Such a run didn't count, so fix the
cause (login, network) and rerun.

The one exception is a local run (SDK 0.10.0+), `--inputs <file> --results <out.json>`, while
iterating (see `cppmodel:simulations`' "Local runs"). Its `(not submitted)` is expected, and an
iteration always ends with a recorded run. Never add `--results` to a `ctest` registration or a CI
step.

A new simulation needs its target in the relevant `CMakeLists.txt` (SDK 0.8+; the project already
has `find_package(cppmodel)`), registered with `ctest`:

```
add_executable(<SimulationName> simulations/<SimulationName>.c models/<Name>Model.c)
target_link_libraries(<SimulationName> PRIVATE cppmodel::cppmodel)
cppmodel_deploy_runtime(<SimulationName>)  # copies the CppModel library next to the executable
add_test(NAME <SimulationName>Test COMMAND <SimulationName>)
```

A project built with MinGW also needs, once per target or project-wide,
`if(MINGW) target_link_options(<SimulationName> PRIVATE -static) endif()`, so the binary doesn't
depend on `libstdc++-6.dll`, `libgcc_s_seh-1.dll` and `libwinpthread-1.dll` being first on PATH.
`cppmodel.dll` stays a shared library next to the executable either way.

Match the project's existing pattern if it has one (a loop over simulation files, a helper
function). Don't add OpenSSL, zlib or `CPPHTTPLIB_*` settings; a project that still has them is on
an SDK before 0.8 (`cppmodel:update-dependencies`).

Do this when the simulation is created, not after - an unregistered simulation can be built and
even run manually indefinitely without ever actually gating anything.

When a **new** simulation passes and the user isn't still changing the plant or controller, offer,
in one line, to finalize their documentation with `cppmodel:documentation`. That means reshaping
the draft to match the code, or writing the document if there is no draft. Don't offer it after
debugging or tuning. Those changes don't need documentation until the solution is settled.

## Debugging a failure: query the real trace, don't guess

The binary's stdout gives nothing to work with beyond pass/fail and a `UI: https://...` link -
there is no local log, file, or cache holding the per-cycle signal trace. It only exists behind the
Workspace API, or, for a local run (SDK 0.10.0+), in the file its `--results` names. Use the `cppmodel` MCP server's `get_latest_result` (see `cppmodel:simulations`)
to pull the full execution trace: every `CppModel_getInput` signal under `inputs`, every
`CppModel_getParameter` under `parameters`, and every `CppModel_setOutput` signal (including
`CppModel.StepResult` and the step number) under `results`, each series as `{label, x, y}`
with `x` in ms. Series only have points where the value changed, plus the end time. Don't grep the project for prior output, don't add
extra logging/printf/file-dumping to the simulation to work around this, and don't write a new
script to reconstruct the trace - the tool already returns it. For a long run, call it with
`summary: true` first, then with `signals: [...]` for `CppModel.StepResult`, the step number
(`CppModel.StepNumber`/`CppModel.Step` with the SDK's steps, or the project's own, e.g.
`internalStepNumber`), and the signals around the failure.

Workflow:

1. Find **every** interval where `CppModel.StepResult` is 0 in the returned time series, not
   just the first. A run is a snapshot of the whole sequence, and it carries on past a failing
   cycle, so one trace holds all its failures: list them all before fixing anything, and don't
   rerun to find the next one. If the simulation uses verification rules (SDK 0.11.0+), start from
   the execution's `verification` instead: each failed rule's outcome gives its `explanation` and
   all its `violations` (time intervals in seconds), and its output series
   `CppModel.Verify.<name>` drops to 0 where it first failed. See `cppmodel:verification`.
   If an earlier run passed, `what_changed` between the two (`cppmodel:simulations`) says first
   whether the code, a parameter or the set of signals changed.
2. For each failure, cross-reference the step number's transitions to identify which step
   was running at that timestamp (with the SDK's steps, the run's exit code is already the first
   failing step's number), and the local time within that step (absolute time minus the step's start
   time).
3. Look at the other signals' values at that same timestamp to see what state the model/controller
   was actually in - usually enough to tell whether the assertion's logic is wrong, its timing is
   wrong, or the code under test has a real bug. Besides reading values, export a `png` of the
   failing step's signals over a window around the failure (`export_signals` with `from`/`to` in
   ms, see `cppmodel:simulations`' "Looking at signals") and look at it: the lag between a command
   and its response, an interlock or an overshoot shows at once. Give the user the export's
   `uiUrl`. An export isn't extra logging or a script: it reads what the execution already
   recorded. Group failures with one cause: a later one can
   be the aftermath of an earlier one when the system didn't get back to a known state in between.
   A fix to controller code (code that ships to the
   target) follows `cppmodel:coding-standard`.
4. Fix, rebuild, rerun, re-fetch, and confirm the trace is clean end to end (`StepResult` never
   dips to 0 anywhere) - not just that the process exit code was 0. With SDK 0.10.0+, the tries
   in between can run without submitting: add `--results <out.json>` and read the trace from that
   file. Add `--inputs <file>` with the failing execution's `inputs` and `parameters` when it ran
   with values other than the fallbacks, leaving out plant-fed inputs in a closed loop (the
   recorded plant trace would override the plant), unless the failing run had them forced. Once a fix looks right, do one recorded run the way the
   failing one ran (plain, or with that `--inputs <file>`), and confirm the clean trace from that
   execution.
5. Compare the new execution with the failing one through the history: `what_changed` with both
   ids (from `list_executions`) for the code, parameters and signal names, then `get_execution`
   for both with the same `signals`, so the fix is shown to change what it was meant to change and
   nothing else. Give the user the comparison's `uiUrl`, which overlays both runs. A `png` export of
   the same signals and window from the new execution shows the fix; give its link as well. Don't add a temporary test or extra outputs to collect
   what the two executions already recorded.

If the trace's `inputs`/`parameters` show values other than the source's fallbacks (for a
plant-fed input in a closed loop, other than what the plant would give, e.g. a switch that stays
put while the plant's position passes it), this run consumed a document posted through the API or
the web UI. Posted documents are one-shot: they
affect only the account's next execution, whichever one that is, such as a `ctest` run or a CI
job with the same login that happened to start first. See `cppmodel:simulation-inputs`.

One recurring, easy-to-miss failure mode: a state field and an output that its new state is
supposed to set can be one cycle out of sync - the state has already transitioned, but the case
body that sets the corresponding output for that new state hasn't run yet until the next cycle. If
an assertion pairs two things that are meant to change together, check the trace for this
off-by-one-cycle pattern before assuming they update atomically.
