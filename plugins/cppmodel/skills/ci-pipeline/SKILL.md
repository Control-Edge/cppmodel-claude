---
name: cppmodel:ci-pipeline
description: Generate or extend a CI pipeline - GitHub Actions, GitLab CI, Bitbucket Pipelines, or Gitea Actions - that builds a CppModel project and runs its simulations/tests, asking which provider, platform(s), and compiler(s) (among those CppModel actually publishes a prebuilt SDK for) to target. Use when asked to set up, add, or fix CI for a project using the CppModel libraries.
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
- How `CMakeLists.txt` links OpenSSL/zlib. CppModel's client libraries (used for Workspace API
  communication) depend on OpenSSL and zlib, so every platform's job needs those dev
  libraries/packages installed - but check *how* the project links them first: bare library names
  (`target_link_libraries(... crypto ssl z ...)`, the Unix `-l<name>` convention) only resolve
  against MinGW-style `.a`/`.dll.a` libraries, not MSVC's differently-named `.lib` files. If the
  project links this way and hasn't been changed to `find_package(OpenSSL)`, **MSVC is not a
  viable Windows target for this project's CI** - use a MinGW/MSYS2 toolchain (UCRT64 or CLANG64)
  on Windows instead, and say so rather than generating an MSVC job that will fail to link.
- `.gitmodules` - if the project has git submodules, note their URL scheme. A private-host
  `ssh://`/`git@` submodule needs its own deploy key/credential set up for CI to check it out -
  every provider below handles this differently (see step 5), and hosted runners never have
  implicit access to a private internal git server.
- `.env.example` or the project's docs for the exact credential variable names expected (normally
  `CPPMODEL_USERNAME`, `CPPMODEL_PASSWORD`, `CPPMODEL_CLIENT_ID` - see
  `cppmodel:simulation-testing`'s "Requirements" - but confirm against this project's own file
  rather than assuming; some projects only require the first two).
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
${CLAUDE_PLUGIN_ROOT}/scripts/templates/install-cppmodel.sh   # Linux + macOS
${CLAUDE_PLUGIN_ROOT}/scripts/templates/install-cppmodel.ps1  # Windows
```

If step 1 found an existing script that already does this, leave it as-is and just note its exact
name/location/argument shape for step 5 (every project seen so far names and parameterizes this
script slightly differently - don't assume it matches the template exactly). Otherwise, copy the
template(s) needed for the chosen platform(s) into the project (a `scripts/` folder is the
established convention - match one if it already exists) and adjust the default `dependencies/`
destination path only if this project's `CMakeLists.txt` points somewhere else. Both templates
already support `VERSION` (env var on the `.sh`, `-Version` param on the `.ps1`; default `latest`)
so the pipeline can pin an exact version - see step 3 - and auto-detect compiler/arch with an
override. Mention to the user that this script was added and needs to be committed. This part is
identical regardless of which provider was chosen in step 0.

## 3. Ask which platform(s), compiler(s), version, and triggers

CppModel publishes separate SDK archives per OS and, for some OSes, per compiler/architecture too,
and this set changes over time (see `cppmodel:update-dependencies` steps 2-3). Fetch
`https://download.cppmodel.com/` fresh and parse the actual filenames present rather than assuming
a fixed set. As of writing that's roughly clang21/gcc12/gcc16 with an x86_64/aarch64 split on
Linux, UCRT64/CLANG64/MSVC toolchains on Windows, and arm64/x86_64 with no compiler split on
macOS (matching the install scripts' own built-in defaults) - but treat that as a hint of the
shape to expect, not the answer; confirm against the live listing before presenting choices.

Ask:

1. **Which OS/platform(s)** to build and test on - within what the chosen provider can actually
   run (see step 4's per-provider runner-availability notes before offering a platform the
   provider can't host). If an install script or existing pipeline from step 1 already targets one
   platform, say so and ask whether to keep that scope or add more. Rule out MSVC up front per
   step 1's linkage check if it applies.
2. **Which compiler/toolchain**, per platform, from what the live listing actually offers for that
   platform - if only one option exists for a chosen platform, don't ask, just confirm it.
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

`runs-on: ubuntu-latest` / `windows-latest` / `macos-latest` (arm64 - GitHub has been reducing
Intel-runner availability over time; check current offerings before assuming an Intel image still
exists). All three are hosted, no extra setup needed to get a runner. This is the best-covered
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

**Toolchain + dependency fetch**: install whatever compiler/build-tool packages the chosen platform
needs (`apt-get` on Linux/Bitbucket's Ubuntu image, Homebrew on macOS with
`LIBRARY_PATH=$(brew --prefix openssl@3)/lib:$LIBRARY_PATH` exported so AppleClang finds OpenSSL,
`msys2/setup-msys2` on GitHub/Gitea Windows or the provider's own MSYS2/Chocolatey equivalent
elsewhere), then run the step-2 install script with `COMPILER=<name>` (sh) or `-Platform <name>`
(ps1) set - on MSYS2-based Windows jobs, run the `.ps1` via a `pwsh`/PowerShell step and switch
later steps to the MSYS2 shell so the toolchain and generator are on PATH.

**Configure + build**: `cmake -S . -B build [-G Ninja] [-DCMAKE_C_COMPILER=...
-DCMAKE_CXX_COMPILER=...]` then `cmake --build build`, matching whatever generator/flags this
project's own build docs or existing pipeline (step 1) already use - don't invent a different one.

**Test**: `ctest --output-on-failure` (or `--test-dir build`), with credentials injected as CI
secrets/variables, never literal values in the config:

- GitHub/Gitea: `env: { CPPMODEL_USERNAME: '${{ secrets.CPPMODEL_USERNAME }}', ... }`.
- GitLab: reference CI/CD variables directly as `$CPPMODEL_USERNAME` (masked + protected, added
  under Settings > CI/CD > Variables) - no `secrets.` wrapper syntax.
- Bitbucket: same direct `$CPPMODEL_USERNAME` reference, added as a (Secured) repository or
  workspace variable under Settings > Repository variables.

Let `ctest`'s own nonzero exit code fail the job everywhere - don't wrap it in something that
swallows the exit code.

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
