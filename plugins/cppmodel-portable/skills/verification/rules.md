# Verification rules: API reference (SDK 0.11.0)

Seconds for every time setting. `NaN` (C/C++) or `None`/`null` (Python/Node) means "any mode" in
`Allow`, and "not checked" in `Dwell`, `Settle`'s overshoot and `Wear`'s limits. Check the project's
vendored headers when in doubt: they are the source of truth for its SDK version.

## Conditions (with margins)

| C++ (`cppmodel::verify`) | C (`CModel.h`) | Python (`cppmodel.verify`) | Node (`verify`) | margin |
| --- | --- | --- | --- | --- |
| `AtMost(x, limit)` | `CppModel_atMost(x, limit)` | `at_most(x, limit)` | `atMost(x, limit)` | `limit - x` |
| `AtLeast(x, limit)` | `CppModel_atLeast(x, limit)` | `at_least(x, limit)` | `atLeast(x, limit)` | `x - limit` |
| `Between(x, lo, hi)` | `CppModel_between(x, lo, hi)` | `between(x, lo, hi)` | `between(x, lo, hi)` | the lower of the two |
| `Near(x, target, tol)` | `CppModel_near(x, target, tol)` | `near(x, target, tol)` | `near(x, target, tol)` | `tol - abs(x - target)` |
| `a && b`, `a \|\| b`, `!a` | `CppModel_and`, `_or`, `_not` | `a & b`, `a \| b`, `~a` | `and(...)`, `or(...)`, `not(a)` | min, max, negated |
| `Implies(a, b)` | `CppModel_implies(a, b)` | `implies(a, b)` | `implies(a, b)` | |
| a `bool` | `CppModel_condition(holds)` | a `bool` | a `boolean` | none |

A condition without a margin never lends its truth to another's margin:
`Implies(mode == RUN, AtMost(valve, 0))` has no margin while the mode isn't RUN.

## Step rules: updated from the step function

| Rule | C++ | C (create in init / update per step) |
| --- | --- | --- |
| Always | `Always r{*this, name, debounce_s = 0};` `r(cond);` | `CppModel_ruleAlways(self, name, debounce_s)` / `CppModel_updateAlways(r, cond)` |
| Response | `Response r{*this, name, deadline_s, hold_s = 0};` `r(trigger, response);` | `CppModel_ruleResponse(self, name, deadline_s, hold_s)` / `CppModel_updateResponse(r, trigger, response)` |
| Settle | `Settle r{*this, name, band, settleLimit_s, stay_s, overshootLimit = NaN};` `r(value, target);` | `CppModel_ruleSettle(self, name, band, settleLimit_s, stay_s, overshootLimit)` / `CppModel_updateSettle(r, value, target)` |
| Mode | `Mode r{*this, name};` `r.Allow(from, to).Dwell(mode, min_s, max_s);` `r(mode);` | `CppModel_ruleMode(self, name)`, `CppModel_modeAllow(r, from, to)`, `CppModel_modeDwell(r, mode, min_s, max_s)` / `CppModel_updateMode(r, mode)` |

Python: `Always(sim, name, debounce_s=0.0)`, `Response(sim, name, deadline_s, hold_s=0.0)`,
`Settle(sim, name, band, settle_limit_s, stay_s, overshoot_limit=None)`, `Mode(sim, name)` with
`.allow(from_mode, to_mode)` / `.dwell(mode, min_s=None, max_s=None)`; update by calling the rule.
Node: the same in camelCase (`deadlineS`, `settleLimitS`, ...); update with `rule.update(...)`.

Semantics worth remembering:

- **Always**: a violation counts once it lasted `debounce_s`; shorter ones touch margin 0. Margin
  `value`.
- **Response**: a trigger while one is pending is ignored. Fails every step past the deadline until
  the response, and the step where a held response breaks. A trigger too close to the end to judge
  is reported, not failed. Margin `time_s`.
- **Settle**: a new target change ends the previous one (an in-band stay cut short still counts).
  Fails while late and while overshooting beyond the limit. Margins `time_s`, `overshoot`; metrics
  settling time, overshoot/undershoot, steady-state error.
- **Mode**: once any transition is allowed, every other change fails its step; leaving before
  `min_s` fails that step; staying past `max_s` fails each step until it changes. Margin `time_s`.
- A step without the update doesn't count (an `Always` violation ends there), but a running time
  limit (deadline, settle limit, max dwell) fails its steps whether or not the rule is updated.

## Signal rules: read an output (or input) by name after every step

| Rule | C++ / Python / Node (`active` last, optional) | C (`active` **before** the thresholds; `NULL` = whole run) |
| --- | --- | --- |
| Oscillation | `Oscillation{*this, name, signal, amplitude, duration_s, active}` | `CppModel_ruleOscillation(self, name, signal, active, amplitude, duration_s)` |
| Wear | `Wear{*this, name, signal, maxReversalsPerHour, maxTravelPerHour = NaN, deadband = 0, active}` | `CppModel_ruleWear(self, name, signal, active, maxReversalsPerHour, maxTravelPerHour, deadband)` |
| Rate | `Rate{*this, name, signal, maxRate, active}` | `CppModel_ruleRate(self, name, signal, active, maxRate)` |
| Energy | `Energy{*this, name, signal, factor, budget, active}` | `CppModel_ruleEnergy(self, name, signal, active, factor, budget)` |
| Percent | `Percent{*this, name, signal, minPercent, active}` | `CppModel_rulePercent(self, name, signal, active, minPercent)` |

Node's `Wear` takes an options object: `{maxReversalsPerHour, maxTravelPerHour, deadband, active}`.

| Rule | Margin | Failing steps |
| --- | --- | --- |
| Oscillation | `value` | while a sustained oscillation (≥ 4 half-cycles above `amplitude`, spanning `duration_s`) goes on |
| Wear | `reversals_per_h`, `travel_per_h` | from where even a still, active rest of the run can't bring the hourly rate within limit |
| Rate | `rate` | every step faster than the limit |
| Energy | `energy` | from where the budget is used up (integral per second × `factor`) |
| Percent | `percent` | from where even an all-good rest of the run can't reach `minPercent` |

`Energy` with a kW signal and `factor = 1.0 / 3600` gives kWh.

## Verdict so far, requirements

- `rule.Passed(&margin)` (C++), `CppModel_rulePassed(r)` (C), `rule.passed` / `rule.margin`
  (Python, Node).
- `VerifyRequirement(id)` (C++), `CppModel_verifyRequirement(self, id)` (C),
  `sim.verify_requirement(id)` (Python), `sim.verifyRequirement(id)` (Node), `cm_verify_requirement`
  (C API). In the constructor/`Init`: the whole run. In the step function: that step.

## Errors

`cppmodel::Error` in C++, a `CppModel: ... failed` line on stderr in C, when a name is already used
by another kind of rule, a step rule is updated outside the step function or twice in one step, or
a rule gets another kind's update. Creating a rule again under the same name returns the same rule
with the new settings.

## Outcome parameter `CppModel.Verify.<name>`

```json
{
  "kind": "response",
  "status": "fail",
  "pass": false,
  "margins": { "time_s": -3.0 },
  "metrics": { "triggers": 1, "answered": 1, "slowest_response_s": 5.0 },
  "violations": [[7202.0, 7205.0]],
  "explanation": "response 5 s after the trigger at t=7200 s (deadline 2 s); 1 of 1 trigger(s) failed"
}
```

`status` is `pass`, `fail` or `error` (a signal rule's signal was never there). `violations` are
time intervals in seconds.

## Requirement file `cppmodel-requirements.json`

```json
{
  "<simulation name>": {
    "time": "23-10-2026 08:07:59",
    "passed": true,
    "requirements": {
      "ZONE-SAF-001": { "whole_run": true, "steps": 0, "from_s": null, "to_s": null },
      "ZONE-SAF-004": { "whole_run": false, "steps": 30, "from_s": 7200.0, "to_s": 7229.0 }
    }
  }
}
```

One entry per simulation, replaced by each of its runs; other simulations' entries are kept.
Concurrent runs in one working directory can overwrite each other's entries: give them separate
files with `CPPMODEL_REQUIREMENTS_FILE`.
