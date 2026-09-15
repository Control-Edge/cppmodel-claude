---
name: cppmodel:update-dependencies
description: Download and install the latest CppModel libraries into the project's dependencies folder, detecting the right platform/toolchain build, diffing the public headers against what's already there to catch interface changes (RunCyclic's signature especially), fixing unambiguous call-site breakage and asking about anything unclear, then rebuilding to verify before offering to sync the version pinned in CI/docs. Use when asked to update, upgrade, or refresh the CppModel dependencies/libraries to the latest version.
---

## What's being updated

Projects using CppModel typically vendor a single prebuilt SDK drop from
`https://download.cppmodel.com/` into a `dependencies/` folder (headers under `include/`, static
libs under `lib/`, third-party licenses under `licenses/`) - don't assume the exact folder name,
confirm it against this project's build files (e.g. grep `CMakeLists.txt` for
`include_directories`/`link_directories` pointing at it). This folder is normally **not** tracked
by git (check `.gitignore`) - there is no source-control safety net for it, which is why step 4
below matters.

No authentication is needed to download from `download.cppmodel.com` itself - it's a plain static
file index. (`CPPMODEL_USERNAME`/`CPPMODEL_PASSWORD`, see `cppmodel:simulations`, are for the
Workspace API/license, not for fetching the SDK.)

## 1. Determine the current version

There's no version marker inside `dependencies/` itself - don't try to infer one from its
contents. Instead check wherever the project *pins* a version to download it, most commonly a CI
config (e.g. grep `bitbucket-pipelines.yml`, `.github/workflows/*.yml`, `Jenkinsfile`, or any
setup script for a `download.cppmodel.com/CppModel-<version>-...` URL). Also check docs
(`README.md` and similar) for a stated version number. If these disagree with each other - which
happens, e.g. a CI pin that's been bumped without updating the README, or vice versa - tell the
user about the mismatch rather than silently trusting one of them.

## 2. Determine the target platform/toolchain - detect, don't hardcode

`download.cppmodel.com` ships separate archives per OS and, for some OSes, per compiler/toolchain
and architecture too (this evolves over time - see step 3, always check what's actually there
rather than assuming a fixed set). Figure out which one this project/build needs, in this order:

1. **The project's own build system first.** For CMake: if a build directory already exists,
   read `CMakeCache.txt` for `CMAKE_CXX_COMPILER`/`CMAKE_GENERATOR`; otherwise check
   `CMakeLists.txt`/toolchain files for anything that pins a compiler. For another build system,
   check its equivalent (toolchain file, Makefile compiler variables, etc.) - use whatever this
   project's own configuration already says, don't assume.
2. **If no build has happened yet and nothing pins a compiler**, detect from the environment/PATH
   - but only consider compilers CppModel actually publishes a matching archive for (check the
     live listing, step 3, rather than assuming a fixed list - as of writing that's roughly
     clang21/gcc12/gcc16 with an x86_64/aarch64 split on Linux, UCRT64/CLANG64/MSVC toolchains on
     Windows, and arm64/x86_64 with no compiler split on macOS). Ignore any other compiler found
     on PATH (e.g. an unrelated older gcc) - there's no archive for it.
3. **If more than one matching compiler/toolchain is found this way, ask the user which to
   target** - don't guess between, say, UCRT64 and CLANG64, or gcc12 and gcc16.
4. Determine the OS the same way (build config first, then environment) - and note that the OS
   you're running/detecting on may differ from the OS a CI pipeline builds for; keep those
   separate (see step 9 - the CI pin may need a different platform suffix than local dev uses).

## 3. Find the latest version for that platform

Fetch `https://download.cppmodel.com/` - it's a plain directory listing (`<a href="...">` entries
with filename, date, size). Parse it for entries matching `CppModel-<version>-<platform
suffix>.<ext>` for the platform/toolchain from step 2, and pick the highest semver version present
for that exact platform suffix. `CppModel-latest-<platform suffix>.<ext>` aliases also exist, but
prefer parsing actual version-numbered filenames - that gives a concrete version string to report
and reuse later (step 9), rather than silently trusting an alias whose target version you'd then
have to re-derive some other way.

Filename shapes have changed across releases (parse fresh, don't hardcode a pattern):
`CppModel-0.4.2-Linux.tar.gz` (older, no compiler suffix), `CppModel-0.5.1-Linux-x86_64-gcc12.tar.gz`
(newer, arch+compiler suffix), `CppModel-0.5.1-Windows-UCRT64.zip`, `CppModel-0.5.1-macOS-arm64.tar.gz`.

If the current version from step 1 is already the latest available for this platform, say so and
stop - there's nothing to update.

## 4. Back up before touching anything

Since `dependencies/` normally isn't in git, copy it aside first (e.g. to
`dependencies.bak-<old-version>/`, or somewhere in the scratch/temp area) so the old headers stay
available for diffing in step 6 and the whole update can be rolled back if the rebuild in step 8
fails.

## 5. Download and stage - don't overwrite in place yet

Download the chosen archive to a temp location and extract it into a **separate staging
directory**, not directly over `dependencies/`. Follow whatever extraction convention the
project's own CI already uses for this (e.g. `tar -xzf <file> -C <staging> --strip-components=1`
for `.tar.gz`, or unzip for `.zip`) so the result has the same internal layout as before.

## 6. Diff the interface headers before swapping in

Compare `include/cppmodel/*.h` between the step-4 backup and the step-5 staged copy - `Model.h`,
`Simulation.h`, and `CModel.h` matter most, since project code calls into them directly (either
straight, or via a project-local wrapper built on top - see `cppmodel:simulation-testing`'s C++/C
sections). Pay particular attention to:

- **`Model::RunCyclic`'s signature** - the method plant models and any class deriving from
  `CppModelBase::Model`/`CppModelBase::Simulation` override. Past CppModel releases have changed
  this parameter's type; it's the single most common source of breakage after an update for
  projects like this one.
- Any other changed function/method signature, struct field, or typedef shape - not just renames.

For everything that changed, grep the project for real call sites/overrides so the full blast
radius is known before editing anything:

- `RunCyclic` overrides: wherever plant models live (e.g. a `models/` folder - see
  `cppmodel:plant-model`) and any file directly subclassing `CppModelBase::Model` or
  `CppModelBase::Simulation`.
- Direct API usage: `CppModel_getInput*`/`CppModel_setOutput*`/`CppModel_getParameter*` (C) or
  `inputs["..."]`/`outputs["..."]` and other `CppModelBase::Simulation` members (C++) - across the
  simulations folder and any project-local base class they're built on.

## 7. Fix call sites: mechanical changes now, ambiguous ones stop and ask

- If a change is unambiguous - a straight rename, a widening conversion, a type swap whose new
  meaning is obvious from the new header (naming, inline comments, an accompanying example in the
  downloaded archive if one exists) - update every affected call site directly.
- If a change's new semantics aren't clear from the header alone - e.g. `RunCyclic`'s time
  parameter changes type and it isn't obvious whether it still means the same thing (same units,
  same "elapsed since start" vs. "delta since last cycle" meaning, etc.) - **stop and ask**,
  showing the old and new signatures side by side and what was found in the project. Guessing
  wrong here silently changes timing-dependent assertions in safety-test simulations without
  anyone noticing, which is worse than pausing to ask.
- Report every file touched, and every file identified as needing a fix, either way.

## 8. Swap in and verify by building

Once the staged headers/libs are confirmed compatible (or already patched per step 7), replace
`dependencies/` with the staged copy - keep the step-4 backup until the next check passes. Rebuild
and run the test suite the same way `cppmodel:simulation-testing` does:

```
cmake --build build --target all
cd build && ctest --output-on-failure
```

If the build or tests fail after the best-effort fix, don't report success - state exactly what
failed, leave the backup in place, and ask before attempting further changes. Once the build and
tests pass, it's safe to remove the backup.

## 9. Offer to keep CI and docs in sync

After a successful local update, report the version change (`<old> → <new>`) and **offer, don't
silently do**, to also:

- Bump the pinned download URL(s) found in step 1 (e.g. in CI config) to the new version - keep
  whatever platform suffix that pin already used (e.g. CI's Linux/gcc12 build), which may differ
  from the platform detected for local use in step 2.
- Update any version number mentioned in project docs (e.g. `README.md`).

Treat both as shared/CI-affecting edits and confirm before making them, the same as any other
change to CI configuration or committed documentation would be confirmed.
