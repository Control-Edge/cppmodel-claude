# CppModel Tools

A Claude Code plugin for projects using the CppModel libraries. Twelve skills:

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
  execution history, or fetch one past execution.
- **`cppmodel:simulation-inputs`** - run a simulation with specific inputs (time series) and
  parameters (constants) posted through the Workspace API, without editing or rebuilding it. Finds
  the exact names the simulation reads, validates and posts the document right before the run (the
  next execution consumes it), and confirms from the execution record that the values were really
  used.
- **`cppmodel:parameter-sweep`** - runs a simulation over a grid or list of parameter values and
  input profiles with `cppmodel-tool sweep` (SDK 0.6.3+), verifying after every run that the
  posted values were applied, then reports the
  pass/fail map, where the boundary lies, and the metrics you care about.
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
- **`cppmodel:language`** - decides C vs C++ for a new plant model or simulation file: checks a
  stored per-project preference (`.claude/cppmodel.local.json`) first, otherwise detects the
  project's existing convention or asks, and can remember the answer so it isn't asked again. Used
  automatically by `cppmodel:plant-model` and `cppmodel:simulation-testing`.
- **`cppmodel:update-dependencies`** - downloads the latest CppModel SDK from
  `download.cppmodel.com` for the right platform/toolchain, diffs its headers against what's
  already vendored to catch interface changes (`RunCyclic`'s signature especially), fixes
  unambiguous call-site breakage and asks about anything unclear, then rebuilds to verify before
  offering to sync the version pinned in CI/docs.
- **`cppmodel:ci-pipeline`** - generates or extends a CI pipeline (GitHub Actions, GitLab CI,
  Bitbucket Pipelines, or Gitea Actions) that builds the project and runs its simulations, asking
  which provider, platform(s), and compiler(s) to target from what CppModel actually publishes a
  prebuilt SDK for. Installs the plugin's `install-cppmodel.sh`/`.ps1` templates into the project
  if it doesn't already have an equivalent script, so CI and local dependency fetches share the
  same logic regardless of provider.
- **`cppmodel:setup-environment`** - first-time machine setup: detects the OS, architecture,
  installed compilers/toolchains, build tools, and OpenSSL/zlib, compares them with the SDK builds
  CppModel actually publishes, and lets you pick an installed match, install a supported compiler,
  or use the closest match. For an unsupported OS/compiler it drafts a request to
  support@cedge.se listing what is available for your OS. Then installs what's missing plus the
  SDK and verifies a build.

## Install

```
/plugin marketplace add git@github.com:Control-Edge/cppmodel-claude.git
/plugin install cppmodel@cppmodel-tools
```

The plugin connects Claude Code to the `cppmodel` MCP server at `https://mcp.cppmodel.com/mcp`.
Run `/mcp` once and authenticate it with your CppModel account.

## Requirements

A CppModel account (free or licensed). Running simulations also needs a `.env` file at your
project root:

```
CPPMODEL_USERNAME=...
CPPMODEL_PASSWORD=...
```

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
- `plugins/cppmodel/skills/update-dependencies/SKILL.md` - the SDK update skill
- `plugins/cppmodel/skills/ci-pipeline/SKILL.md` - the CI pipeline skill (GitHub Actions, GitLab
  CI, Bitbucket Pipelines, Gitea Actions)
- `plugins/cppmodel/skills/setup-environment/SKILL.md` - the environment setup skill
- `plugins/cppmodel/scripts/detect-environment.sh` / `.ps1` - read-only probes the setup skill runs
  to report OS, compilers, tools, libraries, and the currently published SDK builds
- `plugins/cppmodel/skills/simulation-inputs/SKILL.md` - the inputs/parameters skill
- `plugins/cppmodel/skills/parameter-sweep/SKILL.md` - the sweep skill
- `plugins/cppmodel/skills/experiment-design/SKILL.md` - the field experiment-plan skill, with
  `plan-format.md`, the plan format reconciliation reads
- `plugins/cppmodel/skills/experiment-reconcile/SKILL.md` - the field-log reconciliation skill,
  with `reconciliation-format.md`, the format of its findings
- `plugins/cppmodel/scripts/templates/install-cppmodel.sh` / `.ps1` - templates that detect
  platform/compiler and fetch the CppModel SDK into `dependencies/`. The `cppmodel:ci-pipeline`
  and `cppmodel:update-dependencies` skills copy them into a project; `cppmodel:setup-environment`
  also runs them directly with an explicit compiler for first-time setup
- `plugins/cppmodel/.mcp.json` - the `cppmodel` MCP server the query and inputs skills use
