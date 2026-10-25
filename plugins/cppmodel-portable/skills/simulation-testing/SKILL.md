---
name: simulation-testing
description: "Write, extend, or debug a CppModel-based simulation test, in C (the SDK's CModel.h API - CppModel_* functions and its CMODEL_CYCLIC/CMODEL_SIMULATE macros - directly or via a project's own helpers) or C++ (cppmodel::Simulation from cppmodel.hpp, CppModelBase::Simulation in older code, directly or via a project's own wrapper class). Use when asked to add test coverage to a CppModel simulation, when a simulation test fails and the reason isn't obvious from stdout, or when tightening timing-based assertions against real execution data."
---

## Reading notes

- This is the cppmodel plugin's `simulation-testing` skill. It was written for Claude Code, but applies to any
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

## Which side is being simulated

A CppModel simulation always wraps exactly one component - the plant (the physical mechanism) or
the controller - as the thing exposed to CppModel; the other component still exists as real code in
the same binary, wired to the wrapped one directly in-code, not through the input/output boundary
(`CppModel_getInput*`/`setOutput*` in C, `inputs["..."]`/`outputs["..."]` in C++). Only the wrapped
component's boundary crosses that line, so what counts as an "input" vs an "output" flips depending
on which side that is:

- **Simulating the plant** (the common case - see `cppmodel:plant-model`): inputs pull in the
  controller's actuator commands to drive the model, outputs publish the sensor readings the model
  produces back to the real controller.
- **Simulating the controller** (e.g. a decoupled component from `cppmodel:decouple-component`
  exercised on its own): inputs pull in the sensor readings that feed the real controller logic,
  outputs publish the actuator commands it produces.

Even when both a plant model and a controller exist in the same project, pick which one is under
test before writing the per-cycle callback - that decision decides which struct (actuators or
sensors) gets read as input and which gets published as output. Don't straddle both.

## Language: C or C++

Only relevant when creating a **brand-new** simulation file - skip this when extending or
debugging an existing one, whose language is already fixed by its file extension. Use the
`cppmodel:language` skill to decide, then jump to the matching subsection below.

## Anatomy of a simulation

Every CppModel simulation, in either language, does the same three things per cycle: runs one
callback per simulated `task_period_ms`/step, crosses the simulation boundary (read simulated
inputs, run one cycle of the code under test, publish outputs), and reports pass/fail for that
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
simulations in the project do.

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

The simulation still needs a step schedule chaining multiple test scenarios in one file, using
whatever mechanism the chosen path above provides (a `steps` map/vector, or `InternalStep_ts` +
`RunInternalSteps`). Give each distinct scenario a fresh `Init`-style reset function beforehand,
unless deliberately continuing from the previous scenario's end state (also a valid, commonly used
pattern - e.g. confirming a signal set in one step has the expected effect at the very start of
the next).

Assertion style: prefer "eventually true, with a grace window" over exact cycle-counting, e.g.
`return sawExpectedEvent || (localTime_ms < someGenerousMs);`. Real timing (motor ramps, debounce
timers, multi-state sequences) is easy to get wrong by hand - don't guess tight thresholds, derive
them from the actual physics/logic involved, then validate against a real trace (below) before
trusting them.

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
the binary itself gives no detail about which one - it only prints a
`UI: https://<workspace>.cppmodel.com/simulations/<SimulationName>` line, its
`CppModel.BinaryFingerprint`, and, once submitted, the new `Execution:` id. A binary that fails to start with a
missing `libcppmodel.so.1`/`libcppmodel.dylib`/`cppmodel.dll` was built without
`cppmodel_deploy_runtime(<target>)` (below).

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
`CppModel.StepResult` and `internalStepNumber`) under `results`, each series as `{label, x, y}`
with `x` in ms. Series only have points where the value changed, plus the end time. Don't grep the project for prior output, don't add
extra logging/printf/file-dumping to the simulation to work around this, and don't write a new
script to reconstruct the trace - the tool already returns it. For a long run, call it with
`summary: true` first, then with `signals: [...]` for `CppModel.StepResult`,
`internalStepNumber`, and the signals around the failure.

Workflow:

1. Find where `CppModel.StepResult` first drops to 0 in the returned time series. If the
   simulation uses verification rules (SDK 0.11.0+), start from the parameters instead: each
   failed rule's `CppModel.Verify.<name>` gives its `explanation` and `violations` (time
   intervals in seconds), and its output series of the same name drops to 0 where it first
   failed. See `cppmodel:verification`.
2. Cross-reference `internalStepNumber`'s transitions to identify which step function was running
   at that timestamp, and the local time within that step (absolute time minus the step's start
   time).
3. Look at the other signals' values at that same timestamp to see what state the model/controller
   was actually in - usually enough to tell whether the assertion's logic is wrong, its timing is
   wrong, or the code under test has a real bug. A fix to controller code (code that ships to the
   target) follows `cppmodel:coding-standard`.
4. Fix, rebuild, rerun, re-fetch, and confirm the trace is clean end to end (`StepResult` never
   dips to 0 anywhere) - not just that the process exit code was 0. With SDK 0.10.0+, the tries
   in between can run without submitting: add `--results <out.json>` and read the trace from that
   file. Add `--inputs <file>` with the failing execution's `inputs` and `parameters` when it ran
   with values other than the fallbacks. Once a fix looks right, do one recorded run the way the
   failing one ran (plain, or with that `--inputs <file>`), and confirm the clean trace from that
   execution.
5. Compare the new execution with the failing one through the history (`list_executions`, then
   `get_execution` for both ids with the same `signals`), so the fix is shown to change what it
   was meant to change and nothing else. Don't add a temporary test or extra outputs to collect
   what the two executions already recorded.

If the trace's `inputs`/`parameters` show values other than the source's fallbacks, this run
consumed a document posted through the API or the web UI. Posted documents are one-shot: they
affect only the account's next execution, whichever one that is, such as a `ctest` run or a CI
job with the same login that happened to start first. See `cppmodel:simulation-inputs`.

One recurring, easy-to-miss failure mode: a state field and an output that its new state is
supposed to set can be one cycle out of sync - the state has already transitioned, but the case
body that sets the corresponding output for that new state hasn't run yet until the next cycle. If
an assertion pairs two things that are meant to change together, check the trace for this
off-by-one-cycle pattern before assuming they update atomically.
