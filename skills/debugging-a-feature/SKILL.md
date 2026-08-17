---
name: debugging-a-feature
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use when a test fails, verify fails, a shipped feature regresses, or the fix loop in verifying-a-feature has spun twice - decides scope, state and dossier consequences; defers the debugging method itself to a debugging skill
---

# Debugging a feature

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

**This skill does not teach you how to debug.** It answers the questions the harness raises when a bug appears:
where to fix it, which feature it counts against, and what has to change in the state and the dossier.

**Debugging method:** use `superpowers:systematic-debugging` if it is available.
If not → at minimum follow the "Minimum method" section below. Do not jump straight to fixing.

## Step 1 — where does this bug belong

Answer this before editing a single line.

| Situation | How to handle it |
|---|---|
| A bug in the **currently active** feature | Fix it within that feature's scope. Do not change any status. |
| A bug in a `done`/`verified` feature that you just broke | Still the active feature's fault. Fix it, and add a line to **section 8** of the old F's dossier. |
| A pre-existing bug in a shipped feature, unrelated to current work | **Do not fix it in passing.** Open a new fix feature in `feature_list.json`. Record it in `progress.md`. |
| A bug somewhere entirely out of scope | Record an Open Question. Do not touch it. |

**`/freeze` is always on while debugging:** touch only files inside the current feature's scope.
Spot another bug along the way → record it, do not fix it in passing. A mixed diff cannot be reviewed,
and nobody can tell which change actually fixed the bug.

## Step 2 — read the dossier before reading the code

Is the bug in a shipped feature? Read `docs/features/<ID>-<slug>.md` first:

- **Section 6 (Pitfalls when editing)** — usually already names the exact thing you are about to break.
- **Section 4 (Under the hood)** — the main flow + files touched, so you need not rediscover them.
- **Section 5 (Decisions)** — what was **deliberately** not done. Plenty of "bugs" turn out to be settled out-of-scope decisions.

Skipping this step and then "fixing" something that was a deliberate decision is how you break a working feature.

## Minimum method (when no dedicated debugging skill is available)

1. **Reproduce** — one command that re-runs the bug. Not reproduced means not ready to fix.
2. **Narrow** — does the bug survive with less input? Find the smallest unit that is still broken.
3. **Explain** — write one sentence: *the cause is X, therefore Y happens*. Cannot write it means you do not understand it.
4. **Fix the cause** — do not patch the symptom, do not add a try/catch that swallows the error.
5. **Prove it** — the test is red BEFORE the fix and green AFTER. If you never saw it red, you do not know what it checks.

## Step 3 — a bugfix ships with a reproducing test

Mandatory. And you must see it **red** first:

```
write the test → run (MUST BE RED) → fix → run (MUST BE GREEN) → revert the fix → run (MUST BE RED AGAIN) → restore
```

Skip the revert step and you do not know whether the test really checks that bug.
Plenty of "regression tests" turn out to be green both before and after the fix.

Cannot write a reproducing test → you do not understand the bug → go back to step 2 of the method.

## Step 4 — update the state

- **`progress.md`** — what the bug was, the cause, the fix, the test output. This is what the next session needs.
- **`feature_list.json`** — open a fix feature if the bug belongs to a shipped F and is unrelated to current work.
- **Dossier section 8** — a shipped feature changed behaviour → add a dated line. Right now.
- **Dossier section 6** — did this bug expose a pitfall nobody had written down? Add it. That is how section 6 grows.

Then go back to `harness-kit:verifying-a-feature` and re-run the gate.

## When the fix loop has been spinning

`verifying-a-feature` counts the fix loops. Reaching loop 3 without passing means your assumption is wrong,
not that you have not fixed enough. Stop fixing — write down which assumption is wrong, or spawn a
clean-context subagent to re-read from scratch. Loop 5 is the breaker: escalate.

## Red flags

| You think | Reality |
|---|---|
| "I see the bug already, just fix it" | Not reproduced means you do not know it is the bug. |
| "Small bug, no test needed" | Small bugs come back the most. |
| "The test is green, no need to try reverting" | If you never saw it red, you do not know what it checks. |
| "Fix the neighbouring bug while I am here" | `/freeze`. Just record it. |
| "The bug is in an old F, fix it in passing" | No evidence, no dossier. Open a fix feature. |
| "Add a try/catch to make the error go away" | Swallowing an error is not a fix. The symptom disappears, the bug stays. |
| "Reading the dossier wastes time" | Section 6 usually names the exact thing you are about to break. |
| "Three fixes failed, try a fourth" | Loop 3 = wrong assumption. Stop fixing, re-read from scratch. |
