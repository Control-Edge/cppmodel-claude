# Reconciliation format

`experiments/<plan-id>/reconciliation.json` is what `cppmodel:experiment-reconcile` concluded
from one field session's logs against one issued plan. The plan stays as issued; this file sits
beside it. A plan reconciled twice (more logs arrive, or the user corrects the identification) gets
the same file updated, with `revision` incremented.

## Example

```json
{
  "formatVersion": 1,
  "planId": "2026-10-05-boom3-lift-at-reach",
  "revision": 1,
  "created": "2026-10-09",

  "planModel": { "sourceFingerprint": "9f2c...e1", "gitCommit": "d1d3d88", "rebuiltMatches": true },

  "logs": [
    { "file": "logs/boom3_2026-10-08.mf4", "sha256": "77b0...", "format": "MDF4",
      "startUtc": "2026-10-08T09:12:03Z", "durationS": 3120 }
  ],

  "channels": [
    { "id": "p_lift", "logSignal": "P_LIFT_A", "method": "named", "confidence": "high",
      "measuredRateHz": 100 },
    { "id": "outreach", "logSignal": null, "method": "derived from boom/jib angles and drawing 4471 geometry",
      "confidence": "medium", "measuredRateHz": 50 }
  ],

  "loggingFindings": [
    "Hook load is not logged; inferred from lift pressure at known geometry."
  ],

  "segments": [
    { "id": "s01", "log": "logs/boom3_2026-10-08.mf4", "startS": 142.0, "endS": 205.5,
      "run": "r01", "attempt": 1, "confidence": "high",
      "reason": "10 s rest before, outreach plateau 5.02 m, pressure plateau 91 bar" },
    { "id": "s07", "log": "logs/boom3_2026-10-08.mf4", "startS": 1630.0, "endS": 1702.0,
      "run": null, "confidence": "high", "reason": "Slew without load; matches no run (unplanned)" }
  ],

  "runs": [
    {
      "run": "r04",
      "status": "deviated",
      "attempts": [
        {
          "segment": "s05",
          "achieved": { "loadKg": { "value": 1200, "inferred": true }, "outreachM": { "value": 7.1 } },
          "deviations": ["Outreach 7.1 m of 8.2 m planned", "Lift aborted after 6 s of a 10 s hold"],
          "alignment": "Lift command onset at 1180.4 s in the log = 0 ms",
          "asRun": {
            "executionId": "6711...",
            "simulation": { "inputs": [], "parameters": { "Load [kg]": 1200, "Target Outreach [m]": 7.1 } }
          },
          "comparison": {
            "p_lift": { "against": "asRun", "withinTolerance": 0.42, "maxError": 37.5,
                        "plateauError": 35.0, "divergesAt": "from 1100 kg at 7.1 m (t = 2.4 s)" }
          },
          "verdict": "disagrees"
        }
      ],
      "repeatSpread": { "p_lift": 3.1 },
      "hypothesis": "refuted",
      "hypothesisNote": "Pressure saturates at 205 bar; the model has no relief limit and predicts 240 bar."
    },
    { "run": "r06", "status": "skipped", "attempts": [], "hypothesis": "inconclusive",
      "hypothesisNote": "Not attempted; r04 already could not reach full outreach at 1200 kg." }
  ],

  "conclusion": "The model matches below 1000 kg at any outreach. Above that at outreach > 6.5 m the lift cylinder saturates near 205 bar, which the model doesn't limit.",

  "refinements": [
    {
      "id": "v1",
      "description": "Relief pressure limit 205 bar on the lift cylinder",
      "files": ["experiments/2026-10-05-boom3-lift-at-reach/BoomModel.h"],
      "sourceFingerprint": "c41d...9a",
      "fittedOn": ["s05"],
      "checkedOn": ["s06", "s08"],
      "results": [
        { "segment": "s06", "executionId": "6720...",
          "comparison": { "p_lift": { "withinTolerance": 0.97, "maxError": 6.2 } }, "verdict": "agrees" }
      ]
    }
  ],

  "nextStep": { "proposal": "plan-again", "reason": "Confirm the relief limit at 8.2 m with a lighter load before promoting." }
}
```

## Fields

- `planId`, `revision`: which plan, and how many times this file has been redone.
- `planModel`: the plan's model version, and whether the binary used for the as-run simulations
  matched it (`rebuiltMatches`). If it didn't match, no comparison here is valid.
- `logs`: every file used, with a hash so a later reader knows the exact data.
- `channels`: how each plan channel was found in the logs. `method` is `named` (the plan's
  `logSignal`), `identified` (found by behaviour), or a description of how it was derived.
  `measuredRateHz` is the rate actually in the log.
- `loggingFindings`: where the logging differed from the plan's understanding. The next plan reads
  these.
- `segments`: every stretch of log that was interpreted, matched (`run` set) or unplanned
  (`run: null`), with times in seconds from the start of that log file.
- `runs`: one entry per plan run, skipped ones included.
  - `status`: `done` (as planned), `deviated`, `partial`, or `skipped`.
  - `attempts[]`: one per matched segment. `achieved` holds the setpoints actually reached, each
    marked `inferred` when it wasn't logged directly. `asRun` is the simulation of what was
    actually done, in `set_inputs` format, with its execution id. It's `null` when the operator
    side wasn't logged, and `comparison[].against` is then `"planned"`.
  - `comparison`: per channel. `withinTolerance` is a fraction of the attempt's time, and errors
    are in the channel's unit.
  - `verdict`: `agrees`, `disagrees`, or `inconclusive`. `hypothesis`: `supported`, `refuted`, or
    `inconclusive`, with `hypothesisNote` in the plan's own terms.
  - `repeatSpread`: per channel, the spread between repeats, to judge misses against.
- `refinements`: trial model variants on the planned path. Each records its files, its
  fingerprint, the segments it was fitted on and those it was checked on, and the as-run results
  with it. Judge a variant only on its `checkedOn` segments.
- `nextStep.proposal`: `promote`, `plan-again`, or `retune-controller`.
