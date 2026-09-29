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

(`CPPMODEL_CLIENT_ID` is optional; the plugin's scripts default it to `cppmodel-frontend`.)

If `.env` is missing these, tell the user and stop - do not guess or fabricate credentials.

## Finding the workspace

CppModel is multi-tenant: the API lives at `https://{workspace}.cppmodel.com/api`, where `{workspace}` depends on the account type:

- **Licensed accounts** get a dedicated workspace with a `w<number>` subdomain, e.g. `w20011.cppmodel.com`.
- **Free accounts** share a single workspace, `free-workspace.cppmodel.com`. The API and scripts behave the same there. Results are still per user, which is why the list command asks for `scope=user`.

`${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh` derives the workspace automatically from the access token's `groups` claim (`w<number>` for licensed, `free-workspace` for free accounts). It only needs `--workspace <id>` if that token belongs to more than one workspace; the script will say so explicitly if that happens. Don't assume a `w<number>` workspace when reading the user's setup or explaining a URL.

If no `.env` exists yet and the user has no token, the fastest way to learn the workspace with zero auth is to build and run any of their CppModel simulation binaries once - it prints a line like `UI: https://w20011.cppmodel.com/simulations/<name>` (or `UI: https://free-workspace.cppmodel.com/...` for a free account) on stdout.

## Usage

On Linux/macOS/MSYS2-bash, use `cppmodel-fetch.sh`; on a plain Windows PowerShell prompt, use
`cppmodel-fetch.ps1` - same arguments, same output, pick whichever matches the shell actually
running:

```
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh                              # list simulations
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh "<simulation name>"          # latest results for one
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh executions "<simulation name>"  # its execution history
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh execution "<simulation name>" <execution id>  # one past execution's trace
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh inputs "<simulation name>"    # inputs/parameters its next run will use
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh set-inputs "<simulation name>" <file.json>  # replace them (see below)
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh --workspace <id> ...         # override auto-detected workspace
```

```powershell
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1"
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" "<simulation name>"
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" executions "<simulation name>"
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" execution "<simulation name>" <execution id>
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" inputs "<simulation name>"
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" set-inputs "<simulation name>" <file.json>
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" --workspace <id> ...
```

`inputs` returns the document waiting for the simulation's next execution; a 404 "No input data
found" means nothing is pending, which is normal. `set-inputs` posts one, and the next execution
consumes it. Don't call it directly from here. Use `cppmodel:simulation-inputs` for one scenario
or `cppmodel:parameter-sweep` for many; both validate the document and verify it was applied.

The simulation name is exactly the string passed to `CMODEL_SIMULATE(...)` in the source - it may contain spaces, quote it.

Each command prints pretty-printed JSON. The full API contract (endpoints, response shapes, auth scheme) is documented in `${CLAUDE_PLUGIN_ROOT}/api/workspace-api.yaml` - read it if a request needs something the script doesn't already cover.

## Interpreting input/output signals in the results

A result (latest, or one execution by id) is one JSON document:

- `inputs`: a list of `{label, x, y}`, with every `CppModel_getInput*` the simulation read and
  the values it got (posted, or the fallback);
- `parameters`: every `CppModel_getParameter*` it read, name → value, plus the reserved
  `CppModel.SimulationTime`/`StepSize`, in seconds;
- `results`: a list of `{label, x, y}` output series, including `CppModel.StepResult`.

`x` is simulation time in ms. Series are change-compressed: `x` holds only the times the value
changed, plus the end time, so the value between two points is the earlier point's `y`.

Whether a signal is in `inputs` (a `CppModel_getInput*`) or in `results` (a
`CppModel_setOutput*`) tells you it's crossing into or out of whichever component that
simulation wraps - not necessarily "actuator" or "sensor" specifically. See
`cppmodel:simulation-testing`'s "which side is being simulated" note: for a plant simulation,
inputs are actuator commands and outputs are sensor readings; for a controller simulation, inputs
are sensor readings and outputs are actuator commands.
