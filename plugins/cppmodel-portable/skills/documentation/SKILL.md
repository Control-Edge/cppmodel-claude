---
name: documentation
description: "Write or update functional descriptions of a system's control functions (purpose, activation, interface, behaviour, limits, faults and interlocks, plant assumptions) with the plant model as their supporting description (update laws in TeX, parameters, simplifications). Evidence comes from the CppModel workspace: charts exported from specific committed executions, links to those executions, verification outcomes, and permalinks to the exact git commit and lines they ran. Offers once, without pushing, to derive a requirement set. Optionally publishes to the workspace's documentation. Drafted from the user's description before code exists and finalized once settled, or written directly from existing code. Use when asked to document a system function, controller, plant model or simulation, or for a functional description; at the start of cppmodel:plant-model or cppmodel:decouple-component; when a solution is settled or a refinement promoted; and to publish, list, read or delete workspace documentation."
---

## Reading notes

- This is the cppmodel plugin's `documentation` skill. It was written for Claude Code, but applies to any
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

## What this documentation is for

The goal is a **functional description of each system function**: what the control system does,
seen from outside, precisely enough that an engineer can review it, test against it, or
re-implement it. A system function is a behaviour the system delivers, named by what it achieves,
not by the code module: "Close door on command", "Obstacle reversal", "Tank level regulation",
"Motor overload protection".

The plant model is documented **in support of those functions**: it says what the controller can
rely on from the machine, and which simplifications limit what the simulations prove about each
function. It is never the main deliverable, and it stays shorter than the function descriptions.

## Lifecycle: draft first, final at the end

The work runs in this order: describe the system, implement the plant, then build or decouple the
controller. The documentation follows the same order, and it is written **twice**, not at every
change:

1. **Draft, at the start.** Before any model or controller code exists, ask the user for whatever
   description they already have: what the system must do (its functions, modes, limits, fault
   reactions), and how the machine behaves (a spec, a datasheet, notes, a sketch of the I/O, or a
   few sentences). Save it as the draft with as little rewriting as possible, only arranged under
   the headings below. Put this line under each draft's title:

   ```markdown
   > **Draft**: the initial description. It will be reshaped to match the implementation.
   ```

   The draft also feeds `cppmodel:plant-model`'s and `cppmodel:decouple-component`'s questions. Ask
   only what it doesn't already answer. If the user has nothing written, note what they say during
   the questions and offer to save that as the draft. Don't make a draft a precondition. If they
   don't want one, move on.
2. **Pause while the solution changes.** Don't touch the documentation while the model is being
   tuned, the controller reworked, or simulations iterated. The user can stop the documentation
   work at any point. The draft marker shows it is waiting to be finalized, so it carries over
   between sessions.
3. **Final, once the solution is settled.** Settled means the plant and controller both run, their
   simulations pass, and the user isn't still changing them. At that point, offer once to reshape
   the draft to match the code. Keep the customer's intent and reasons, correct what the
   implementation changed, add the evidence, and remove the draft marker. If the user says
   "later", leave the draft as it is.

After the documentation is final, offer an update only when a later change alters what it states:
a new or changed function, signal, state, limit, fault reaction or update law, or a promoted
refinement from `cppmodel:experiment-reconcile`. Renames, refactors, and tuning within the
documented ranges don't need one. "Keeping evidence current" says how to tell.

## Documenting an existing system

Often the controller already works and nobody wrote down what it does: the customer asks to
document it. Then there is no draft and no settling phase; write the final version directly:

1. **Ask once for anything written**: a spec, old manuals, requirement lists, tickets, or a few
   sentences on what the machine is for. Treat it as the customer's intent, as a draft would be.
2. **Read the code and the simulations**: the controller's modes, states, outputs and limits; the
   plant model; each simulation, its scenarios and its verification rules; and the workspace's
   history (`list_simulations` with `scope: "team"`, see "Evidence comes from committed runs").
3. **Propose the function list** ("Find the system functions first") and confirm it.
4. **Write each function from the code**, with evidence, as for a final version.
5. **Separate what from why.** The code says what the controller does, not why. A limit, timeout,
   or interlock whose reason nobody stated is an open question for the customer, never a guess.
   Where the code and the customer's written intent disagree, write what the code does and list
   the disagreement as an open question: it may be a bug, and that's the customer's call.

Don't refactor or fix the controller while documenting it. Report what looks wrong, as open
questions or findings, and leave the change to a separate task.

## When to offer it

Each skill makes at most one offer per task, as a single line that doesn't block the work:

- **At the start of `cppmodel:plant-model` or `cppmodel:decouple-component`**, when no
  documentation exists: ask for the initial description (step 1).
- **When the solution is settled**: offer the final version (step 3). This is usually at the end
  of `cppmodel:simulation-testing`, once the new simulation covering the plant and controller
  passes, or at the end of `cppmodel:verification`.
- **In `cppmodel:experiment-reconcile`**, when a refinement is promoted: offer to update the plant
  description and any function whose plant assumptions it changed.
- **When the user asks to document existing code**: no offer needed, see "Documenting an existing
  system".

Don't offer it after debugging, sweeps, inputs runs, CI, dependency updates, or environment setup.
Also stay quiet in these cases:

- **The user declined or said "later"** earlier in the session: don't offer again.
- **The user says never** for this project: store `"documentation": "never"` in
  `.claude/cppmodel.local.json`, merging with the keys already there (as `cppmodel:language` does).
  Check that key before offering. An explicit request still overrides it.

To find existing documentation, look under `docs/`, next to the controller or the model, or for a
file that links to their source.

## Find the system functions first

Before writing the final version, list the system functions and confirm the list with the user.
Take them from, in this order: the customer's description and requirements, the controller's
modes and top-level states, the simulations and their verification rules (each rule usually
guards one function), and the outputs the controller drives. One function usually maps to one
mode, one control loop, or one protection. Keep housekeeping (initialisation, logging, diagnostics
plumbing) out unless the customer cares about it. Show the list as one line per function, with the
code it lives in and the simulations that exercise it, and ask whether anything is missing or
should be split or merged.

While listing them, also find how they interact, since that is where functional descriptions most
often go wrong:

- **System modes**: the top-level modes (for example manual, automatic, maintenance, emergency
  stop), what switches between them, and which functions are active in each.
- **Shared actuators**: every output driven by more than one function, and which one wins
  (priority, override, latching), as the code decides it.
- **Dependencies**: a function that waits for, enables, or inhibits another.

A function no simulation exercises stays on the list, marked as such (see "Structure").

## Where it goes

Don't assume a path. Use the project's existing documentation folder if it has one. Otherwise
suggest this layout under `docs/` and confirm it with the user:

```
docs/
  index.md              the system: its functions, the closed loop, links to everything below
  functions/<Name>.md   one functional description per system function (the main deliverable)
  plant/<Model>.md      the plant model, supporting the functions
  img/                  figures exported from recorded executions
  requirements.json     only if the customer asked for a requirement set
```

A small system with one or two functions can keep everything in one file: the functions first,
the plant last. If several simulations share a plant model, keep one plant description and list
in it the functions and simulations that use it.

## Ground it in the code and the workspace, not memory

In the final documentation, every name, number, state and limit comes from the source files, from
a recorded execution, or from what the customer said. The draft is the exception, since it records
the customer's description before any code exists. Re-read the controller, the model, and the
simulation files before writing. Never write from what you remember.

If a value isn't in the code and nobody stated it, such as a physical unit, a tolerance, or why a
limit exists, write it as an open question. Never invent it. Results, verification outcomes and
figures come from the `cppmodel` MCP server (see `cppmodel:simulations`, including its account
check before the first call). Never take them from a local file or from memory. If the server is
unavailable, leave the evidence sections saying so.

## Links: relative, execution, and commit

Use three kinds of links, each for its own purpose:

- **Relative links** to the current source, for "where does this live now":
  `[DoorController.c](../../src/DoorController.c)`. Every function section links the code it
  describes.
- **Execution links** for evidence: the execution's `uiUrl` from `list_executions` or
  `get_execution` (`<workspace>/results/<name>/executions/<id>`), or the simulation's page for "the
  latest run". These are the lasting links. Workspace links open only for workspace members; say
  so once in `index.md`.
- **Chart page links** (`<workspace>/snapshots/<id>`, an export's `uiUrl`) may be noted next to a
  figure, so readers can open the interactive chart while it lasts, but always marked temporary
  with the export's `expiresAt` date, and always beside the execution link, never instead of it.
- **Commit permalinks** for "exactly the code that produced this evidence": the execution's
  `CppModel.GitHash` (SDK 0.15.0+) pins the commit it ran. Link the commit, and the lines of the
  function's code at that commit, so a reader sees the code, the run and the figure line up.

Build permalinks from the repository itself:

1. Base URL: `git remote get-url origin`, turned into its https form
   (`git@github.com:org/repo.git` becomes `https://github.com/org/repo`). No remote: give the
   commit hash as text and use relative links only.
2. Full hash: `git rev-parse <GitHash>` (without its `-dirty`). If it doesn't resolve, the run came
   from a commit this clone doesn't have; say so instead of linking.
3. Pushed? `git branch -r --contains <sha>`. If nothing contains it, the link won't open until the
   commit is pushed: tell the user.
4. Line numbers at that commit, not in the working tree: `git show <sha>:<path> | grep -n ...`.
5. Format per host:

   | Host | Commit | Lines of a file at a commit |
   |------|--------|------------------------------|
   | GitHub | `<base>/commit/<sha>` | `<base>/blob/<sha>/<path>#L10-L42` |
   | GitLab | `<base>/-/commit/<sha>` | `<base>/-/blob/<sha>/<path>#L10-42` |
   | Bitbucket | `<base>/commits/<sha>` | `<base>/src/<sha>/<path>#lines-10:42` |
   | Gitea | `<base>/commit/<sha>` | `<base>/src/commit/<sha>/<path>#L10-L42` |

**Evidence comes from committed runs.** A run with `-dirty`, or without a git hash, ran code no
commit holds, so it can't back a final description. Use the newest committed execution
(`list_simulations` shows `lastCommittedGitHash`; `tracking: "committed"` filters), preferably one
from CI. If there is none, ask the user to commit and run the simulation again (you don't commit),
or leave the evidence marked as pending. For a VirtualPLC simulation the fingerprint doesn't cover
the `.st` files, so the git hash is the only thing tying a run to its controller code.

**Look across the team.** Committed runs usually come from CI, which runs under its own account,
so `list_simulations` and `list_executions` without `scope: "team"` don't show them. Search with
`scope: "team"`, and when a run you cite came from another account (CI or a colleague), say so in
the caption.

**Report the status as it is.** If the newest committed run of a simulation fails, don't go back
to an older passing run to make the evidence look green. Document the failure: which rule or step
failed, its `explanation` and `violations` from the execution's `verification`, and a link to the
run. Mark the function's evidence as failing in the index, and tell the user. A function is only
shown as passing when its newest committed run passes. An older passing run may still serve as a
figure of the intended behaviour, but only labelled as older, with its commit.

**Running a simulation for evidence.** When no recorded run covers a case (typically a fault or
limit case), a new run is needed. Before running anything, check the credentials as
`cppmodel:simulation-testing`'s "Requirements" describes (`.env` with `CPPMODEL_USERNAME`,
`CPPMODEL_PASSWORD`, `CPPMODEL_CLIENT_ID`); if they're missing, stop and tell the user. Run the
case with its inputs through `cppmodel:simulation-inputs`, which confirms from the execution that
the inputs were really applied (`expected`, `applied`, `differences`). A run whose inputs weren't
applied doesn't show the case, so it can't be evidence. A case needing its own logic is a new
simulation (`cppmodel:simulation-testing`), not a documentation step: list it as missing evidence
and offer that instead.

## Evidence costs least as recorded runs plus exports

Every figure, number and status in the documentation comes from an execution submitted to the
workspace, read back with the `cppmodel` tools. That is also the cheapest way to get it, in tokens
and in time:

- **A submitted run costs nothing extra.** The workspace already stores every input, parameter and
  output series, and the verification outcomes with their margins. Each question afterwards is one
  tool call whose answer is cut to size: `export_signals` `png` for a figure, `csv` for the values
  behind a number in a table, `get_execution` with `summary: true` for the signal names and ranges,
  `what_changed` for what differs between two runs.
- **Running offline and building scripts around it costs far more**, and it buys nothing: writing
  a plotting or parsing script, fixing it when it doesn't run the first time, reading a whole
  results file into context to find a few values, rendering a chart, then cleaning up leftover
  files, and the result is a picture nobody can trace back to a run or check later.
- **So never run a simulation offline (`--results`) to produce documentation, and never write a
  script to plot, parse or re-check results for it.** If no recorded run covers what a figure
  needs, run the simulation so it submits (with `cppmodel:simulation-inputs` for a scenario), then
  export from that execution.

## Figures from recorded executions

Each function gets one to three figures, chosen to show the function doing what the text claims:
the nominal case, and the most important fault, interlock or limit case. A figure is worth adding
only where its shape says something: a response and its settling, a sequence of states, a reaction
to a fault. Skip figures for a function whose behaviour a table says completely.

1. **Pick the execution**: the newest committed run of the simulation that exercises the case
   (`list_executions` with `scope: "team"`, `get_execution` with `summary: true` for the signal
   names), from the evidence commit (see "Keeping evidence current"). For a fault case, an
   execution with the fault injected, often a scenario run with its own inputs (see "Running a
   simulation for evidence").
2. **Export it**: `export_signals` with `format: "png"`, the command and the response together, at
   most 4-5 signals, `from`/`to` cut to the part that matters, `scale`/`yOffset` to bring signals
   onto one readable axis, `xOffset` to line a response up with its command, and the parameters
   that matter as `parameters` (they become the caption). A width of about 1200 px reads well in
   a page.
3. **Look at it** and check it shows what the text says. If not, the text or the choice of run is
   wrong: fix that, never the figure.
4. **Save the image next to the documentation**, as `docs/img/<function>-<case>.png` (or the
   project's own image folder beside the pages). Figures belong in the repository with the pages
   that show them, so they outlive the export. The export result comes with a line
   `[Image: source: <path>]` naming the PNG the client already wrote to disk: copy that file
   (`cp "<path>" docs/img/<function>-<case>.png`), and check it with `file` (a PNG of the size you
   asked for). Don't re-fetch it or regenerate it another way. Only if your client gives no such
   path, list for the user each export's `uiUrl` (its page has a PNG download) with the path to
   save it as, all in one message, since exports last 7 days. Until the file is there, the figure
   line stays in the document with its execution link.
5. **Caption it** with everything needed to find the run again:

   ```markdown
   ![Door closes on command and stops at the closed limit](../img/close-door-nominal.png)

   *Figure 1. Close on command.* Simulation `DoorSim`,
   [execution 64f2a1](<execution uiUrl>), commit [`d6ebfd2`](<commit permalink>),
   code at that commit: [DoorController.c#L40-L88](<lines permalink>). Signals `cmd_close`,
   `door_pos_mm`, `motor_dir`, 0-12 s. [Interactive chart](<export uiUrl>) (temporary, until
   2026-11-14).
   ```

Never draw a figure yourself from exported values: the workspace chart is the evidence. A chart
across several executions (for example a sweep's pass/fail boundary), which no export draws, is
the one exception (`dataviz`, see `cppmodel:simulations`).

## Keeping evidence current

The documentation is evidence from one point in time. Keep it consistent and say when it's old:

- **One evidence commit.** Take all figures and statuses from runs of one commit, ideally one CI
  run of it, and name that commit once in `index.md`. If some simulation has no committed run at
  that commit, use its newest committed run and give its own commit in that figure's caption, so
  no reader assumes it matches the rest.
- **Staleness check, before any update and when asked whether the docs are current.** For each
  function, compare the evidence commit with `HEAD` for the files the function lives in:
  `git diff --stat <evidence sha> HEAD -- <function's files>`. Then run `what_changed` between the
  evidence execution and the newest committed one (`current_id`, `previous_id`): code rebuilt,
  parameters changed, signals added or gone. No change in either: the evidence still stands. A
  change: re-read the diff, update the text if the behaviour changed, and refresh the function's
  figures and status from a run at the new commit.
- **Refresh figures as a set.** When the evidence commit moves, re-export every figure from the
  new runs (same signals, range and file names, so the pages don't change), and update the
  captions' execution, commit and line links. Then the index names the new commit.
- **Expired chart links.** A temporary chart link (`/snapshots/`) dies after its `expiresAt` date.
  On every update, replace each expired link with the new export's, or remove it. The execution
  link and the saved PNG stay.
- **Old evidence is labelled, not hidden.** If the user doesn't want a refresh now, leave the
  figures and add one line to the index: the evidence commit, and that the code has changed since
  in the functions listed.

## Keep it short

A long description loses its readers. Write the shortest one that lets an engineer new to the
project review, test, or re-implement the function. Anyone who needs more can ask.

- **One to two screens per function**, about a page for the plant. `index.md` fits on one screen.
- **Tables, equations, and diagrams instead of prose.** Each section opens with at most one or two
  sentences.
- **Behaviour, not code.** Describe what the function does and link the source. Leave out helper
  functions, struct layout, and the cycle callback's mechanics.
- **Don't explain CppModel itself.** Readers can follow the links.
- **Leave out the obvious.** Skip rows and sections that say nothing a reader couldn't guess.
- **Say each fact once.** A signal is described in the function that owns it; others link there.
  Plant behaviour lives in the plant description; functions link to its sections.
- **When updating, keep to the same budget.** Replace outdated text instead of adding to it, and
  don't keep a change log. Git history already has one.

## Structure

Include only the sections with something real to say.

### `index.md`: the system

- Two or three sentences: what the system is and what it is for.
- The system functions as a table: function (linked), what it achieves, simulations that exercise
  it (linked to their workspace pages), and the status of its newest committed run (passing,
  failing, or "not exercised by simulation").
- The system modes as a Mermaid `stateDiagram-v2`: the modes, what switches between them, and
  which functions are active in each. Leave it out when the system has one mode.
- Shared actuators as a table: actuator, the functions that drive it, and which wins (priority,
  override, latching), with a link to the code that decides it. Leave it out when each output has
  one owner.
- The closed loop as a Mermaid `flowchart LR`: controller functions, the plant, and the signals
  between them.
- One line on where the evidence lives: the workspace (members only), the evidence commit, and,
  if the code has moved on since, which functions changed (see "Keeping evidence current").

A function no simulation exercises gets a description like any other, with its evidence section
saying "not exercised by simulation" and what a simulation would need to cover it. Offer once, in
one line, to add that coverage with `cppmodel:simulation-testing`.

### `functions/<Name>.md`: one system function

1. **Purpose**: one or two sentences. What the function achieves, and for whom (operator, machine,
   another function).
2. **Activation**: when it runs, and what must hold before it may act (mode, permissives, other
   functions it waits for). A short list. Link the index's system modes and, for a shared
   actuator, its row in the shared-actuators table, saying which functions this one overrides or
   yields to.
3. **Interface**: one table with columns signal, direction (in or out), source or destination,
   type or range with unit, and meaning. Include commands, sensors, parameters and status outputs.
4. **Behaviour**: for a sequence or mode logic, a Mermaid `stateDiagram-v2` with the code's guard
   names on the arrows, and a table of what each state commands. For continuous control, the
   control law in TeX (setpoint, error, gains, limits, anti-windup, rate limits), with each symbol
   mapped to its code identifier. Link the code (relative, plus the commit permalink once evidence
   exists). For a decoupled component, add one line naming the entry point and the vendor calls it
   replaced.
5. **Performance and limits**: one table with columns property, value, and source. Response
   times, timeouts, settling, accuracy, ranges, cycle period. Source is the code line, the
   customer, a verification rule's margin, or a parameter sweep's boundary (with its execution
   links, see `cppmodel:parameter-sweep`).
6. **Faults and interlocks**: one table with columns condition, how it is detected, reaction, and
   recovery. Only the ones the function handles; link others to the function that does.
7. **Plant assumptions**: what this function relies on from the machine (a sensor that switches
   before the end stop, a travel time within a range, a monotonic response), each linked to the
   plant description's section. Name the plant simplifications that limit what the simulations
   prove about this function.
8. **Evidence**: the figures (above), then, if the simulation has verification rules
   (`cppmodel:verification`), one table with columns requirement ID, rule, settings, and latest
   status with margin, taken from the execution's `verification` and `requirements`. A failing
   rule shows as failing, with its `explanation` and a link to the run. List what the simulations
   don't cover, too.
9. **Open questions**: a bullet list, only if there are any.

### `plant/<Model>.md`: the supporting plant model

1. **Overview**: two or three sentences. The mechanism, what the model is for (exercising the
   controller, not physical accuracy), and the functions it supports (linked).
2. **Interface**: one table with columns signal, direction (actuator or sensor), source, type or
   range, and meaning. Source is the input document, the plant (as the input's fallback,
   overridable), or the controller. List only signals the function descriptions don't already
   cover; link to them for the rest.
3. **Update laws**: the per-cycle laws in math (below), then one parameters table with columns
   name, default, unit, and source.
4. **Simplifications**: a bullet list of what was left out, why, and which function it affects,
   one line each, in the customer's words where possible. It is the hardest part to rebuild later.
5. **Validation**: field experiments, one line per plan with its status
   (`cppmodel:experiment-design`, `cppmodel:experiment-reconcile`), and, where measured data was
   recorded as its own simulation (`<name> (field)`), a link to that execution next to the
   simulated one. Leave the section out if the model was never compared with the machine.
6. **Open questions**: only if there are any.

## Math: TeX in Markdown

Write equations as TeX. GitHub, GitLab, Gitea, VS Code's Markdown preview, and the workspace's
documentation viewer all render it: use `$...$` inline and `$$...$$` for display. The model and
the controller work in cycles, not seconds, so write discrete-time laws indexed by the cycle $k$
with period $T$ (`task_period_ms`):

```markdown
$$
x_{k+1} =
\begin{cases}
\min\left(x_k + \Delta,\ x_{\max}\right) & \text{if } u_k = \text{extend} \\
\max\left(x_k - \Delta,\ x_{\min}\right) & \text{if } u_k = \text{retract} \\
x_k & \text{otherwise}
\end{cases}
\qquad
\Delta = \frac{x_{\max} - x_{\min}}{t_{\text{traverse}} / T}
$$
```

Stay inside what both KaTeX and MathJax support: `cases`, `aligned`, `\frac`, `\text`, `\mathrm`,
`\le`/`\ge`, and `\lfloor\cdot\rfloor` for integer configuration types. Don't use `\usepackage`,
`\newcommand` across blocks, TikZ, or `align` outside `$$`. Write `\lt`/`\gt` instead of a bare
`<`/`>` next to letters, which some renderers read as HTML. Leave a blank line around each `$$`
block. Name every symbol after its first equation, and map it to its code identifier.

Bitbucket doesn't render TeX: there, put each law in a fenced code block as plain text
(`x[k+1] = min(x[k] + delta, x_max)`) with the TeX underneath in a collapsed `<details>` block.
Use math only where the content has an equation. A threshold or a table often says it better.

## Diagrams

Draw state machines as Mermaid `stateDiagram-v2` and the closed loop as a `flowchart LR`. GitHub,
GitLab, Gitea, and VS Code (with a Mermaid extension) render both; the workspace viewer doesn't
(see Publishing). Label transitions with the guard names the code uses. TikZ doesn't render in
Markdown, so don't use it.

## Offering a requirement set (once, never pushed)

Functional descriptions are close to requirements, and some customers want those too. When the
final documentation is done, and only if the customer has no requirement set for these functions
yet, offer it **once**, in one line at the end of your report, for example: "If it's useful, I can
also derive a requirement set from these functional descriptions." Then drop it:

- Don't repeat the offer, argue for it, or bring it up again in later tasks. If the user ignores it
  or says no, that is the answer. If they say never for this project, store
  `"requirements": "never"` in `.claude/cppmodel.local.json` (merged as above) and check it before
  offering.
- If the customer already has requirements, don't offer new ones: reference their IDs in the
  function descriptions instead, and offer `cppmodel:verification` if they aren't verified yet.

If they accept:

- Derive each requirement from a statement in a function description: one testable "shall" per
  behaviour, limit, or fault reaction, with the number and unit the description gives. Nothing the
  description doesn't say. Open questions become open questions, not requirements.
- Propose an ID scheme (`<AREA>-<KIND>-NNN`, as in `cppmodel:verification`) and get a yes before
  using it.
- Write them to `docs/requirements.json` in the SDK's shape, which `cppmodel:verification` checks
  coverage against: `{"requirements": [{"id": "...", "description": "..."}]}`. Add a short table
  of the IDs derived from each function (ID, requirement, source section) to that function's
  description.
- Mark them as proposed: the customer owns the wording and reviews every one. Say which statements
  were left out as not testable by simulation (hardware, EMC, process).
- Then offer, in one line, to verify them in simulation with `cppmodel:verification`.

## PDF, only if asked

If the user wants a PDF, check whether `pandoc` and a TeX engine (`xelatex` or `pdflatex`) are
installed. If they are, run `pandoc <doc>.md -o <doc>.pdf --pdf-engine=xelatex --resource-path=<doc's folder>`
so the figures resolve. The `$...$` math carries through as real LaTeX. Mermaid needs a filter
such as `mermaid-filter`; without one, mention that the diagrams won't appear. Don't install a TeX
distribution without asking, because it is large.

## Publishing to the workspace

A licensed (`w#####`) workspace can host documentation: per documentation project, one set of
Markdown pages plus images (PNG, JPEG, GIF, SVG, WebP), PDFs, text, CSV and JSON (at most 5000
files and 300 MB), readable by everyone in the workspace. Free-workspace accounts get `403`; then
the documentation stays in the repository only. The `cppmodel` MCP server's tools:

| Tool | Use |
|------|-----|
| `list_docs` | the workspace's documentation projects, with site name, who uploaded when, and `siteUrl` |
| `get_docs` | a project's manifest (site name, `nav`, files with sizes and page titles), or with `file` one file: Markdown/text as `text`, an image to look at |
| `upload_docs` | publish `files` (`[{path, text}]`, or `{path, base64}` for an image or PDF), optional `site_name` and `nav`; with `merge: true` keep the rest (and `remove` some) |
| `delete_docs` | IRREVERSIBLE: the project's whole set, for everyone |

- **Only when the user asks to publish.** The repository copy is the source; the workspace copy is
  a published snapshot of it. Never publish a draft unless the user asks for that explicitly, and
  don't re-publish on every edit: offer once, when the final version or an update is done. Don't
  offer at all on a free workspace.
- **Read before writing.** Call `list_docs`, and `get_docs` for the project you'll write to, to
  see what's already there and who uploaded it. Pick the project name with the user (1-64 letters,
  digits, `.`, `_` or `-`); the repository's or product's name is a good default.
- **Without `merge`, an upload replaces the whole set**: files left out are deleted. When the
  project holds more than this documentation (other systems, other people's pages), upload with
  `merge: true` and only the files that changed, and `remove` only files you put there. A full
  replace is right only when the upload is the complete set, such as the repository's whole
  `docs/` folder.
- **Upload the files as they are in the repository**, with their relative paths, and every figure
  the pages link to (`base64 -w0 docs/img/<file>.png` for its `base64`). Relative links between
  pages and to figures keep working. Execution and commit permalinks keep working too, since
  they're absolute. Relative links to source files outside the uploaded set
  (`../../src/DoorController.c`) don't: leave them, the commit permalinks cover the reader there.
  Anything other than the types above comes back in `skipped`: tell the user.
- **Navigation**: without `nav`, it follows the folder tree (`index.md` first, titles from each
  page's first `#` heading), and a merge keeps the current one and appends new pages. Pass `nav`
  (`[{title, path | url | children}]`, as `get_docs` shows it) when the user wants an order of
  their own, for example the functions in operating order before the plant.
- **Rendering**: the viewer renders navigation, admonitions, tables, highlighted code and TeX math.
  Mermaid isn't among them, so check with the user whether diagrams showing as source is
  acceptable there.
- **`siteUrl` is temporary**, and a browser opens it only as `<siteUrl>?access_token=<token>`. Give
  the user `siteUrl` and say it needs their token; never append a token to it yourself, and never
  put `siteUrl` into anything meant to last (the documentation itself, a README, a commit).
- **`delete_docs` can't be undone** and removes the set for everyone: only when the user explicitly
  asks, after saying what will be lost.

## Finish

Tell the user where the documentation is, which functions it describes, whether any of it is still
a draft, and which sections were left as open questions. Give the evidence commit, and list the
figures saved (and any still waiting to be downloaded from their export pages, with the links and
target paths), the functions whose evidence is failing, not exercised by simulation, or pending
because no committed run or no pushed commit exists yet, and any disagreements found between the
code and the customer's intent. If it was an update, say which functions changed.
If it was published, give the project name, the files uploaded and any `skipped`, and `siteUrl`.
Mention, in one line, that any part can be expanded if they want more detail. Then, if the
conditions above hold, the one-line requirement-set offer.
