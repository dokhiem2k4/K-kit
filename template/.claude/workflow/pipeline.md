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
Only ship when:
- [ ] The relevant `init.sh` is **all green**.
- [ ] `parallel-review` (subagent) — **0 confirmed P0s** on the diff.
- [ ] The SECURITY gate passed; 0 secrets in the client bundle.
- [ ] `feature_list.json` + `progress.md` updated (with evidence).
- [ ] The **feature dossier** `docs/features/<ID>-<slug>.md` is finished, all 8 sections present, `feature_list.json` has the `doc` field, `./init.sh docs` is **green**. Start from `docs/features/_TEMPLATE.md`.
- [ ] **Docs (Diataxis)** matching the diff: *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (the main flow), *Explanation* (why).
- The commit/PR states the feature id + the REQs covered; the PR body lists the `done_when` items that passed.

**Ripple:** if the feature being shipped **changes the behaviour of an older F**, you must add a dated line to **section 8 (Updates)** of that older F's dossier — inside this SHIP, never deferred. A dossier that drifts from the code is worse than no dossier.

## 10. MONITOR — post-ship
- Health check after deploy.
- Smoke test the main flow.
- Check the infrastructure (DB advisors, logs, error rate).
- Record the results in `progress.md`; a regression → open a new fix feature, never patch in place.

---

## Checkpoint gates (never skipped)
- **BUILD→VERIFY:** status DONE/DEFERRED with a reason; nothing left BLOCKED unresolved.
- **VERIFY→SECURITY:** the adversarial refute pass ran; traceability is complete.
- **SECURITY→SHIP:** 0 security P0s; 0 secrets in the bundle.
- **SHIP→next:** state updated + evidence + docs in sync + **the feature dossier written** (`./init.sh docs` green).

## Memory routine (every end of session)
Record in the harness memory whatever cannot be derived from the code: architectural decisions that emerged, pitfalls hit, trade-offs. Update `session-handoff.md` before stopping.
