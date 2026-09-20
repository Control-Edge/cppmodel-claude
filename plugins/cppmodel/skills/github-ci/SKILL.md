---
name: cppmodel:github-ci
description: Generate a GitHub Actions workflow that builds a CppModel project and runs its simulations/tests in CI, asking which platform and compiler (among those CppModel actually publishes a prebuilt SDK for) to target. GitHub Actions only for now - not Bitbucket Pipelines, GitLab CI, or Jenkins. Use when asked to set up, add, or fix a GitHub CI/Actions pipeline for a project using the CppModel libraries.
---

## What this produces

A `.github/workflows/<name>.yml` workflow with one `test` job matrixed over the chosen
platform(s), each entry installing its toolchain, fetching the matching CppModel SDK via a
committed `install-cppmodel.sh`/`.ps1` script (see step 2 - reused or added, never re-derived
inline), then configuring, building, and `ctest`-ing with repository secrets for credentials.
GitHub Actions only - if the project actually runs on Gitea Actions, Bitbucket Pipelines, GitLab
CI, or Jenkins instead, say so rather than silently generating a GitHub workflow nobody will run
(Gitea Actions shares GitHub Actions' workflow syntax almost exactly, so if asked to also cover
Gitea, everything below still applies - just written to `.gitea/workflows/`).

## 1. Look for what already exists - don't start from a blank page

Before asking anything, check the project for:

- An existing SDK install/update script - grep the whole repo for `download.cppmodel.com` (common
  names seen in the wild: `install-cppmodel.sh`/`.ps1`, `scripts/update-cppmodel.sh`/`.ps1`). If
  found, reuse and extend it (step 2) rather than adding a second, competing one.
- Any existing CI config, for GitHub or another provider (`.github/workflows/*.yml`,
  `.gitea/workflows/*.yml`, `bitbucket-pipelines.yml`, `Jenkinsfile`, `.gitlab-ci.yml`). An existing
  pipeline for another provider is the single best reference for this project's real build steps
  (compiler, generator, extra install steps, submodules) - mirror its structure into the new GitHub
  workflow rather than guessing from `CMakeLists.txt` alone, and don't remove or replace it unless
  asked to.
- How `CMakeLists.txt` links OpenSSL/zlib. CppModel's client libraries (used for Workspace API
  communication) depend on OpenSSL and zlib, so every platform's job needs those dev
  libraries/packages installed - but check *how* the project links them first: bare library names
  (`target_link_libraries(... crypto ssl z ...)`, the Unix `-l<name>` convention) only resolve
  against MinGW-style `.a`/`.dll.a` libraries, not MSVC's differently-named `.lib` files. If the
  project links this way and hasn't been changed to `find_package(OpenSSL)`, **MSVC is not a
  viable Windows target for this project's CI** - use a MinGW/MSYS2 toolchain (UCRT64 or CLANG64)
  on Windows instead, and say so rather than generating an MSVC job that will fail to link.
- `.gitmodules` - if the project has git submodules, note their URL scheme. An `ssh://`/`git@` URL
  to a private host means the GitHub workflow needs its own deploy key/SSH secret to check them
  out (GitHub-hosted runners have no access to a private internal git server by default); a plain
  `https://github.com/...` submodule usually needs nothing extra beyond `actions/checkout`'s
  built-in `submodules:` option.
- `.env.example` or the project's docs for the exact credential variable names expected (normally
  `CPPMODEL_USERNAME`, `CPPMODEL_PASSWORD`, `CPPMODEL_CLIENT_ID` - see
  `cppmodel:simulation-testing`'s "Requirements" - but confirm against this project's own file
  rather than assuming; some projects only require the first two, since `CPPMODEL_CLIENT_ID` may
  already default correctly in code).
- Any other local-only step a human currently runs between checkout and a working build (unzipping
  vendored BSW archives, code generation, a `CMakePresets.json`) - the workflow needs an equivalent
  step for each one it finds, not just checkout+fetch-deps+build+test.

## 2. Ensure a per-platform install script exists - reuse the plugin's template

The actual SDK download/extract logic (detect OS/arch/compiler, build the archive URL, download,
flatten, install into `dependencies/`) should live in a script committed to the project, not
inline in the workflow YAML - that's what makes it runnable identically by a developer locally and
by CI, and this plugin ships ready-made templates instead of hand-deriving this logic each time:

```
${CLAUDE_PLUGIN_ROOT}/scripts/templates/install-cppmodel.sh   # Linux + macOS
${CLAUDE_PLUGIN_ROOT}/scripts/templates/install-cppmodel.ps1  # Windows
```

If step 1 found an existing script that already does this, leave it as-is and just note its exact
name/location/argument shape for step 4 (every project seen so far names and parameterizes this
script slightly differently - don't assume it matches the template exactly). Otherwise, copy the
template(s) needed for the chosen platform(s) into the project (a `scripts/` folder is the
established convention - match one if it already exists) and adjust the default `dependencies/`
destination path only if this project's `CMakeLists.txt` (`include_directories`/`link_directories`)
points somewhere else. Both templates already support `VERSION` (env var on the `.sh`, `-Version`
param on the `.ps1`; default `latest`) so the workflow can pin an exact version - see step 3 - and
auto-detect compiler/arch with an override, matching `cppmodel:update-dependencies`'s own
detect-first approach. Mention to the user that this script was added and needs to be committed.

## 3. Ask which platform(s) and compiler(s) - from the live listing, not a hardcoded list

CppModel publishes separate SDK archives per OS and, for some OSes, per compiler/architecture too,
and this set changes over time (see `cppmodel:update-dependencies` steps 2-3). Fetch
`https://download.cppmodel.com/` fresh and parse the actual filenames present rather than assuming
a fixed set. As of writing that's roughly clang21/gcc12/gcc16 with an x86_64/aarch64 split on
Linux, UCRT64/CLANG64/MSVC toolchains on Windows, and arm64/x86_64 with no compiler split on
macOS (matching the install scripts' own built-in defaults) - but treat that as a hint of the
shape to expect, not the answer; confirm against the live listing before presenting choices.

Ask:

1. **Which OS/platform(s)** to build and test on. If an install script or existing CI config from
   step 1 already targets one platform (e.g. Linux only), say so and ask whether to keep that scope
   or add more - don't silently expand it into a multi-platform matrix nobody asked for. Rule out
   MSVC up front per step 1's linkage check if it applies.
2. **Which compiler/toolchain**, per platform, from what the live listing actually offers for that
   platform - if only one option exists for a chosen platform, don't ask, just confirm it.
3. **Which SDK version to pin** - the version already pinned elsewhere in the project (see step 3
   below / `cppmodel:update-dependencies` step 1), or `latest` if nothing is pinned yet and the
   user is fine tracking it (worth flagging: CI silently picking up new SDK releases can turn an
   unrelated release into a surprise CI failure).
4. **Which events/branches** should trigger the pipeline (push, and to which branches; pull
   requests; `workflow_dispatch` for manual runs). Suggest push + pull_request against the
   project's default branch as a reasonable default, but confirm rather than assuming - an existing
   CI config from step 1 is the best signal of what this project actually wants here.

## 4. Map each platform/compiler to a runner, toolchain step, and dependency-fetch step

Model each matrix entry on this shape (a real, working example - adapt names/versions to what was
actually chosen, don't copy the specific compiler versions blindly):

- **Linux (gcc)**: `runs-on: ubuntu-latest`. Install the exact requested compiler version if it's
  not already on the default image (check https://github.com/actions/runner-images first), e.g.
  for gcc16 via the `ubuntu-toolchain-r/test` PPA, and export `CC`/`CXX` via `$GITHUB_ENV` so
  later steps pick it up. Then run the install script with `COMPILER=<name>` set:
  `COMPILER=gcc16 ./scripts/install-cppmodel.sh`.
- **Linux (clang)**: same runner; `apt-get install -y clang`; `COMPILER=clang21
  ./scripts/install-cppmodel.sh`.
- **macOS**: `runs-on: macos-latest` (arm64 - GitHub has been reducing Intel-runner availability
  over time; if x86_64 macOS is genuinely needed, check current GitHub-hosted runner offerings
  before assuming an Intel image still exists). Install OpenSSL via Homebrew and point the linker
  at it, since AppleClang doesn't find it by default: `brew install openssl@3` then append
  `LIBRARY_PATH=$(brew --prefix openssl@3)/lib:$LIBRARY_PATH` to `$GITHUB_ENV`. Then run
  `./scripts/install-cppmodel.sh` (no `COMPILER` needed - macOS archives aren't compiler-split).
- **Windows, UCRT64/CLANG64 (MinGW via MSYS2)**: `runs-on: windows-latest`, set up via
  `msys2/setup-msys2@v2` with `msystem: UCRT64` (or `CLANG64`) and `install:` naming the
  MSYS2-prefixed packages needed (`mingw-w64-ucrt-x86_64-gcc`, `-cmake`, `-ninja`, `-openssl`,
  `-zlib`, etc. - swap the `ucrt-x86_64` infix for `clang-x86_64` under CLANG64). Fetch
  dependencies with `shell: pwsh` running `.\scripts\install-cppmodel.ps1 -Platform UCRT64`
  (PowerShell is available even in a job that later switches shells) - configure/build/test steps
  after that instead use `shell: msys2 {0}` so the MSYS2 toolchain and generator are actually on
  PATH.
- **Windows, MSVC**: only if step 1's linkage check didn't rule it out. `runs-on: windows-latest`,
  rely on the image's preinstalled MSVC (a Developer Command Prompt-style step, e.g.
  `ilammy/msvc-dev-cmd`) or whatever this project's own Windows build docs already specify, then
  `.\scripts\install-cppmodel.ps1 -Platform MSVC`.

If more than one platform/compiler was chosen, use one `test` job with `strategy.matrix.include:`
listing explicit `{os, name, ...}` entries (not a Cartesian `os x compiler` product - not every
compiler applies to every OS) and `if: runner.os == 'Linux'/'macOS'/'Windows'` guards per step, the
way a project building for several platforms in one job actually does it - don't split into
separate jobs unless the user specifically wants that instead.

## 5. Remaining workflow steps

1. `actions/checkout@v4` - with `submodules: true`/`recursive` if step 1 found plain public
   submodules; a private-host submodule instead needs its own SSH key/deploy key step first (see
   step 1), added as a GitHub Actions secret, never written into the workflow file itself.
2. Toolchain + dependency-fetch steps from step 4, plus anything else step 1 found a human
   currently does before building (archive extraction, code generation, etc.).
3. Configure + build, matching whatever generator/compiler flags this project's own build docs or
   existing CI already use - e.g. `cmake -S . -B build [-G Ninja] [-DCMAKE_C_COMPILER=...
   -DCMAKE_CXX_COMPILER=...]` then `cmake --build build`. Don't invent a different generator than
   what's already established, and use the matching shell (`msys2 {0}` on the MSYS2 platforms).
4. Test: `ctest --output-on-failure` (run from the build directory, or via `--test-dir build`) with
   `CPPMODEL_USERNAME`, `CPPMODEL_PASSWORD`, and `CPPMODEL_CLIENT_ID` (whatever step 1's
   `.env.example` actually names) set once at the job level from `${{ secrets.<NAME> }}`, never as
   literal values in the YAML. Let `ctest`'s own nonzero exit code fail the job - don't wrap it in
   something that swallows the exit code.

## 6. Secrets are the user's to create, not yours

Tell the user exactly which secret names the generated workflow expects and where to add them
(repo Settings > Secrets and variables > Actions) - don't invent, print, or commit real credential
values, and don't run `gh secret set` on their behalf unless they explicitly ask for it; that
changes shared repo state and gets confirmed first like any other GitHub-visible action.

## After generating

Show the generated workflow to the user, and call out explicitly: which secrets it needs, whether
it added a new `install-cppmodel.*` script or `.github/workflows/` directory, and whether an
existing CI config for another provider was left untouched. If the project's CppModel SDK version
is later updated via `cppmodel:update-dependencies`, that skill's own step 9 already offers to bump
the version pinned here (step 3's `VERSION`/`-Version` choice) - point back to it rather than
duplicating that sync logic here.
