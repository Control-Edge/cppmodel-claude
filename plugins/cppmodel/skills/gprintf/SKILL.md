---
name: cppmodel:gprintf
description: Add gprintf, CppModel's "visual printf" (SDK 0.18.0+), to code that is already running - a bench program, a hardware-in-the-loop rig, a real-time loop, a script, a long computation - so chosen values show up as live time graphs in the workspace's Streams view, with no simulation loop, step size or end time. Covers C (gprintf.h), C++ (cppmodel::gprintf, cppmodel::Stream), Python and Node (gprintf, Stream), naming the stream, flushing, turning it off for production and CI, and when a simulation output is the better tool. Use when asked to graph, plot live, watch or log values from running code to the workspace, to "swap a printf for a graph", or about gprintf, gp_init or streams.
---

> **The workspace is integral to CppModel.** gprintf sends its samples to the workspace, and the
> graphs are viewed there. Never work around it with a local log file or a plotting script of your
> own. If the workspace can't be reached, fix the login with the user (`cppmodel:simulations`, "The
> workspace is part of the loop").

## What it is, and when to use it

gprintf turns a value in code that is **already running** into a live time graph in the workspace.
A call such as `gprintf("motor.speed", speed)` records a timestamped sample of a named signal, and
a background thread sends the samples to the workspace. The program never waits for the network.

Use it for code that **isn't a CppModel simulation**:

- a bench or test-rig program driving real hardware;
- the real controller running on a PC target, a soft-PLC, or in a hardware-in-the-loop setup;
- a script or tool: a calibration routine, a data-processing job, a long optimisation;
- a quick look at what a loop is doing, where a `printf` would scroll by.

**Not for a simulation.** In a CppModel simulation, record values as outputs
(`CppModel_setOutput*` / `outputs["..."]`, `cppmodel:simulation-testing`). Outputs are part of the
execution: they are stamped with simulation time, checked by verification rules, compared across
runs with `what_changed`, and exported as charts. A gprintf call inside a simulation goes to a
separate stream on wall-clock time, linked to none of that. Don't add gprintf to a simulation to
debug it either; its execution already holds the trace (`cppmodel:simulation-testing`,
"Debugging a failure").

**Viewing is in the web UI only.** The workspace's **Streams** view lists the streams with each
one's latest run and whether it is live, and draws a stream's run live while the program runs. The
`cppmodel` MCP server has no tool that reads streams: you can't fetch or look at a stream's
samples for the user. Give them the link the program prints (below), or the workspace's Streams
view (`get_workspace` gives the UI URL), and ask them to describe or screenshot what they see if
you need it. If a question needs the values analysed, a simulation, or measured data recorded as
an execution (`cppmodel:simulations`, `submit_execution`), is the tool for it.

## 1. Check the SDK

gprintf needs SDK 0.18.0+. Check the project's vendored headers: `gprintf.h` next to `CModel.h`,
or `cm_stream_log` in `cppmodel.h`; for Python `cppmodel.gprintf`, for Node `gprintf` exported by
the `cppmodel` package. If it isn't there, offer `cppmodel:update-dependencies` and stop until it's
updated. Don't write a stand-in that posts values some other way.

It also needs a workspace that accepts streams. When it doesn't, the program prints a message
(`CppModel stream: ...`) and carries on without sending.

## 2. Choose the signals and the stream name with the user

- **Signals**: the few values the user wants to watch, with names in the project's style.
  Dotted names group well (`motor.speed`, `motor.current`). Put the unit in the name when it isn't
  obvious (`tank.level [m]`). A signal is just its name: no declaration, and each one may log at its
  own rate.
- **Stream name**: one stream per process, and each time the program runs is one run of it.
  Name it after what runs (`motor-bench`, `hil-rig-2`) with `gp_init` / `Stream`, before the first
  `gprintf`. The naming rules are a simulation's. Without a name, the first `gprintf` starts an
  unnamed stream, which the workspace files under the executable's or script's name: fine for a
  quick look, but name it once it is worth finding again.
- **Where to call it**: where the value is computed, at the rate it changes. Samples are buffered
  (by default the last 10000 per signal) and sent every 500 ms, so a fast loop that logs every
  iteration drops its oldest samples between sends when it outruns the buffer. Log at the rate the
  user needs to see, or raise the buffer (step 4).

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
  `cppmodel:simulation-testing`'s "Requirements" describes before the first run.
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
  simulation does.

## 4. Settings

Environment variables, read when the stream starts; values passed in code win:

| Variable | Default | Meaning |
| --- | --- | --- |
| `CPPMODEL_STREAM` | on | `off` (or `0`, `false`, `no`) discards every sample without signing in |
| `CPPMODEL_STREAM_FLUSH_MS` | 500 | how often samples are sent |
| `CPPMODEL_STREAM_BUFFER` | 10000 | samples kept per signal between sends |
| `CPPMODEL_STREAM_EXIT_TIMEOUT_MS` | 5000 | how long a flush or the exit keeps trying |

## 5. Run it and show the user where to look

Build and run the program as the project normally does. On the first successful send it prints the
stream and run, and a `UI: https://...` link to the stream's live page: give that link to the user.
Otherwise point them at the workspace's **Streams** view. If nothing appears, read the
`CppModel stream: ...` lines on stderr: no sign-in, a workspace without streams, or
`CPPMODEL_STREAM=off` set somewhere.

## 6. Production code and CI

- **Controller code that ships to a target** shouldn't depend on the CppModel library. Keep gprintf
  calls in the PC-side program, the rig or the harness. If the user wants them in shared controller
  source, put them behind the project's own build switch or logging macro so the target build
  compiles them out, and follow `cppmodel:coding-standard` for that code.
- **CI**: a program with gprintf that runs in CI without credentials should set
  `CPPMODEL_STREAM=off`, unless the user wants CI runs streamed. With `CI` set, a missing sign-in
  fails at once instead of waiting for the browser prompt; the program still carries on.
- gprintf is a viewing aid, not a test. For pass/fail over time, the code belongs in a simulation
  with verification rules (`cppmodel:simulation-testing`, `cppmodel:verification`).
