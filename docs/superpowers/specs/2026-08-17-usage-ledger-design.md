# Design — append-only usage ledger (inspired by Pi's AgentHarness usage ledger)

**Date:** 2026-08-17
**Status:** approved (awaiting an implementation plan)
**Scope:** `hooks/usage-ledger` (new), `hooks/usage-ledger.js` (new), `hooks/hooks.json`, `template/.gitignore` (new), `template/init.sh`, `tests/*`

---

## 1. The problem

Pi's `AgentHarness` keeps an append-only usage ledger as one of its three durable stores — "the ledger
survives everything; billing never loses records, even if orchestration state aborts." harness-kit has
no equivalent at all: `progress.md` records evidence as free text, but nothing anywhere answers "how
many tokens has feature F03 cost so far" or "what did this whole project cost this month." That
question currently has no mechanical answer in a harness-kit project.

## 2. Feasibility — verified, not assumed

Claude Code hook events do **not** carry token/cost fields directly (confirmed against the hooks
documentation). But every hook event includes `transcript_path`, and that file — inspected directly
against a real, live transcript during this design's research — **does** carry per-turn usage:

```json
{"message":{"usage":{"input_tokens":2,"output_tokens":214,
  "cache_read_input_tokens":21484,"cache_creation_input_tokens":17512, ...}}, ...}
```

This is empirically confirmed (not merely inferred from docs), but the transcript file's schema is
**not documented as a stable public contract** — it is the internal conversation log format, and could
change across Claude Code versions without notice. This risk is carried forward explicitly into §7; the
design must degrade gracefully (§4 step 4) rather than assume the shape forever.

There is no `cost` (currency) field anywhere — only token counts. This ledger tracks **tokens**, not
dollars; converting to cost would require a model-to-price table this codebase has no reason to own.

## 3. Decisions already settled

| Question | Settled | Reason |
|---|---|---|
| Which hook event | **`Stop`** (fires after each agent turn completes) | Frequent enough that a crash mid-*next* turn still leaves the ledger current as of the last *completed* turn — closer to Pi's "commit after every step" than waiting for `SessionEnd`, which may not fire on a hard crash at all. |
| Storage location | **In the repo, gitignored: `.claude/usage-ledger.jsonl`** | Unlike the session-checkpoint log (crash-recovery only, ephemeral by nature — see `2026-08-17-session-checkpoint-design.md`), a usage ledger has standing analytical value across the whole project lifetime. Temp storage that can be wiped by a reboot would contradict the entire point of "survives everything." |
| Row semantics | **Cumulative snapshot per `Stop` event, not a delta** | See §4. Avoids needing a cursor into the transcript (which the session-checkpoint design needs for a different reason); trades a few redundant rows for a design with no way to double-count or under-count. |
| What happens if the transcript shape changes | **Fail open, write nothing, never crash the hook** | See §7. |

**Deliberately NOT doing (YAGNI):**

- Converting tokens to a dollar cost — no model-price table exists in this codebase to do it correctly;
  a wrong number is worse than no number.
- A report/dashboard command (`./init.sh usage` or similar) that summarizes the ledger — this spec
  only produces the raw ledger. A summarizer is a legitimate follow-up, not bundled here (YAGNI: no
  evidence yet that raw `jq`/`node -e` one-liners over the JSONL are insufficient).
- Delta-based rows (only the usage *since* the last `Stop`) — rejected in favor of the simpler
  cumulative-snapshot model (§2 of this table); revisit only if ledger file size becomes a real problem
  (unlikely — see §6, growth is bounded per session).
- Bootstrap.mjs changes to merge `.gitignore` into an existing project file — see §5; handled by
  shipping a template `.gitignore` for fresh projects plus a mechanical check for existing ones,
  matching the layered-defense pattern `verify-gate` already uses for its own contract (see
  `README.md`'s "Two signals, because one was not enough" / three-layer `VERIFY OK` contract sections).

## 4. Row semantics — cumulative snapshot, not a delta

Each `Stop` event:

1. Read `transcript_path` (given in the event JSON) in full.
2. Parse every line as JSON; **skip unparseable lines** (same torn-line tolerance as the
   session-checkpoint design — a transcript file being actively written to can end mid-line).
3. Sum `message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}`
   across every line where `message.usage` exists.
4. **If nothing summed (zero lines had a `usage` object at all) — write nothing.** This is the
   graceful-degradation path for §2's documented-schema risk: if Claude Code ever changes the
   transcript shape so `message.usage` no longer exists or is renamed, this hook goes silent rather
   than writing zeros or crashing. A silent ledger is a visible, honest signal (no new rows appearing)
   rather than a corrupted one.
5. Append one row to `.claude/usage-ledger.jsonl`:
   ```json
   {"t":"2026-08-17T10:22:31.000Z","sessionId":"<session_id>","input":12345,"output":6789,"cacheRead":98765,"cacheCreation":4321}
   ```
   This row is **this session's running total as of now**, not an increment. A session that has 40
   `Stop` events over its life produces 40 rows, each one superseding the last for that `sessionId`.

**Reading the ledger** (documented behavior, not built as tooling in this spec — see YAGNI): total
project usage = group rows by `sessionId`, take the row with the latest `t` per group, sum across
groups. A single line of `node -e` or `jq` does this; no dedicated script is justified yet.

## 5. `.gitignore` — layered, not assumed

`bootstrap.mjs` never overwrites an existing file (`bootstrap.mjs:97`), so if a target project already
has its own `.gitignore` (the common case — most repos do), a template `.gitignore` would silently be
skipped and `.claude/usage-ledger.jsonl` would never get ignored. Rather than teach `bootstrap.mjs` a
special "append instead of skip" case for exactly one file (new, untested branch in a script that must
stay simple), this is handled the same way the codebase already handles a fact that cannot be
guaranteed structurally: **ship the default, then verify it mechanically.**

1. `template/.gitignore` (new) — ships `.claude/usage-ledger.jsonl` (and nothing else; do not invent
   additional entries not asked for). Covers every **fresh** bootstrap with no pre-existing `.gitignore`.
2. A new step folded into `check_secret` in `template/init.sh` (it already exists to catch things that
   must never reach a commit): if `.claude/usage-ledger.jsonl` exists on disk **and**
   `git check-ignore -q .claude/usage-ledger.jsonl` fails (not ignored) → `[WARN]` (not `[FAIL]` — see
   the same reasoning as the worktree check: a missing `.gitignore` line is a hygiene issue, not proof
   the current feature's code is wrong).

This mirrors the worktree design's warn-only posture and the `VERIFY OK` contract's own layered
defense: a default that works for the common case, plus a mechanical check for the case it does not
cover, rather than a single point that must not fail.

## 6. Growth bound

A ledger row is written per `Stop` event, and `Stop` events are bounded by how many turns a single
Claude Code session has — sessions do not run forever, and each gets a fresh `sessionId`. There is no
compaction step in this spec (unlike `progress.md`'s Log — see the state-compaction design) because the
ledger is not read into any agent's context on a routine basis; it is an on-disk record consulted on
demand. Revisit only if a project's `.claude/usage-ledger.jsonl` is measured to actually cause a
problem (disk size, `git status` noise if ever accidentally tracked) — none of which this design
predicts will happen within any plausible project lifetime.

## 7. Files to change — 5

| File | Work |
|---|---|
| `hooks/usage-ledger` | new — bash wrapper, mirrors `hooks/verify-gate` (node check, fail-open, `exec`s the `.js` file so stdin reaches it intact) |
| `hooks/usage-ledger.js` | new — the logic in §4 |
| `hooks/hooks.json` | add a `Stop` hook group pointing at `usage-ledger` |
| `template/.gitignore` | new — `.claude/usage-ledger.jsonl` |
| `template/init.sh` | extend `check_secret` with the `.gitignore` mechanical check (§5.2) |

**Tests (folded into `tests/run-tests.sh`):** a synthetic transcript fixture file with known `usage`
values fed through `hooks/usage-ledger` via a crafted `Stop` event JSON → assert the summed row is
correct; a transcript with zero `usage` objects → assert nothing is written; a project missing
`.gitignore` entirely → assert `check_secret` stays quiet until `.claude/usage-ledger.jsonl` actually
exists on disk, then warns if it is not ignored; a project whose `.gitignore` does cover it → no warning.

**Untouched:** `hooks/verify-gate.js`, `hooks/session-checkpoint.js` (separate spec, separate hook,
no shared code beyond the same bash-wrapper shape both mirror from `hooks/verify-gate`).

## 8. Completion criteria

- [ ] A synthetic transcript with known token counts, run through `hooks/usage-ledger` on a simulated
      `Stop` event, appends exactly one row whose sums match by hand-calculation.
- [ ] A transcript with no `usage` objects at all → no row is written, no crash.
- [ ] A non-harness project (no `feature_list.json`) → no row is written.
- [ ] A fresh bootstrap ships `.claude/usage-ledger.jsonl` already covered by `template/.gitignore`.
- [ ] A project with a pre-existing `.gitignore` that does *not* cover the ledger path, once the ledger
      file exists on disk → `./init.sh secret` (or `all`) prints `[WARN]`, never `[FAIL]`.
- [ ] `bash tests/run-tests.sh` green, with the new assertions counted.

## 9. Risks

**The transcript schema is not a public contract.** This is the central risk of the whole design (§2).
Mitigated by: summing defensively (skip anything unparseable), writing nothing rather than wrong
numbers when the expected shape disappears (§4 step 4), and treating every number here as
harness-kit-observed, not Anthropic-guaranteed. If Claude Code changes the transcript format, this
hook goes quiet — it does not silently start lying.

**No cost, only tokens.** A team wanting a dollar figure will be disappointed; deliberately not solved
here (§3 YAGNI) rather than solved with a price table that goes stale the moment a provider changes
pricing.

**`.gitignore` coverage is probabilistic, not guaranteed**, for the reason in §5: bootstrap cannot
retrofit an existing file. The mechanical `[WARN]` is the actual guarantee; the shipped `.gitignore` is
only the common-case convenience on top of it.
