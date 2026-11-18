# Verification rules: API reference (SDK 0.11.0+; 0.18.0 additions marked)

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
| Tracking (0.18.0+) | `Tracking{*this, name, signal, reference, absTol, relTol = 0, lagging_s = 0, leading_s = 0, active}` | `CppModel_ruleTracking(self, name, signal, reference, active, absTol, relTol, lagging_s, leading_s)` |

Node's `Wear` takes an options object: `{maxReversalsPerHour, maxTravelPerHour, deadband, active}`.
Python: `Tracking(sim, name, signal, reference, abs_tol, rel_tol=0.0, lagging_s=0.0, leading_s=0.0,
active=None)`. Node: `new verify.Tracking(sim, name, signal, reference, {absTol, relTol, laggingS,
leadingS, active})`.

| Rule | Margin | Failing steps |
| --- | --- | --- |
| Oscillation | `value` | while a sustained oscillation (≥ 4 half-cycles above `amplitude`, spanning `duration_s`) goes on |
| Wear | `reversals_per_h`, `travel_per_h` | from where even a still, active rest of the run can't bring the hourly rate within limit |
| Rate | `rate` | every step faster than the limit |
| Energy | `energy` | from where the budget is used up (integral per second × `factor`) |
| Percent | `percent` | from where even an all-good rest of the run can't reach `minPercent` |
| Tracking | `value`: the closest the signal came to the tube's edge (< 0: outside by that much) | every step outside the tube, `leading_s` late |

**Tracking's tube**: at time t, the lowest and highest value of `reference` over
`[t - lagging_s, t + leading_s]`, each side widened by `max(absTol, relTol × |that value|)`.
Metrics: `worst_deviation`, `worst_at_s`, `outside_s`, `checked_s`, `excursions`, `signal`,
`reference`. A reference that is never there is an error, like a missing signal.

`Energy` with a kW signal and `factor = 1.0 / 3600` gives kWh.

## Presentation (SDK 0.18.0+)

Only change what the workspace draws; the updates and signals still decide pass/fail.

| What | C++ | C | Python / Node |
| --- | --- | --- | --- |
| the signal an `Always` bounds, and its limits | `rule.Limits(signal, min, max = none)` (chainable) | `CppModel_alwaysLimits(r, signal, min, max)` (`NAN`: no such side) | `rule.limits(signal, min=None, max=None)` / `rule.limits(signal, min, max)` |
| step rules: the output (or input) showing what the rule checks | `rule.Signal(name)` | `CppModel_ruleSignal(r, name)` | `rule.signal(name)` |
| record only the verdict (no verifier signals, no `overlays`) | `rule.Visual(false)` | `CppModel_ruleVisual(r, 0)` | `rule.visual(False)` / `rule.visual(false)` |

`Signal()` on a signal rule is an error (it reads its own signal). A name that is no output or input
of the run prints a warning at the end of the run.

**Verifier signals**: outputs `CppModel.Verifier.<name>.<field>`, hidden from the legend like every
`CppModel.*` output.

| Field | Meaning | Written by |
| --- | --- | --- |
| `status` | 1 passed the step, 0 failed it, -1 didn't apply | every rule |
| `min`, `max` | the allowed range | `Always` with `Limits`, `Settle` (target ± band), `Tracking` (the tube) |
| `target` | the desired value | `Settle` |
| `window` | 1 while the time allowance is open | `Response` (deadline), `Settle` (settle limit) |
| `mode` | the current mode | `Mode` |

An output the simulation records itself under the same name is kept instead.

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

## Outcome: `verification.<name>`

Each rule's outcome is stored in the execution's `verification` field under its name (SDK 0.12.0+;
0.11.0 stored it as the parameter `CppModel.Verify.<name>`, which the `cppmodel` MCP server also
returns under `verification`):

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

From SDK 0.18.0 a visual rule's outcome also has `overlays`: `fields` (the verifier signals it
wrote), `signal` (the checked signal: a signal rule's own, or a step rule's `Signal()`/`Limits()`
signal), `reference` (`Tracking`'s), `markers` (point events such as a response, the settling
point, the worst point, an illegal transition, each with its `label`, `time_s`, `value` and `pass`) and
`badge` (the metric to show next to the rule). The first seven fields are always there.

## Requirement coverage: `requirements` and `cppmodel-requirements.json`

From SDK 0.12.0 the execution has `requirements`: each ID the run named, with the same entry as in
the file below. The file is still written, and with 0.11.0 it is the only place the IDs are kept.

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
