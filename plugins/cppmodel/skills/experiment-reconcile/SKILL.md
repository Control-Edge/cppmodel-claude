---
name: cppmodel:experiment-reconcile
description: Reconcile field logs from a real machine with the experiment plan that produced them - find each planned run in the unannotated logs, infer what the operator actually did against what was asked (skipped, partial, different setpoints, extra manoeuvres), re-simulate what was actually done, and compare predicted vs actual on the same graphs, run by run, against the plan's tolerances. Then turn the gap into a minimal plant-model refinement on the planned path and test it against the same logs. Use when logs come back from a field session run with a cppmodel:experiment-design plan, when asked how the machine compared to the model's prediction, or when asked to refine a plant model from field data.
---

## What this is

The second half of the loop that `cppmodel:experiment-design` starts. Its inputs are an issued
`plan.json` (format: [../experiment-design/plan-format.md](../experiment-design/plan-format.md))
and the raw logs in `experiments/<plan-id>/logs/`. Nobody annotated those logs and nobody recorded
deviations; working them out is this skill's job:

1. **Identify** which stretch of log is which planned run.
2. **Infer** what actually happened against what was asked.
3. **Compare** what the model predicts with what the machine did.
4. **Refine** the plant model from the gap, on the planned path, and show whether the refined model
   closes it.

Its output is `experiments/<plan-id>/reconciliation.json` (format:
[reconciliation-format.md](reconciliation-format.md)) and a page showing predicted vs actual on the
same plots. The plan itself is never edited except for its `status`.

The operator's job was only to move the machine, so never ask them to annotate or re-label logs.
Show what you inferred and let the user correct it (step 5).

## Preconditions

- **The plan exists and is `issued`.** A `draft` plan was never run in the field; say so and stop.
  If several plans have logs, ask which one.
- **The logs are present** in `experiments/<plan-id>/logs/` (or wherever the user put them; move
  nothing without asking).
- **The model version.** Rebuild the planned simulation's binary and compare its fingerprint (or
  git commit) with the plan's `model`. If they differ, the model has changed since the plan was
  issued. Comparisons in step 4 still go against the plan's model, because that was the hypothesis
  the field session tested: check out or keep a build of that version for the as-run simulations,
  and tell the user. The planned predictions themselves are never regenerated: fetch them by the
  plan's `prediction.executionId` with `get_execution`. A newer model is evaluated in step 6 as a refinement.
- **Running anything** needs `.env` (`CPPMODEL_USERNAME`/`CPPMODEL_PASSWORD`) and the `cppmodel`
  MCP server authenticated (see `cppmodel:simulations`). If either is missing, say so and stop.

Field logs aren't simulation results: they never went through the Workspace API, so reading them
is local work. Short scripts to read them are expected; keep them in scratch, or in
`experiments/<plan-id>/` if they're worth reusing. Simulation results, planned or as-run, still
come only from the `cppmodel` MCP server or the sweep's output; never from anywhere else.

## 1. Read the logs

Find out what's there before interpreting anything:

- **Format.** CSV/TSV, MDF4 (`asammdf`), raw CAN (`.blf`/`.asc`, `python-can` plus `cantools`; a
  DBC is needed to decode signals, so ask for it if it's missing), or a vendor format. If the
  format can't be read, say which tool it needs rather than guessing at the bytes.
- **Inventory** per file: channels, units, sample rate (measured, not assumed), start/end time,
  gaps and dropouts, the time base (absolute or from logger start; several files may need
  aligning).
- **Map channels to the plan.** For each plan channel, find its `logSignal`. When the plan has
  `null` or the name doesn't exist, identify the channel by behaviour and range, or derive it from
  others (e.g. outreach from boom angles and the geometry), and record how and with what
  confidence.
- **Compare the reality with the plan's `logging` understanding.** A lower rate than planned, a
  missing channel, different units or scaling: each is a finding in itself, and the next plan
  depends on it.

## 2. Identify the runs

Split the logs into segments and match each segment to a planned run, using:

- the **markers** the plan put between runs (rests in a fixed pose for a fixed time);
- each run's **`identification`** and **`setpoints`** signature;
- the planned **order** as a prior only, since operators reorder, repeat, and skip.

Then classify each one:

- **Matched** segments, each with a confidence and the reason for it. A repeat is another attempt
  of the same run.
- **Unplanned** segments: something happened that matches no run. Keep it, since it's real data
  about the machine, but don't compare it against a prediction it wasn't designed for.
- **Skipped** runs: no matching segment.

Give low confidence rather than force a match. A wrong match produces a convincing but false
model error.

## 3. Infer what actually happened

For each matched attempt, compare what was done with what was asked:

- **Achieved setpoints**: e.g. outreach reached 7.1 m of the planned 8.2 m. When a setpoint isn't
  logged directly (load is often missing), infer it from what is (pressure at known geometry), and
  say that it's inferred.
- **Deviations**: partial (aborted before the end), different setpoint, different timing (shorter
  holds, faster ramps), out of order, or a missing dependency (`dependsOn` not done first).
- **Why, where the log shows it**: a skipped or aborted run near a limit is often the answer to
  the hypothesis ("couldn't lift 1500 kg at 8.2 m" *is* the weak-boom finding). Record it as
  evidence, not as an operator failure.

Never adjust the log to fit the plan, or the plan to fit the log.

## 4. Compare predicted vs actual

Two predictions matter, and the page shows both:

- **Planned prediction**: the trace stored in the plan. It's what the plan promised and the
  reference for "did the field follow the plan".
- **As-run prediction**: the same model driven with what the operator actually did. This
  separates model error from operator deviation, so it's the one that decides whether the model is
  right. Produce it with the planned simulation:
  - take the operator-side channels (the commands/setpoints the plan's `simulation.inputs` hold)
    from the log segment, convert them to `set_inputs` format (`x` in ms from the segment start,
    staircase at the simulation step or coarser), and set the achieved run conditions as
    parameters;
  - run one execution per attempt with `cppmodel:parameter-sweep`, using an explicit `runs` list,
    against the plan's model version (see Preconditions);
  - if the operator-side channels weren't logged, there is no as-run prediction. Compare against
    the planned prediction only, and mark those runs' verdicts as weaker for it.

**Align in time** on the first command change in the segment (sim time 0 is the start of the run),
and say how you aligned. Resample both onto the channel's logged rate with hold-last-value before
comparing.

Per attempt and channel, compute against the plan's `tolerance`:

- the fraction of time within tolerance, the maximum error, and the error at plateaus/holds;
- **where the divergence starts**: the setpoint level or the moment the two first leave tolerance;
- **spread across repeats** compared with the miss. A miss smaller than the repeat spread is noise,
  not model error.

Verdict per attempt: `agrees`, `disagrees`, or `inconclusive` (skipped, missing channel, low-
confidence match, no as-run prediction where one was needed). Then, per run, whether its
`hypothesis` is supported or refuted, in the hypothesis's own words: "pressure saturates at 205
bar from 1200 kg at 7.1 m; the model has no relief limit, so it predicts 240 bar: refuted".

Write all of this to `reconciliation.json` as you go.

## 5. Show it: the reconciliation page

Publish an Artifact (load `artifact-design`, and `dataviz` before any chart), built from
`reconciliation.json` and the plan. If the Artifact tool isn't available, write
`experiments/<plan-id>/reconciliation.html` and give the path. It shows:

- **a timeline of each log** with the identified runs shaded and labelled (and unplanned segments
  marked), so the user can check the identification at a glance;
- **per run, predicted vs actual on one plot per channel**: the actual trace, the as-run
  prediction, the planned prediction (fainter), and the tolerance band around the as-run
  prediction, with time on the x-axis and stepped lines, the way the workspace UI shows results.
  Repeats are overlaid;
- **the deviations** from step 3, and the verdict and hypothesis outcome per run;
- **the logging findings** from step 1 (rates, missing channels);
- **a short conclusion**: what the model gets right, where and how it diverges, and what the
  evidence suggests is missing.

The user confirms or corrects: a mismatched run, a channel mapping, an alignment. For each
correction, redo the affected steps and republish to the same URL. This page is the verification
evidence, so it stays readable on its own by someone who never saw the plan.

## 6. Feed the gap into the plant model

Propose the **smallest model change that explains the gap the evidence shows**, e.g. a relief
pressure limit on the lift cylinder, or a first-order lag on a valve. `cppmodel:plant-model`'s
"keep it minimal" still holds, but the field data now says what matters to the controller, so add
what the logs show and nothing more. Get the user's OK before writing it.

- Write it as a **trial variant on the planned path**, a copy under `experiments/<plan-id>/`, and
  point the planned simulation at it. Never edit the production model from here.
- **Fit on some attempts, check on others.** Identify any new constants (a relief pressure, a time
  constant) from part of the attempts, typically one of each repeat, and judge the variant on the
  rest. A variant that only matches the data it was tuned on hasn't shown anything.
- **Re-run the as-run simulations with the variant** (same inputs, `cppmodel:parameter-sweep`).
  The "before" runs are already in the history, so only the variant runs. Compare by execution id
  as in step 4, and add the result to `reconciliation.json` and the page as a third trace:
  "before" vs "after" vs actual.
- Record the variant's fingerprint or commit, since it is a different model.

## 7. Close the loop

Set the plan's `status` to `reconciled`. Then, from the evidence, propose one of:

- **Promote**, when the (refined) model agrees within tolerance on the runs that carry the goal, or
  when the customer now uses it as a production function. Follow `cppmodel:experiment-design`'s
  "Promotion" steps, and only with the user's yes.
- **Plan again**, when there's still a gap, an inconclusive hypothesis, or a logging problem.
  Hand off to `cppmodel:experiment-design` for a new plan (`supersedes` this one), aimed at what is
  still unexplained and built on this reconciliation's logging findings and achieved setpoints.
- **Re-tune the controller**, when the model now agrees and the problem is the control algorithm
  on the real machine. That's `cppmodel:simulation-testing` work on the planned path first.

Finish with where `reconciliation.json`, the page, and any model variant are, the plan's new
status, and which next step you propose.

When a refinement is promoted, the model's document (if one exists) is out of date. Offer to
update it with `cppmodel:documentation`: the new update law or constant, where its value came from
(the attempts it was fitted on), and the field validation. If no document exists, offer to write
one.
