---
name: cppmodel:verification
description: Turn a controller's requirements into CppModel verification rules (Always, Response, Settle, Mode, Oscillation, Wear, Rate, Energy, Percent) and requirement coverage (VerifyRequirement / CppModel_verifyRequirement) in a simulation, prove each rule can fail, read the rules' outcomes and margins from the recorded execution, and report which requirements are covered, by which simulation and rule, and whether they passed. Use when asked to verify a controller against requirements or a spec, add pass/fail criteria for timing, ranges, interlocks, mode sequences, settling or oscillation, trace tests to requirement IDs, report requirement coverage, or explain why a verification rule failed. Needs SDK 0.11.0+.
---

## What this is

From SDK 0.11.0 the library checks how a run behaves over time with **verification rules**: objects
created once in the simulation, each with a name and its settings. They replace hand-written
`CppModel.StepResult` logic for anything that is about time (deadlines, settling, dwell, rates,
oscillation, energy, share of time in a band). The library also records which **requirement IDs**
a simulation verifies, and over which steps. The full reference is the SDK's
`documentation/Verification.md` when the project vendors it. Otherwise use
[rules.md](rules.md) in this skill, which has every signature in C, C++, Python and Node.

What the library does with them:

- At every step, `CppModel.StepResult` is the AND of all rules (and of the simulation's own value,
  if it sets one). A step fails where a rule is violated, or where a rule has certainly failed and
  the failure is still going on. So the failure shows where it happens.
- Each rule writes the output `CppModel.Verify.<name>`: 1 until the rule first fails, then 0 to the
  end. A short failure in a long run stays visible.
- At the end of the run, each rule's outcome is printed (`CppModel.Verify.<name>: PASS|FAIL ...`)
  and stored in the execution's `verification` field under the rule's name: a JSON object with
  `kind`, `status` (`pass`/`fail`/`error`), `pass`, `margins`, `metrics`, `violations` (time
  intervals in seconds) and `explanation`. SDK 0.11.0 stored it as the parameter
  `CppModel.Verify.<name>` instead; the `cppmodel` MCP server returns those under `verification`
  too.
- Every rule has a **margin** in physical units: > 0 is headroom, < 0 is how far it missed.
- `VerifyRequirement(id)` called in the constructor/`Init` covers the whole run. Called in the
  step function, it covers that step. At the end the IDs are printed (`CppModel.Requirements: ...`)
  and written to `cppmodel-requirements.json` in the working directory, or to the file
  `CPPMODEL_REQUIREMENTS_FILE` names. From SDK 0.12.0 they are also in the execution's
  `requirements` field (ID → `whole_run`, `steps`, `from_s`, `to_s`). With 0.11.0 they are not
  part of the execution record, only in the file.

## 0. Check the SDK

Grep the vendored headers for `cm_rule_always` (`cppmodel.h`), `CppModel_ruleAlways` (`CModel.h`)
or `namespace verify` (`cppmodel.hpp`). If they aren't there, the project is on an SDK before
0.11.0. Offer `cppmodel:update-dependencies` and stop until it's updated. Don't hand-roll rule
logic in the simulation as a stand-in.

Check credentials before running anything, as `cppmodel:simulation-testing`'s "Requirements"
describes.

## 1. Get the requirements

Ask once where the requirements are: a spec, a list, a ReqIF/CSV/Excel export from a requirements
tool, tickets, a state chart. Read it if it's a file. If the customer gave a description to
`cppmodel:documentation` or `cppmodel:decouple-component`, start from that.

- **Use the customer's IDs exactly.** Never invent an ID that looks like theirs. If the
  requirements have no IDs, propose a scheme (`<AREA>-<KIND>-NNN`, as in the SDK's
  `simulations/requirements.json`) and get a yes before using it.
- **A requirements list in the project.** The library reads only IDs, not texts. Unless the
  project already keeps requirements somewhere (a tool export, a docs folder), offer a
  `requirements.json` in the SDK example's shape:
  `{"requirements": [{"id": "...", "description": "..."}]}`. It is what step 6 checks coverage
  against. Keep the customer's wording in `description`; don't paraphrase.
- **Not every requirement belongs in a simulation.** Hardware, EMC, documentation, process,
  or anything the plant model doesn't represent can't be verified here. List those as "not
  verified by simulation" with the reason, so the gap is visible rather than silently missing.

## 2. Map each requirement to rules, and confirm before writing code

For each requirement, choose the rule that states it most directly:

| The requirement says | Rule | Updated with |
| --- | --- | --- |
| a value stays in a range, never X, X only when Y, X implies Y | `Always` (+ `debounce_s` only if the requirement allows a transient) | `Between`, `AtMost`, `AtLeast`, `Near`, `Implies`, `&&`, `\|\|`, `!` |
| after event A, B happens within T (and stays for H) | `Response(deadline_s, hold_s)` | `(trigger, response)` |
| a required order A, then B, then C | a chain of `Response`s (A→B, B→C) | |
| after a setpoint change, settles within ±band in T, stays S, overshoot ≤ O | `Settle` | `(value, target)` |
| allowed state/mode transitions, minimum/maximum time in a mode | `Mode` + `Allow`/`Dwell` | `(mode)` every step |
| no sustained oscillation / hunting above A for D | `Oscillation` (signal rule) | reads an output |
| at most N reversals or X travel per hour (actuator wear) | `Wear` (signal rule) | reads an output |
| changes by at most R per second | `Rate` (signal rule) | reads an output |
| uses at most E energy / budget | `Energy` (signal rule, `factor` for units) | reads an output |
| within limits at least P % of the time | `Percent` (signal rule) on a 0/1 output | reads an output |

Then decide, per rule:

- **Thresholds come from the requirement**, never from what the current controller happens to do.
  If the requirement has no number ("quickly", "stable"), ask for one. Don't pick a value that
  makes today's run pass. Units: time settings are seconds; values are in the signal's own units.
- **Scope**: when the requirement applies. For a step rule, update it only at those steps
  (`if (occupied) settle(...)`). For a signal rule, pass an `active` output that is non-zero while it
  applies (e.g. `Zone.Running`). Without one, the rule applies to the whole run.
- **Name**: start each rule's name with the requirement ID it checks
  (`"ZONE-SAF-004 smoke shutdown"`), so its outcome, its output series and the coverage report
  trace back to the requirement without a separate mapping. If a project already has a naming
  scheme for rules, keep it, and keep the ID → rule mapping in the requirements list instead. One
  name is one rule: reusing it for another kind is an error.
- **Requirement coverage**: `VerifyRequirement(id)` in the constructor/`Init` if it applies to the
  whole run, else inside the same guard as the rule's update. Its steps then show where the
  requirement was actually exercised.

Show the mapping as one table (ID, requirement text, rule kind and name, settings, scope, new
outputs it needs) and get the user's confirmation before writing code. List the requirements
you couldn't map, and why.

## 3. Write the rules

Follow the simulation's language and its existing structure (`cppmodel:simulation-testing`,
"Anatomy of a simulation"). [rules.md](rules.md) has the signatures. Things that are easy to get
wrong:

- **C++**: make each rule a member constructed with `*this` (`verify::Always valveRange{*this,
  "..."};`). Configure `Mode` transitions in the constructor. Call step rules like functions in
  `RunCyclic`.
- **C**: create each rule once in the init function (`CppModel_setInitFunction`) and keep its
  handle in a `static`. **The C signal rules take `active` before the thresholds**
  (`CppModel_ruleRate(self, name, signal, active, maxRate)`), unlike C++/Python/Node where it is
  last. Pass `NULL` for no `active`.
- `NaN` (`NAN`, `std::nan("")`; `None`/`null` in Python/Node) means "any mode" in `Allow` and "not
  checked" in `Dwell`, `Settle`'s overshoot and `Wear`'s limits.
- A step rule is updated **only from the step function, at most once per step**. Once any
  transition is allowed, `Mode` must be updated every step.
- A signal rule's signal must be an output (or input) the simulation writes. Publish the derived
  0/1 flags it needs (`Zone.Comfortable`, `Zone.Running`) as outputs every step. A signal that is
  never there gives `status: error` and fails the last step.
- A plain `bool` condition has no margin. Prefer `AtMost`/`Between`/... over a hand-written
  comparison wherever there is a number, so the margin says how close it came.
- Leave the simulation's existing `CppModel.StepResult` logic alone unless the rules now cover it.
  Both are ANDed. Remove a hand-written check only once a rule states the same thing, and say which
  ones you removed.
- If the project has its own simulation wrapper with a requirement-tracing helper, ask whether it
  should call the library's `VerifyRequirement` now, rather than adding a second mechanism next to
  it.

Register the simulation with `ctest` if it's new (`cppmodel:simulation-testing`, "Build and run").

## 4. Prove that each rule can fail

A rule that can't fail verifies nothing. A wrong signal, a wrong scope or a wrong sign passes
silently. For each rule, show one run where it fails, at the step where it should:

- Prefer an input scenario that breaks the requirement: smoke arriving, a setpoint step, a
  disturbance. Run it with `--inputs <file>` (`cppmodel:simulation-inputs`).
- Where only a broken controller can show the failure (late response, aggressive gains), prefer a
  separate **negative simulation** that wires a deliberately broken controller variant in C/C++,
  with the same rules (`cppmodel:simulation-testing`, "New case: input document or new simulation"). A
  test-only fault switch read from a parameter in the harness also works, and the SDK's
  `VerifyZoneControl` does this (the parameter `Controller` with `reference`, `late-smoke`,
  `aggressive`...; never a `CppModel.*` name, which is reserved); follow it only if the project already uses that pattern. Never add a fault
  switch to production controller code.
- While iterating, these can be local runs (`--results`). Finish with recorded runs.
- Check from each run's `verification` that the expected rules failed, with the expected
  `violations` intervals, and that the others still passed. `what_changed` against the passing
  run confirms the failing run differs only in what you meant to change (the input, or the build).
- Keep the negative cases as `ctest` tests marked `WILL_FAIL`
  (`cppmodel:ci-pipeline`'s "Input profiles" and "Sweeps"), so a rule that stops being able to fail is
  noticed.

## 5. Run, and read the outcomes from the recorded execution

Run as `cppmodel:simulation-testing` describes. Stdout shows each rule's one-line outcome and the
covered requirement IDs. Report from the recorded execution, through the `cppmodel` MCP server
(`cppmodel:simulations`):

- `get_execution` (or `get_latest_result`) with `summary: true`, then `signals` for
  `CppModel.StepResult` and the failing rules' `CppModel.Verify.<name>` series. `verification`
  carries every rule's outcome object.
- Report one row per rule: requirement ID, rule, `status`, its margins with units, and the
  `explanation` for a failure. Give the execution id and its `uiUrl`.
- **Flag thin margins** on passing rules, e.g. a response with 0.1 s left of a 2 s deadline.
  The run passed, but a small change could break it. Offer `cppmodel:parameter-sweep` with the
  margin as the metric to find how much headroom there really is.
- For a failed rule, or a thin margin, export a `png` of the rule's signal and its
  `CppModel.Verify.<name>` series around the `violations` interval (`export_signals`, see
  `cppmodel:simulations`' "Looking at signals"). `violations` are in seconds and `from`/`to` in
  ms, so multiply by 1000. Look at it, and give the snapshot link in the report row along with the
  execution's `uiUrl`.
- For a failure, `violations` gives the time; from there, follow
  `cppmodel:simulation-testing`'s "Debugging a failure". Don't loosen a threshold to make a run
  pass. A threshold changes only when the requirement changes, and the customer decides that.

## 6. Report requirement coverage

From SDK 0.12.0, each execution carries its own coverage in `requirements`: per ID `whole_run`,
`steps`, `from_s`, `to_s`. Read it from the workspace, together with the verdict:

- **Use each simulation's recorded run with its normal inputs**: its latest execution
  (`list_executions`/`get_execution`), checking with `what_changed` against the previous one that
  it wasn't a negative or scenario run (different parameters) or an old build (`code_changed`).
  If the latest is one of those, take the last normal run, or run the simulations again as
  recorded runs (usually `ctest` from the build folder).
- **Take the verdict from the same execution**: its rules' outcomes and pass/fail, with its id.

With SDK 0.11.0, coverage is only in `cppmodel-requirements.json` (or
`CPPMODEL_REQUIREMENTS_FILE`), which the library writes in the working directory. It keeps one
entry per simulation, from its last run there: `time`, `passed`, and the same per-ID entries. A
local run, a negative test or an old build also replaces its simulation's entry, so run the
simulations the report is about as recorded runs first, then read the file and check each entry's
`time` against the run. Take each verdict from the workspace, not from the file's `passed`.

- **Build the matrix**: one row per requirement in the project's list, with the simulations and
  rules that cover it, whole run or the covered time range, pass/fail, the lowest margin, and the
  execution id. Then list:
  - requirements no simulation covers (gaps);
  - IDs a simulation covers that aren't in the list (typos or missing requirements);
  - requirements covered only at very few steps (`steps` small): exercised briefly, so a
    scenario that exercises them more is worth offering;
  - requirements marked "not verified by simulation" in step 1.
- **Covered is not verified.** A requirement counts as verified only if a rule that can fail
  (step 4) checks it, and that rule passed in a recorded run. A `VerifyRequirement` call without a
  rule only says the test exercised it. Say so in the report.

Give the matrix in the reply. If the user wants to keep or share it, offer to write it to the
project (e.g. `docs/requirements-coverage.md`, linking each execution by its `uiUrl`) or publish it as a
page. The file links executions only, never `/snapshots/` links: those expire after 7 days.
In CI, `cppmodel:ci-pipeline` can keep the file as a build artifact.

## Afterwards

- When the controller code itself changes to meet a requirement, follow `cppmodel:coding-standard`
  for that code.
- Once the solution is settled, `cppmodel:documentation`'s Validation section lists the
  requirements and the rules that verify them.
