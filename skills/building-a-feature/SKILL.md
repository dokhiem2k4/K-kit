---
name: building-a-feature
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use before writing implementation code for a feature in a harness project - enforces scope boundaries from feature_list.json, live testing over code reading, and the escalation ladder when the spec is ambiguous
---

# Building a feature

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

**Principle:** `scope` and `done_when` in `feature_list.json` are the contract. Code outside the contract
is overreach, even when it is "obviously needed".

## Before typing the first line

- [ ] `harness-kit:harness-startup` has already run in this session.
- [ ] Read the feature's `scope` — that is the list of things you are allowed to touch.
- [ ] Read `done_when` — that is what you must get right, and nothing more.
- [ ] Read the corresponding Blueprint section.
- [ ] Read the **Invariants** section in `CLAUDE.md` — those hold no matter what the spec says.

## While building

**Live testing — mandatory.** Anything that can run must be *actually run*: curl the endpoint, open the app,
build the artifact, call the function in a REPL. Reading code and concluding "it will work" is not a test.

**A bugfix ships with a reproducing test.** Fix a bug with no test that was red before and green after, and the bug comes back.
If you cannot write a reproducing test → you do not understand the bug yet → invoke the debugging skill first.

**`/freeze`.** While fixing a bug in some F, touch only files inside that F's scope. Spot a bug elsewhere →
record it under Open in `progress.md`, do not fix it in passing.

**`/careful`.** Destructive commands (`rm -rf`, `DROP`, `TRUNCATE`, `force-push`, `reset --hard`,
deleting a migration, overwriting a file you have not read) → stop, ask the Homeowner. There is no "it is probably fine" exception.

**Atomic commits.** One feature/bugfix = one tight commit. The message states the **reason** + the feature id.

## The escalation ladder — do not decide at the wrong rung

| Rung | Examples | What to do |
|---|---|---|
| **L1** | Variable names, code style, import order, extracting a helper | Decide yourself, do not ask |
| **L2** | Vague spec, choosing between 2 patterns, a perf/readability trade-off | **Stop**, ask in the report, propose one option |
| **L3** | Changing scope / architecture / a business rule / anything touching security | **STOP**, escalate to the Homeowner, write no more code |

Mistaking an L3 for an L1 is the fastest way to have to rebuild the whole feature.

## Scope boundaries — what you may NOT do

- Add a feature not in `feature_list.json` (even if it is "only 5 lines").
- Change the architecture approved in the Blueprint.
- Refactor files outside the current feature's `scope`.
- Add a new dependency the Blueprint never mentions → L3.
- Fix an unrelated bug "while you are in there" → record it, do not fix it.

Found something that needs doing but is out of scope → write it under Open Questions in `progress.md`
and propose a new feature. Do not just do it.

## When you are finished

Do not mark `done` yourself. Invoke `harness-kit:verifying-a-feature`.

## Red flags

| You think | Reality |
|---|---|
| "This is obviously needed, just add it" | Obvious to you ≠ in scope. L3. |
| "Refactor it while I am here, keep it clean" | An out-of-scope refactor makes the diff unreviewable. |
| "I read the code, it is right, no need to run it" | Reading code ≠ live testing. Run it. |
| "This bug is one line, no test needed" | One-line bugs come back the most. |
| "The spec is vague, I will guess what the Homeowner meant" | Guessing turns an L2 into an L1. Ask. |
| "Fix the neighbouring bug while I am here" | `/freeze`. Just record it. |
| "`rm -rf` is quicker, I know what I am doing" | `/careful`. Ask. |
