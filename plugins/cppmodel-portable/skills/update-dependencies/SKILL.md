---
name: update-dependencies
description: "Download and install the latest CppModel libraries into the project's dependencies folder, detecting the right platform build, diffing the public headers against what's already there to catch interface changes (RunCyclic's signature especially), migrating the build files when moving from an SDK before 0.8 (per-compiler static libraries) to 0.8+ (one shared library, find_package(cppmodel)), fixing unambiguous call-site breakage and asking about anything unclear, then rebuilding to verify before offering to sync the version pinned in CI/docs. Use when asked to update, upgrade, or refresh the CppModel dependencies/libraries to the latest version."
---

## Reading notes

- This is the cppmodel plugin's `update-dependencies` skill. It was written for Claude Code, but applies to any
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

## What's being updated

Projects using CppModel typically vendor a single prebuilt SDK drop from
`https://download.cppmodel.com/` into a `dependencies/` folder - don't assume the exact folder
name, confirm it against this project's build files. From SDK 0.8 the build finds it with
`find_package(cppmodel)` and a `CMAKE_PREFIX_PATH` pointing at it; before 0.8, it was
`include_directories`/`link_directories` and bare library names (`CppModelBase`, `ixwebsocket`,
`crypto ssl z`). This folder is normally **not** tracked by git (check `.gitignore`) - there is no
source-control safety net for it, which is why step 4 below matters.

What a drop contains changed in 0.8:

- **0.8+**: one self-contained shared library per OS and architecture, the same for every
  compiler: `lib/` (`libcppmodel.so.1`, `libcppmodel.dylib`, or Windows' import library
  `cppmodel.lib`), `bin/` (`cppmodel.dll` on Windows, and the prebuilt `cppmodel-tool`),
  `include/cppmodel/` (`cppmodel.h` C API, `cppmodel.hpp` header-only C++ API, `CModel.h`, and the
  old header names, which include `cppmodel.hpp`), `include/nlohmann/`, `lib/cmake/cppmodel/` (the
  CMake package), `share/cppmodel/example/`, `licenses/`.
- **Before 0.8**: static libraries per OS and compiler (`libCppModelBase.a`, ...), the engine's
  headers, third-party headers (`httplib.h`, `jwt-cpp`, `ixwebsocket`), and `cppmodel-tool` as
  source in `share/cppmodel/tools/`.

No authentication is needed to download from `download.cppmodel.com` itself - it's a plain static
file index. (`CPPMODEL_USERNAME`/`CPPMODEL_PASSWORD`, see `cppmodel:simulation-testing`, are for running
simulations against the Workspace API, not for fetching the SDK - free and licensed accounts download the same archives.)

## 1. Determine the current version

From 0.8, the installed version is recorded in the drop:
`set(PACKAGE_VERSION "<version>")` in `dependencies/lib/cmake/cppmodel/cppmodelConfigVersion.cmake`.
Before 0.8 there's no version marker inside `dependencies/` - if that file is missing, it's an SDK
before 0.8, and don't try to infer which one from the contents.

Either way, also check wherever the project *pins* a version to download it, most commonly a CI
config (e.g. grep `bitbucket-pipelines.yml`, `.github/workflows/*.yml`, `.gitlab-ci.yml`,
`Jenkinsfile`, or any setup script for a `download.cppmodel.com/CppModel-<version>-...` URL) or a
committed install script (see step 1a - a `VERSION`/`-Version` default other than `latest`, if it
sets one), and a `find_package(cppmodel <version>)` minimum in `CMakeLists.txt`. Also check docs
(`README.md` and similar) for a stated version number. If these disagree with each other - which
happens, e.g. a CI pin that's been bumped without updating the README, or vice versa - tell the
user about the mismatch rather than silently trusting one of them.

## 1a. Check for an existing install script - prefer it over hand-rolling detection/download

Grep the project for `download.cppmodel.com` in a shell script (common names:
`install-cppmodel.sh`/`.ps1`, `scripts/update-cppmodel.sh`/`.ps1` - see `cppmodel:ci-pipeline` step 2,
which installs `<plugin>/scripts/templates/install-cppmodel.sh`/`.ps1` into projects
that don't already have one). If the project has one **that handles 0.8+ archive names**, it
already encapsulates steps 2-3 and 5 below - **use it** instead of re-deriving that logic:

```
DEPS_DIR=<step-5 staging dir> VERSION=<step-3 version> ./path/to/install-cppmodel.sh
```

```powershell
& .\path\to\install-cppmodel.ps1 -DepsDir <step-5 staging dir> -Version <step-3 version>
```

A script written for SDKs before 0.8 builds per-compiler names (`Linux-x86_64-gcc12`,
`Windows-UCRT64`, a `COMPILER`/`-Platform` argument) that 0.8+ doesn't publish, so it can't fetch
the new SDK. When moving to 0.8+, offer to replace it with the plugin's current template (same
path, same `DEPS_DIR`/`VERSION` interface; `COMPILER` and `-Platform` are accepted and ignored, so
a MinGW `-Platform UCRT64` fetches the `Windows-x64` archive). It's a committed file other people and CI run, so confirm first, and
note its callers for step 9.

Point `DEPS_DIR`/`-DepsDir` at the step-4/5 **staging** location, not the real `dependencies/` -
this skill still needs the old copy intact for the step-6 diff before swapping anything in. Skip
straight to step 4 once this has staged a copy. Only fall through to steps 2-3-5 by hand if no
usable script exists - and in that case, once the update is verified (step 8), consider offering to
add the plugin's template script to the project so future updates and CI (`cppmodel:ci-pipeline`)
can reuse it too.

## 2. Determine the target platform - detect, don't hardcode

Skip this step if step 1a already found and used an install script - it does this detection
itself. From 0.8 an archive is per OS and architecture only - `Linux-x86_64`, `Linux-aarch64`,
`Windows-x64`, `Windows-ARM64`, `macOS-universal` as of writing (check the live listing, step 3).
Determine the OS and architecture the project builds for: a build directory's `CMakeCache.txt`
(`CMAKE_SYSTEM_PROCESSOR`, `CMAKE_GENERATOR_PLATFORM`), a toolchain file, else the machine itself.
The OS you're running on may differ from the OS a CI pipeline builds for; keep those separate (see
step 9).

The compiler no longer selects the archive, but it must be a supported one: GCC or Clang on Linux
(glibc 2.28+), MSVC or clang-cl on Windows, Apple Clang on macOS 11+. MSYS2's MinGW toolchains
(UCRT64, CLANG64, MINGW64) are supported on Windows x64 and use the same `Windows-x64` archive as
MSVC: only C crosses the DLL boundary and the DLL carries its own CRT, and GNU ld and lld link
`cppmodel.lib` like any import library. A project that builds with MinGW (`CMakeCache.txt`'s
`CMAKE_CXX_COMPILER` under `msys64`, or a CI job using `msys2/setup-msys2`) keeps its toolchain;
only the archive name changes (`Windows-UCRT64`/`Windows-CLANG64` become `Windows-x64`). MinGW on
Windows ARM64 isn't supported.

## 3. Find the latest version for that platform

Needed either way - even when step 1a's script handles the download itself, it still needs a
concrete `VERSION` passed in (or `latest`, if deliberately tracking it). Fetch
`https://download.cppmodel.com/` - it's a plain directory listing (`<a href="...">` entries
with filename, date, size). Parse it for entries matching `CppModel-<version>-<platform>.<ext>` for
the platform from step 2, and pick the highest semver version present. `CppModel-latest-<platform>.<ext>`
aliases also exist, but prefer parsing actual version-numbered filenames - that gives a concrete
version string to report and reuse later (step 9).

Filename shapes have changed across releases (parse fresh, don't hardcode a pattern):
`CppModel-0.4.2-Linux.tar.gz` (no suffix), `CppModel-0.7.2-Linux-x86_64-gcc12.tar.gz` and
`CppModel-0.7.2-Windows-UCRT64.zip` (per compiler, before 0.8), `CppModel-0.8.0-Linux-x86_64.tar.gz`,
`CppModel-0.8.0-Windows-x64.zip`, `CppModel-0.8.0-macOS-universal.tar.gz` (per OS and architecture).

If the current version from step 1 is already the latest available for this platform, say so and
stop - there's nothing to update.

## 4. Back up before touching anything

Since `dependencies/` normally isn't in git, copy it aside first (e.g. to
`dependencies.bak-<old-version>/`, or somewhere in the scratch/temp area) so the old headers stay
available for diffing in step 6 and the whole update can be rolled back if the rebuild in step 8
fails.

## 5. Download and stage - don't overwrite in place yet

Skip this step if step 1a already staged a copy via the project's install script. Otherwise:
download the chosen archive to a temp location and extract it into a **separate staging
directory**, not directly over `dependencies/`. Archives hold one top-level
`CppModel-<version>-<platform>/` folder; stage its contents (e.g. `tar -xzf <file> -C <staging>
--strip-components=1`, or unzip and move the folder's contents up) so the result has the layout
described above. On Windows, extract the `.zip` with PowerShell's `Expand-Archive` or
`C:\Windows\System32\tar.exe`; Git Bash's and MSYS2's `tar` can't read it.

## 6. Diff the interface headers before swapping in

Compare `include/cppmodel/` between the step-4 backup and the step-5 staged copy. From 0.8 the
interface is three headers: `cppmodel.hpp` (the C++ classes: `Simulation`, `PersistentSimulation`,
`Model`, `SimulationInputs`/`Outputs`, `Parameters`, `JsonInput`, `ExpectValue`), `CModel.h` (the
`CppModel_*` functions and `CMODEL_*` macros), and `cppmodel.h` (the C API both are built on;
additive changes only within a major `CM_API_VERSION`). Before 0.8 the corresponding headers were
`Model.h`, `Simulation.h` and `CModel.h`. Pay particular attention to:

- **`RunCyclic`'s signature** - the method plant models and any class deriving from
  `cppmodel::Model`/`cppmodel::Simulation` (or the old `CppModelBase::` names) override, and the C
  per-cycle callback's. Past releases have changed this parameter's type (0.6: `double` became
  `unsigned long long simulationTime_ms`); it's the single most common source of breakage after an
  update for projects like this one.
- Any other changed function/method signature, struct field, or typedef shape - not just renames.

For everything that changed, grep the project for real call sites/overrides so the full blast
radius is known before editing anything:

- `RunCyclic` overrides: wherever plant models live (e.g. a `models/` folder - see
  `cppmodel:plant-model`) and any file directly subclassing `Model` or `Simulation`.
- Direct API usage: `CppModel_getInput*`/`CppModel_setOutput*`/`CppModel_getParameter*` (C) or
  `inputs[...]`/`outputs[...]`/`parameters[...]`/`GetParameter`/`GetSafe` and other `Simulation`
  members (C++) - across the simulations folder and any project-local base class they're built on.

## 6a. Moving from an SDK before 0.8

Crossing 0.8 changes the build files as well as the headers. Read the staged
`share/cppmodel/example/CMakeLists.txt` for the reference shape, then make these changes, showing
the diff before writing:

- **CMake**: remove `include_directories(dependencies/include)`, `link_directories(dependencies/lib)`,
  `add_definitions(-DCPPHTTPLIB_OPENSSL_SUPPORT)`/`target_compile_definitions(... CPPHTTPLIB_*)`,
  `find_package(OpenSSL)`/`ZLIB`, and `CppModelBase`, `CppModelLib`, `ixwebsocket`, `crypto`, `ssl`,
  `z`, `crypt32`, `ws2_32` from `target_link_libraries`. Add, once:
  `list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_SOURCE_DIR}/dependencies")` and
  `find_package(cppmodel 0.8 REQUIRED)` (CMake 3.21+); and per simulation:
  `target_link_libraries(<target> PRIVATE cppmodel::cppmodel)` and
  `cppmodel_deploy_runtime(<target>)`, which copies the shared library next to the executable and
  sets its rpath. A C-only target no longer needs `LINKER_LANGUAGE CXX`.
- **C++ standard**: `cppmodel.hpp` needs C++17. Raise `CMAKE_CXX_STANDARD` if it's lower.
- **Other build systems** (Makefile, ...): link `cppmodel` (Windows: `cppmodel.lib`), add
  `include/cppmodel` and `include` to the include path, ship the library next to the executable,
  and on Linux link with `-Wl,-rpath,'$ORIGIN'` (`$$ORIGIN` in a Makefile), on macOS with
  `-Wl,-rpath,@executable_path`.

Source code usually compiles unchanged: `Simulation.h`, `Model.h`, `CppModelLib.h` and the other
old headers include `cppmodel.hpp`, and `CppModelBase`/`CppModelLib` are namespace aliases of
`cppmodel`. What does need edits (0.8.0 release notes):

- `inputs[...]` and `GetSafe()` return the value (`nlohmann::json`), not a reference. Assigning to
  the result still compiles but does nothing - grep for `inputs[` on the left of `=`.
- `outputs[...]` and `parameters[...]` return proxies that write through to the library. `.get<T>()`,
  assignment, conversion to numbers and comparisons work as before; a `nlohmann::json&` bound to
  one doesn't compile and needs a copy (`nlohmann::json value = parameters["x"];`).
- Inputs and outputs are numbers (stored as `double`); assigning a string or object to an output
  throws `cppmodel::Error`. Parameters keep their JSON type.
- A custom `DataAdapter` derives from `cppmodel::DataAdapter`.
- `ApiConnector`, `AuthHandler` (except `AuthHandler::RequireNonInteractive`), `Tools`,
  `SimulationController` and the other engine classes are gone. Code using `Tools::Workspace`
  should move to `cppmodel-tool` (prebuilt in `bin/`) or, for interactive work, the `cppmodel` MCP
  server. Ask before rewriting such a utility.
- `Simulate()` throws `cppmodel::Error` when `stepSize_ms` is 0 (it used to loop forever).
- `CPPMODEL_OFFLINE` is gone; its replacement is `CPPMODEL_DISCARD_RESULTS`. If a script, CI file or
  test property sets either, point it out - the plugin's skills never run without submitting.
- From 0.9.1, `CPPMODEL_DISCARD_RESULTS` and `runOffline` (C++), `set_run_offline` (C API) and the
  bindings' `offline` option make the run fail, and so does a run that can't log in to or reach the
  workspace (it prints a `CppModel workspace:` line; it used to print `Running offline.` and pass).
  Tests that relied on running offline, such as a `ctest` `ENVIRONMENT
  "CPPMODEL_DISCARD_RESULTS=true"` property, now fail: point them out and ask before removing the
  setting, since those runs will then be submitted. Without credentials, the browser sign-in now
  waits 60 seconds (`CPPMODEL_LOGIN_TIMEOUT`; `0` fails at once) instead of indefinitely.
- 0.10.0 (release notes):
  - **`CPPMODEL_DISCARD_RESULTS` is removed.** Where it's still set, it no longer fails the run:
    the run submits like any other. Point out every place that sets it, and ask before removing
    it.
  - **New local-run options:** binaries take `--inputs <file>` and `--results <file>` (see
    `cppmodel:simulations`' "Local runs"). The library reads them from the command line itself.
    So a project whose own `main()` already parses an `--inputs` or `--results` option, or a Python
    script using `argparse` with those names, now has them read twice. Grep for them and point out
    any clash.
  - **`cppmodel-tool sweep` now passes `--inputs`.** It refuses a binary built with an older SDK
    (the first run isn't `applied`), so rebuild the simulations together with the update.
    `summary.json` rows have `executionId` instead of `index`: update any CI step or script that
    reads `index`.
  - **`JsonInput` (C++) is deprecated** in favour of `--inputs`. It still works; mention it, don't
    rewrite.
- 0.11.0 (release notes): nothing existing changes, so nothing needs fixing.
  - **Verification rules** (`cppmodel::verify`, `CppModel_rule*`, `cm_rule_*`) and **requirement
    coverage** (`VerifyRequirement`) are new. After the update, if the project's simulations set
    `CppModel.StepResult` from hand-written timing checks or trace requirements through a helper of
    their own, mention `cppmodel:verification` once. Don't rewrite them.
  - A simulation that calls `VerifyRequirement` writes `cppmodel-requirements.json` into its
    working directory. Offer to add it to `.gitignore`.
  - The Python and Node packages need the 0.11.0 library for these.
  - `CPPMODEL_BUILD_TOOL` (CMake, on by default) only matters to projects that build the library
    from source.
- 0.14.0 (release notes):
  - **Scenarios are now input profiles.** The 0.13.0 steps API names are removed, with no aliases.
    It's a straight rename (step 7 does it without asking), headers only; the library's exports and
    the C API are unchanged. Grep for `Scenario`/`scenario` and rename:
    `CppModelScenario_ts` → `CppModelInputProfile_ts`, `CMODEL_SCENARIO` → `CMODEL_INPUT_PROFILE`,
    `CMODEL_STEP_SCENARIO` → `CMODEL_STEP_INPUT_PROFILE`, `CppModel_runScenario` →
    `CppModel_runInputProfile`, `CppModel_scenarioDuration` → `CppModel_inputProfileDuration`,
    `CppModel_scenarioSteps` → `CppModel_inputProfileSteps`, `CppModel_loadScenarioInputs` →
    `CppModel_loadInputProfile`, `CppModelStep_ts::scenario` → `::profile` (designated or
    positional initializers that name it), `cppmodel::Scenario` → `cppmodel::InputProfile`,
    `RunScenario` → `RunInputProfile`, `LoadScenarioInputs` → `LoadInputProfile`. Python/Node:
    `InputProfile`, `run_input_profile`/`runInputProfile`, `load_input_profile`/`loadInputProfile`.
    Leave the project's own identifiers and comments that say "scenario" alone unless asked.
  - **A request rejected with HTTP 401 is retried once with a new token**, by the library and
    every `cppmodel-tool` command (not with `CPPMODEL_ACCESS_TOKEN`, which can't be refreshed), and
    **a submit is tried three times over about 10 s** on a connection failure or 5xx. Nothing to
    fix; a script that re-ran a simulation after a 401 can drop that.

## 7. Fix call sites: mechanical changes now, ambiguous ones stop and ask

- If a change is unambiguous - a straight rename, a widening conversion, a type swap whose new
  meaning is obvious from the new header (naming, inline comments, the archive's
  `share/cppmodel/example/`), or one of step 6a's listed edits - update every affected call site
  directly.
- If a change's new semantics aren't clear from the header alone - e.g. `RunCyclic`'s time
  parameter changes type and it isn't obvious whether it still means the same thing (same units,
  same "elapsed since start" vs. "delta since last cycle" meaning, etc.) - **stop and ask**,
  showing the old and new signatures side by side and what was found in the project. Guessing
  wrong here silently changes timing-dependent assertions in safety-test simulations without
  anyone noticing, which is worse than pausing to ask.
- Report every file touched, and every file identified as needing a fix, either way.

## 8. Swap in and verify by building

Once the staged headers/libs are confirmed compatible (or already patched per steps 6a-7), replace
`dependencies/` with the staged copy - keep the step-4 backup until the next check passes. When
crossing 0.8, delete the old build directory and configure afresh (its cache still holds the old
include/link settings). Rebuild and run the test suite the same way `cppmodel:simulation-testing`
does - `ctest` executes the same simulation binaries, so it needs the same credentials sourced
first (see that skill's "Requirements" section; if `.env` is missing, stop and tell the user rather
than reporting a false regression):

```
cmake --build build
set -a && source .env && set +a && ctest --test-dir build --output-on-failure
```

Passing isn't the only check. Every simulation's history already holds its executions from before
the update, so for each one compare the new execution with the last one before the swap
(`list_executions` for the ids, `what_changed` with both, then `get_execution` for both with the
same `signals`; see `cppmodel:simulations`' "Comparing runs"). `what_changed` should show the code
changed and no parameter differences, apart from any the new SDK adds or retires. Outputs that changed with no input or
code change in between are a behaviour change in the SDK; report them even if every test passed.
A new `CppModel.BinaryFingerprint` is expected (the executables were relinked) and isn't one.

The fingerprint hashes the executable only, not the shared library next to it. A normal rebuild
relinks every simulation against the new SDK, so the fingerprint changes; but if the library
alone were swapped beside an unchanged executable, its runs would share a fingerprint with the old
SDK's. Always rebuild after an update rather than copying a library in by hand.

If the build or tests fail after the best-effort fix, don't report success - state exactly what
failed, leave the backup in place, and ask before attempting further changes. Once the build and
tests pass, it's safe to remove the backup.

`cppmodel-tool` ships prebuilt in `dependencies/bin/` from 0.8, so it updates with the SDK. A
project or CI job that built it from `dependencies/share/cppmodel/tools` (into e.g.
`build/cppmodel-tool/`) should use `dependencies/bin/cppmodel-tool` instead (step 9). Don't run it
here: sweeps and runs with posted inputs go through the MCP server.

## 9. Offer to keep CI and docs in sync

After a successful local update, report the version change (`<old> → <new>`) and **offer, don't
silently do**, to also:

- Bump the pinned download URL(s) or `VERSION` found in step 1 (e.g. in CI config) to the new
  version, keeping the platform the pin already used, which may differ from the one detected for
  local use in step 2. When crossing 0.8, the suffix changes too: `Linux-<arch>-<compiler>` becomes
  `Linux-<arch>`, `Windows-MSVC`/`Windows-CLANGCL` become `Windows-x64`, `macOS-arm64` becomes
  `macOS-universal`, and `Windows-UCRT64`/`Windows-CLANG64` become `Windows-x64` too (the MinGW
  job keeps its MSYS2 toolchain).
- When crossing 0.8, also clean up the pipeline: drop the OpenSSL/zlib/vcpkg install steps, the
  `COMPILER=`/`-Platform` arguments to the install script, and any step that builds
  `cppmodel-tool` from `share/cppmodel/tools` (use `dependencies/bin/cppmodel-tool`). An MSYS2 job
  keeps its MSYS2 setup but no longer needs OpenSSL/zlib packages. `cppmodel:ci-pipeline` step 5 shows the 0.8
  shape.
- Update any version number mentioned in project docs (e.g. `README.md`) and the
  `find_package(cppmodel <version>)` minimum, if the project relies on something new.

Treat these as shared/CI-affecting edits and confirm before making them, the same as any other
change to CI configuration or committed documentation would be confirmed.

If the project has no CI pipeline yet to sync a pin into, that's a separate task - see
`cppmodel:ci-pipeline`, which builds one from scratch rather than updating an existing pin.
