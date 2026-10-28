---
name: cppmodel:coding-standard
description: Offer and apply a coding standard - MISRA C or MISRA C++, or another one the customer names - when writing or changing controller (production/embedded) code, using the customer's own licensed copy of the rules rather than general knowledge, and remembering the choice per project. Use whenever controller code is written or modified - decoupling a component (cppmodel:decouple-component), fixing or re-tuning a controller found failing in simulation (cppmodel:simulation-testing, cppmodel:verification, cppmodel:experiment-reconcile), or writing new control logic - and when asked about MISRA compliance of controller code. Not for simulation-only code (plant models, simulation harnesses).
---

## When this applies

Controller code is the code that ships to the target: a decoupled component's module, the control
law, the state machine, and the code that calls them on the target. Use this skill before writing
or changing it.

Simulation-only code is out of scope: plant models, simulation harnesses, test-only fault
switches. It runs only on the PC and calls the CppModel SDK. Apply a standard there only if the
user asks.

## 1. Check the stored choice

Look in `.claude/cppmodel.local.json` at the project root for a `codingStandard` key:

```json
{
  "codingStandard": {
    "name": "MISRA C:2012",
    "rules": "/home/me/licensed/misra-c-2012-headlines.txt",
    "deviations": "docs/misra-deviations.md",
    "checker": "cppcheck --addon=misra"
  }
}
```

or `"codingStandard": "none"`. Use it silently if it's there: don't ask again. If `rules` names a
file that no longer exists or can't be read, say so and ask for the new location. Don't fall back
to general knowledge.

## 2. Otherwise, offer it once

Look first at what the project already does: a coding-standard section in its docs or
`CONTRIBUTING`, a static analyser configuration (cppcheck's `misra` addon, PC-lint/FlexeLint,
Polyspace, Helix QAC, Parasoft, clang-tidy), suppression or deviation comments in the controller
source, a deviation register. Name what you found in the offer.

Then ask with `AskUserQuestion`, using what you found as the hint:

- **MISRA C** (default suggestion for C controller code), in the edition and amendments they use.
- **MISRA C++** (for C++ controller code), in the edition they use.
- **Another standard** they name (CERT C, AUTOSAR C++14, a company standard).
- **None**: write the code in the project's existing style, as before.

Ask whether to remember the answer for this project.

## 3. Get the customer's own copy of the rules

MISRA documents are licensed per user. **Don't apply MISRA rules from general knowledge, and don't
quote, paraphrase or reproduce rule texts from memory.** Rule numbers, categories and wording
differ between editions and amendments, and a half-remembered rule is worse than none in a
compliance argument. Ask the user for the copy they hold:

- the MISRA PDF they bought;
- or a rule-texts file in the form their checker reads (e.g. the headline file cppcheck's `misra`
  addon takes with `--rule-texts=<file>`);
- or a company document that lists the rules, categories and approved deviations.

Ask for a path, rather than having the text pasted, so it stays where they keep it. Read only the
parts you need, when you need them, from that file (a PDF by its pages).

Licensing limits what you do with it:

- Never copy the rule texts into the project, a commit, the plugin, memory, a generated document,
  a page, or anywhere else that persists or is shared. Store only the **path** in
  `.claude/cppmodel.local.json`. Cite a rule by its number in code comments and reports, as the
  user's checker does, not by its text.
- If the path is inside the repository, check that `.gitignore` excludes it and say so if it
  doesn't. The user decides whether it may be committed.

If the user doesn't provide a copy, say plainly that the code won't be checked against MISRA. Then
offer to write it in the project's existing style and to run their own checker if they have one.
Never call code "MISRA compliant" without their rules and a checker run to back it.

Store the choice if asked (step 1's shape), merging with the keys already in the file, as
`cppmodel:language` does. If the project has a `.gitignore` that doesn't already exclude
`.claude/*.local.json`, mention it.

## 4. Write the controller code against their rules

- Read the rules that apply to what you're about to write: types and conversions, control flow,
  functions, pointers, memory, preprocessor, and so on, as their document groups them.
- Follow each rule's **category** and what their document says a category allows (which rules
  admit deviations, and how). Advisory guidance is followed unless the project says otherwise.
- Match the project's existing pattern for compliant code: fixed-width types, its own boolean
  type, how it writes deviations (a comment format, a register, checker suppressions). Don't
  invent a second convention.
- **Deviations**: don't add one on your own. If a rule can't reasonably be met (often in glue that
  calls a vendor API), stop and explain the rule number, where, why, and what a compliant
  alternative would cost. Record it only after the user agrees, in the project's deviation format.
- The decoupled shape from `cppmodel:decouple-component` (a pure function over one plain struct,
  no hardware, RTOS or dynamic memory) usually suits MISRA well. Keep it that way while making the
  code compliant.

Behaviour comes first. A compliance rewrite must not change what the controller does: rerun its
simulations (and verification rules, `cppmodel:verification`) and compare the executions before
and after through the workspace history (`what_changed`, then the signals; `cppmodel:simulations`).

## 5. Check with their checker, then report

- If the project has a checker configured, run it on the changed controller files only, with the
  user's rule-texts file if it takes one (e.g. `cppcheck --addon=misra` with a `misra.json` whose
  `args` give `--rule-texts=<their file>`). Don't install a checker or change its configuration
  without asking. Many rules can't be decided by reading code, which is why a checker run counts.
- Report: the standard and edition, the files covered, the checker and its result, the rules you
  checked by hand, any deviations (agreed or proposed), and what wasn't checked. Rules are cited by
  number only.
- No checker? Say which rules you applied by reading their document, and that a tool run is still
  needed before claiming compliance.
