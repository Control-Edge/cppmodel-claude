---
name: cppmodel:simulations
description: Query CppModel Workspace API results - list simulations, fetch the latest results for one, list its execution history, or compare executions with each other. Every simulation run is submitted to the workspace, and its execution history is how runs are compared. Use when asked about CppModel simulation results, executions, how a run compares with an earlier one, or the Workspace API, in a project that uses the CppModel libraries.
---

## The tools: the `cppmodel` MCP server

All Workspace API access goes through the plugin's `cppmodel` MCP server
(`https://mcp.cppmodel.com/mcp`, declared in the plugin's `.mcp.json`). It signs in with the
user's CppModel account (free or licensed, both work the same) over OAuth, so querying results
needs no `.env` and no local tool.

The server's instructions name the account and workspace the session is signed in as. Before the
first `cppmodel` tool call in a conversation, tell the user that account and workspace in one short
line, so they can stop you if it's the wrong one (e.g. a free account when they expected their
licensed workspace).

If the `cppmodel` tools aren't available, or fail with an authentication error, tell the user to
authenticate the server with `/mcp` and stop. Never re-implement API calls with curl, a script, or
an ad-hoc program instead, and never search the project for result files in their place.

| Tool | Use |
|------|-----|
| `list_simulations` | list simulations with execution counts (`scope: "team"` for the whole team) |
| `get_latest_result` | the latest execution: inputs, parameters, results |
| `list_executions` | execution history, newest first, with id, time, status |
| `get_execution` | one past execution by id, same shape as `get_latest_result` |
| `get_pending_inputs` | the document waiting for the next execution (usually none) |
| `set_inputs` | post the next execution's inputs/parameters (see below) |
| `delete_simulation` | IRREVERSIBLE (see below) |
| `get_workspace` | which workspace the server is connected to, with UI and API URLs |

The simulation name is exactly the string passed to `CMODEL_SIMULATE(...)` in the source; case
and spaces matter. `list_simulations` shows the names.

Results can be large. Call `get_latest_result`/`get_execution` with `summary: true` first to see
which signals exist and their ranges, then with `signals: [...]` to fetch only the series you need.

`set_inputs` posts a document the next execution consumes. Don't call it directly from here. Use
`cppmodel:simulation-inputs` for one scenario or `cppmodel:parameter-sweep` for many; both verify
the document was applied.

`delete_simulation` removes the simulation with its entire execution history and any pending
document, the same as deleting it in the UI. It can't be undone and affects everyone who uses that
simulation, so only call it when the user explicitly asks, after telling them what will be lost.

## The workspace is part of the loop

Every simulation run is submitted to the workspace, and its execution history is the record of the
work: each execution keeps the inputs and parameters it read and every output series, retrievable
by id later. So:

- **Always run online.** Never set `CPPMODEL_OFFLINE`, never pass `runOffline`, and never run
  offline to save time or avoid the API. A run whose output says `Could not reach API. Running
  offline.` produced nothing anyone can look at or compare later. Treat it as a run that didn't
  happen: fix the cause (`.env`, network, login) and run again.
- **Compare runs through the history.** Before vs after a change, one scenario against another, a
  sweep against an earlier sweep: `list_executions` finds them, `get_execution` fetches each by id,
  with `signals` for just the series being compared. Don't rebuild an old version to regenerate
  results the history already holds. Don't write scripts, extra tests, or extra printf/logging to
  collect data an execution already recorded.
- **Look before running.** If the question is "what did the simulation do when...", check the
  history first. Run again only when no execution covers it (different code, inputs, or
  parameters).
- **Keep simulation names stable.** The history is per name. A renamed simulation starts with an
  empty history and can't be compared with the old one by id, so rename only on purpose and say
  that this is the consequence.
- **Name executions when reporting.** When reporting a result, give its execution id (and the UI
  link: `<uiUrl>/simulations/<name>`), so the user and later sessions can find exactly that run.
- **History isn't clutter.** Never delete a simulation to tidy up (see `delete_simulation` above).

## Workspaces

CppModel is multi-tenant: licensed accounts get a dedicated `w<number>.cppmodel.com` workspace,
free accounts share `free-workspace.cppmodel.com` (results are still per user). The MCP server
picks the workspace from the login; `get_workspace` says which one, and a simulation's page in the
UI is `<uiUrl>/simulations/<url-encoded name>`. Don't assume a `w<number>` workspace when
explaining a URL.

## Running simulations still needs `.env`

The MCP server only reads and posts data. The simulation binaries themselves (and `ctest`, and
`cppmodel-tool sweep`) log in with `.env` at the project root:

```
CPPMODEL_USERNAME=...
CPPMODEL_PASSWORD=...
```

If `.env` is missing these when something has to run, tell the user and stop - do not guess or
fabricate credentials. The binaries cache the login in a `.cppmodeltoken` file in the directory
they run from. It holds a live access token: check that the project's `.gitignore` covers
`.cppmodeltoken` (anywhere in the tree) and `.env`, and offer to add them if not. Never print,
copy, or commit either file.

## Interpreting input/output signals in the results

A result (latest, or one execution by id) is one JSON document:

- `inputs`: a list of `{label, x, y}`, with every posted input plus the fallback of each
  `CppModel_getInput*` the simulation read that wasn't posted;
- `parameters`: the same for parameters, name → value, plus the reserved
  `CppModel.SimulationTime`/`StepSize`, in seconds. A posted name appears even if the code never
  reads it;
- `results`: a list of `{label, x, y}` output series, including `CppModel.StepResult` (1 for a
  cycle that passed, 0 for one that failed).

`x` is simulation time in ms. Series are change-compressed: `x` holds only the times the value
changed, plus the end time, so the value between two points is the earlier point's `y`.

Whether a signal is in `inputs` (a `CppModel_getInput*`) or in `results` (a
`CppModel_setOutput*`) tells you it's crossing into or out of whichever component that
simulation wraps - not necessarily "actuator" or "sensor" specifically. See
`cppmodel:simulation-testing`'s "which side is being simulated" note: for a plant simulation,
inputs are actuator commands and outputs are sensor readings; for a controller simulation, inputs
are sensor readings and outputs are actuator commands.
