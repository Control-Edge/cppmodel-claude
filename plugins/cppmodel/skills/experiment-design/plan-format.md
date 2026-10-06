# Experiment plan format

`experiments/<plan-id>/plan.json` is the contract between `cppmodel:experiment-design`, which
writes it, and `cppmodel:experiment-reconcile`, which reads it together with the returned logs.
Everything reconciliation needs must be in the plan; it doesn't re-derive anything from the
conversation that produced it.

## Example

```json
{
  "formatVersion": 1,
  "id": "2026-10-05-boom3-lift-at-reach",
  "status": "issued",
  "created": "2026-10-05",
  "issued": "2026-10-06",
  "supersedes": null,

  "goal": "Lift rated load at full outreach without stalling",

  "machine": {
    "name": "Boom 3",
    "unit": "serial 41-0087",
    "description": "Knuckle boom crane, two lift cylinders, telescope; the weak boom of the fleet"
  },

  "understanding": [
    { "id": "u1", "topic": "machine", "statement": "Max outreach 8.2 m (drawing 4471 rev C)", "source": "drawing", "confidence": "high" },
    { "id": "u2", "topic": "suspect", "statement": "At full outreach the lift cylinder reaches its relief pressure before rated load; the model has no relief limit", "source": "earlier log 2026-09-20", "confidence": "medium" },
    { "id": "u3", "topic": "logging", "statement": "Cylinder pressures logged at 100 Hz over CAN", "source": "assumed", "confidence": "low" }
  ],

  "model": {
    "simulation": "planned-2026-10-05-boom3-lift-at-reach",
    "source": "experiments/2026-10-05-boom3-lift-at-reach/BoomPlanned.cpp",
    "binary": "build/experiments/BoomPlanned",
    "plantModel": ["models/BoomModel.h"],
    "controller": ["src/BoomControl.c"],
    "binaryFingerprint": 4510872319245113,
    "gitCommit": "d1d3d88",
    "gitDirty": false,
    "knownLimitations": ["No hydraulic dynamics", "Rigid boom"]
  },

  "channels": [
    { "id": "p_lift", "description": "Lift cylinder piston-side pressure", "unit": "bar",
      "simSignal": "Lift Pressure [bar]", "logSignal": "P_LIFT_A", "rateHz": 100,
      "tolerance": { "abs": 8 } },
    { "id": "outreach", "description": "Outreach from slew centre", "unit": "m",
      "simSignal": "Outreach [m]", "logSignal": null, "rateHz": 20,
      "tolerance": { "abs": 0.1 } }
  ],

  "safetyNote": "Follow site lifting procedures. Skip any run the machine or the site doesn't allow.",
  "estimatedDurationMin": 45,

  "runs": [
    {
      "id": "r01",
      "order": 1,
      "label": "Baseline: 500 kg at mid outreach",
      "instruction": "With 500 kg on the hook, extend to about 5 m, hold 10 s, lift 0.5 m, hold 10 s, lower to rest.",
      "setpoints": { "loadKg": 500, "outreachM": 5.0 },
      "durationS": 60,
      "repeat": 1,
      "dependsOn": [],
      "identification": "Preceded by 10 s at rest fully retracted; outreach plateau near 5 m; pressure plateau near 90 bar.",
      "hypothesis": "The model matches here. A miss means a setup problem (scaling, units), not the suspect behaviour.",
      "channels": ["p_lift", "outreach"],
      "simulation": {
        "inputs": [{ "label": "Lift Command [%]", "x": [0, 10000, 20000, 30000], "y": [0, 60, 0, -40] }],
        "parameters": { "Load [kg]": 500, "Target Outreach [m]": 5.0 }
      },
      "prediction": {
        "index": 0,
        "executionId": null,
        "passed": true,
        "traces": [
          { "channel": "p_lift", "x": [0, 10, 20], "y": [12.0, 12.4, 13.1] }
        ]
      }
    }
  ]
}
```

## Fields

**Top level**

- `formatVersion`: `1`. Bump it on any change a reader has to handle differently.
- `id`: date plus short slug; also the folder name and the suffix of the planned simulation's name.
- `status`: `draft` while being shaped with the user; `issued` once handed to the field (frozen
  from then on); `reconciled`, `promoted`, or `abandoned` afterwards. Only `status` may
  change after `issued`. Reconciliation writes its findings to a separate
  `reconciliation.json` beside the plan (format:
  [../experiment-reconcile/reconciliation-format.md](../experiment-reconcile/reconciliation-format.md)).
- `supersedes`: the id of the plan this one replaces, or `null`.
- `goal`: one sentence, in the customer's terms.
- `machine.unit`: identifies the physical machine, not the model or type.

**`understanding`**: the statements shown to the user for confirmation, as they stood when the plan
was issued. `topic` is `machine`, `model`, `suspect`, or `logging`. `source` is where the
statement came from (`code`, `drawing`, `log`, `user`, `assumed`); a statement the user confirmed
or corrected has `source: "user"`. `confidence` is `high`, `medium`, or `low`.

**`model`**: what the predictions were computed with. `binaryFingerprint` is the planned binary's
`CppModel.BinaryFingerprint` (SDK 0.7.0+), `null` with an older SDK. `gitCommit`/`gitDirty` are
always recorded. Reconciliation compares only against
predictions from this exact model; a refined model means new predictions.

**`channels`**: every signal compared between simulation and field, defined once and referred to
by `id` from the runs.

- `simSignal`: the output name in the planned simulation's execution record.
- `logSignal`: the name in the field log, or `null` when it isn't known yet. Reconciliation then
  has to identify it, or derive the channel from others, and says which it did.
- `rateHz`: the planned logging rate. Predicted traces are stored at this rate.
- `tolerance`: how close actual and predicted must be for the run to count as agreeing (`abs` in
  the channel's unit, and/or `rel` as a fraction). This is the agreement test for promotion, so set
  it with the user.

**`runs`**: in the order the operator does them.

- `id`, `order`, `label`: identity. `label` is what the widget and reconciliation report use.
- `instruction`: what the operator does, in plain words.
- `setpoints`: the run conditions as numbers, which reconciliation uses to recognise the run.
- `durationS`, `repeat`: expected length of one attempt and how many attempts the plan asks for.
- `dependsOn`: run ids that must have been done first. Empty for most runs, since any run may be
  skipped.
- `identification`: how to find this run in an unannotated log (the markers before it, its
  setpoint signature).
- `hypothesis`: what the model predicts and what each kind of miss would mean.
- `simulation`: exactly the `inputs`/`parameters` posted for this run's planned execution, in
  `set_inputs` format (input `x` in ms).
- `prediction.index`: the planned execution the traces came from, as its run index under
  `model.binaryFingerprint` (`get_binary_runs`). `prediction.executionId` is set instead, and
  `index` is `null`, only when there's no fingerprint (SDK before 0.7.0). `passed` is its
  pass/fail.
- `prediction.traces`: one per channel in `channels`, inline (the widget draws from them). `x` is
  in ms from the start of the run, `y` in the channel's unit, sampled at the channel's `rateHz`
  with hold-last-value from the execution record.
