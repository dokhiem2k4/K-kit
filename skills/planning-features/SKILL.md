---
name: planning-features
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use when turning an approved blueprint or a rough idea into entries in feature_list.json, when done_when is vague or untestable, or when the human asks to add/split/reorder features - every criterion must name a command or an observable
---

# Planning features

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

**Principle:** if `done_when` is wrong, every gate downstream is useless. Verify is only as strong as the criteria it checks.

This skill comes **before** BUILD. It turns approved design into machine-readable state.

## Before writing any feature

The harness assumes **the Blueprint exists and is approved**. It does not?

- Still unclear what to build or who for → it is not this skill's turn yet. Brainstorm first
  (`superpowers:brainstorming` if available), write the Blueprint, then come back.
- A Blueprint exists but is vague exactly where you are about to code → L2: ask the Homeowner, do not guess.

Do not use this skill to *invent* the product. It is for *translating* a product that is already settled.

## What a good feature looks like in `feature_list.json`

Required (the validator needs these): `id`, `name`, `description`, `status`.
Recommended: `scope`, `done_when`, `verify`, `dependencies`, `doc`.

```json
{
  "id": "F04",
  "name": "Password reset by email",
  "description": "A user forgot their password: they receive a link that expires in 15 minutes by email and set a new password.",
  "dependencies": ["F03"],
  "status": "pending",
  "doc": "docs/features/F04-password-reset.md",
  "scope": ["request-reset endpoint", "confirm-reset endpoint", "email template", "reset_token table"],
  "done_when": [
    "POST /auth/request-reset with a real email -> 202, one row in reset_token",
    "POST /auth/request-reset with an unknown email -> 202 (does not reveal which emails are registered)",
    "a token older than 15 minutes -> confirm returns 410",
    "reusing an already-used token -> 410"
  ],
  "verify": ["npm test -- auth/reset", "./init.sh", "./init.sh docs"]
}
```

## `done_when` must be testable — this is the easiest part to get wrong

Every criterion must be answerable by **one command** or **one observable action**.
The formula: **input condition → observable result**.

| Wrong | Why | Fix it to |
|---|---|---|
| "Auth works" | No command can prove it | "a protected endpoint with no token → 401" |
| "The UI looks good" | Not objectively observable | "the form shows a validation error directly under the offending field" |
| "Errors are handled well" | "Well" cannot be measured | "DB timeout → return 503 + retry-after, no stack trace leaked" |
| "Fast" | No threshold | "p95 < 300ms over 100 sequential requests" |
| "Tested" | Circular | "`npm test -- auth` green, covering all 4 cases above" |
| "Clean code" | Not a feature criterion | Drop it. That is review, not `done_when`. |

After writing each criterion, ask yourself: **"which command would prove this false?"**
No answer → that criterion is not usable yet.

## Remember the negative cases

`done_when` listing only the happy path is why the refute pass at VERIFY always finds something.
For any feature touching data or auth, add at least one criterion for:

- a missing / wrong / expired token
- another user's data
- empty / malformed / oversized input
- calling it a second time (idempotency)

## Sizing features correctly

- **Too big** — more than 6–7 `done_when` criteria, or a `scope` spanning unrelated layers → split it.
- **Too small** — cannot ship independently, does not deserve a dossier → fold it into the parent feature.
- A good measure: **one feature = one dossier that reads meaningfully**.

## `dependencies` and ordering

- Record only **real** dependencies: this F cannot be built or tested until that F is finished.
- Do not record a dependency just because "it makes sense to do it later" — that locks the schedule for no reason.
- No cycles allowed: A depends on B, B depends on A → re-split them.
- `active_feature` must point at a feature whose **every** dependency is `done`/`verified`.
  The session-start hook warns `DEPS NOT DONE` when it is not.

## Tracing back to the Blueprint

Every REQ in the Blueprint must be covered by **at least one** feature. Check both directions:

- A REQ no feature covers → a missing feature, or that REQ is out of scope (write that down).
- A feature mapping to no REQ → ask the Homeowner: is this scope creep, or is the Blueprint incomplete?

## Before finishing

- [ ] Every feature has `id`, `name`, `description`, `status`
- [ ] Every `done_when` survives the question "which command would prove this false?"
- [ ] Features touching data/auth have at least 1 negative case
- [ ] `dependencies` has no cycles and no fake entries
- [ ] `doc` points correctly at `docs/features/<ID>-<slug>.md`
- [ ] `active_feature` has all its dependencies finished
- [ ] Every Blueprint REQ is mapped

## Red flags

| You think | Reality |
|---|---|
| "Write `done_when` loosely now, tighten it later" | Later never comes. And verify will pass vacuously. |
| "This feature is obvious, skip `done_when`" | No criteria means nothing to verify. |
| "Code first, fix feature_list afterwards" | Fixing afterwards = rewriting criteria to match the code you wrote. Backwards. |
| "Splitting costs management overhead" | A huge feature = a meaningless dossier + an unreviewable diff. |
| "Add a dependency just to be safe" | Fake dependencies block work for no reason. Record only real ones. |
| "The Blueprint is vague but I get the idea" | L2. Ask. Guessing wrong here ruins the whole feature. |
| "Let VERIFY catch the negative cases" | VERIFY will catch them, and then you go back to BUILD. Write them now. |
