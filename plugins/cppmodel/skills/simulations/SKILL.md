---
name: cppmodel:simulations
description: Query CppModel Workspace API results - list simulations, fetch the latest results for one, or list its execution history. Use when asked about CppModel simulation results, executions, or the Workspace API, in a project that uses the CppModel libraries.
---

## Requirements

A CppModel account (free or licensed - both work the same way here), and `.env` at the project root with:

```
CPPMODEL_USERNAME=...
CPPMODEL_PASSWORD=...
```

If `.env` is missing these, tell the user and stop - do not guess or fabricate credentials.

## The tool: cppmodel-tool

All Workspace API access goes through `cppmodel-tool`. It ships as source with the CppModel SDK
from 0.6.2 on, in `<sdk>/share/cppmodel/tools`, and builds with CMake into one program with the
same commands on Linux, macOS, and Windows. Find or build it once per project, in this order:

1. **Already built**: `build/cppmodel-tool/cppmodel-tool` (`.exe` on Windows), or `cppmodel-tool`
   on `PATH`. Use it.
2. **The project's SDK has the source**: `dependencies/share/cppmodel/tools` exists. Build it with
   the same toolchain as the project (on Windows with MSYS2, from that environment's shell):

   ```
   cmake -S dependencies/share/cppmodel/tools -B build/cppmodel-tool
   cmake --build build/cppmodel-tool
   ```

3. **The project's SDK is older than 0.6.2** (no `share/cppmodel/tools`). The tool only talks to
   the API, so it doesn't have to match the project's SDK version. Either offer
   `cppmodel:update-dependencies`, or build it from a separately downloaded current SDK without
   touching the project's `dependencies/`:

   ```
   DEPS_DIR=<scratch>/cppmodel-sdk COMPILER=<gcc12|...> bash "${CLAUDE_PLUGIN_ROOT}/scripts/templates/install-cppmodel.sh"
   cmake -S <scratch>/cppmodel-sdk/share/cppmodel/tools -B <scratch>/cppmodel-tool
   cmake --build <scratch>/cppmodel-tool
   ```

   (Windows: `install-cppmodel.ps1 -DepsDir ... -Platform ...`; see `cppmodel:setup-environment`
   for choosing the compiler.)

Never re-implement API calls with curl, a script, or an ad-hoc program instead. If the tool can't
be built, say why and stop.

The tool and the SDK cache the login in a `.cppmodeltoken` file in whatever directory they run
from. It holds a live access token. Check that the project's `.gitignore` covers
`.cppmodeltoken` (anywhere in the tree, not just the root), and offer to add it if not. Never
print, copy, or commit that file.

## Finding the workspace

CppModel is multi-tenant: the API lives at `https://{workspace}.cppmodel.com/api`, where `{workspace}` depends on the account type:

- **Licensed accounts** get a dedicated workspace with a `w<number>` subdomain, e.g. `w20011.cppmodel.com`.
- **Free accounts** share a single workspace, `free-workspace.cppmodel.com`. The API and tool behave the same there. Results are still per user, which is why listing only returns your own simulations.

`cppmodel-tool` picks the workspace from the account's login (`w<number>` for licensed,
`free-workspace` for free accounts). It needs `--workspace <id>`, or `CPPMODEL_WORKSPACE` in
`.env`, only if the account belongs to more than one workspace; it says so explicitly when that
happens. Don't assume a `w<number>` workspace when reading the user's setup or explaining a URL.

If no `.env` exists yet and the user has no token, the fastest way to learn the workspace with zero auth is to build and run any of their CppModel simulation binaries once - it prints a line like `UI: https://w20011.cppmodel.com/simulations/<name>` (or `UI: https://free-workspace.cppmodel.com/...` for a free account) on stdout.

## Usage

```
cppmodel-tool fetch                                            # list simulations
cppmodel-tool fetch "<simulation name>"                        # latest execution
cppmodel-tool fetch executions "<simulation name>"             # execution history, newest first
cppmodel-tool fetch execution "<simulation name>" <id>         # one past execution
cppmodel-tool fetch inputs "<simulation name>"                 # document pending for the next run
cppmodel-tool fetch set-inputs "<simulation name>" <file.json> # replace it (see below)
cppmodel-tool fetch delete "<simulation name>" --yes           # IRREVERSIBLE (see below)
cppmodel-tool fetch --workspace <id> --env <file> ...          # override workspace / .env
```

The tool loads the nearest `.env` in the current directory or a parent; run it from the project,
or pass `--env`. Output is pretty-printed JSON. On an API error it prints the server's
`{"code","message"}` body and exits 1. On a usage error (bad arguments, an invalid JSON file,
`delete` without `--yes`) it exits 2 without contacting the server.

`inputs` returns the document waiting for the simulation's next execution; a 404 "No input data
found" means nothing is pending, which is normal. `set-inputs` posts one, and the next execution
consumes it. Don't call it directly from here. Use `cppmodel:simulation-inputs` for one scenario
or `cppmodel:parameter-sweep` for many; both validate the document and verify it was applied.

`delete` removes the simulation with its entire execution history and any pending document, the
same as deleting it in the UI. It can't be undone and affects everyone who uses that simulation,
so only run it when the user explicitly asks, after telling them what will be lost.

The simulation name is exactly the string passed to `CMODEL_SIMULATE(...)` in the source - it may contain spaces, quote it.

The full API contract (endpoints, response shapes, auth scheme) is documented in `${CLAUDE_PLUGIN_ROOT}/api/workspace-api.yaml`.

## Interpreting input/output signals in the results

A result (latest, or one execution by id) is one JSON document:

- `inputs`: a list of `{label, x, y}`, with every posted input plus the fallback of each
  `CppModel_getInput*` the simulation read that wasn't posted;
- `parameters`: the same for parameters, name → value, plus the reserved
  `CppModel.SimulationTime`/`StepSize`, in seconds. A posted name appears even if the code never
  reads it;
- `results`: a list of `{label, x, y}` output series, including `CppModel.StepResult`.

`x` is simulation time in ms. Series are change-compressed: `x` holds only the times the value
changed, plus the end time, so the value between two points is the earlier point's `y`.

Whether a signal is in `inputs` (a `CppModel_getInput*`) or in `results` (a
`CppModel_setOutput*`) tells you it's crossing into or out of whichever component that
simulation wraps - not necessarily "actuator" or "sensor" specifically. See
`cppmodel:simulation-testing`'s "which side is being simulated" note: for a plant simulation,
inputs are actuator commands and outputs are sensor readings; for a controller simulation, inputs
are sensor readings and outputs are actuator commands.
