---
name: cppmodel:setup-environment
description: Set up a machine to build CppModel projects from scratch - detects the OS, architecture, installed C++ compilers/toolchains, build tools, and OpenSSL/zlib, compares them against the SDK builds download.cppmodel.com actually publishes, then lets the user pick the closest match, install a supported compiler, or (for an unsupported OS/arch/compiler) draft a request to support@cedge.se listing what is available for their OS. Finishes by installing the missing packages and the matching CppModel SDK and verifying a build. Use when asked to install, set up, or prepare a CppModel development environment, or when asked which compiler to use with CppModel.
---

## What this sets up

Building a CppModel project needs four things on the machine, all of which must agree with each
other:

1. **A C++ compiler/toolchain that matches a prebuilt CppModel SDK archive.** CppModel ships
   static libraries per OS and, on Linux and Windows, per compiler. A mismatched compiler
   typically fails at link time or, worse, links and misbehaves.
2. **Build tools**: CMake and a generator (Ninja or Make), plus git, curl, and tar/unzip for fetching.
3. **OpenSSL and zlib development libraries.** CppModel's client libraries (used for Workspace API
   communication) link against both.
4. **The CppModel SDK itself**, extracted into the project's `dependencies/` folder.

This skill is for **first-time setup**. If the project already has a populated `dependencies/`
folder and the user wants a newer SDK, use `cppmodel:update-dependencies` instead. That skill
diffs headers and fixes call sites, which a fresh install doesn't need.

Never install anything before step 4's confirmation. Detection (steps 1-2) is read-only.

## 1. Detect the environment - run the probe, don't improvise

The plugin ships a read-only probe for each OS family. Run the one for the current shell:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-environment.sh"
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\detect-environment.ps1"
```

Both print `key=value` lines:

- `os`, `os_pretty`, `os_id`/`os_id_like`/`os_version` (Linux distro), `arch`, `wsl`, `pkg_manager`
- `compiler=<family> <major> <full version> <path>` (Linux/macOS; family is `gcc`, `clang`, or `appleclang`)
- `toolchain=<UCRT64|CLANG64|MINGW64|MSVC|CLANGCL> ...` (Windows), plus `msys2`, `vcpkg`, and
  `path_compiler` (what a bare `cmake` would find on the plain PATH)
- `tool=<name> <version|missing>` and `lib=<name> found|missing ...`
- `latest_version`, and one `published=<platform tag>` per archive of that version, for all OSes

If the `.sh` reports `os=Windows` (Git Bash/MSYS2 shell), run the `.ps1` instead. Under WSL, the
machine is a Linux machine for this purpose. Windows compilers on the host can't build Linux code,
and the probe deliberately skips `/mnt/<drive>` PATH entries. If `published_status` isn't `ok`,
fetch `https://download.cppmodel.com/` yourself before going further. Never fall back to a
remembered list of what's published. The set changes between releases; `clang14` and `CLANGCL`
were added in 0.5.2, for example.

## 2. Match installed compilers against what's published

Filter the `published=` tags down to this OS and arch. Tag shapes as of writing:

| OS | Tag shape | Compiler dimension |
|---|---|---|
| Linux | `Linux-<x86_64\|aarch64>-<gcc12\|gcc16\|clang14\|clang21>` | family + major version |
| Windows | `Windows-<UCRT64\|CLANG64\|MSVC\|CLANGCL>` | toolchain, not version |
| macOS | `macOS-arm64` | none - uses Xcode's Apple clang |

Treat that table as a hint about the shape, not the answer. Always use the live tags from step 1.

Then classify each installed compiler:

- **Exact match**: family and major version equal a published tag (Linux), or the toolchain
  exists and has a published tag (Windows). On macOS, any Apple clang on a published arch counts.
  On Windows, also check that the matching `lib=` lines for that toolchain say `found`.
- **Near match**: same family, different major version (e.g. installed gcc 13, published gcc12
  and gcc16). Pick the nearest *older* published major as "closest". GCC's libstdc++ keeps backward
  compatibility, so a library built with an older GCC usually links under a newer one, while the
  reverse usually fails. If no older one is published, pick the nearest newer one and say it's
  less likely to work. A near match is **not a supported combination**. Say so plainly. Step 6's
  build is what proves whether it works.
- **No match**: nothing of that family is published for this OS (e.g. `MINGW64` on Windows).

Separately, check whether the **OS/arch itself** is published at all. Examples of platforms with
nothing published: Linux on armv7/i686/riscv64, Windows on ARM64, FreeBSD, and Intel macOS. Intel
macOS last had a build in 0.4.2, so verify against the full listing before saying so. If nothing
is published for the platform, no compiler choice can fix that. Go straight to step 3's "request
support" path.

## 3. Present the options - let the user choose

Start by showing a short summary:

- OS, arch, and distro/version
- each detected compiler with its classification from step 2
- missing tools and libraries
- **the full list of compilers/toolchains CppModel publishes for this OS/arch**

The user needs that last list for every choice below, so always include it.

Then ask with `AskUserQuestion`. Build the options from what was actually found, most suitable
first, and put `(Recommended)` on the one you'd pick:

1. **Use an installed exact match.** Offer this when one exists. With several (e.g. UCRT64 and
   MSVC both installed), make each one its own option. Don't pick between them silently.
2. **Install a supported compiler.** Offer the published compiler that's easiest to get on this
   OS, e.g. the one in the distro's own repos, or the toolchain whose MSYS2 environment is already
   present. Name the exact package and say whether it needs a third-party repository (see step 4).
   Put other published compilers in the option's description so "Other" can name them.
3. **Use the closest match**, `<installed compiler>` with the `<nearest published>` SDK. Offer
   this only when there's a near match and no exact match. Label it as unsupported and
   verified only by building.
4. **Request support for my compiler/platform.** Offer this whenever an installed compiler, or
   the OS/arch itself, has no exact match.

Special cases:

- If there's exactly one exact match, and tools and libraries are all present, skip the question.
  State the choice and continue to step 5.
- Windows, MSVC or CLANGCL: check how the project's `CMakeLists.txt` links OpenSSL/zlib first.
  Bare names (`target_link_libraries(... crypto ssl z)`) only resolve against MinGW-style
  libraries, so those toolchains won't link without changing it to `find_package(OpenSSL)`
  (same check as `cppmodel:ci-pipeline` step 1). Say so in those options' descriptions.

### The "request support" path

Don't send email yourself. Draft the message for the user to send to **support@cedge.se**, filled
in from the step-1 output:

```
To: support@cedge.se
Subject: CppModel SDK request: <OS> <arch> <compiler + version>

Hello,

I'd like to use CppModel on a platform/compiler that has no prebuilt SDK at download.cppmodel.com:

- OS: <os_pretty> (<arch>)
- Compiler: <family> <full version> (<path>)
- CppModel version wanted: <latest_version, or the version the project pins>
- Project/use case: <one line - ask the user, or leave a placeholder>

Currently published for <OS>/<arch>: <list, or "nothing">.

Is a build for this configuration available or planned?
```

Afterwards, tell the user which published compilers they could install meanwhile to get working
today (step 4's commands for this OS). Offer to continue with one of them. Don't stop at the
email.

## 4. Install what's missing - show commands, confirm, then run

List every package the chosen option still needs (compiler, tools, OpenSSL/zlib dev libraries) as
the exact commands for this OS's package manager. **Check availability before proposing a
package**, using `apt-cache policy <pkg>`, `dnf list --available <pkg>`, `pacman -Ss <pkg>`,
`brew info <pkg>`, or `winget search <id>`. Package names and versions differ between distro
releases. The lines below are starting points, not guarantees.

These commands change the system, so get explicit confirmation before running them. Most need
`sudo`/admin rights. If `sudo -n true` fails, don't try to supply a password. Give the user the
commands to run themselves (in Claude Code they can prefix one with `!`), then re-run the probe to
confirm.

**Debian/Ubuntu (apt):** `sudo apt-get install -y build-essential cmake ninja-build git curl
libssl-dev zlib1g-dev`, plus the compiler: `g++-12`, `clang-14`, or `g++-16`/`clang-21` if the
release has them. Otherwise `clang-21` comes from LLVM's own repository (`https://apt.llvm.org/llvm.sh`,
run as `sudo bash llvm.sh 21`), and a newer GCC usually comes from the `ubuntu-toolchain-r/test`
PPA. Adding a third-party repository is a separate thing to call out and confirm.

**Fedora/RHEL/Rocky (dnf):** `sudo dnf install -y gcc-c++ cmake ninja-build git openssl-devel
zlib-devel`. Fedora ships a single current GCC. On RHEL-family, older GCCs come as
`gcc-toolset-<N>`, enabled with `source /opt/rh/gcc-toolset-<N>/enable`. That only affects the
current shell, so point CMake at `/opt/rh/gcc-toolset-<N>/root/usr/bin/g++`.

**Arch (pacman):** `sudo pacman -S --needed base-devel cmake ninja git openssl zlib`. Arch
ships a rolling GCC/clang, so a specific older major may need the AUR. Say so rather than
installing an AUR helper unasked.

**macOS:** `xcode-select --install` (Apple clang), then `brew install cmake ninja openssl@3`. When
building, export `LIBRARY_PATH="$(brew --prefix openssl@3)/lib:$LIBRARY_PATH"` so Apple clang finds
OpenSSL.

**Windows, UCRT64/CLANG64 (MSYS2):** install MSYS2 if `msys2=missing` (`winget install MSYS2.MSYS2`).
Then, from the MSYS2 shell, run
`pacman -S --needed mingw-w64-ucrt-x86_64-{gcc,cmake,ninja,openssl,zlib}` for UCRT64, or
`mingw-w64-clang-x86_64-{clang,cmake,ninja,openssl,zlib}` for CLANG64. Build from that
environment's shell, or put its `bin` first on PATH.

**Windows, MSVC/CLANGCL:** Visual Studio Build Tools with the C++ workload
(`Microsoft.VisualStudio.Workload.VCTools`; look up the current package id with
`winget search Microsoft.VisualStudio`). For CLANGCL, also add the "C++ Clang tools" component, or
install `LLVM.LLVM`. OpenSSL/zlib come from vcpkg (`vcpkg install openssl zlib --triplet
x64-windows`) and are passed to CMake through vcpkg's toolchain file. Build from a Developer
PowerShell/Command Prompt so `cl`/`clang-cl` are on PATH.

After installing, re-run the step-1 probe and confirm the chosen compiler and libraries now show up.

## 5. Install the CppModel SDK

Find where the project expects the SDK. Usually that's `dependencies/`, but confirm by grepping
`CMakeLists.txt` for `include_directories`/`link_directories`. If the current directory isn't a
CppModel project (no `CMakeLists.txt` referencing it), ask where to put it.

Use the plugin's install templates, which already handle download, extraction, and layout
flattening. Always pass the chosen compiler explicitly: auto-detection refuses near matches, which
is right for CI but not here.

```
DEPS_DIR=<project>/dependencies COMPILER=<gcc12|...> VERSION=<version> bash "${CLAUDE_PLUGIN_ROOT}/scripts/templates/install-cppmodel.sh"
```

```powershell
& "${CLAUDE_PLUGIN_ROOT}\scripts\templates\install-cppmodel.ps1" -DepsDir <project>\dependencies -Platform <UCRT64|...> -Version <version>
```

On macOS, leave `COMPILER` unset. For `VERSION`, use the version the project already pins in CI
or docs (see `cppmodel:update-dependencies` step 1). If nothing is pinned, use `latest_version`
from the probe.

If the project has no committed `install-cppmodel.*` script yet, offer to copy the template into
its `scripts/` folder. Teammates and CI (`cppmodel:ci-pipeline`) can then reuse it. Offer this;
don't do it silently.

## 6. Verify with a build

Configure and build with the chosen compiler set explicitly, so CMake doesn't pick up a different
one from PATH:

```
cmake -S . -B build -G Ninja -DCMAKE_C_COMPILER=<cc> -DCMAKE_CXX_COMPILER=<c++>
cmake --build build
```

Follow the project's own generator/preset if it has one (`CMakePresets.json`, its README). A
successful link is the real proof that the compiler and SDK match. This matters most for a
step-3 near match. If a near match fails to link, report the actual error, and offer the step-4
install of the exact compiler or the support email. Don't try linker workarounds.

Running the simulations (`ctest`) also needs credentials. Check for a `.env` at the project root
with `CPPMODEL_USERNAME`/`CPPMODEL_PASSWORD` (see
`cppmodel:simulation-testing`'s "Requirements"). If it's missing, stop after the build and tell
the user what to add. Don't run `ctest` without it; the resulting failures would look like
regressions when they aren't.

Querying results and posting inputs go through the plugin's `cppmodel` MCP server, which needs no
local build; mention that the user authenticates it once with `/mcp`. Only parameter sweeps need
the SDK's `cppmodel-tool`, and `cppmodel:parameter-sweep` builds it when first needed.
The SDK writes a `.cppmodeltoken` login cache into the directory a simulation runs from, so make
sure the project's `.gitignore` covers `.cppmodeltoken` along with `.env`.

## Report

Finish with:

- the detected platform
- the compiler and SDK archive chosen, and whether that's an exact or near match
- what was installed, and anything the user still has to run themselves
- where the SDK went
- the build result
- whether `.env` is in place

If the user took the support path, repeat the drafted email and the list of published compilers
for their OS.
