# Design — Tier, Rollback, Frontmatter, Drift-lock for harness-kit

**Date:** 2026-08-04
**Status:** approved (awaiting an implementation plan)
**Scope:** `hooks/verify-gate.js`, `template/*`, `skills/*`, `tests/*`, `README.md`

---

## 1. The problem

Four remaining limitations, after checking the analysis against the real implementation:

1. **No rollback strategy.** Grepping the whole repo for `rollback|recovery|revert strategy`: 0 hits.
   The only path is forward-fix (`pipeline.md:58` — "a regression → open a new fix feature").
   Forward-fix cures code; it does not cure a migration that already ran, data already overwritten, or a webhook already fired.
2. **No workflow tiering.** Fixing a typo and changing authentication go through the same 7 gates and the same 8-section dossier.
3. **The dossier has no structured metadata.** The `_TEMPLATE.md:3` line (`> **Status:** … · **Date:** …`)
   already duplicated `status` from `feature_list.json`, but being unstructured, nobody could check it.
4. **The SHIP checklist is duplicated with nothing locking it.** And it **has already drifted** — see §5.

**Three initial observations were refuted after checking the code; recorded so we do not relitigate:**

| Observation | Why it is wrong |
|---|---|
| "The documentation is too large" | At runtime only `CLAUDE.md` (86 lines) + exactly 1 skill (57–120 lines) are loaded. The README never enters the agent's context. |
| "Dependency management is missing" | `feature_list.json` already has `dependencies`; `hooks/session-start:51-55` blocks a feature with unfinished deps. |
| "The agent has to remember the process itself" | `hooks/session-start` injects the state; `hooks/verify-gate` blocks writing `done` without evidence. Still open: `progress.md`, `session-handoff.md`. |

## 2. Decisions already settled

| Question | Settled | Reason |
|---|---|---|
| Who assigns `tier` | **The Homeowner assigns it; the agent may only raise it** | Reuses the existing mechanism (`verify-gate` blocking writes to `feature_list.json`) rather than inventing a new one |
| Which gates a tier skips | **Verify is never skipped.** Only the dossier cost + review change | Keeps tier something that **can be assigned wrongly while the system stays safe**; the `VERIFY OK` contract does not change by a single character |
| Where rollback lives | **Section 9 of the dossier, appended at the end.** `Updates` stays as section 8 | In harness-kit, anything without a validator does not exist |
| What the frontmatter holds | **Replaces the old metadata line.** 3 mirrored fields with a gate + 5 dossier-owned fields | No more duplication than today, but checkable for the first time |
| How drift is prevented | **A two-sided assertion (coverage + a count pin)**, not generation | The repo already has the right precedent: the `VERIFY OK` contract is held by assertions |

**Deliberately NOT doing (YAGNI):**

- `required_by` — derivable in reverse from `dependencies`; adding the field creates divergent state.
- A separate "Impact Analysis" section — sections 1, 4 and 6 already cover most of it.
- Inferring `tier` from the diff — that pushes the hardest part into `init.sh`, the very file users must customize.
- Auto-generating the frontmatter — `init.sh` must purely read and judge, never edit what it is grading.
- Automating rollback (revert scripts, health-check gates) — the harness orchestrates the agent, it does not run infrastructure.

## 3. Tier

### 3.1 Data model

A new field on each feature in `feature_list.json`:

```json
{ "id": "F03", "name": "Auth", "tier": "strict", "status": "pending" }
```

The scale: `lite` < `standard` < `strict`. **Absent = `standard`** — already-bootstrapped projects need to change nothing.

### 3.2 What a tier changes

| | `lite` | `standard` | `strict` |
|---|---|---|---|
| The relevant `init.sh` + secret grep | ✅ | ✅ | ✅ |
| Dossier | ❌ (one line of evidence in `progress.md`) | ✅ 9 sections | ✅ 9 sections |
| Section 9 Rollback | — | may be `—` | **must have real content** |
| `parallel-review` | ❌ | optional | ✅ |
| Security checklist | reduced (secret grep) | the relevant parts | full STRIDE |

The first row is invariant: verify runs at every tier. A mechanical consequence — `verify-gate` **need not know `tier` exists**
for the `status` rule, and there is no "lite passes without a marker" branch. If `lite` were exempt from verify, a
`lite` feature would never have a marker, forcing us to teach the gate an exception — and that exception is exactly
the loophole this whole architecture exists to close.

### 3.3 The blocking rule — a different kind from the `status` rule

The `status` rule is *conditional* (it blocks when the marker is missing) and **fails open** when the contract breaks
(`verify-gate.js:108-122`), because at that point no path exists for the agent to satisfy the gate.

The `tier` rule has no such property — a valid path always exists (do not lower the tier, or ask the Homeowner):

> **Block if the resulting tier of any feature is lower than its previous tier**, where "previous" = the tier on disk,
> or `standard` if the feature did not exist. **Independent of the marker. Never fails open.**

Deliberate consequences:

- An agent creating a new feature **does not write `tier`** → it falls back to `standard`.
- Writing `"tier": "lite"` on a new feature **is blocked** (lower than the default).
- Raising to `strict` **is always allowed** — the agent has exactly one direction of freedom: the one that tightens the process.
- Setting `lite` is an exemption, and an exemption needs a human signature: the Homeowner edits the file themselves.

### 3.4 How the hook computes the "resulting tier"

Inside the `pre-edit` branch of `hooks/verify-gate.js`, after the existing `status` check block:

- `Write` → take `tool_input.content`.
- `Edit` → read the file on disk and replace `old_string` with `new_string`.
- `MultiEdit` → apply each of the `edits` in order.

Parse the JSON on both sides and compare per `id`. A parse failure → **do not let it through** (following the precedent at `verify-gate.js:101`).

### 3.5 Who assigns the tier

`skills/planning-features` is edited to ask the Homeowner for the tier when creating a feature and to record the answer.
Because the gate blocks every value below `standard`, an answer of `lite` must be applied by a human editing the file.

## 4. Dossier — frontmatter + section 9

### 4.1 Frontmatter

Replace the blockquote line `_TEMPLATE.md:3` with:

```yaml
---
feature: F03          # mirror — must match feature_list.json
status: done          # mirror
tier: strict          # mirror
date: 2026-08-04      # dossier-owned
commit: a1b2c3d       # dossier-owned
blueprint: "§4.2"     # dossier-owned
security: passed      # dossier-owned
reversible: false     # dossier-owned — ties into section 9
---
```

The parser: a hand-written **flat** YAML reader inside `check_docs` — only `key: value`, no nesting, no lists.
Roughly 10 lines of node. No new dependency; harness-kit still needs only `node` + `bash`.

Parser rules, pinned down so the implementation need not guess:

- The frontmatter must be the first block in the file, opened and closed by exactly one `---` line.
- Every line is `key: value`. Blank lines and lines starting with `#` are skipped.
- Everything after ` #` (a hash preceded by a space) is stripped — an end-of-line comment.
  The `# mirror` comments in the example above are annotations belonging to this spec; the shipped `_TEMPLATE.md` does **not** carry them.
- Values are trimmed, and a surrounding pair of quotes is removed if present. No type parsing — `reversible: false` is compared
  as the string `"false"`.
- A missing frontmatter block, or a missing one of the three mirrored fields → FAIL.

The frontmatter uses `---`, so it collides with neither existing scan rule: the line-wise `## N.` scan, nor the ban on `<!--`.

### 4.2 Section 9

```markdown
## 9. Rollback & Recovery

**How to revert:** <concrete commands/steps — which commit to revert, which version to roll back, which flag to turn off>

**CANNOT be reverted:** <migrations already run, data already overwritten, webhooks/emails already sent, third-party caches — or "—">

**Signs a rollback is needed:** <observable symptoms, concrete thresholds — or "—">
```

The middle line is why this section exists. It is the one thing forward-fix cannot replace,
and the one thing people only think about when forced to write it down.

### 4.3 New rules in `check_docs`

| Condition | Behaviour |
|---|---|
| `tier: lite` + status `done`/`verified` | **skipped entirely** — no `doc` field required, no dossier scan |
| everything else | a dossier with all **9 sections** in order, no `<TODO:` placeholders, no `<!--` (the existing rules stay) |
| every scanned dossier | the frontmatter parses; `feature`/`status`/`tier` match `feature_list.json` |
| `tier: strict` | section 9 has real content — see the rule below |
| `tier: strict` + `reversible: false` | **print a warning, do NOT fail** — see §4.4 |

**The "real content" rule for section 9 (applies only at `tier: strict`).** The validator anchors on three fixed bold
labels — the same way it already anchors on the `## N.` headings:

- The body of section 9 must contain all three lines starting with `**How to revert:**`, `**CANNOT be reverted:**`,
  and `**Signs a rollback is needed:**`. A missing label → FAIL.
- `**How to revert:**` specifically must have content after the colon, and that content **must not be `—`**.
- The other two labels may be `—` (not every feature has an irreversible part).

At `tier: standard`, only the `## 9.` heading has to exist — the body may be `—`.

### 4.4 Why `reversible` is not a hard gate

`reversible` is a field **the agent declares itself**. Making it block the ship would only teach the agent to write `reversible: true`.
A self-declared field must never gate itself — which is precisely the principle `verify-gate` already applies
when it reads `init.sh` output rather than what the agent says.

So it splits into two layers:

- `init.sh` **prints a warning** on `strict` + `reversible: false`, without failing.
- `skills/shipping-a-feature` treats that combination as an **L3 escalation** — stop, ask the Homeowner.

The field's real value comes during an incident: answering "which features cannot be reverted" with a single grep.

## 5. Drift-lock for the SHIP checklist

### 5.1 Current state — already drifted

The SHIP checklist has **two** copies, not three:

- `pipeline.md:42-50` — 6 `- [ ]` boxes
- `skills/shipping-a-feature/SKILL.md:18-25` — 8 `- [ ]` boxes
- `CLAUDE.md:68-73` — **not** a SHIP checklist but the *Definition of Done*, at a different granularity

The other two have already drifted: the skill splits "SECURITY gate" and "0 secrets in the client bundle" into two boxes; the pipeline merges them.
The drift already happened, nobody had noticed. **Unify the granularity first, lock it second** — with nothing unified,
there is nothing to count.

### 5.2 The canonical list — 8 items

Take the skill's (finer) granularity as canonical and bring `pipeline.md` §9 into line:

| key | concept |
|---|---|
| `verify` | the relevant `./init.sh` is all green |
| `review` | the diff review ran, 0 confirmed P0s |
| `security` | the SECURITY gate passed |
| `secret` | 0 secrets in the client bundle |
| `state` | `feature_list.json` + `progress.md` updated |
| `dossier` | the dossier has all 9 sections, `./init.sh docs` green |
| `docs` | docs matching the diff (Diataxis) |
| `commit` | the commit/PR states the feature id + REQs |

The checklist keeps **8 boxes at every tier** — the box count is a constant, so the count pin in §5.3 means something.
The tier changes *how a box is ticked*, not *how many boxes there are*: at `lite`, the `dossier` box is ticked with a line of evidence in
`progress.md` instead of a dossier file, and the `review` box is ticked with "not applicable at this tier".
Both must state the reason when ticked — `lite` is not a licence to leave boxes blank.

### 5.3 The assertion — two sides

In `tests/run-tests.sh`, an array of 8 `key|regex` lines, then:

1. **Coverage** — each regex matches in **both** files. Catches "added an item in one place, forgot the other".
2. **The count pin** — the number of `- [ ]` lines in each file is exactly 8. Catches "added an item without declaring it in the canonical array".

Side 2 is the one with teeth. Coverage checks *"what I know about is present"*; the count pin checks *"nothing exists that I do not know about"*.

`CLAUDE.md` stays outside the lock (a different artifact). It only gets one standalone assertion: the `documented` line in
the Definition of Done must say **9 sections**.

## 6. Files to change — 15

**Mechanism (4)**

| File | Work |
|---|---|
| `hooks/verify-gate.js` | the tier-lowering rule in the `pre-edit` branch (§3.3, §3.4) |
| `template/init.sh` | rewrite `check_docs`: tier-aware, frontmatter, 9 sections, the `reversible` warning |
| `template/feature_list.json` | a `tier` field on the 3 sample features + `legend` + `_howto` |
| `template/docs/features/_TEMPLATE.md` | the frontmatter replacing line 3 + section 9 |

**Instructions (6)**

| File | Work |
|---|---|
| `template/CLAUDE.md` | the tier table; DoD `documented` → 9 sections; mention section 9 |
| `template/.claude/workflow/pipeline.md` | unify §9 to 8 boxes; note the tiers; a rollback step in MONITOR |
| `skills/planning-features` | ask the Homeowner for the tier when creating a feature |
| `skills/shipping-a-feature` | 9 sections; a tier-aware checklist; `reversible: false` → L3 |
| `skills/writing-feature-dossier` | frontmatter + section 9 |
| `README.md` | tier, rollback, frontmatter, drift-lock; "8 sections" → "9 sections"; the new assertion counts; a section on upgrading older projects |

**Tests (3)**

| File | Work |
|---|---|
| `tests/run-tests.sh` | the `valid_dossier()` fixture gains frontmatter + section 9; "8 sections" → 9; tier assertions (lite skipped, a mismatched mirror → fail, strict + an empty section 9 → fail); the two-sided drift assertion; `_TEMPLATE.md` has frontmatter + 9 sections |
| `tests/test-verify-gate.sh` | lowering the tier via `Write` → deny; via `Edit` → deny; a new feature set to `lite` → deny; raising to `strict` → allow; independent of the marker |
| `tests/eval-faithfulness.sh` | the `honest-pass` fixture updated to the new dossier definition |

**Untouched:** `tests/acceptance.sh` (the fixture features have no `tier` → they fall back to `standard`, behaviour unchanged),
`bootstrap.mjs` (stays pure copy + token replacement).

## 7. Implementation order — 3 chunks

The four points do not split into four independent parts: **rollback and frontmatter are coupled** through `reversible`,
and both are validated by the same rewrite of `check_docs`. Splitting them means editing `check_docs` twice.

| Chunk | Content | Depends on |
|---|---|---|
| **1. Tier** | the field + the `standard` default + the tier-lowering rule + `planning-features` | — |
| **2. Dossier schema** | frontmatter + section 9 + a tier-aware `check_docs` + `_TEMPLATE.md` | `tier` from chunk 1 |
| **3. Drift lock** | unify `pipeline.md` §9 + the two-sided assertion | "9 sections" settled in chunk 2 |

Each chunk ends green and can ship independently.

## 8. Previously bootstrapped projects

They inherit nothing automatically — `bootstrap.mjs` does not overwrite existing files. That is the correct behaviour: no upgrade
should silently turn a running project's `init.sh` red.

The README gains a short section on the manual upgrade path: re-run bootstrap with `--force` for `init.sh` and
`_TEMPLATE.md` only, then add the frontmatter + section 9 to existing dossiers. Anyone who does nothing keeps the 8-section behaviour.

## 9. Completion criteria

- [ ] `bash tests/run-tests.sh` green, with the assertion count up by exactly the number of new assertions.
- [ ] `bash tests/test-verify-gate.sh` green, with all 4 tier cases present.
- [ ] `bash tests/eval-faithfulness.sh` — `honest-pass` still green on both Sonnet and Haiku.
- [ ] `bash tests/acceptance.sh` — 5/5 unchanged.
- [ ] Bootstrap a clean project → a `lite` `done` feature demands no dossier; a `strict` `done` feature missing section 9 → `./init.sh docs` red.
- [ ] An agent trying to lower a tier from `strict` → `lite` is refused by `verify-gate`, even while a marker is present.

## 10. Risks

**The `honest-pass` probe in `eval-faithfulness.sh`.** It is the control and **must stay green** — without it,
a skill that refuses everything still scores 100%. It is green because the fixture matches the current definition of "a valid dossier",
and chunk 2 changes that definition. The fixture must be updated **inside chunk 2**, never deferred — otherwise the
"Sonnet 5/5, Haiku 5/5" figure in the README becomes false with nobody re-running it to find out.

**Tier becomes a new keyword for the agent to game.** Mitigated by design: the agent can only raise, never lower,
and even a wrongly assigned tier still runs the full `init.sh`. The worst damage from a wrong tier is thin documentation,
not unchecked code.

**`check_docs` grows.** It is currently ~30 lines of inline node in `init.sh`; adding a frontmatter parser,
the tier branches and the section 9 check pushes it to ~80 lines. Acceptable, but past that point it should be split into
`scripts/check-docs.mjs` — for the same reason `verify-gate.js` was once split out of the bash hook.
