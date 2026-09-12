# CppModel Tools

A Claude Code plugin for projects using the CppModel libraries. Three skills:

- **`cppmodel:plant-model`** - build a minimal plant model for a new physical mechanism (asks
  about its sensors, actuators, and timing/velocity first) and scaffold a starter simulation file.
- **`cppmodel:simulation-testing`** - write, extend, build, run, and debug a CModel-based
  simulation test (`CMODEL_CYCLIC`/`CMODEL_SIMULATE`), including using the API trace to pinpoint
  why a test failed instead of guessing from stdout.
- **`cppmodel:simulations`** - query the Workspace API: list your simulations, fetch a
  simulation's latest results, or list its execution history.

## Install

```
/plugin marketplace add <this-repo>
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

- `plugins/cppmodel/skills/plant-model/SKILL.md` - the model-authoring skill
- `plugins/cppmodel/skills/simulation-testing/SKILL.md` - the write/debug-tests skill
- `plugins/cppmodel/skills/simulations/SKILL.md` - the query skill
- `plugins/cppmodel/scripts/cppmodel-fetch.sh` / `.ps1` - the CLI the query skill wraps (bash and
  PowerShell versions, list / get / executions, with automatic per-workspace routing)
- `plugins/cppmodel/api/workspace-api.yaml` - the full Workspace API spec
