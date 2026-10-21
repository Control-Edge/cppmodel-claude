---
name: ci-pipeline
description: "Generate or extend a CI pipeline - GitHub Actions, GitLab CI, Bitbucket Pipelines, or Gitea Actions - that builds a CppModel project and runs its simulations/tests, asking which provider, platform(s), and compiler(s) (among those CppModel actually publishes a prebuilt SDK for) to target. Use when asked to set up, add, or fix CI for a project using the CppModel libraries."
---

## Reading notes

- This is the cppmodel plugin's `ci-pipeline` skill. It was written for Claude Code, but applies to any
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

## What this produces

A pipeline config for one of four providers - `.github/workflows/<name>.yml` (GitHub Actions),
`.gitlab-ci.yml` (GitLab CI), `bitbucket-pipelines.yml` (Bitbucket Pipelines), or
`.gitea/workflows/<name>.yml` (Gitea Actions) - that fetches the chosen platform/compiler's
toolchain, installs the matching CppModel SDK via a committed `install-cppmodel.sh`/`.ps1` script
(step 2 - reused or added, never re-derived inline), then configures, builds, and `ctest`-s with
CI secrets/variables for credentials. Jenkins and other providers aren't covered - say so rather
than improvising a `Jenkinsfile` from this skill's shape.

## 0. Determine the provider

Check for an existing config first: `.github/workflows/*.yml`, `.gitlab-ci.yml`,
`bitbucket-pipelines.yml`, `.gitea/workflows/*.yml`. If one exists, that's the provider to extend
- don't create a second pipeline for a different provider unless the user explicitly asks for one
in addition. If none exists, ask which provider to target; the git remote's host (`github.com`,
`gitlab.com`, `bitbucket.org`, or a self-hosted Gitea instance) is a reasonable default to suggest,
but confirm rather than assume - a GitHub-hosted repo can still be mirrored to and built by a
self-hosted Gitea/GitLab instance, and vice versa.

Everything in steps 1-3 and 5-6 below is provider-agnostic; step 4 (runners) and the pipeline-step
syntax are where providers actually diverge - jump to the matching provider subsection there.

## 1. Look for what already exists - don't start from a blank page

Before asking anything, check the project for:

- An existing SDK install/update script - grep the whole repo for `download.cppmodel.com` (common
  names seen in the wild: `install-cppmodel.sh`/`.ps1`, `scripts/update-cppmodel.sh`/`.ps1`). If
  found, reuse and extend it (step 2) rather than adding a second, competing one.
- The existing pipeline config found in step 0, if any - it's the single best reference for this
  project's real build steps (compiler, generator, extra install steps, submodules) - mirror its
  structure rather than guessing from `CMakeLists.txt` alone, and don't remove or replace it unless
  asked to.
- How `CMakeLists.txt` finds the SDK. A 0.8+ project uses `find_package(cppmodel)` and links
  `cppmodel::cppmodel`; the SDK's shared library carries OpenSSL, zlib and its other dependencies,
  so no job installs those. A project that still links `CppModelBase`/`crypto ssl z` was written
  for an SDK before 0.8, whose per-compiler archives CI would have to match: offer
  `cppmodel:update-dependencies` first, and only generate a pipeline for the old SDK if the user
  wants to stay on it.
- `.gitmodules` - if the project has git submodules, note their URL scheme. A private-host
  `ssh://`/`git@` submodule needs its own deploy key/credential set up for CI to check it out -
  every provider below handles this differently (see step 5), and hosted runners never have
  implicit access to a private internal git server.
- `.env.example` or the project's docs for the exact credential variable names expected (normally
  `CPPMODEL_USERNAME` and `CPPMODEL_PASSWORD` - see `cppmodel:simulation-testing`'s
  "Requirements" - but confirm against this project's own file rather than assuming; older
  projects may also set `CPPMODEL_CLIENT_ID`, which is harmless).
- Any other local-only step a human currently runs between checkout and a working build (unzipping
  vendored BSW archives, code generation, a `CMakePresets.json`) - the pipeline needs an equivalent
  step for each one it finds, not just checkout+fetch-deps+build+test.

## 2. Ensure a per-platform install script exists - reuse the plugin's template

The actual SDK download/extract logic (detect OS/arch/compiler, build the archive URL, download,
flatten, install into `dependencies/`) should live in a script committed to the project, not
inline in pipeline config - that's what makes it runnable identically by a developer locally and
by CI, on any provider, and this plugin ships ready-made templates instead of hand-deriving this
logic each time:

```
<plugin>/scripts/templates/install-cppmodel.sh   # Linux + macOS
<plugin>/scripts/templates/install-cppmodel.ps1  # Windows
```

If step 1 found an existing script that already does this, leave it as-is and just note its exact
name/location/argument shape for step 5 (every project seen so far names and parameterizes this
script slightly differently - don't assume it matches the template exactly). Otherwise, copy the
template(s) needed for the chosen platform(s) into the project (a `scripts/` folder is the
established convention - match one if it already exists) and adjust the default `dependencies/`
destination path only if this project's `CMakeLists.txt` points somewhere else. Both templates
already support `VERSION` (env var on the `.sh`, `-Version` param on the `.ps1`; default `latest`)
so the pipeline can pin an exact version - see step 3 - and pick the archive from the runner's OS
and architecture (`ARCH=`/`-Arch` overrides it). They install SDK 0.8 or later. An existing script
that passes `COMPILER=`/`-Platform` was written for older SDKs (see `cppmodel:update-dependencies`
step 1a). Mention to the user that this script was added and needs to be committed. This part is
identical regardless of which provider was chosen in step 0.

## 3. Ask which platform(s), compiler(s), version, and triggers

CppModel publishes one SDK archive per OS and architecture, and this set changes over time (see
`cppmodel:update-dependencies` steps 2-3). Fetch `https://download.cppmodel.com/` fresh and parse
the actual filenames present rather than assuming a fixed set. As of writing (0.8) that's
`Linux-x86_64` and `Linux-aarch64` (glibc 2.28+, GCC or Clang), `Windows-x64` and `Windows-ARM64`
(MSVC or clang-cl), and `macOS-universal` (macOS 11+, Apple Clang) - but treat that as a hint of the
shape to expect, not the answer; confirm against the live listing before presenting choices. On
`Windows-x64`, MSYS2's MinGW toolchains (UCRT64 with GCC, CLANG64, MINGW64) use the same archive as
MSVC; `Windows-ARM64` is MSVC or clang-cl only. A Linux job's image must have glibc 2.28
or newer (Debian 10+, Ubuntu 20.04+, RHEL/Rocky 8+; not Alpine).

Ask:

1. **Which OS/platform(s)** to build and test on - within what the chosen provider can actually
   run (see step 4's per-provider runner-availability notes before offering a platform the
   provider can't host). If an install script or existing pipeline from step 1 already targets one
   platform, say so and ask whether to keep that scope or add more.
2. **Which compiler(s)**, per platform, from the families that platform supports (GCC/Clang,
   MSVC/clang-cl/MinGW, Apple Clang). One archive serves all of them, so a GCC and a Clang job on Linux
   share the install step; only offer more than one when the user wants the code itself checked
   against several compilers. If only one option exists for a chosen platform, don't ask, just
   confirm it.
3. **Which SDK version to pin** - the version already pinned elsewhere in the project (see
   `cppmodel:update-dependencies` step 1), or `latest` if nothing is pinned yet and the user is
   fine tracking it (worth flagging: CI silently picking up new SDK releases can turn an unrelated
   release into a surprise CI failure).
4. **Which events/branches** should trigger the pipeline. Suggest push + pull/merge-request against
   the project's default branch as a reasonable default, but confirm rather than assuming - an
   existing pipeline from step 1 is the best signal of what this project actually wants here.

## 4. Map each platform/compiler to a runner - provider-specific availability and syntax

Not every provider can host every platform the same way - check this **before** finalizing step
3's platform list, not after generating something that can't run.

### GitHub Actions

`runs-on: ubuntu-latest` / `windows-latest` / `macos-latest` (arm64; the `macOS-universal` SDK runs
on Intel images too, while they still exist). GitHub also hosts ARM64 Linux and Windows runners
(`ubuntu-24.04-arm`, `windows-11-arm` as of writing - check current labels and whether the
repository's plan has them). All are hosted, no extra setup needed to get a runner. This is the best-covered
provider - see the worked example in step 5.

### Gitea Actions

Syntax is almost identical to GitHub Actions (same `on:`/`jobs:`/`steps:`/`uses:` shape, written to
`.gitea/workflows/`), but **Gitea has no hosted runner fleet** - every `runs-on:` label must match
one a self-hosted `act_runner` was actually registered with on that instance. Don't assume
`ubuntu-latest`/`windows-latest`/`macos-latest` resolve to anything; ask the user (or check the
instance's runner registration) which labels exist before picking one, and check whether
runners for every platform the user wants are even registered - if not, that platform isn't
available on this instance without first standing up a runner for it, which is outside this
skill's scope.

### GitLab CI

Written to `.gitlab-ci.yml`. GitLab's shared SaaS runners use `tags:` like
`saas-linux-small-amd64`, `saas-windows-medium-amd64`, `saas-macos-medium-m1` - but Windows and
macOS shared runners are limited-availability/paid-tier and have changed over time; verify what
the project's actual GitLab plan/instance offers rather than assuming full parity with GitHub's
free-for-public-repos hosted runners. If the project uses self-hosted GitLab Runners instead,
match whatever `tags:` its existing `.gitlab-ci.yml` (step 1) already uses - don't invent new tags
a registered runner won't pick up.

### Bitbucket Pipelines

Written to `bitbucket-pipelines.yml`. Bitbucket Cloud's hosted pipelines run **Linux Docker
containers only** (`image: <docker image>` per step/pipeline) - there is no hosted Windows or
macOS runner. Windows is possible only via a self-hosted Bitbucket Runner
(`runs-on: ['self.hosted', 'windows']`); macOS isn't supported by Bitbucket Pipelines at all,
hosted or self-hosted, as of writing - confirm current support before promising it, and if the
user needs macOS coverage, tell them Bitbucket can't do it and ask whether a different provider (or
skipping macOS in CI) is acceptable instead of silently dropping the platform.

## 5. Remaining pipeline steps and provider syntax

The steps are the same everywhere - checkout, toolchain + dependency-fetch, configure/build, test -
but each provider expresses them differently.

**Checkout & submodules**: GitHub/Gitea use `actions/checkout@v4` (with `submodules: true` for
public submodules; a private-host submodule needs an SSH key added as a secret first, injected via
an earlier step - see step 1). GitLab checks out automatically; set
`GIT_SUBMODULE_STRATEGY: recursive` (and `GIT_SUBMODULE_DEPTH` if needed) in the job/pipeline
`variables:`, with a private submodule's deploy key added as a GitLab CI/CD variable or SSH key
resource. Bitbucket also checks out automatically but does **not** natively follow submodules -
add an explicit `git submodule update --init --recursive` step, with any private submodule's SSH
key added via Repository Settings > SSH keys (or as a secured variable written to `~/.ssh` in the
step, matching the pattern of an existing Bitbucket pipeline if step 1 found one).

**Toolchain + dependency fetch**: install the compiler and build tools the chosen platform needs
(`apt-get install build-essential cmake ninja-build` or `clang` on Linux/Bitbucket's image, nothing
or `brew install ninja` on macOS, where Xcode's Apple Clang is preinstalled; the Visual Studio that
GitHub's Windows images ship, or Build Tools on a self-hosted runner). No OpenSSL, zlib or vcpkg:
the SDK carries them. Then run the step-2 install script (`bash scripts/install-cppmodel.sh`, or
the `.ps1` in a `pwsh` step), with `VERSION`/`-Version` set to step 3's pin.

On Windows, either use a Visual Studio generator (`cmake -S . -B build -A x64`, `-A ARM64`, add
`-T ClangCL` for clang-cl), which finds MSVC itself, or put MSVC on PATH for Ninja first (on
GitHub/Gitea, e.g. `ilammy/msvc-dev-cmd`; elsewhere, run `vcvarsall.bat` in the job's shell). With
a Visual Studio generator, build and test with the configuration named: `cmake --build build
--config Release` and `ctest --test-dir build -C Release`.

A MinGW job on GitHub/Gitea uses `msys2/setup-msys2@v2` with `msystem: UCRT64` (or `CLANG64`,
`MINGW64`) and `pacboy: toolchain:p cmake:p ninja:p`, then runs its build steps with
`shell: msys2 {0}`. Run the install script in its own `pwsh` step; when configuring from the MSYS2
shell, pass the SDK path as a Windows path (`-DCMAKE_PREFIX_PATH="$(cygpath -m "$PWD/dependencies")"`)
if `CMakeLists.txt` doesn't set it.

**Configure + build**: `cmake -S . -B build [-G Ninja] [-DCMAKE_C_COMPILER=...
-DCMAKE_CXX_COMPILER=...]` then `cmake --build build`, matching whatever generator/flags this
project's own build docs or existing pipeline (step 1) already use - don't invent a different one.
`cppmodel_deploy_runtime()` in the project's `CMakeLists.txt` puts the shared library next to each
simulation, so `ctest` runs them from the build folder with no `LD_LIBRARY_PATH`/`PATH` setup. If a
simulation fails to start with a missing `libcppmodel.so.1`/`cppmodel.dll`, that call is missing
for its target - fix the `CMakeLists.txt`, not the pipeline.

**Test**: `ctest --output-on-failure` (or `--test-dir build`), with credentials injected as CI
secrets/variables, never literal values in the config:

- GitHub/Gitea: `env: { CPPMODEL_USERNAME: '${{ secrets.CPPMODEL_USERNAME }}', ... }`.
- GitLab: reference CI/CD variables directly as `$CPPMODEL_USERNAME` (masked + protected, added
  under Settings > CI/CD > Variables) - no `secrets.` wrapper syntax.
- Bitbucket: same direct `$CPPMODEL_USERNAME` reference, added as a (Secured) repository or
  workspace variable under Settings > Repository variables.

Never set `CPPMODEL_DISCARD_RESULTS` (removed in 0.10.0; before 0.8: `CPPMODEL_OFFLINE`) in CI,
and never pass a simulation `--results` there. CI runs are submitted to the workspace like any
other, and their executions are the history later runs are compared against (see
`cppmodel:simulations`' "The workspace is part of the loop"). From SDK 0.10.0 a run with
`--results` fails when `CI` is set, which every supported provider sets.

Set `CPPMODEL_LOGIN_TIMEOUT: 0` (as a plain value, not a secret) next to the credentials (SDK
0.9.1+). With a missing or wrong secret, a run then fails at once with a `CppModel workspace:` line
instead of printing a browser sign-in link and waiting 60 seconds per simulation.

Let `ctest`'s own nonzero exit code fail the job everywhere - don't wrap it in something that
swallows the exit code.

**Posting inputs or running sweeps (only when the pipeline needs it)**: a job that runs a
simulation with posted inputs or parameters, or a whole parameter sweep, has no MCP server, so it
uses the SDK's `cppmodel-tool` (`cppmodel-tool sweep <plan.json> <out>`; plan format in
`cppmodel:parameter-sweep`'s "In CI or a script"). This is the one place the plugin uses the tool -
interactive work goes through the MCP server and doesn't need it. From SDK 0.8 it ships prebuilt
with the SDK, so there's nothing to build: after the dependency fetch it's
`dependencies/bin/cppmodel-tool` (`dependencies\bin\cppmodel-tool.exe` on Windows). With an SDK
before 0.8 it ships as source and is built with the project's toolchain:
`cmake -S dependencies/share/cppmodel/tools -B build/cppmodel-tool && cmake --build build/cppmodel-tool`.

It logs in with the same `CPPMODEL_USERNAME`/`CPPMODEL_PASSWORD` variables (via a `.env` written
from the secrets at the project root, or `--env <file>`).
- **From SDK 0.10.0,** the sweep passes each run's document to the binary with `--inputs`, so jobs
  on several platforms can sweep the same simulation with the same login at once. The simulation
  binaries must be built with 0.10.0+ as well.
- **Before 0.10.0,** it posts documents on that account. A sweep job then must not run concurrently
  with another job that runs the same simulation with the same login: serialize them
  (GitHub/Gitea `concurrency:`, GitLab `resource_group:`, Bitbucket separate steps).

Let the sweep's exit code fail the job (`0` every run verified, `1` stopped early). Keep
`<out>/summary.json` as an artifact: its rows' `executionId` can be read later with `get_execution`
(before 0.10.0: `fingerprint`/`index` with `get_binary_runs`). To also assert the expected outcome
of each run, as a test, read `summary.json`'s `passed` per run in a follow-up step. The SDK's own
`ParameterSweep` CTest (`tests/ParameterSweep.cmake` in the CppModel sources) does this with
CMake's `string(JSON)`, which reads booleans as `ON`/`OFF`. Don't add any of this unless the user
asked for it.

### Worked example (GitHub Actions, Linux+macOS+Windows matrix)

For reference - a real, working shape (adapt names/versions to what was actually chosen, this
isn't a template to copy blindly): one `test` job with `strategy.matrix.include:` listing explicit
`{os, name, ...}` entries (not a Cartesian `os x compiler` product - not every compiler applies to
every OS) and `if: runner.os == 'Linux'/'macOS'/'Windows'` guards per step. GitLab/Bitbucket express
the same idea as separate `stages`/jobs per platform instead of one matrixed job, since neither has
a direct equivalent of GitHub's `strategy.matrix` combined with per-step OS conditionals - mirror
whichever shape the target provider actually supports rather than forcing GitHub's exact structure
onto it.

## 6. Secrets/variables are the user's to create, not yours

Tell the user exactly which secret/variable names the generated pipeline expects and where to add
them for the chosen provider (GitHub/Gitea: repo Settings > Secrets and variables > Actions;
GitLab: Settings > CI/CD > Variables; Bitbucket: Settings > Repository variables) - don't invent,
print, or commit real credential values, and don't set them on the user's behalf via an API/CLI
unless they explicitly ask for it; that changes shared repo state and gets confirmed first like any
other CI-visible action.

## After generating

Show the generated config to the user, and call out explicitly: which provider it targets, which
secrets/variables it needs, whether it added a new `install-cppmodel.*` script or pipeline file,
and whether an existing pipeline for another provider was left untouched (never remove or replace
one unless asked). If the project's CppModel SDK version is later updated via
`cppmodel:update-dependencies`, that skill's own step 9 already offers to bump the version pinned
here (step 3's `VERSION`/`-Version` choice) - point back to it rather than duplicating that sync
logic here.
