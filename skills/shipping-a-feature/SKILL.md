---
name: shipping-a-feature
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use at the ship gate once a feature passes verify and security, before committing or opening a PR, and at the end of every session - runs the blocking ship checklist, the post-ship monitor step, and the clean-restart handoff
---

# Shipping a feature

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

**Principle:** SHIP is a gate, not a ritual. Every unticked box is a reason not to ship.

## The SHIP checklist — every item needs evidence

- [ ] **The relevant part of `./init.sh` is all green** — fresh output, pasted into `progress.md`.
- [ ] **The diff review has run** — `Workflow({ name:'parallel-review' })` if opted in, or spawn an `Agent` review by hand. **0 confirmed P0s.**
- [ ] **The SECURITY gate passed** — `harness-kit:security-gate` has run, every applicable P0 green.
- [ ] **0 secrets in the client bundle** — `./init.sh secret`.
- [ ] **State updated** — `feature_list.json` status + the `doc` field; `progress.md` holds the evidence.
- [ ] **The dossier is finished** — `docs/features/<ID>-<slug>.md` with all 9 sections and a frontmatter matching `feature_list.json`, `./init.sh docs` green. At tier `lite`: tick this with one line of evidence in `progress.md` instead, and say why. See `harness-kit:writing-feature-dossier`.
- [ ] **Docs matching the diff (Diataxis)** — *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (the main flow), *Explanation* (why). Only write the parts the diff actually touches.
- [ ] **Worktree cleaned up** — if this feature was built in `.worktrees/<slug>` and is now merged: `git worktree remove .worktrees/<slug>`. Not applicable if built directly on the branch.
- [ ] **Commit/PR** carrying the feature id + the REQs covered; the PR body lists the `done_when` items that passed.

**Any** box still empty → do not ship. There is no "ship now, tick later".

## DevEx — 2 questions before shipping

- **TTHW:** clone a clean repo → how long until it runs? Are the README and `.env.example` sufficient?
- **Friction:** vague errors, missing scripts, hidden manual steps? Record them; fix them when cheap.

## Ripple into older features

Did this feature change the behaviour of an already-shipped F? Add a dated line to **section 8** of that F's dossier.
Right now, inside this SHIP.

## `reversible: false` at tier `strict` → L3

`./init.sh docs` prints `[WARN]` here rather than FAILing, because `reversible` is a field **you**
declare — turning it into a hard gate would only teach you to write `true`.

So the stopping rule lives here instead: seeing that warning, **stop and escalate L3**. Never decide
alone to ship something that cannot be undone. If the Homeowner approves, record that decision in
section 5 of the dossier, so the next reader finds the reasoning rather than just the consequence.

## MONITOR — after shipping

Shipping is not the end:

- Health check after deploy.
- Smoke test the main flow.
- Check the infrastructure: DB advisors, logs, error rate.
- Record the results in `progress.md`.
- Found a regression → open that F's dossier and read **section 9 (Rollback & Recovery)** before deciding:
  - revertible and the damage is spreading → roll back exactly as *How to revert* says, then open a fix feature
  - something under *CANNOT be reverted* is involved → **L3, stop, ask the Homeowner**
  - otherwise → forward-fix: **open a new fix feature**, never patch in place

  This is where section 9 pays for itself: written at SHIP so it can be read during an incident.

## End of Session — so the next session restarts clean

Before ending the session, even if the feature is unfinished:

1. **`feature_list.json`** — a status matching reality + the `doc` field if you just shipped.
2. **`progress.md`** — Current State + evidence (command output, not a summary). If a feature shipped this session, move its Log entry into `progress-archive.md` and leave a one-line pointer tagged `(shipped — see progress-archive.md)` — `./init.sh state` checks this.
3. **`session-handoff.md`** — Blockers, Files touched, **Recommended Next Step**.
   The Next Step must be concrete enough that the next session can act immediately: file names, command names, feature ids.
   "Continue F03" is not a next step.
4. **Memory** — record in the harness memory whatever **cannot be derived from the code**: architectural decisions that emerged, pitfalls hit, trade-offs chosen and why. Do not restate what the code already says.

## Red flags

| You think | Reality |
|---|---|
| "One box is unticked but it does not matter" | Every box is a gate. Tick them all or do not ship. |
| "I will write the dossier later" | `./init.sh docs` FAILs. And later never comes. |
| "The diff review costs tokens, skip it" | Cheaper than a P0 in production. |
| "Ship now, monitor later" | MONITOR is step 10, not an option. |
| "Small regression, just patch it in place" | Patching in place = no evidence, no dossier. Open a fix feature. |
| "'Continue F03' is a good enough next step" | The next session will spend half an hour rediscovering. Name the file and the command. |
| "Short session, skip the handoff" | Compaction does not care how long the session was. |
| "This P0 is minor" | A P0 is not minor. That is what P0 means. |
