# Design — State compaction and drift-lock for harness-kit (inspired by Pi's AgentHarness)

**Date:** 2026-08-17
**Status:** approved (awaiting an implementation plan)
**Scope:** `template/progress.md`, `template/session-handoff.md`, `template/scripts/*`, `template/init.sh`, `skills/shipping-a-feature/*`, `tests/*`, `README.md`

---

## 1. The problem

A comparison against `earendil-works/pi`'s `AgentHarness` design (a durable agent-session runtime; see
`packages/agent/docs/harness.md` in that repo) surfaced two real, observable issues in this repo's own
state files — not hypothetical ones:

1. **Unbounded read cost per session.** `template/progress.md`'s `## Log (newest first)` section grows
   forever: every feature that ships adds a permanent entry, even though the durable record of a shipped
   feature already lives in its dossier (`docs/features/<ID>-<slug>.md`, section 7 = evidence, section 8
   = updates). A session starting on project month 12 re-reads month-1 evidence that is already duplicated
   elsewhere, for no benefit. Pi's harness solves the equivalent problem with compaction: old context is
   summarized and only a `retainedTail` stays inline — "context never reads past a compaction."
2. **Duplicated, driftable state.** `progress.md` and `session-handoff.md` each carry their own free-text
   "Current Objective / Active feature" field, independent of `feature_list.json.active_feature` — the
   field `hooks/session-start` already reads mechanically to inject live state every session. Three
   places can disagree; nothing pins them together. This repo has already shipped a fix for exactly this
   bug class once (the SHIP-checklist drift-lock, `2026-08-04-harness-tier-rollback-design.md` §5), so the
   precedent for closing it — not generating one copy from another, but locking or eliminating the
   duplicate — is already established.
3. **Dead state left after an operation finishes.** `.worktrees/feat-tier-rollback` is a live example in
   *this* repo right now: the branch is merged into `main`, but the worktree directory is still on disk.
   Pi's harness deletes every register belonging to an operation the moment it finishes ("zero dead
   state"). `skills/shipping-a-feature/SKILL.md`'s SHIP checklist has no equivalent step.

**What this is explicitly not:** an attempt to bring Pi's runtime (durable registers, the effect
sandwich, crash recovery of an LLM tool-call loop) into harness-kit. That machinery answers "how does an
agent process survive a mid-tool-call crash," a question harness-kit has no access to — it governs a
workflow layered on top of Claude Code, not the token loop underneath it. The transferable part is
narrower and already proven in this repo: *one source of truth per fact, and delete what an operation no
longer needs.*

## 2. Decisions already settled

| Question | Settled | Reason |
|---|---|---|
| What happens to a shipped feature's Log entries | **Move to a new `progress-archive.md`**, leave a one-line pointer in `progress.md` | Keeps `progress.md` bounded by "features currently in flight," not by project age; nothing is lost, it just moves to where old evidence belongs |
| How compaction is enforced | **A script + a gate in `init.sh`**, not a skill instruction alone | Every other harness-kit rule with teeth (dossier, language, the SHIP-checklist count) works this way; an unchecked instruction is the one thing this repo's own history shows gets missed |
| How to remove the active-feature duplication | **Delete the field**, replace with a static reference line | `feature_list.json.active_feature` is already the source `hooks/session-start` reads; a field with nothing to fill in cannot drift |
| How to clean up a merged worktree | **A manual checklist line in `shipping-a-feature`**, not an automated script | Matches how every other SHIP item works — checklist + evidence, not an autorun git command taken on the agent's behalf |

**Deliberately NOT doing (YAGNI):**

- Touching `"Recommended Next Step"` in either file — it is a judgment call the agent writes, not raw
  data recoverable from `feature_list.json`, so it is not a real duplicate.
- An automated `./init.sh cleanup` that deletes worktrees itself — rejected in favor of the checklist
  line; revisit only if the manual step is repeatedly missed in practice.
- Any change to the LLM tool-call loop, context compaction, or crash recovery inside a single Claude Code
  session — out of scope for a workflow-layer harness.
- Enforcing that a pointer line, once written, must stay forever — the check only forbids an *untagged*
  full entry for a done/verified feature; it does not police what happens after that.

## 3. Log compaction — `progress.md` → `progress-archive.md`

### 3.1 Heading convention

Every Log entry tied to a feature must carry that feature's id in its heading, in a fixed, greppable
position:

```
### {{DATE}} — F03: Auth
```

When F03 ships (status `done`/`verified`, dossier written), the agent moves that entry's full body into
`progress-archive.md` and replaces it in `progress.md` with a one-line pointer carrying a fixed tag
string:

```
### 2026-08-17 — F03: Auth (shipped — see progress-archive.md)
```

The tag `(shipped — see progress-archive.md)` is the anchor `check-state.mjs` looks for — the same
fixed-string-anchor style `check-docs.mjs` already uses for section 9's three bold labels (§4.1 of the
2026-08-04 spec). Entries with no recognizable feature id (e.g. the template's initial "Harness setup"
entry) are never tied to a feature and are never checked.

### 3.2 `progress-archive.md` — new template file

A new file, structurally minimal — a header plus whatever entries get moved in:

```markdown
# Progress Archive — {{PROJECT_NAME}}

> Full Log entries for shipped features, moved out of progress.md to keep it bounded.
> The durable record is the dossier (docs/features/<ID>-<slug>.md); this file is a secondary,
> chronological reference for old evidence you do not want to open a dossier to find.
```

It ships empty. Nothing reads it mechanically except a human; `check-state.mjs` only ever *writes*
nothing to it and never requires it to exist (§4.2).

## 4. `scripts/check-state.mjs` + `./init.sh state`

### 4.1 Rule

For every feature in `feature_list.json` whose `status` is `done` or `verified`: scan `progress.md` for
heading lines matching `— <id>:` for that exact id (escaped before use in a `RegExp`, the same defensive
pattern `verify-gate.js` already uses when building patterns from untrusted input). Any such heading line
found **without** the fixed tag `(shipped — see progress-archive.md)` → `[FAIL]`, naming the id and the
offending line.

### 4.2 Edge cases, pinned down so the implementation need not guess

| Case | Behaviour |
|---|---|
| No done/verified features yet | `(nothing to archive yet — skip)`, exit 0 — mirrors `check-docs.mjs`'s `n === 0` branch |
| A done feature has **no** heading referencing its id anywhere in `progress.md` | Not a failure — already fully archived, or never had a Log entry. Nothing to check. |
| A done feature's heading is present and already carries the tag | Pass |
| `progress-archive.md` does not exist | Never checked directly — the rule only inspects `progress.md`. A missing archive file with an untagged entry still fails on the untagged-entry rule alone. |
| Two features share a heading (convention violation) | Out of scope — the checker does substring matching per id, same "screen, not proof" limit `check-lang.mjs` already documents about itself |

### 4.3 Wiring into `init.sh`

Follows the exact shape of `check_docs`/`check_lang` in `template/init.sh`:

```bash
check_state() {
  step "STATE (progress.md compaction for shipped features)"
  command -v node >/dev/null 2>&1 || { skip "no node — cannot validate progress.md compaction"; return; }
  [ -f feature_list.json ] || { skip "no feature_list.json"; return; }
  if [ ! -f scripts/check-state.mjs ]; then
    echo "   [FAIL] scripts/check-state.mjs is missing — the state validator was removed"
    FAIL=1
    return
  fi
  node scripts/check-state.mjs || FAIL=1
}
```

Added to the `case` dispatch as `state)`, and to the `all)` line alongside `check_scaffold`,
`check_build`, `check_secret`, `check_docs`. Usage comment on line 3 gains `state` in the target list.
This is a hard-FAIL-on-missing-script, not a SKIP, for the same reason `check_docs`/`check_lang` already
are: a counted SKIP still prints `VERIFY OK`, handing back a bypass.

## 5. Removing the active-feature duplication

`template/progress.md`'s `## Current State` block and `template/session-handoff.md`'s
`## Where things stand` block both currently carry a **filled-in** `**Current Objective / Active
feature:**` line. Both are replaced with one **static** line — not a field a session fills in, so there
is nothing left to go stale:

```markdown
> Active feature: see `feature_list.json.active_feature` — also surfaced automatically by the
> SessionStart hook at the top of every session.
```

`"Recommended Next Step"` is untouched in both files (§2, YAGNI). `template/CLAUDE.md`'s Startup
Workflow section already tells the agent to read `feature_list.json` for `active_feature` — no change
needed there beyond noting the two templates now point at it instead of repeating it.

## 6. Worktree cleanup — `shipping-a-feature`

One new line added to the SHIP checklist in `skills/shipping-a-feature/SKILL.md`, next to the existing
"State updated" item:

```markdown
- [ ] **Worktree cleaned up** — if this feature was built in `.worktrees/<slug>` and is now merged:
      `git worktree remove .worktrees/<slug>`. Not applicable if built directly on the branch.
```

This makes the SHIP checklist 9 boxes instead of 8. The drift-lock from the 2026-08-04 spec (§5.2–5.3 of
that spec) already asserts an exact count between `pipeline.md` and `shipping-a-feature/SKILL.md` — that
assertion's expected count must be updated to 9 in the same change, or the drift-lock itself goes red.
This is a real coupling, not incidental: touching the SHIP checklist always touches the count pin.

## 7. Files to change — 9

**Mechanism (4)**

| File | Work |
|---|---|
| `template/scripts/check-state.mjs` | new — the compaction validator (§4) |
| `template/init.sh` | add `check_state`, wire into `state` + `all`, update the usage comment |
| `template/progress.md` | Log heading convention note; remove the Active-feature field; add the reference line |
| `template/session-handoff.md` | remove the Active-feature field; add the reference line |

**New template file (1)**

| File | Work |
|---|---|
| `template/progress-archive.md` | new — empty archive template (§3.2) |

**Instructions (3)**

| File | Work |
|---|---|
| `template/CLAUDE.md` | mention `progress-archive.md`, the `state` target, and the reference-line convention |
| `skills/shipping-a-feature/SKILL.md` | End-of-Session: archive step for the just-shipped feature's Log entry; SHIP checklist: worktree-cleanup line (now 9 boxes) |
| `README.md` | 5-subsystems table gains `progress-archive.md` under State; `init.sh` target list gains `state`; SHIP-checklist count references updated 8 → 9 |

**Tests (1)**

| File | Work |
|---|---|
| `tests/run-tests.sh` | `check-state.mjs` exists; 3 fixture cases (nothing to archive → skip; done + untagged heading → fail; done + tagged heading → pass); `progress.md`/`session-handoff.md` no longer contain the old field name; `progress-archive.md` template exists; SHIP-checklist drift-lock count pin updated 8 → 9 |

**Untouched:** `hooks/verify-gate.js` (this design adds no new PreToolUse rule — compaction is checked
post-hoc by `init.sh`, exactly like the dossier), `bootstrap.mjs` (pure copy + token replacement, no
change needed).

## 8. Implementation order — 2 chunks

| Chunk | Content | Depends on |
|---|---|---|
| **1. Compaction mechanism** | `check-state.mjs` + `init.sh` wiring + `progress-archive.md` + the heading convention documented in `progress.md` | — |
| **2. De-duplication + cleanup** | remove the Active-feature fields, add the worktree checklist line, update the SHIP-checklist count pin | independent of chunk 1, but touches the same drift-lock assertion `tests/run-tests.sh` already has, so land both test edits together |

Each chunk ends green independently; nothing in chunk 2 depends on `check-state.mjs` existing.

## 9. Previously bootstrapped projects

Same story as every prior harness-kit change: `bootstrap.mjs` never overwrites an existing file, so an
already-bootstrapped project keeps its current `progress.md`/`session-handoff.md`/`init.sh` exactly as
they are — no `state` target, no compaction requirement, nothing silently turns red. Upgrading is
`bootstrap.mjs --force` (pulls in `init.sh`, `scripts/`, and the new `progress-archive.md` template) plus
manually re-applying local `CONFIG` edits to `init.sh` and manually removing the old Active-feature lines
from an existing project's `progress.md`/`session-handoff.md`.

## 10. Completion criteria

- [ ] `bash tests/run-tests.sh` green, with the assertion count up by exactly the number of new assertions.
- [ ] A fresh bootstrap: `progress.md` and `session-handoff.md` contain the static reference line, not a
      fillable Active-feature field.
- [ ] Marking a feature done/verified, then running `./init.sh state` with its Log entry still untagged
      in `progress.md` → `[FAIL]`; tagging it (or moving it to `progress-archive.md` and leaving the
      pointer) → the same run passes.
- [ ] `./init.sh` with no done/verified features at all → `state` prints "(nothing to archive yet)", not
      a FAIL and not a SKIP miscounted as one.
- [ ] The SHIP-checklist drift-lock (`pipeline.md` vs `shipping-a-feature/SKILL.md`) still asserts an
      exact match, now at count 9.

## 11. Risks

**Heading-convention detection is a screen, not a proof** — exactly the caveat `check-lang.mjs` already
states about itself. An agent that archives correctly but free-texts a differently shaped heading, or
that never used the `— <id>:` convention at all, will not be caught. Mitigated the same way the language
checker is: documented plainly as a limit, not sold as a guarantee.

**The SHIP-checklist count pin is now tightly coupled to this change.** §6 already flags this: the
9-box line item must land in the same commit as the drift-lock assertion update, or `run-tests.sh` goes
red for a reason unrelated to anything the implementer touched on purpose. Same shape as the risk the
2026-08-04 spec called out for the `honest-pass` fixture — a control that must move in lockstep with the
definition it is checking.

**A long-lived project could still let `progress-archive.md` grow unbounded.** Out of scope by design
(§2 YAGNI) — the goal here is bounding the *session-start read cost* (`progress.md`), not the total
history of the project. `progress-archive.md` is read on demand, not injected every session.
