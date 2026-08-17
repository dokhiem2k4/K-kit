---
name: harness-startup
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use at the start of every session in a harness project, when resuming work, when the human says "continue"/"carry on"/"pick up where we left off", or whenever you are unsure which feature is active - reads state files in a fixed order before any code is read or written
---

# Harness startup

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

**Principle:** read the state first, the code second. Code cannot tell you which feature is active,
what `done_when` says, or where the previous session stopped.

## Read in exactly this order

Finish all 5 steps before touching any code. Create one todo per step.

1. **`progress.md`** — Current State + the last evidence. This is "where things stand".
2. **`session-handoff.md`** — Blockers, Files touched, Recommended Next Step. This is "what the last session intended".
3. **`feature_list.json`** — take `active_feature`, read its `scope`, `done_when`, `verify`, `dependencies`.
4. **The Blueprint** (path in the `blueprint` field) — read the section covering the active feature.
5. **The dossier of any related feature** — see below.

## When reading a dossier is MANDATORY

About to touch a feature with status `done` or `verified`? Read `docs/features/<ID>-<slug>.md`
(path in the `doc` field) **before opening any code file**:

- **Section 4 (Under the hood)** — the main flow + the files-touched table. Saves a whole session of rediscovery.
- **Section 6 (Pitfalls when editing)** — invariants to preserve, hidden dependencies. This is what breaks the code if you skip it.

Skipping this step is the most common reason a working feature gets broken by the next one.

## Checks before starting

- [ ] Are **all** the `dependencies` of `active_feature` `done`/`verified`? If not → do not start, tell the Homeowner.
- [ ] Is `done_when` **testable**? Every criterion must be answerable by a command or an observable action. If not → fix `done_when` first, do not code first.
- [ ] Is any blocker waiting on the Homeowner in `session-handoff.md`? If a blocker affects this feature → ask, do not decide alone.
- [ ] What is the current status of `active_feature`? `in_progress` means work is already underway — find it in `progress.md`, do not start over.

## After reading

Report back to the Homeowner in **3 lines**: which feature you are on, what `done_when` is still missing, what the next step is.
Then invoke `harness-kit:building-a-feature`.

## Red flags

| You think | Reality |
|---|---|
| "Reading code is faster than reading state" | Code does not contain `done_when`. You will build against the wrong criteria. |
| "The last session was me, I remember" | The context was compacted. `progress.md` remembers; you do not. |
| "This feature is simple, skip the dossier" | Section 6 exists precisely because it is not simple. |
| "Reading 5 files costs too many tokens" | Cheaper than building the wrong thing and redoing it. |
| "`done_when` is vague but I get the idea" | Getting the idea ≠ being able to verify. Fix `done_when`. |
