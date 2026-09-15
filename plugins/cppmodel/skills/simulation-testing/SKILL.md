---
name: cppmodel:simulation-testing
description: Write, extend, or debug a CppModel-based simulation test, in C (CppModelBase's CModel.h API, directly or via a project's own CMODEL_CYCLIC/CMODEL_SIMULATE macros) or C++ (CppModelBase::Simulation, directly or via a project's own wrapper class). Use when asked to add test coverage to a CppModel simulation, when a simulation test fails and the reason isn't obvious from stdout, or when tightening timing-based assertions against real execution data.
---

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

### C++

Check first whether this project has its own base class layered on top of
`CppModelBase::Simulation` (`cppmodel/Simulation.h`) - e.g. a project-specific wrapper might add a
`steps` map of `{time_ms, function}` chained through a `CallStep()`-like helper, a per-cycle entry
point override, and helpers for tracing which requirements each simulation exercises out to a
requirements file. If a wrapper like this exists anywhere in the project, subclass *that* and
follow its exact shape (populate its step container, override its per-cycle method, call its
requirement-tracing helper if the scenario covers a named requirement) - don't build a second,
competing mechanism alongside it.

If no such wrapper exists, subclass `CppModelBase::Simulation` directly: override
`RunCyclic(double time)` as the per-cycle callback, use `inputs["name"]` / `outputs["name"]`
(`SimulationInputs`/`SimulationOutputs`, indexable like a map) to cross the boundary, and always
set `outputs["CppModel.StepResult"]`. `main()` constructs the simulation object and calls
`.Simulate()`.

### C

Check first whether the project has a `ModelHelpers.h` (or similarly-named header) providing
`CMODEL_CYCLIC() { ... }` / `CMODEL_SIMULATE("Name", totalTime_ms, task_period_ms)` macros (the
latter expands to `main()`) plus an `InternalStep_ts` step-schedule array run through
`RunInternalSteps`. Grep for `CMODEL_SIMULATE`/`ModelHelpers.h` first - if present, use it exactly
as existing C simulations in the project do.

If absent, use the lower-level `CModel.h` API directly: `CppModel_create(name, totalTime_ms,
task_period_ms)` to build the simulation, `CppModel_setRunStepFunction(sim, RunCyclic)` to
register a per-cycle callback shaped `void RunCyclic(CModelSimulation_ts *self, unsigned long
time)`, `CppModel_getInput{U8,I32,...}(self, "name", fallback)` / `CppModel_setOutput{U8,I32,...}
(self, "name", value)` to cross the boundary, `CppModel_Simulate(sim)` to run it, and
`CppModel_getSimulationResult(sim)` as `main`'s return value. Always call
`CppModel_setOutputU8(self, "CppModel.StepResult", result)` every cycle.

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

Then run the binary directly - it needs the CppModel credentials in `.env` (see the
`cppmodel:simulations` skill) sourced into its environment:

```
set -a && source .env && set +a && ./build/<path-to>/<SimulationName>
```

Exit code 0 means every cycle's `StepResult` was 1. Nonzero means at least one cycle failed, but
the binary itself gives no detail about which one - it only prints a
`UI: https://<workspace>.cppmodel.com/simulations/<SimulationName>` line.

If this simulation isn't yet wired into `ctest`, register it in the relevant `CMakeLists.txt`:

```
add_test(NAME <SimulationName>Test COMMAND <SimulationName>)
```

Do this when the simulation is created, not after - an unregistered simulation can be built and
even run manually indefinitely without ever actually gating anything.

## Debugging a failure: query the real trace, don't guess

The binary's stdout gives nothing to work with beyond pass/fail. Use
`${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh "<SimulationName>"` (or `GET /simulations/{id}`
from the Workspace API directly) to pull the full execution trace: every
`CppModel_setOutput`/`getInput` signal as a time series, plus `CppModel.StepResult` and
`internalStepNumber`.

Workflow:

1. Find where `CppModel.StepResult` first drops to 0 in the returned time series.
2. Cross-reference `internalStepNumber`'s transitions to identify which step function was running
   at that timestamp, and the local time within that step (absolute time minus the step's start
   time).
3. Look at the other signals' values at that same timestamp to see what state the model/controller
   was actually in - usually enough to tell whether the assertion's logic is wrong, its timing is
   wrong, or the code under test has a real bug.
4. Fix, rebuild, rerun, re-fetch, and confirm the trace is clean end to end (`StepResult` never
   dips to 0 anywhere) - not just that the process exit code was 0.

One recurring, easy-to-miss failure mode: a state field and an output that its new state is
supposed to set can be one cycle out of sync - the state has already transitioned, but the case
body that sets the corresponding output for that new state hasn't run yet until the next cycle. If
an assertion pairs two things that are meant to change together, check the trace for this
off-by-one-cycle pattern before assuming they update atomically.
