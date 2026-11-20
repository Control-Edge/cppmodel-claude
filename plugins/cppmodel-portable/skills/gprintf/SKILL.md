---
name: gprintf
description: "Print any value from running C, C++, Python or Node code (a bench program, a HIL rig, a real-time loop, a script, an algorithm being debugged) and get it back as a chart image (PNG) to look at, a table (CSV), the series (JSON), and a live graph for the user in the workspace. gprintf (SDK 0.18.0+) is CppModel's \"visual printf\": one call per value, no simulation loop. It replaces printf debugging, dumping values to a CSV or log file, and plotting scripts. Covers adding the calls, naming the stream, reading it back via the cppmodel MCP server (list_streams, get_stream, export_signals with `stream`), and turning it off for production and CI. Use when asked to print, log, dump, trace, plot, chart or watch values from code that isn't a CppModel simulation; when you need to see how a value evolves over time in such code; to export a program's values to PNG, CSV or JSON; to look at or export a stream; or about gprintf, gp_init or streams."
---

## Reading notes

- This is the cppmodel plugin's `gprintf` skill. It was written for Claude Code, but applies to any
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

> **The workspace is integral to CppModel.** gprintf sends its samples to the workspace, and they
> are read back from there, by you through the `cppmodel` MCP server and by the user in the web UI.
> Never work around it with a local log file, a CSV your code writes, or a plotting script of your
> own. If the workspace can't be reached, fix the login with the user (`cppmodel:simulations`, "The
> workspace is part of the loop").

## What it is: print to PNG, CSV, JSON and a live graph

gprintf is `printf` for values you want to **see over time**. One call,
`gprintf("motor.speed", speed)`, records a timestamped sample of a named signal; a background thread
sends the samples to the workspace without the program ever waiting for the network. Each process
is one **stream**, and each time it runs is one **run** of that stream.

What you get back, without writing any parser or plotting code:

| You want | You get it from |
|---|---|
| to **look** at the values: shape, overshoot, oscillation, lag, a glitch, drift | `export_signals {stream, format: "png"}` - a chart image you examine |
| the **numbers**: values at given times, a metric to compute | `export_signals {stream, format: "csv"}` - a `time_ms` column plus one per signal |
| the **series** themselves | `export_signals {stream, format: "json"}`, or `get_stream` with `summary: false` |
| which signals arrived, their ranges, whether the run finished | `get_stream` (summarized by default) |
| the user to watch it **live** while it runs | the stream's page (`uiUrl` from `list_streams`/`get_stream`, also printed by the program) |
| a link to **share** that outlives the next run | the export's `uiUrl` (`<workspace>/snapshots/<id>`, 7 days) |

So when you are tempted to add `printf`/`std::cout`/`print` lines and read them back, write values
to a CSV file, or plot with matplotlib, use gprintf instead: the calls are one line each, the data
lands where both you and the user can see it, and the program's stdout stays readable.

### When to use it, and when a simulation is the tool

Use gprintf in code that **isn't a CppModel simulation**:

- a bench or test-rig program driving real hardware;
- the real controller running on a PC target, a soft-PLC, or in a hardware-in-the-loop setup;
- a script or tool: a calibration routine, a data-processing job, a long optimisation;
- an algorithm, a unit-test binary or any loop whose numbers you (or the user) need to see over
  time to understand or debug it, where a `printf` would scroll by.

**Not in a simulation.** In a CppModel simulation, record values as outputs
(`CppModel_setOutput*` / `outputs["..."]`, `cppmodel:simulation-testing`). Outputs are part of the
execution: stamped with simulation time, checked by verification rules, compared across runs with
`what_changed`, and exported as charts. A gprintf call inside a simulation goes to a separate
stream on wall-clock time, linked to none of that. Don't add gprintf to a simulation to debug it
either; its execution already holds the trace (`cppmodel:simulations`, "Looking at signals").

**Not a test.** gprintf shows values; it doesn't judge them. For pass/fail over time, the logic
belongs in a simulation with verification rules (`cppmodel:simulation-testing`,
`cppmodel:verification`). Measured data the user wants kept and compared run by run belongs in an
execution (`submit_execution`, `cppmodel:simulations`). A stream keeps only its current run.

## 1. Check the SDK

gprintf needs SDK 0.18.0+. Check the project's vendored headers: `gprintf.h` next to `CModel.h`,
or `cm_stream_log` in `cppmodel.h`; for Python `cppmodel.gprintf`, for Node `gprintf` exported by
the `cppmodel` package. If it isn't there, offer `cppmodel:update-dependencies` and stop until it's
updated. Don't write a stand-in that posts values some other way.

It also needs a workspace that accepts streams. When it doesn't, the program prints a message
(`CppModel stream: ...`) and carries on without sending. Reading streams back needs a `cppmodel`
MCP server with `list_streams`, `get_stream` and `stream` on `export_signals` (step 6).

## 2. Choose the signals and the stream name

When the user asked for it, agree on these with them. When you add gprintf for your own debugging,
pick them yourself and say what you added.

- **Signals**: the few values worth watching, with names in the project's style. Dotted names group
  well (`motor.speed`, `motor.current`). Put the unit in the name when it isn't obvious
  (`tank.level [m]`). A signal is just its name: no declaration, and each one may log at its own
  rate. Up to 8 go on one exported chart, so a handful is plenty.
- **Stream name**: one stream per process. Name it after what runs (`motor-bench`, `hil-rig-2`,
  `kalman-debug`) with `gp_init` / `Stream`, before the first `gprintf`. The naming rules are a
  simulation's. Without a name, the first `gprintf` starts an unnamed stream, which the workspace
  files under the executable's or script's name: fine for a quick look, but name it so you can find
  it with `list_streams`.
- **Where to call it**: where the value is computed, at the rate it changes. Samples are buffered
  (by default the last 10000 per signal) and sent every 500 ms, so a fast loop that logs every
  iteration drops its oldest samples between sends when it outruns the buffer (`get_stream` reports
  them in `dropped`). Log at the rate needed, or raise the buffer (step 4).
- **Time is wall-clock.** Every sample's x is milliseconds since the run started; there is no way to
  pass your own x. For a computation where the iteration matters more than the time (a solver, an
  optimiser), also log the iteration count as a signal (`solver.iter`) so the chart and CSV can be
  read against it.

## 3. Add the calls

Follow the file's language. Values are numbers; integers and bools convert to double.

**C** (`#include <gprintf.h>`, header-only over the SDK's shared library; link `cppmodel` as for a
simulation, e.g. `target_link_libraries(<target> PRIVATE cppmodel::cppmodel)`):

```c
#include <gprintf.h>

int main(void)
{
    gp_init("motor-bench");              /* optional: names the stream; before the first gprintf */
    for (;;)
    {
        double speed = read_speed();
        gprintf("motor.speed", speed);   /* a timestamped sample; never waits for the network */
        gprintf("motor.enabled", enabled);
        /* ... */
    }
    gp_flush();                          /* optional: waits until everything so far was sent */
    gp_shutdown();                       /* optional: done at exit anyway */
    return 0;
}
```

`gp_init_with(name, flushInterval_ms, bufferSamples)` sets the flush interval and buffer size too
(0 keeps the default). `gp_init` and `gp_flush` return 1, or 0 with the reason printed.

**C++** (`cppmodel.hpp`):

```cpp
#include <cppmodel.hpp>

int main()
{
    cppmodel::Stream stream("motor-bench");     // optional: names the stream; closes it when it goes out of scope
    while (running)
    {
        cppmodel::gprintf("motor.speed", speed);  // any arithmetic type; never throws
    }
    stream.Flush();                              // optional: false when some samples weren't sent
}
```

`cppmodel::Stream(name, flushInterval_ms, bufferSamples)` takes the same options. It throws
`cppmodel::Error` when the stream already started under another name (for instance a `gprintf` ran
first) or was closed, so create it at the start of `main`, not in a loop.

**Python**:

```python
import cppmodel

with cppmodel.Stream("motor-bench"):         # optional: names the stream
    while running:
        cppmodel.gprintf("motor.speed", speed)
```

`Stream(name="", flush_interval_ms=0, buffer_samples=0)`, with `flush()` (False when some samples
weren't sent) and `close()`. The stream records the main script as the program that ran, with its
git commit.

**Node**:

```js
const { gprintf, Stream } = require('cppmodel');

const stream = new Stream('motor-bench');    // optional: names the stream
gprintf('motor.speed', speed);
// stream.flush(); stream.close();
```

`new Stream(name, { flushIntervalMs, bufferSamples })`; `flush()` returns false when some samples
weren't sent.

What to know whichever the language:

- **Sign-in is the same as for a simulation**: the saved login, `CPPMODEL_USERNAME` /
  `CPPMODEL_PASSWORD` (e.g. from the project's `.env`), `CPPMODEL_ACCESS_TOKEN`, or the browser
  prompt. It happens in the background; the program doesn't wait for it. Check credentials as
  `cppmodel:simulation-testing`'s "Requirements" describes before the first run. The account the
  program sends as should be the one the MCP server reads as, or `list_streams` won't show the
  stream (try `scope: "team"`).
- **What's left is sent at exit.** The headers and bindings register this for a normal exit. A
  process that is killed, crashes or calls `_exit` loses the samples since the last send; call
  `gp_flush()` / `Flush()` / `flush()` at points where the data must not be lost.
- **Don't let a flush decide the exit code.** A flush reports failure (and prints why) whenever
  samples weren't sent, including when `CPPMODEL_STREAM=off`. A program that exits non-zero on a
  failed flush fails every CI job that turns streams off. Treat the result as information.
- **Failures never stop the program.** When the workspace can't be reached, samples are kept
  (within the buffer) and sent again; when it refuses streams or the sign-in fails, a message is
  printed and samples are discarded from then on.
- The run records the program's fingerprint and, inside a git repository, `CppModel.GitHash`, as a
  simulation does (`get_stream` returns them as `parameters`).

## 4. Settings

Environment variables, read when the stream starts; values passed in code win:

| Variable | Default | Meaning |
| --- | --- | --- |
| `CPPMODEL_STREAM` | on | `off` (or `0`, `false`, `no`) discards every sample without signing in |
| `CPPMODEL_STREAM_FLUSH_MS` | 500 | how often samples are sent |
| `CPPMODEL_STREAM_BUFFER` | 10000 | samples kept per signal between sends |
| `CPPMODEL_STREAM_EXIT_TIMEOUT_MS` | 5000 | how long a flush or the exit keeps trying |

## 5. Run it

Build and run the program as the project normally does. On the first successful send it prints the
stream and run, and a `UI: https://...` link to the stream's live page: give that link to the user.
If nothing appears, read the `CppModel stream: ...` lines on stderr: no sign-in, a workspace
without streams, or `CPPMODEL_STREAM=off` set somewhere. Don't parse the program's stdout for the
values; read them back from the workspace (step 6).

## 6. Read it back: `list_streams`, `get_stream`, `export_signals`

All through the `cppmodel` MCP server. Before its first call in a conversation, tell the user the
account and workspace it is signed in as (`cppmodel:simulations`, "The tools").

1. **Find the stream: `list_streams`.** The most recently active first, each with its `name`,
   current `run`, `status`, `startedAt` (UTC), `samples` and `uiUrl`. By default only the streams
   whose current run this account sent; `scope: "team"` lists everyone's, with `owner`.
   - `live`: the program is still sending. What you read is what has arrived so far.
   - `finished`: the final batch arrived (normal exit or explicit close); the run is complete.
   - `stale`: no batch for a while (`staleSeconds`) and no final one: the program hangs, was
     killed, or crashed. What arrived is still readable.
   For a program that runs to completion, wait for `finished` before drawing conclusions. Check
   `startedAt`/`run` to be sure it is the run you just started, not the one before it.
2. **See what's in it: `get_stream {stream}`.** Each signal summarized (point count, time span,
   first/last, min/max), plus `parameters` (`CppModel.GitHash`, fingerprint), `dropped` per signal
   and `uiUrl`. Use the exact labels it shows for the export. `missingSignals` names any you asked
   for with `signals` that the run doesn't have. `summary: false` returns the series `{label, x,
   y}`; over 256 KiB it is refused, so ask for fewer `signals` or export a CSV with a time range.
3. **Look at it or get the numbers: `export_signals {stream, format, signals, ...}`.** The same
   tool and options as for an execution (`cppmodel:simulations`, "Looking at signals"): up to 8
   signals, `from`/`to` (ms since the run started), per-signal `scale`/`yOffset`/`xOffset`,
   `width`/`height`, `format` `png`/`csv`/`json`/`none`. Give `stream` **instead of**
   `simulation`, and leave out `execution_id`, `verifiers` and any signal's
   `executionId`/`simulationId`: a stream has one run and no rules, and its export draws only that
   run.

   ```
   export_signals {stream: "motor-bench", format: "png",
     signals: ["motor.speed", "motor.setpoint", {label: "motor.enabled", scale: 100}],
     from: 2000, to: 8000}
   ```

   A stream's signals are drawn as **samples joined by straight lines**, not held as steps like a
   simulation's, and the CSV has a row per sample time. Pick `png` to judge a shape, `csv` to
   compute from the values, `json` for the series.
4. **Give the user the links.** The export's `uiUrl` (`<workspace>/snapshots/<id>`) shows the same
   chart with PNG and CSV downloads; `streamUiUrl` (or the stream's `uiUrl`) is the live page.
   Don't fetch either with curl or a script: they need the user's login, and the tools return the
   PNG and CSV themselves. `get_export` reads an export again, or one the user pastes.

**A restart replaces the run.** The stream keeps only its current run, so the next start of the
program overwrites what `get_stream` returns and what the live page shows. An export is a **copy**
of the run taken when it was created: it survives restarts (and the stream being deleted) for its 7
days. So:

- export the run you care about **before** you run the program again;
- to compare before and after a change, export the "before" run, change and re-run, export the
  "after" run, and compare the two (two PNGs, or two CSVs). One export can't overlay two stream
  runs; if runs must be overlaid, judged and kept, the code belongs in a simulation, or the
  measurements in executions;
- in anything meant to last (documentation, a commit message, a ticket), an export link is
  temporary: note its `expiresAt` date, or keep the PNG file the client saved
  (`cppmodel:documentation`).

## 7. Clean up, production code and CI

- **gprintf you added for your own debugging** comes out again once the question is answered,
  unless the user wants to keep it. Say what you added and offer to remove or keep it.
- **Controller code that ships to a target** shouldn't depend on the CppModel library. Keep gprintf
  calls in the PC-side program, the rig or the harness. If the user wants them in shared controller
  source, put them behind the project's own build switch or logging macro so the target build
  compiles them out, and follow `cppmodel:coding-standard` for that code.
- **CI**: a program with gprintf that runs in CI without credentials should set
  `CPPMODEL_STREAM=off`, unless the user wants CI runs streamed. With `CI` set, a missing sign-in
  fails at once instead of waiting for the browser prompt; the program still carries on.
