---
name: cppmodel:simulation-testing
description: Write, extend, or debug a CModel-based simulation test (CMODEL_CYCLIC/CMODEL_SIMULATE). Use when asked to add test coverage to a CppModel simulation, when a simulation test fails and the reason isn't obvious from stdout, or when tightening timing-based assertions against real execution data.
---

## Anatomy of a CModel simulation

A simulation `.c` file has three required pieces:

- `CMODEL_CYCLIC() { ... }` - the per-cycle callback, invoked once per simulated `task_period_ms`.
  Read simulated inputs into your model/controller state with
  `CppModel_getInput{U8,I32,...}(self, "name", var)`, run one cycle of the code under test, publish
  outputs with `CppModel_setOutput{U8,I32,...}(self, "name", value)`, and always set
  `CppModel_setOutputU8(self, "CppModel.StepResult", result)` where `result` is 1 (pass) or 0
  (fail) for that cycle. Any single cycle returning 0 fails the whole run - there is no "mostly
  passing".
- `CMODEL_SIMULATE("Name", totalTime_ms, task_period_ms)` - expands to `main()`; builds and runs
  the simulation for `totalTime_ms` at `task_period_ms` resolution.
- A step schedule: an array of `{function, duration_ms}` pairs (`InternalStep_ts`) run through
  `RunInternalSteps` (from `ModelHelpers.h`), chaining multiple test scenarios in one file. Give
  each distinct scenario a fresh `Init`-style reset function beforehand, unless deliberately
  continuing from the previous scenario's end state (also a valid, commonly used pattern - e.g.
  confirming a signal set in one step has the expected effect at the very start of the next).

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
