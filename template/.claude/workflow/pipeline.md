# Extended pipeline — {{PROJECT_NAME}} (vibecode-kit + gaps)

The base is the 8-step vibecode-kit. What vibecode-kit lacks is added on top (measured against gstack):
**adversarial VERIFY, SECURITY gate, DevEx review, SHIP, MONITOR, Diataxis docs, guardrails, memory**.

```
SCAN → RRI → VISION → BLUEPRINT ─┐  (design approved)
                                  ▼
   BUILD(6) → VERIFY(7) → SECURITY(7.5) → DEVEX(7.6) → REFINE(8) → SHIP(9) → MONITOR(10)
     │guardrails   │adversarial   │STRIDE/OWASP   │TTHW      │        │gate   │post-deploy
```

For each feature in `feature_list.json`, go through BUILD→...→SHIP before moving to the next one.

---

## 6. BUILD — with guardrails
- Implement exactly the `scope` + `done_when`. Do NOT add beyond scope. A spec conflict → escalate L2/L3.
- **Live testing:** anything runnable must be *actually run* (curl the endpoint, open the app, build the artifact) — not just read.
- **`/freeze`:** while fixing a bug, touch only files belonging to the current feature.
- **`/careful`:** a destructive command → stop, confirm with the Homeowner.
- **Atomic commits:** one feature/bugfix = one tight commit, the message stating the reason + the feature id. A bugfix ships with a reproducing test.

## 7. VERIFY — adversarial (replacing one-directional self-review)
1. Run the relevant part of `init.sh` → all green, paste the output into `progress.md`.
2. **Refute pass (subagent):** the saved workflow **`adversarial-verify`** — see `subagents.md`. Pass `done_when` through `args.criteria`.
   Each criterion → a skeptic *trying to refute it* + a judge reproducing. **≥1 `confirmedFailures` → not done**, go back to BUILD.
   - Workflow not opted in → spawn an `Agent` (Explore) by hand in the same spirit.
3. **Requirement traceability:** every REQ in the Blueprint must map to a feature. Missing one → Open Question.

## 7.5 SECURITY gate (CSO)
Run the parts of the `security.md` checklist that apply to the feature. **Do not SHIP while any P0 remains.**

## 7.6 DEVEX review
- **TTHW (time-to-hello-world):** clone → how long until it runs? Are the README + `.env.example` sufficient?
- **Friction map:** vague errors, missing scripts, hidden manual steps → record them + fix when cheap.

## 8. REFINE
Allowed: editing text/content inside existing sections, fixing VERIFY/SECURITY issues.
Not allowed (go back to VISION): adding a feature, a major layout change, changing the stack, adding a module. → L3.

## 9. SHIP — gate + docs
Only ship when **all 9 boxes** are ticked — same granularity as `harness-kit:shipping-a-feature`,
so the two copies can be compared mechanically rather than by eye:
- [ ] **The relevant `init.sh` is all green** — fresh output, pasted into `progress.md`.
- [ ] **The diff review has run** — `parallel-review` (subagent) or a manual review. **0 confirmed P0s.** Tier `lite`: skip it and state the reason.
- [ ] **The SECURITY gate passed** — the applicable `security.md` checklist, 0 P0s.
- [ ] **0 secrets in the client bundle** — `./init.sh secret`.
- [ ] **State updated** — `feature_list.json` status + the `doc` field; `progress.md` holds the evidence.
- [ ] **The dossier is finished** — `docs/features/<ID>-<slug>.md`, all 9 sections, frontmatter matching `feature_list.json`, `./init.sh docs` green. Tier `lite`: one line of evidence in `progress.md` instead. Start from `docs/features/_TEMPLATE.md`.
- [ ] **Docs (Diataxis)** matching the diff: *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (the main flow), *Explanation* (why).
- [ ] **Worktree cleaned up** — if this feature was built in `.worktrees/<slug>` and is now merged: `git worktree remove .worktrees/<slug>`. Not applicable if built directly on the branch.
- [ ] **Commit/PR** stating the feature id + the REQs covered; the PR body lists the `done_when` items that passed.

The box count is a **constant 9 at every tier**. A tier changes *how* a box is ticked, never *how many*
there are — otherwise the count could not be pinned, and an item could be dropped without anything noticing.

**Ripple:** if the feature being shipped **changes the behaviour of an older F**, you must add a dated line to **section 8 (Updates)** of that older F's dossier — inside this SHIP, never deferred. A dossier that drifts from the code is worse than no dossier.

## 10. MONITOR — post-ship
- Health check after deploy.
- Smoke test the main flow.
- Check the infrastructure (DB advisors, logs, error rate).
- Record the results in `progress.md`.
- **A regression:** open that F's dossier and read **section 9 (Rollback & Recovery)** before deciding.
  - Revertible, and damage is spreading → roll back exactly as *How to revert* says, then open a fix feature.
  - Something under *CANNOT be reverted* is involved → **L3, stop, ask the Homeowner.** Never decide alone.
  - Otherwise → forward-fix: open a new fix feature, never patch in place.

  This is where section 9 pays for itself: written at SHIP so it can be read during an incident.

---

## Checkpoint gates (never skipped)
- **BUILD→VERIFY:** status DONE/DEFERRED with a reason; nothing left BLOCKED unresolved.
- **VERIFY→SECURITY:** the adversarial refute pass ran; traceability is complete.
- **SECURITY→SHIP:** 0 security P0s; 0 secrets in the bundle.
- **SHIP→next:** state updated + evidence + docs in sync + **the feature dossier written** (`./init.sh docs` green).

## Memory routine (every end of session)
Record in the harness memory whatever cannot be derived from the code: architectural decisions that emerged, pitfalls hit, trade-offs. Update `session-handoff.md` before stopping.
