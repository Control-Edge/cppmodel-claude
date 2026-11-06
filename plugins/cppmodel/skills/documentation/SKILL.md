---
name: cppmodel:documentation
description: Write or update a concise Markdown document describing a CppModel plant model and the controller it exercises - signal interface, plant behaviour as per-cycle update laws (TeX math), parameters and timing, the controller's states and transitions, the closed loop, the simplifications made and why, and how it is validated. Optionally publishes it to the CppModel workspace's documentation (w##### workspaces), where everyone in the workspace can read it. Starts as a draft from the user's own initial description before any code exists, stays untouched while the solution changes, and is reshaped to match the code once the plant and controller are settled. Use when asked to document a plant model, a controller, or a simulation, at the start of cppmodel:plant-model or cppmodel:decouple-component (to collect the initial description), when a solution is settled or a refinement is promoted, and when asked to publish, list, read or delete the workspace's documentation.
---

## Lifecycle: draft first, final at the end

The work runs in this order: describe the plant, implement it, then build or decouple the
controller. The document follows the same order, and it is written **twice**, not at every change:

1. **Draft, at the start.** Before any model or controller code exists, ask the user for whatever
   description they already have: a spec, a datasheet, notes, a sketch of the I/O, or a few
   sentences on how the machine behaves. Save it as the draft document with as little rewriting as
   possible. Only arrange it under the headings below. Put this line under the title:

   ```markdown
   > **Draft**: the initial description. It will be reshaped to match the implementation.
   ```

   The draft also feeds `cppmodel:plant-model`'s questions. Ask only what it doesn't already
   answer. If the user has nothing written, note what they say during the questions and offer to
   save that as the draft. Don't make a draft a precondition. If they don't want one, move on.
2. **Pause while the solution changes.** Don't touch the document while the model is being tuned,
   the controller reworked, or simulations iterated. Code changes during this phase don't need
   documentation updates, and the user can stop the documentation work at any point. The draft
   marker shows that the document is waiting to be finalized, so it carries over between sessions.
3. **Final, once the solution is settled.** Settled means the plant and controller both run, their
   simulations pass, and the user isn't still changing them. At that point, offer once to reshape
   the draft to match the code. Keep the customer's intent and reasons, correct what the
   implementation changed, and remove the draft marker. If the user says "later", leave the draft
   as it is.

After the document is final, offer an update only when a later change alters what it states, such
as a new signal, update law, or state, or a promoted refinement from `cppmodel:experiment-reconcile`.
Renames, refactors, and tuning within the documented ranges don't need one.

## When to offer it

Each skill makes at most one offer per task, as a single line that doesn't block the work:

- **At the start of `cppmodel:plant-model` or `cppmodel:decouple-component`**, when no document
  exists: ask for the initial description (step 1).
- **When the solution is settled**: offer the final version (step 3). This is usually at the end
  of `cppmodel:simulation-testing`, once the new simulation covering the plant and controller
  passes.
- **In `cppmodel:experiment-reconcile`**, when a refinement is promoted: offer to update the
  sections it changed.

Don't offer it after debugging, sweeps, inputs runs, CI, dependency updates, or environment setup.
Also stay quiet in these cases:

- **The user declined or said "later"** earlier in the session: don't offer again.
- **The user says never** for this project: store `"documentation": "never"` in
  `.claude/cppmodel.local.json`, merging with the keys already there (as `cppmodel:language` does).
  Check that key before offering. An explicit request for a document still overrides it.

To find an existing document, look next to the model, under `docs/`, or for a file that links to
the model's source.

## Where it goes

Don't assume a path. Use the project's existing documentation folder if it has one. Otherwise
suggest `docs/<Name>.md` (for example `docs/ConveyorModel.md`) and confirm it with the user. Use
one document per plant and controller pair. If several simulations share a model, keep one document
for the model and list each simulation in it.

## Ground it in the code, not memory

In the final document, every name, number, and state comes from the source files or from what the
customer said while the model was being built. The draft is the exception, since it records the
customer's description before any code exists. Re-read the model, the controller, and the simulation file
before writing. Never write from what you remember. Link each section to its source with a relative
link, for example `[ConveyorModel.c](../models/ConveyorModel.c)`, so a reader can check it.

If a value isn't in the code and nobody stated it, such as a physical unit or why a limit exists,
write it as an open question. Never invent it. Validation results come from the `cppmodel` MCP
server (`get_latest_result`, `list_executions`; see `cppmodel:simulations`). Never take them from a
local file or from memory. If the server is unavailable, leave the validation section saying so.

## Keep it short

A long document loses its readers. Write the shortest one that lets an engineer new to the project
understand what the plant does, what the controller does, and what was left out. Anyone who needs
more can ask. Concretely:

- **Aim for one to two screens.** A simple actuator model needs about a page. If the draft is much
  longer, cut it before showing it.
- **Use tables, equations, and diagrams instead of prose.** Use a sentence only where a table
  can't say it. Each section opens with at most one or two sentences.
- **Don't repeat the code.** Give the behaviour and link to the source. Leave out implementation
  detail such as helper functions, struct layout, and the cycle callback's mechanics.
- **Don't explain CppModel itself.** Leave out how simulations, the workspace, or the input/output
  boundary work. Readers can follow the links.
- **Leave out the obvious.** Skip rows and sections that state nothing a reader couldn't guess,
  such as a boolean sensor that is "true when active".
- **When updating, keep to the same budget.** Replace outdated text instead of adding to it, and
  don't keep a change log in the document. Git history already has one.

## Structure

Include only the sections with something real to say. Sections 1 to 4 are usually enough:

1. **Overview**: two or three sentences. Say what the mechanism is, what the model is for
   (exercising the controller, not physical accuracy), and whether the simulation runs the plant
   alone or the controller with the plant as feedback.
2. **Interface**: one table with columns signal, direction (actuator or sensor), source, type or
   range, and meaning. Source is where the value comes from: the input document, the plant (as
   the input's fallback, overridable), or the controller. In a
   complete-system simulation list each cross-linked signal once, under the controller's name,
   and add plant rows only for signals the controller doesn't observe.
3. **Plant**: the per-cycle update laws in math (below), then one parameters table with columns
   name, default, unit, and source. Give the delta-per-cycle derivation as a single equation.
4. **Controller**: a state diagram (below). Add a short guards table only if the guards don't fit
   on the diagram's arrows. For a decoupled component, add one line naming the entry point and the
   vendor calls it replaced.
5. **Simplifications**: a bullet list of what was left out and why, one line each, in the
   customer's words where possible. Include this whenever something was left out. It is the hardest
   part to rebuild later.
6. **Validation**: one or two lines with the simulation name, its workspace link, and the latest
   result from the API. Link the simulation's or the execution's page, never a `/snapshots/`
   export, which expires after 7 days. If there were field experiments, add one line per plan with its status.
   If the simulation has verification rules (`cppmodel:verification`), add one table with columns
   requirement ID, rule, settings, and latest status with its margin. List the requirements that
   aren't verified by simulation too.
7. **Open questions**: a bullet list, only if there are any.

## Math: TeX in Markdown

Write equations as TeX. GitHub, GitLab, Gitea, and VS Code's Markdown preview all render it
(through MathJax or KaTeX): use `$...$` inline and `$$...$$` for display. The model works in cycles,
not seconds, so write discrete-time laws indexed by the cycle $k$ with period $T$
(`task_period_ms`):

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

Stay inside what both KaTeX and MathJax support. Use `cases`, `aligned`, `\frac`, `\text`,
`\mathrm`, `\le`/`\ge`, and `\lfloor\cdot\rfloor` for integer configuration types. Don't use
`\usepackage`, `\newcommand` across blocks, TikZ, or `align` outside `$$`. Write `\lt`/`\gt`
instead of a bare `<`/`>` next to letters, which some renderers read as HTML. Leave a blank line
around each `$$` block. Name every symbol after its first equation, and map it to its code
identifier in the parameters table.

Check where the document will be read before relying on math rendering. Bitbucket doesn't render
TeX: there, put each law in a fenced code block as plain text (`x[k+1] = min(x[k] + delta, x_max)`)
with the TeX underneath in a collapsed `<details>` block. Use math only where the content has an
equation. A threshold or a table says many things better than a formula does.

## Diagrams

Draw the controller's state machine as a Mermaid `stateDiagram-v2`, and the closed loop as a
`flowchart LR`. GitHub, GitLab, Gitea, and VS Code (with a Mermaid extension) render both. Label
the transitions with the same guard names the code uses. TikZ doesn't render in Markdown, so don't
use it.

## PDF, only if asked

If the user wants a PDF, check whether `pandoc` and a TeX engine (`xelatex` or `pdflatex`) are
installed. If they are, run `pandoc <doc>.md -o <doc>.pdf --pdf-engine=xelatex`. The `$...$` math
carries through as real LaTeX. Mermaid needs a filter such as `mermaid-filter`. Without one,
mention that the diagrams won't appear. Don't install a TeX distribution without asking, because
it is large.

## Publishing to the workspace

A licensed (`w#####`) workspace can host documentation: per documentation project, one set of
Markdown pages plus images (PNG, JPEG, GIF, SVG, WebP), PDFs, text, CSV and JSON (at most 5000
files and 300 MB), readable by
everyone in the workspace. Free-workspace accounts get `403`; then the document stays in the
repository only. The `cppmodel` MCP server's tools (see `cppmodel:simulations` for the account
check before the first call):

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
  project holds more than this one document (several models, other people's pages), upload with
  `merge: true` and only the files that changed, and `remove` only files you put there. A full
  replace is right only when the upload is the complete set, such as the repository's whole `docs/`
  folder.
- **Upload the files as they are in the repository**, with their relative paths, and every image
  the pages link to. Relative links between pages and to images keep working; links to source
  files outside the uploaded set (`../models/ConveyorModel.c`) don't, so leave them as they are.
  Anything other than the types above comes back in `skipped`: tell the user.
- **Navigation**: without `nav`, it follows the folder tree (`index.md` first, titles from each
  page's first `#` heading), and a merge keeps the current one and appends new pages. Pass `nav`
  (`[{title, path | url | children}]`, as `get_docs` shows it) only when the user wants an order of
  their own.
- **Rendering**: the viewer renders navigation, admonitions, tables, highlighted code and TeX math.
  Mermaid isn't among them, so check with the user whether diagrams showing as source is
  acceptable there.
- **`siteUrl` is temporary**, and a browser opens it only as `<siteUrl>?access_token=<token>`. Give
  the user `siteUrl` and say it needs their token; never append a token to it yourself, and never
  put `siteUrl` into anything meant to last (the document itself, a README, a commit).
- **`delete_docs` can't be undone** and removes the set for everyone: only when the user explicitly
  asks, after saying what will be lost.

## Finish

Tell the user where the document is, whether it is still a draft, and which sections were left as
open questions. If it was an update, say which sections changed. If it was published, give the project name,
the files uploaded and any `skipped`, and `siteUrl`. Mention, in one line, that any
part can be expanded if they want more detail. Expand only the part they ask about, and keep the
rest short.
