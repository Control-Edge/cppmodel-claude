---
name: cppmodel:simulations
description: Query CppModel Workspace API results - list simulations, fetch the latest results for one, or list its execution history. Use when asked about CppModel simulation results, executions, or the Workspace API, in a project that uses the CppModel libraries.
---

## Requirements

A valid CppModel license, and `.env` at the project root with:

```
CPPMODEL_USERNAME=...
CPPMODEL_PASSWORD=...
CPPMODEL_CLIENT_ID=cppmodel-frontend
```

If `.env` is missing these, tell the user and stop - do not guess or fabricate credentials.

## Finding the workspace

CppModel is multi-tenant: each customer's API lives at `https://{workspace}.cppmodel.com/api`, not a shared host. `${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh` derives the workspace automatically from the access token's `groups` claim and only needs `--workspace <id>` if that token belongs to more than one workspace (the script will say so explicitly if that happens).

If no `.env` exists yet and the user has no token, the fastest way to learn the workspace with zero auth is to build and run any of their CppModel simulation binaries once - it prints a line like `UI: https://w20011.cppmodel.com/simulations/<name>` on stdout.

## Usage

On Linux/macOS/MSYS2-bash, use `cppmodel-fetch.sh`; on a plain Windows PowerShell prompt, use
`cppmodel-fetch.ps1` - same arguments, same output, pick whichever matches the shell actually
running:

```
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh                              # list simulations
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh "<simulation name>"          # latest results for one
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh executions "<simulation name>"  # its execution history
${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.sh --workspace <id> ...         # override auto-detected workspace
```

```powershell
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1"
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" "<simulation name>"
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" executions "<simulation name>"
& "${CLAUDE_PLUGIN_ROOT}/scripts/cppmodel-fetch.ps1" --workspace <id> ...
```

The simulation name is exactly the string passed to `CMODEL_SIMULATE(...)` in the source - it may contain spaces, quote it.

Each command prints pretty-printed JSON. The full API contract (endpoints, response shapes, auth scheme) is documented in `${CLAUDE_PLUGIN_ROOT}/api/workspace-api.yaml` - read it if a request needs something the script doesn't already cover.

## Interpreting input/output signals in the results

Whether a signal in the returned time series is a `CppModel_getInput*` (input) or
`CppModel_setOutput*` (output) tells you it's crossing into or out of whichever component that
simulation wraps - not necessarily "actuator" or "sensor" specifically. See
`cppmodel:simulation-testing`'s "which side is being simulated" note: for a plant simulation,
inputs are actuator commands and outputs are sensor readings; for a controller simulation, inputs
are sensor readings and outputs are actuator commands.
