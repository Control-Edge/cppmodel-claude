---
name: cppmodel:setup-environment
description: Set up a machine to build CppModel projects from scratch - detects the OS, architecture, C library, installed C/C++ compilers/toolchains and build tools, compares them against the SDK builds download.cppmodel.com actually publishes (one per OS and architecture), then lets the user pick an installed supported compiler, install one, or (for an unsupported OS/arch/compiler) draft a request to support@cedge.se listing what is available for their OS. Finishes by installing the missing packages and the matching CppModel SDK and verifying a build. Use when asked to install, set up, or prepare a CppModel development environment, or when asked which compiler to use with CppModel.
---

## What this sets up

Building a CppModel project needs three things on the machine:

1. **A supported C/C++ compiler.** From SDK 0.8 the SDK is one self-contained shared library per
   OS and architecture, and its only binary interface is C. Any compiler of the platform's
   supported family works with the same archive: GCC or Clang on Linux, MSVC or clang-cl on
   Windows (x64 also MSYS2's MinGW toolchains: UCRT64, CLANG64, MINGW64), Apple Clang on macOS.
   C++ simulations need C++17.
2. **Build tools**: CMake 3.21+ and a generator (Ninja, Make or Visual Studio), plus git, curl,
   and tar/unzip for fetching.
3. **The CppModel SDK itself**, extracted into the project's `dependencies/` folder. OpenSSL, zlib,
   the C++ runtime and the SDK's other dependencies are linked into it, so nothing else needs
   installing.

This skill is for **first-time setup**. If the project already has a populated `dependencies/`
folder and the user wants a newer SDK, use `cppmodel:update-dependencies` instead. That skill
diffs headers and fixes call sites, which a fresh install doesn't need. A project whose
`CMakeLists.txt` links `CppModelBase` (or `crypto ssl z`) was written for an SDK before 0.8: use
`cppmodel:update-dependencies` for it too, since moving it to 0.8 changes the build files.

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
- `libc` (Linux): `glibc <version>`, `musl`, or `unknown`
- `compiler=<family> <major> <full version> <path>` (Linux/macOS; family is `gcc`, `clang`, or `appleclang`)
- `toolchain=<MSVC|CLANGCL|UCRT64|CLANG64|MINGW64> ...` (Windows), plus `msys2`, `visual_studio`,
  and `path_compiler` (what a bare `cmake` would find on the plain PATH)
- `tool=<name> <version|missing>`
- `latest_version`, and one `published=<platform tag>` per archive of that version, for all OSes

If the `.sh` reports `os=Windows` (Git Bash/MSYS2 shell), run the `.ps1` instead. Under WSL, the
machine is a Linux machine for this purpose. Windows compilers on the host can't build Linux code,
and the probe deliberately skips `/mnt/<drive>` PATH entries. If `published_status` isn't `ok`,
fetch `https://download.cppmodel.com/` yourself before going further. Never fall back to a
remembered list of what's published: the set changes between releases (0.8 replaced the
per-compiler archives with one per OS and architecture, for example).

## 2. Match the machine against what's published

Filter the `published=` tags down to this OS. Tag shapes from 0.8 on:

| OS | Tag | Requirements | Compilers |
|---|---|---|---|
| Linux | `Linux-x86_64`, `Linux-aarch64` | glibc 2.28+ | GCC, Clang |
| Windows | `Windows-x64`, `Windows-ARM64` | - | MSVC, clang-cl; on x64 also MinGW (MSYS2 UCRT64, CLANG64, MINGW64) |
| macOS | `macOS-universal` (arm64 + x86_64) | macOS 11+ | Apple Clang |

Treat that table as a hint about the shape, not the answer. Always use the live tags from step 1.

Then check, in this order:

- **The platform.** Is there a tag for this OS and `arch` (the probe prints `x86_64`/`aarch64` on
  Linux, `x64`/`ARM64` on Windows)? On Linux, is `libc` glibc 2.28 or newer? On macOS, is the
  version 11 or newer? Platforms with nothing published include Linux on armv7/i686/riscv64, musl
  distributions such as Alpine, glibc older than 2.28 (e.g. CentOS 7, Ubuntu 18.04), FreeBSD, and
  macOS 10.x. No compiler choice can fix that. Go straight to step 3's "request support" path.
- **The compilers.** Each detected compiler is **supported** when its family is listed for the
  OS and architecture, or **unsupported** otherwise (on Windows ARM64: the MinGW toolchains; on
  x64 the probe's `UCRT64`, `CLANG64` and `MINGW64` toolchains are supported). Versions don't need to match anything. Only C++17 matters: any GCC or Clang a
  glibc-2.28 distribution ships is new enough, and so is any Visual Studio 2019 or later. A C-only
  project needs nothing beyond a C compiler of a supported family.

## 3. Present the options - let the user choose

Start by showing a short summary:

- OS, arch, distro/version, and on Linux the glibc version
- each detected compiler, supported or not
- missing tools
- **the archive this machine uses** (e.g. `CppModel-0.8.0-Linux-x86_64.tar.gz`) and the compilers
  it supports

Then ask with `AskUserQuestion`. Build the options from what was actually found, most suitable
first, and put `(Recommended)` on the one you'd pick:

1. **Use an installed supported compiler.** With several (e.g. GCC and Clang, or MSVC, clang-cl
   and MSYS2 UCRT64), make each one its own option. Don't pick between them silently.
2. **Install a supported compiler.** Offer this when none is installed. Name the one that's easiest
   to get on this OS (the distro's own `g++`, Visual Studio Build Tools, Xcode's command line tools)
   and the exact package.
3. **Request support for my compiler/platform.** Offer this whenever the platform has no archive,
   or the only installed compilers are unsupported (e.g. MinGW only on Windows ARM64) and the user wants to keep
   using them.

Special cases:

- If there's exactly one supported compiler and every tool is present, skip the question. State
  the choice and continue to step 5.
- Windows x64 with only MSYS2 installed: its UCRT64, CLANG64 and MINGW64 toolchains use the same
  `Windows-x64` archive as MSVC (only C crosses the DLL boundary, and the DLL carries its own CRT),
  so use one of them. Prefer UCRT64 (or CLANG64) over MINGW64, which uses the old msvcrt.
- Windows ARM64 with only MinGW installed: there's no MinGW support on ARM64. Recommend installing
  Visual Studio Build Tools (MSVC, optionally with clang-cl), and offer the support request as the
  alternative.

### The "request support" path

Don't send email yourself. Draft the message for the user to send to **support@cedge.se**, filled
in from the step-1 output:

```
To: support@cedge.se
Subject: CppModel SDK request: <OS> <arch> <compiler + version>

Hello,

I'd like to use CppModel on a platform/compiler that has no prebuilt SDK at download.cppmodel.com:

- OS: <os_pretty> (<arch>, <libc>)
- Compiler: <family> <full version> (<path>)
- CppModel version wanted: <latest_version, or the version the project pins>
- Project/use case: <one line - ask the user, or leave a placeholder>

Currently published for <OS>: <list, or "nothing">.

Is a build for this configuration available or planned?
```

Afterwards, tell the user which supported compilers they could install meanwhile to get working
today (step 4's commands for this OS). Offer to continue with one of them. Don't stop at the
email.

## 4. Install what's missing - show commands, confirm, then run

List every package the chosen option still needs (compiler, build tools) as the exact commands for
this OS's package manager. **Check availability before proposing a package**, using
`apt-cache policy <pkg>`, `dnf list --available <pkg>`, `pacman -Ss <pkg>`, `brew info <pkg>`, or
`winget search <id>`. Package names differ between distro releases. The lines below are starting
points, not guarantees.

These commands change the system, so get explicit confirmation before running them. Most need
`sudo`/admin rights. If `sudo -n true` fails, don't try to supply a password. Give the user the
commands to run themselves (in Claude Code they can prefix one with `!`), then re-run the probe to
confirm.

**Debian/Ubuntu (apt):** `sudo apt-get install -y build-essential cmake ninja-build git curl`
(`clang` instead of, or as well as, `build-essential`'s GCC if the user prefers it). Debian 10 and
Ubuntu 20.04 ship CMake older than 3.21: get a newer one from Kitware's apt repository or
`pip install cmake`, and call out a third-party repository as a separate thing to confirm.

**Fedora/RHEL/Rocky (dnf):** `sudo dnf install -y gcc gcc-c++ cmake ninja-build git`. On RHEL 8
family, `cmake` may be older than 3.21; the `cmake` from AppStream updates or `pip install cmake`
fixes that.

**Arch (pacman):** `sudo pacman -S --needed base-devel cmake ninja git`.

**macOS:** `xcode-select --install` (Apple Clang), then `brew install cmake ninja`.

**Windows (MSVC/clang-cl):** Visual Studio Build Tools with the C++ workload
(`Microsoft.VisualStudio.Workload.VCTools`; look up the current package id with
`winget search Microsoft.VisualStudio`). For clang-cl, also add the "C++ Clang tools" component, or
install `LLVM.LLVM`. CMake and Ninja come with the workload, or as `Kitware.CMake`/`Ninja-build.Ninja`.
Build from a Developer PowerShell/Command Prompt so `cl`/`clang-cl` are on PATH, or use a Visual
Studio generator, which finds MSVC itself. On Windows on ARM, install the ARM64 build tools
component to build native ARM64 binaries.

**Windows x64 (MSYS2 MinGW):** in the MSYS2 shell for the chosen environment,
`pacman -S --needed mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja`
(`mingw-w64-clang-x86_64-*` for CLANG64, `mingw-w64-x86_64-*` for MINGW64). MSYS2 itself is
`winget install MSYS2.MSYS2`. Build from that environment's shell so its compiler and CMake are on
PATH.

After installing, re-run the step-1 probe and confirm the chosen compiler and tools now show up.

## 5. Install the CppModel SDK

Find where the project expects the SDK. Usually that's `dependencies/`: a 0.8+ project points
`CMAKE_PREFIX_PATH` at it before `find_package(cppmodel)`. Confirm by grepping `CMakeLists.txt`
for `find_package(cppmodel` and `CMAKE_PREFIX_PATH`. If the current directory isn't a CppModel
project yet, ask where to put it (and see "A new project" below).

Use the plugin's install templates, which handle the download, extraction, and layout flattening:

```
DEPS_DIR=<project>/dependencies VERSION=<version> bash "${CLAUDE_PLUGIN_ROOT}/scripts/templates/install-cppmodel.sh"
```

```powershell
& "${CLAUDE_PLUGIN_ROOT}\scripts\templates\install-cppmodel.ps1" -DepsDir <project>\dependencies -Version <version>
```

They pick the archive from the OS and architecture (`ARCH=`/`-Arch` overrides it, e.g. to fetch
the Windows ARM64 SDK on an x64 machine). For `VERSION`, use the version the project already pins
in CI or docs (see `cppmodel:update-dependencies` step 1). If nothing is pinned, use
`latest_version` from the probe. The templates install 0.8 or later only; a project pinned to an
older SDK needs `cppmodel:update-dependencies` first.

The SDK unpacks as `lib/` (the shared library; on Windows the import library), `bin/` (on Windows
`cppmodel.dll`, and `cppmodel-tool` everywhere), `include/cppmodel/` (`cppmodel.h`, `cppmodel.hpp`,
`CModel.h`, and the old header names), `include/nlohmann/`, `lib/cmake/cppmodel/` (the CMake
package; `cppmodelConfigVersion.cmake` holds the installed version), and `share/cppmodel/example/`.

If the project has no committed `install-cppmodel.*` script yet, offer to copy the template into
its `scripts/` folder. Teammates and CI (`cppmodel:ci-pipeline`) can then reuse it. Offer this;
don't do it silently.

### A new project

If there's no project yet, the build files are this skill's to start. The CMake shape every
CppModel 0.8+ project uses:

```cmake
cmake_minimum_required(VERSION 3.21)
project(<ProjectName> LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
enable_testing()

# The CppModel SDK, unpacked into dependencies/. Elsewhere: -DCMAKE_PREFIX_PATH=<unpacked SDK>.
list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_SOURCE_DIR}/dependencies")
find_package(cppmodel 0.8 REQUIRED)

# One block per simulation, added with the simulation itself (cppmodel:simulation-testing):
# add_executable(<Simulation> simulations/<Simulation>.c models/<Name>Model.c)
# target_link_libraries(<Simulation> PRIVATE cppmodel::cppmodel)
# cppmodel_deploy_runtime(<Simulation>)
# add_test(NAME <Simulation>Test COMMAND <Simulation>)
```

Don't link OpenSSL, zlib or IXWebSocket, and don't define `CPPHTTPLIB_*`: the SDK's library
carries them. `.gitignore` should cover `build/`, `dependencies/` (when the install script is
committed instead), `.env` and `.cppmodeltoken`.

## 6. Verify with a build

Configure and build with the chosen compiler set explicitly, so CMake doesn't pick up a different
one from PATH:

```
cmake -S . -B build -G Ninja -DCMAKE_C_COMPILER=<cc> -DCMAKE_CXX_COMPILER=<c++>
cmake --build build
```

On Windows with a Visual Studio generator, pass `-A x64` or `-A ARM64` instead of the compiler
(and `-T ClangCL` for clang-cl); executables then land in `build/<Config>/`, and `ctest` needs
`-C <Config>`. With MSYS2 MinGW, run the Ninja line from that environment's shell; pass
`CMAKE_PREFIX_PATH` as a Windows path (`-DCMAKE_PREFIX_PATH="$(cygpath -m "$PWD/dependencies")"`)
when it isn't set in `CMakeLists.txt`.

Follow the project's own generator/preset if it has one (`CMakePresets.json`, its README). A
project with no simulation yet can only configure, which still proves that `find_package(cppmodel)`
finds the SDK. The SDK's `share/cppmodel/example/` is a C and a C++ simulation that build on their
own (`cmake -S dependencies/share/cppmodel/example -B build/example
-DCMAKE_PREFIX_PATH=$PWD/dependencies`) if the user wants a full compile-and-link check; build it,
but don't run it, since every run is submitted to the workspace.

If the build fails, report the actual error. A link error mentioning `CppModelBase`, `ssl` or
`crypto` means the build files are from before 0.8: hand over to `cppmodel:update-dependencies`.
Don't try linker workarounds.

`cppmodel_deploy_runtime()` copies the library next to each executable, so the build folder runs
as it is. A simulation that fails to start with "cannot open shared object file
libcppmodel.so.1" (or a missing `cppmodel.dll`) was built without it.

With MSYS2 MinGW, it doesn't copy the compiler's own runtime DLLs (`libstdc++-6.dll`,
`libgcc_s_seh-1.dll`, `libwinpthread-1.dll`). Run from anywhere but that environment's shell, a
simulation then loads whichever copy comes first on PATH, such as Git for Windows', and exits at
once with `0xc0000139` and no message. Add `if(MINGW) add_link_options(-static) endif()` to
`CMakeLists.txt` after `find_package(cppmodel ...)`, so the simulations carry the runtime
themselves.

Running the simulations (`ctest`) also needs credentials. Check for a `.env` at the project root
with `CPPMODEL_USERNAME`/`CPPMODEL_PASSWORD` (see `cppmodel:simulation-testing`'s
"Requirements"). If it's missing, stop after the build and tell the user what to add. Don't run
`ctest` without it; the resulting failures would look like regressions when they aren't.

Querying results and posting inputs go through the plugin's `cppmodel` MCP server, which needs no
local build; mention that the user authenticates it once with `/mcp`. Runs with posted inputs and
parameter sweeps go through it too, so don't use the SDK's prebuilt `bin/cppmodel-tool` here. It's
only for CI jobs and scripts (`cppmodel:ci-pipeline`).
The SDK writes a `.cppmodeltoken` login cache into the directory a simulation runs from, so make
sure the project's `.gitignore` covers `.cppmodeltoken` along with `.env`.

## Report

Finish with:

- the detected platform
- the compiler and SDK archive chosen
- what was installed, and anything the user still has to run themselves
- where the SDK went
- the build result
- whether `.env` is in place

If the user took the support path, repeat the drafted email and the list of published archives
and supported compilers for their OS.
