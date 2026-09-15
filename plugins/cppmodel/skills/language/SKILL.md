---
name: cppmodel:language
description: Decide whether a new plant model or a brand-new simulation file should be written in C or C++, using any stored project preference first, otherwise detecting the project's existing convention or asking. Use from cppmodel:plant-model or cppmodel:simulation-testing right before scaffolding a new file - not for editing/debugging an existing one, whose language is already fixed by its file extension, and not for cppmodel:decouple-component.
---

## When this applies

Only when about to create a **new** file for simulation-only code: a plant model
(`cppmodel:plant-model`) or a brand-new simulation harness file (`cppmodel:simulation-testing`).

Never for `cppmodel:decouple-component`'s extracted controller module. That code is normally also
compiled into the real embedded target alongside the rest of the production controller source, so
it must match whatever language that production code already uses - almost always C, even in
projects whose simulations are C++ - not this preference. Simulation-only code (models,
simulation harness files) never ships to the target, so it's free to differ.

## 1. Check for a stored preference

Look for `.claude/cppmodel.local.json` at the project root:

```json
{ "language": "c" }
```

(or `"cpp"`). If it exists and has a `language` field, use it silently - don't ask again.

## 2. Otherwise, detect the project's existing convention

Look at the existing `models/` and `simulations/` folders (or wherever this project keeps them -
don't assume the path, the same way `cppmodel:plant-model` doesn't). Count `.c`/`.h` files versus
`.cpp`/`.hpp` files used for models and simulation harnesses specifically - not the
controller/production code under `sut`/`application*` or similar, which follows the embedded
target's language, a separate concern (see above). If one is clearly dominant (e.g. most existing
simulations are `.cpp`), that's the detected convention.

## 3. Ask, using the detection as a hint

Ask the user to confirm before generating anything, e.g.: "This project's simulations look mostly
C++ ([N] of [M] existing simulation files) - use C++ for this one too, or C?" If detection was
inconclusive (no existing simulations/models yet, or a near-even split), default the suggested
answer to **C**. Also ask whether to remember the choice so this isn't asked again next time.

## 4. Store it, if asked to remember

Write `.claude/cppmodel.local.json` (create the `.claude` directory first if it doesn't exist yet)
with `{ "language": "c" }` or `{ "language": "cpp" }`. If other keys already exist in that file,
merge into them rather than overwriting the whole file. The `.local.json` naming mirrors Claude
Code's own `settings.local.json` convention for personal, not-necessarily-committed preferences -
if the project has a `.gitignore` that doesn't already exclude `.claude/*.local.json`, mention
that to the user rather than silently deciding whether the file should be tracked.
