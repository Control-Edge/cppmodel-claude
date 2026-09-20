# CppModel Tools

A Claude Code plugin for projects using the CppModel libraries. Seven skills:

- **`cppmodel:decouple-component`** - decouple a vendor-coupled controller component (one that
  calls a vendor BSW/RTOS/HAL API directly) so it can run in isolation under CppModel.
- **`cppmodel:plant-model`** - build a minimal plant model for a new physical mechanism (asks
  about its sensors, actuators, and timing/velocity first) and scaffold a starter simulation file.
- **`cppmodel:simulation-testing`** - write, extend, build, run, and debug a CppModel-based
  simulation test, in either C or C++ (whichever the project already uses, or is chosen via
  `cppmodel:language`), including using the API trace to pinpoint why a test failed instead of
  guessing from stdout.
- **`cppmodel:simulations`** - query the Workspace API: list your simulations, fetch a
  simulation's latest results, or list its execution history.
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

## Install

```
/plugin marketplace add git@github.com:Control-Edge/cppmodel-claude.git
/plugin install cppmodel@cppmodel-tools
```

## Requirements

A CppModel license, and a `.env` file at your project root:

```
CPPMODEL_USERNAME=...
CPPMODEL_PASSWORD=...
CPPMODEL_CLIENT_ID=cppmodel-frontend
```

Installing the plugin is free and requires nothing further; using it against real data still
requires a valid CppModel account.

## What's inside

- `plugins/cppmodel/skills/decouple-component/SKILL.md` - the vendor-decoupling skill
- `plugins/cppmodel/skills/plant-model/SKILL.md` - the model-authoring skill
- `plugins/cppmodel/skills/simulation-testing/SKILL.md` - the write/debug-tests skill
- `plugins/cppmodel/skills/simulations/SKILL.md` - the query skill
- `plugins/cppmodel/skills/language/SKILL.md` - the C vs C++ decision skill
- `plugins/cppmodel/skills/update-dependencies/SKILL.md` - the SDK update skill
- `plugins/cppmodel/skills/ci-pipeline/SKILL.md` - the CI pipeline skill (GitHub Actions, GitLab
  CI, Bitbucket Pipelines, Gitea Actions)
- `plugins/cppmodel/scripts/cppmodel-fetch.sh` / `.ps1` - the CLI the query skill wraps (bash and
  PowerShell versions, list / get / executions, with automatic per-workspace routing)
- `plugins/cppmodel/scripts/templates/install-cppmodel.sh` / `.ps1` - templates the
  `cppmodel:ci-pipeline` and `cppmodel:update-dependencies` skills copy into a project (not run
  from the plugin itself) to detect platform/compiler and fetch the CppModel SDK into
  `dependencies/`
- `plugins/cppmodel/api/workspace-api.yaml` - the full Workspace API spec
