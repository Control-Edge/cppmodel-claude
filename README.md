# CppModel Tools

A Claude Code plugin for projects using the CppModel libraries. Fifteen skills:

- **`cppmodel:decouple-component`** - decouple a vendor-coupled controller component (one that
  calls a vendor BSW/RTOS/HAL API directly) so it can run in isolation under CppModel.
- **`cppmodel:plant-model`** - build a minimal plant model for a new physical mechanism (asks
  about its sensors, actuators, and timing/velocity first) and scaffold a starter simulation file.
- **`cppmodel:simulation-testing`** - write, extend, build, run, and debug a CppModel-based
  simulation test, in either C or C++ (whichever the project already uses, or is chosen via
  `cppmodel:language`), including using the API trace to pinpoint why a test failed instead of
  guessing from stdout.
- **`cppmodel:simulations`** - query the Workspace API through the plugin's `cppmodel` MCP server
  (`mcp.cppmodel.com`): list your simulations, fetch a simulation's latest results, list its
  execution history, fetch one past execution, or fetch all the runs of one build (e.g. a whole
  sweep) by its `CppModel.BinaryFingerprint`.
- **`cppmodel:simulation-inputs`** - run a simulation with specific inputs (time series) and
  parameters (constants) without editing or rebuilding it. Finds the exact names the simulation
  reads, validates the document, and passes it to the binary with `--inputs` (SDK 0.10.0+; older
  SDKs get it posted right before the run). It can explore values with local runs first. It then
  confirms from the recorded execution that the values were really used.
- **`cppmodel:parameter-sweep`** - runs a simulation over a grid or list of parameter values and
  input profiles: a run of the binary with that run's document per run (`--inputs`, or `set_inputs`
  before SDK 0.10.0), and one `get_binary_runs` call that checks every run used its values. A
  coarse exploratory pass can run locally. Then it reports the
  pass/fail map, where the boundary lies, and the metrics you care about. Nothing is built besides
  the simulation. Points worth keeping become `ctest` tests that run with `--inputs`.
- **`cppmodel:experiment-design`** - designs a field data-collection plan for a real machine,
  aimed at the behaviour the plant model is least sure of. Every run carries the trace the current
  model predicts, computed by a `planned-<plan-id>` simulation that stays out of `ctest`/CI until
  the plan proves realistic or the customer adopts it. Shows the machine/model understanding and
  the predicted graphs in a widget to confirm or correct, then issues a frozen `plan.json` (format:
  `skills/experiment-design/plan-format.md`) for the operator to follow.
- **`cppmodel:experiment-reconcile`** - takes the field logs back from a plan: identifies each
  planned run in the unannotated logs, infers what was actually done against what was asked,
  re-simulates what was actually done, and shows predicted vs actual on the same plots against the
  plan's tolerances. Then proposes a minimal plant-model refinement on the planned path, checks it
  against the same logs, and recommends promoting, planning again, or re-tuning the controller.
- **`cppmodel:verification`** - turns a controller's requirements into the SDK's verification
  rules (`Always`, `Response`, `Settle`, `Mode`, `Oscillation`, `Wear`, `Rate`, `Energy`,
  `Percent`, SDK 0.11.0+) and requirement coverage (`VerifyRequirement`). It confirms the
  requirement-to-rule mapping with you before writing code, proves each rule can fail, and reports
  each rule's outcome and margin from the recorded execution. It then builds a coverage matrix from
  `cppmodel-requirements.json`: covered, gaps, unknown IDs, and what isn't verifiable by simulation.
- **`cppmodel:coding-standard`** - when controller (production) code is written or changed, offers
  MISRA C/C++ or the project's own standard. MISRA is licensed per user, so it works from your own
  copy of the rules (a path to your PDF or rule-texts file), never from general knowledge. It never
  copies the rule texts anywhere, runs your checker if the project has one, and remembers the
  choice in `.claude/cppmodel.local.json`.
- **`cppmodel:documentation`** - a short Markdown document (one to two screens) for a plant model
  and its controller: interface table, per-cycle update laws in TeX math (`$...$`/`$$...$$`),
  parameters, the controller's state machine (Mermaid), the simplifications made and why, and
  validation results from the workspace. It starts as a draft from your own initial description,
  is left alone while the solution changes, and is reshaped to match the code once the plant and
  controller are settled. More detail only on request. Answer "never" and it is stored in
  `.claude/cppmodel.local.json`.
- **`cppmodel:language`** - decides C vs C++ for a new plant model or simulation file: checks a
  stored per-project preference (`.claude/cppmodel.local.json`) first, otherwise detects the
  project's existing convention or asks, and can remember the answer so it isn't asked again. Used
  automatically by `cppmodel:plant-model` and `cppmodel:simulation-testing`.
- **`cppmodel:update-dependencies`** - downloads the latest CppModel SDK from
  `download.cppmodel.com` for the right platform, diffs its headers against what's already
  vendored to catch interface changes (`RunCyclic`'s signature especially), migrates the build
  files when moving a project from an SDK before 0.8 to the 0.8 shared library
  (`find_package(cppmodel)`), fixes unambiguous call-site breakage and asks about anything
  unclear, then rebuilds to verify before offering to sync the version pinned in CI/docs.
- **`cppmodel:ci-pipeline`** - generates or extends a CI pipeline (GitHub Actions, GitLab CI,
  Bitbucket Pipelines, or Gitea Actions) that builds the project and runs its simulations, asking
  which provider, platform(s), and compiler(s) to target from what CppModel actually publishes a
  prebuilt SDK for. Installs the plugin's `install-cppmodel.sh`/`.ps1` templates into the project
  if it doesn't already have an equivalent script, so CI and local dependency fetches share the
  same logic regardless of provider. Each behaviour is its own simulation and `ctest` test; value
  variants and sweep points run as `ctest` tests with `--inputs`. The pipeline needs nothing
  besides the SDK.
- **`cppmodel:setup-environment`** - first-time machine setup: detects the OS, architecture, C
  library, installed compilers/toolchains and build tools, compares them with the SDK builds
  CppModel actually publishes (one per OS and architecture from SDK 0.8), and lets you pick an
  installed supported compiler or install one. For an unsupported platform or compiler (such as
  MinGW on Windows ARM64) it drafts a request to support@cedge.se listing what is available for your OS. Then
  installs what's missing plus the SDK and verifies a build.

## Install

```
/plugin marketplace add git@github.com:Control-Edge/cppmodel-claude.git
/plugin install cppmodel@cppmodel-tools
```

The plugin connects Claude Code to the `cppmodel` MCP server at `https://mcp.cppmodel.com/mcp`.
Run `/mcp` once and authenticate it with your CppModel account.

### Other agents

`plugins/cppmodel-portable` is the same plugin as an [Agent Plugins](https://agent-plugins.org)
package (Agent Skills plus the `cppmodel` MCP server) and a Gemini CLI extension:

| Agent | Install |
|---|---|
| OpenAI Codex | `codex plugin marketplace add Control-Edge/cppmodel-claude`, then install `cppmodel` from `/plugins` |
| GitHub Copilot CLI | `copilot plugin marketplace add Control-Edge/cppmodel-claude`, then `copilot plugin install cppmodel@cppmodel-tools` |
| Cursor | add `https://github.com/Control-Edge/cppmodel-claude` as a team marketplace (it reads `.cursor-plugin/marketplace.json`), or copy `plugins/cppmodel-portable` to `~/.cursor/plugins/local/cppmodel` |
| Gemini CLI | clone this repository, then `gemini extensions install <clone>/plugins/cppmodel-portable` (Gemini installs only a repository whose root is the extension) |

Then sign in to the `cppmodel` MCP server the way that agent does it, with your CppModel account.

Don't edit `plugins/cppmodel-portable` or the `marketplace.json` files under `.agents/`,
`.github/plugin/` and `.cursor-plugin/`: they are generated from `plugins/cppmodel` by
`python3 tools/build-portable-plugin.py`, which gives the skills Agent Skills-conformant names and
the same reading notes `get_guide` adds (below). Run it after changing the plugin, and
`python3 tools/build-portable-plugin.py --check` to see whether the committed output is current.

Other AI assistants get the same skills from that server without the plugin: its `get_guide` tool
reads them from this repository's `main` branch (cached for an hour) and serves them as guides,
with a `new-project` guide that puts them in order. So what's merged here reaches those clients
too. Keep the skills free of anything only Claude Code can follow, beyond what `get_guide`'s
reading notes translate (`cppmodel:<name>` skills, `${CLAUDE_PLUGIN_ROOT}` paths and links to a
skill's own files, `AskUserQuestion`, Artifacts, `/mcp`, `.claude/cppmodel.local.json`).

## Requirements

A CppModel account (free or licensed). Running simulations also needs a `.env` file at your
project root:

```
CPPMODEL_USERNAME=...
CPPMODEL_PASSWORD=...
```

Building simulations needs the CppModel SDK. From 0.8 it is one self-contained shared library per
OS and architecture (Linux x86_64/aarch64 with glibc 2.28+, Windows x64/ARM64, macOS 11+
universal), used with GCC or Clang, MSVC or clang-cl (on x64 also MSYS2's MinGW toolchains), or
Apple Clang. The skills set up 0.8+ projects with `find_package(cppmodel)`, and
`cppmodel:update-dependencies` moves older projects over.

Running simulations with posted inputs (`cppmodel:simulation-inputs`) and parameter sweeps
(`cppmodel:parameter-sweep`) also needs:

- a `cppmodel` MCP server whose `get_latest_result`, `get_execution` and `get_binary_runs` take the
  `expected` argument, which checks a run's recorded values against the posted document;
- CppModel SDK 0.7.2 or later, whose simulations print their `CppModel.BinaryFingerprint` when they
  finish. With 0.7.0 to 0.7.1 the skills read the fingerprint from the execution record instead,
  and before 0.7.0 there is none (`cppmodel:update-dependencies` updates the SDK).

Installing the plugin is free and requires nothing further; using it against real data still
requires a CppModel account. Free accounts use the shared `free-workspace.cppmodel.com` workspace
and licensed ones their dedicated `w<number>.cppmodel.com` workspace. The plugin picks the right
one from your login automatically, and every skill works the same with either.

## What's inside

- `plugins/cppmodel/skills/decouple-component/SKILL.md` - the vendor-decoupling skill
- `plugins/cppmodel/skills/plant-model/SKILL.md` - the model-authoring skill
- `plugins/cppmodel/skills/simulation-testing/SKILL.md` - the write/debug-tests skill
- `plugins/cppmodel/skills/simulations/SKILL.md` - the query skill
- `plugins/cppmodel/skills/language/SKILL.md` - the C vs C++ decision skill
- `plugins/cppmodel/skills/documentation/SKILL.md` - the plant/controller documentation skill
- `plugins/cppmodel/skills/update-dependencies/SKILL.md` - the SDK update skill
- `plugins/cppmodel/skills/ci-pipeline/SKILL.md` - the CI pipeline skill (GitHub Actions, GitLab
  CI, Bitbucket Pipelines, Gitea Actions)
- `plugins/cppmodel/skills/setup-environment/SKILL.md` - the environment setup skill
- `plugins/cppmodel/scripts/detect-environment.sh` / `.ps1` - read-only probes the setup skill runs
  to report OS, architecture, C library, compilers, tools, and the currently published SDK builds
- `plugins/cppmodel/skills/simulation-inputs/SKILL.md` - the inputs/parameters skill
- `plugins/cppmodel/skills/parameter-sweep/SKILL.md` - the sweep skill
- `plugins/cppmodel/skills/experiment-design/SKILL.md` - the field experiment-plan skill, with
  `plan-format.md`, the plan format reconciliation reads
- `plugins/cppmodel/skills/experiment-reconcile/SKILL.md` - the field-log reconciliation skill,
  with `reconciliation-format.md`, the format of its findings
- `plugins/cppmodel/scripts/templates/install-cppmodel.sh` / `.ps1` - templates that detect the OS
  and architecture and fetch the CppModel SDK (0.8+) into `dependencies/`. The
  `cppmodel:ci-pipeline` and `cppmodel:update-dependencies` skills copy them into a project;
  `cppmodel:setup-environment` also runs them directly for first-time setup
- `plugins/cppmodel/.mcp.json` - the `cppmodel` MCP server the query, inputs and sweep skills use
- `plugins/cppmodel-portable/` - generated: the plugin for Codex, Copilot, Cursor and Gemini CLI
  (see "Other agents")
- `tools/build-portable-plugin.py` - generates `plugins/cppmodel-portable` and the other agents'
  marketplace files
