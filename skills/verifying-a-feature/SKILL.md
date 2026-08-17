---
name: verifying-a-feature
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use when you think a feature is finished and before marking it done/verified in feature_list.json - requires fresh command output as evidence, an adversarial refute pass over every done_when, and a bounded fix loop that escalates instead of spinning
---

# Verifying a feature

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

**Principle:** evidence first, claims second. Always.

```
NEVER CLAIM DONE WITHOUT AN EXIT CODE FROM THIS TURN
```

## The gate function — run it before every claim

```
1. IDENTIFY: which command proves this?  (take it from the feature's `verify` field)
2. RUN:      run that command IN FULL, fresh, never reuse an old result
3. READ:     read all the output, check the exit code, count the failures
4. COMPARE:  does the output actually confirm what you are about to say?
   - NO  → report the REAL state along with the output
   - YES → make the claim WITH the output as evidence
5. ONLY THEN may you say "done"
```

Skipping any step is lying, not verifying.

## Step 1 — mechanical evidence

Run the relevant part of `./init.sh` (usually `all`). **Paste the raw output into `progress.md`**,
do not summarize. A non-zero exit code → not done, go back to BUILD.

If `init.sh` prints SKIP or "(no ... script)" for a check this feature NEEDS — that is not a pass.
That is a check that did not run. Fix `init.sh`, or run it by hand and paste the output.

## Step 2 — the adversarial refute pass

One-directional self-review misses bugs systematically: you go looking for reasons to believe you are right.
The refute pass inverts that: go looking for an input that makes it wrong.

If `Workflow` is opted in → use the saved workflow `adversarial-verify`:

```
Workflow({ name:'adversarial-verify', args:{
  featureId:'F0X',
  criteria:[ ...done_when... ],
  securityChecks:[ ...from security.md... ]
}})
```

Not opted in → spawn an `Agent` (Explore) by hand in the same spirit: **default to REFUTED
unless you can positively establish the opposite**. For each `done_when`, go hunting for one of these:

- empty / malformed / oversized input
- another user's data
- a missing token, an expired token, another user's token
- a stale cache, or no cache at all
- lax CORS, a secret leaking into the client bundle
- untrusted input reaching a sink (SQL / shell / LLM prompt)
- a race between two requests
- **the code simply having never been built**

`confirmedFailures` >= 1 → **not done**, go back to BUILD.

## Step 3 — requirement traceability

Has every Blueprint REQ within this feature's scope been mapped to something in the code?
Missing one → record an Open Question, do not quietly move on.

## A bounded fix loop — do not spin

When verify fails, count the loops. Never repeat unbounded.

| Loop | What to do |
|---|---|
| 1–2 | Fix directly, re-run steps 1 + 2 |
| 3 | **Stop fixing.** Write down: which of your assumptions is wrong? Cannot answer → `harness-kit:debugging-a-feature` before fixing anything else |
| 4 | Spawn a fresh subagent (clean context) to re-read the feature from scratch — your context is contaminated with a wrong assumption |
| 5 | **BREAKER.** Stop. For each remaining finding: is it load-bearing? |
| | · Any load-bearing finding → report **BLOCKED** to the Homeowner, do not ship |
| | · Otherwise → record each finding + the reason for waiving it in `progress.md`, ask the Homeowner to approve |

Reaching loop 6 without escalating is your fault, not the code's.

## Only when all 3 steps are green

Update `feature_list.json` status → `done`, with the evidence in `progress.md`.
Then invoke `harness-kit:security-gate`.

`verified` is a different tier: only the Homeowner sets it, after running the real flow. You never set `verified` yourself.

## Red flags

| You think | Reality |
|---|---|
| "The build was green earlier, it still is" | Run it again. You just changed the code. |
| "Tests pass, skip the refute pass" | Tests check what you thought of. Refute finds what you did not. |
| "The subagent said OK" | Check independently. An agent's report is not evidence. |
| "A green linter means it builds" | A linter does not compile. Run the build. |
| "`init.sh` printed SKIP, treat it as a pass" | SKIP = did not run. Not a pass. |
| "Summarize the output to keep it short" | Paste it verbatim. Summarizing is where you hide the numbers. |
| "I am confident it is right" | Confidence ≠ evidence. |
| "Loop 5 already, but I am nearly there" | The breaker has tripped. Escalate. |
| "Just this once as an exception" | There are no exceptions. |
