---
name: cppmodel:experiment-design
description: Design a field data-collection plan for a real machine - an experiment tailored to that machine and concentrated on the behaviour the plant model is least sure of, where every run carries the trace the current model predicts. The predictions come from a "planned" CppModel simulation kept apart from the production simulations until the plan proves realistic or the customer adopts it. Shows the AI's understanding of the machine and model, with predicted graphs, in a widget for the user to confirm or correct before anyone drives the machine. Use when a customer asks for a new simulation or plant model of a real machine, wants to tune or optimize a controller toward a goal on the real machine, reports that the simulation and the machine disagree, or wants to think through the process of collecting logs and converging the model.
---

## What this is

Controller work on a real machine bootstraps: a naive plant model, a controller built on it, then
real machine logs under that controller to refine the model, and around again. How fast that
converges depends mostly on **how the logs are collected**. This skill designs the collection.

- **Tailored, not a checklist.** The plan is for the specific machine in front of the operator and
  concentrates on the suspect behaviour (e.g. lift capacity at full outreach on a weak boom).
- **Every run is a hypothesis test.** Each run carries what the logs should look like if the current
  plant model were right. The gap between that and the real log is the information.
- **The only manual act is moving the machine.** Designing the plan, predicting, and later working
  out what really happened are done by the system, not on a clipboard.
- **v1 is present-and-follow.** The operator follows the plan as far as the machine allows and skips
  any run that can't be done. There is no editing and no form to fill in. Deviations are inferred
  later from the logs against the plan.

Its output is the **plan** (`plan.json`), whose format is in
[plan-format.md](plan-format.md). The plan is the whole contract with the reconciliation step,
which takes the returned logs plus the plan. Reconciliation is a separate skill
(`cppmodel:experiment-reconcile`), so keep everything it will need inside the plan.

## When to use it, and when not

Step in when:

- **A new simulation or plant model stands for a real machine.** Once `cppmodel:plant-model` has
  built the first, naive model, the next useful thing is the first field plan to test it. If no
  model exists yet, have `cppmodel:plant-model` build the naive one first, then come back. A
  prediction needs a model, and a naive model's prediction is still worth testing.
- **A controller is to be tuned or optimized toward a goal on the real machine** ("lift rated load
  at full outreach without stalling").
- **The simulation passes but the machine doesn't**, or a model refinement has stalled.
- **The customer wants to think about the process**: what to log, how to test the machine, how to
  get to a trustworthy model faster.

Not for purely simulated scenarios with no machine behind them (`cppmodel:simulation-testing`), or
for many runs over a parameter range in simulation alone (`cppmodel:parameter-sweep`).

## Planned vs production: two paths

The predicted traces are **just another CppModel simulation**: the same plant model and
controller, driven by the plan's manoeuvres. That simulation is built, run, and queried like any
other. It's kept apart from the production simulations, the ones the customer relies on in
`ctest`/CI, until it has earned its place:

| | Planned | Production |
|---|---|---|
| Files | `experiments/<plan-id>/`: `plan.json`, the planned simulation source, any trial model variant, returned logs | the project's existing simulations/models folders |
| Simulation name | `planned-<plan-id>` | the project's own naming |
| Build | its own CMake target | as today |
| `ctest`/CI | not registered | registered |
| Plant model | references the production model; a hypothesis that needs a changed model goes in a copy under `experiments/<plan-id>/` | never edited from here |

Keeping it out of `ctest`/CI matters for more than tidiness: step 4 runs it through posted inputs,
and any other execution of the same simulation on the same account would consume a posted
document.

Check whether the project already has an `experiments/` (or similar) convention and follow it. Ask
before creating the folder the first time, and ask whether returned logs belong in git (they can be
large; a `.gitignore`d `logs/` folder is the usual answer).

**Promotion** from planned to production happens when either:

- reconciliation (`cppmodel:experiment-reconcile`) shows predicted and actual agree within the
  plan's tolerances for the runs that matter, so the model is realistic for this goal; or
- the customer starts using it as a production function: wants it in CI, ships the manoeuvre, or
  wants it as a regression test.

Never promote on your own; propose it and wait for a yes. Promoting means:

1. move the simulation (and, after the user confirms, the trial model variant over the production
   model) into the production folders;
2. give it a production name, which is a new simulation on the server with an empty history (the
   planned history stays readable under `planned-<plan-id>`; say so);
3. turn the plan's runs into committed scenario files (`cppmodel:simulation-inputs`) or explicit
   scenario steps (`cppmodel:simulation-testing`);
4. register it in `ctest`/CI (`cppmodel:ci-pipeline`);
5. set the plan's `status` to `promoted`.

## 1. Gather what's already known

Before asking the user anything, read what exists:

- the controller under test and the plant model(s): what the model represents and what it leaves
  out (e.g. "no hydraulic dynamics", "rigid boom");
- existing simulations and their latest results, through the `cppmodel` MCP server (see
  `cppmodel:simulations`, including naming the account and workspace first);
- earlier plans under `experiments/` and how far they got: which runs were skipped, which
  predictions missed;
- any field logs, drawings, data sheets, or specs the user has pointed at.

Then get the **goal** in one sentence from the user if it isn't already clear. That is the one
thing to ask up front. Everything else is shown to the user in step 3 rather than asked.

## 2. Draft the understanding and the runs

### The understanding

Write down what you believe about the machine, the model, and the logging setup, as a list of
statements that can each be confirmed or corrected in one sentence. Give each one its source
(code, drawing, earlier log, assumption) and a confidence. Include:

- **machine**: which unit (one physical machine, not the type; two "identical" booms can differ),
  geometry, actuators, rated limits;
- **model**: which files, what it ignores, which version it is (step 4 records the fingerprint);
- **suspect behaviour**: what you think the model gets wrong, and why you think so;
- **logging**: which channels the machine can log, at what rate, and how a log comes back. When
  you don't know, assume something specific ("pressure at 100 Hz") and mark it low confidence. A
  wrong specific guess gets corrected; a vague question gets a vague answer.

### The runs

Each run is one manoeuvre. Design them so that the real logs separate model error from noise and
from operator variation:

- **Concentrate on the suspect behaviour.** Put most runs where the model and the machine are most
  likely to diverge, approaching it in steps (e.g. load in increments toward rated at full
  outreach) so the log shows *where* the divergence starts, not only that it exists.
- **Anchor with a baseline.** Start with one or two runs the model should certainly get right. If
  those miss, the problem is the setup (channels, scaling, units), not the suspect behaviour.
- **Repeat the runs that carry the answer**, at least twice, so the spread between repeats shows
  how much of a miss is noise.
- **Order from easy to hard, and safe to less safe.** A run the operator skips must not be needed
  to do a later run; if it is, say so in the later run's `dependsOn`.
- **Make every run findable in the log afterwards.** Reconciliation has to match runs to stretches
  of log with no annotations. Give each run a distinct signature (its setpoints) and separate runs
  with a deliberate marker the logs can show, such as a rest in a fixed pose for a fixed time.
  Write down in each run how to recognise it.
- **Plain operator language.** "With 1500 kg on the hook, extend to full outreach slowly, hold 10 s,
  lift 0.5 m, hold 10 s, lower" - not controller variable names.
- **Hold long enough to settle.** Holds and ramps follow the dynamics the run is meant to show.
- **Sample fast enough.** Per channel, at least 5-10 samples across the fastest transient that
  matters for the hypothesis. If that's beyond what the understanding says the logger can do, flag
  it rather than silently lowering it.
- **Size it to one field session.** State the estimated total time. Field time is the expensive
  part; cut low-information runs before cutting repeats of the decisive ones.
- **Stay within the machine's rated limits.** Approach a limit in steps, and the operator can always
  skip. The plan never replaces site safety procedures; say so in it.

Each run states its **hypothesis**: what the current model predicts, and what each kind of miss
would mean ("pressure saturating below the predicted plateau means less cylinder force than
modelled").

## 3. Predict: build and run the planned simulation

Preconditions: `.env` has `CPPMODEL_USERNAME`/`CPPMODEL_PASSWORD`, and the `cppmodel` MCP server
is authenticated. If either is missing, say so and stop.

1. **Build the planned simulation** under `experiments/<plan-id>/`, named `planned-<plan-id>`, as
   `cppmodel:simulation-testing` describes (`cppmodel:language` for a new file). It wires the
   existing plant model and controller exactly as the production simulation does, but reads the
   operator's side of a manoeuvre (commands, setpoints) as **inputs** and the run conditions
   (load, outreach) as **parameters**, so one binary serves every run and every later revision of
   the plan without a rebuild. It publishes as outputs every channel the field will log, under the
   names the plan maps to the log channels.
2. **Run one execution per run** with `cppmodel:parameter-sweep`, using an explicit `runs` list:
   one sweep run per plan run, with that run's inputs and parameters. The sweep verifies every run
   used what was posted. Each prediction is an execution in the workspace history, which the plan
   references by the sweep's `fingerprint` and `index` (or execution id with an SDK before 0.7.0),
   so reconciliation and later plans fetch it from there (`get_binary_runs`) instead of
   regenerating it.
3. **Record the model version.** Copy the binary's `CppModel.BinaryFingerprint` (SDK 0.7.0+; the
   sweep's `fingerprint`) into the plan, together with the git commit and whether the tree
   was dirty. With an older SDK there's no fingerprint: tell the user the predictions are tied to
   the model only by the commit.
4. **Copy each prediction into the plan.** From each run's execution record, take every logged
   channel's series, resample it with hold-last-value onto that channel's planned log rate, and
   store it in the run's `prediction`, with its index (or execution id). See
   [plan-format.md](plan-format.md).

A run that fails in simulation (`CppModel.StepResult` drops to 0, or the model stalls) is a
prediction too: "the model says this stalls". Keep it as it is. Don't adjust the run or the model
to make the prediction pass.

## 4. Present it: the widget

Show the understanding and the plan in one page instead of a list of questions. The message to the
user is: here's the machine and model I think I'm looking at, and the experiment I'd have you run;
correct me where I'm wrong.

Publish it as an Artifact (load `artifact-design`, and `dataviz` before any chart). Build it from
`plan.json`, so the page and the plan never disagree. If the Artifact tool isn't available, write
it to `experiments/<plan-id>/plan.html` and give the user the path. The page shows:

- **the goal**;
- **the understanding**: each statement with its source and confidence, low-confidence ones first,
  since those are the ones the plan depends on most;
- **the runs, in order**: the operator instruction, setpoints, channels and rates, the hypothesis,
  and **the predicted traces as graphs**, time on the x-axis and stepped (hold-last-value) lines,
  the way simulation results look in the workspace UI. A developer should be able to look at a
  predicted curve and disagree before anyone drives the machine;
- **the estimated session time**, and the safety note.

The user confirms or nudges ("can't reach full outreach at that load", "we only log pressure at
10 Hz"). For each correction: update the understanding, redesign the runs it affects, rerun their
predictions, and republish to the same URL. Repeat until the user says the plan is ready. There is
no editing in the page in v1: corrections come back through the conversation.

## 5. Issue it to the field

- Set `status` to `issued` and fill in `issued`. **An issued plan is never changed.**
  Reconciliation compares logs against exactly what was issued. A change after that is a new plan
  with a new id and `supersedes` set.
- The same page is the operator's sheet: offer an operator view (runs only, large type, in order,
  readable on a phone).
- Tell the user what to bring back: **the raw logs as recorded**, from start to end, untrimmed,
  with no annotations needed. Skipped or half-done runs are fine and expected. A free-text note is
  welcome but not required. Logs go in `experiments/<plan-id>/logs/`.

Finish with where the plan, the planned simulation, and the page are, and what happens when the
logs come back: `cppmodel:experiment-reconcile` takes them from there.
