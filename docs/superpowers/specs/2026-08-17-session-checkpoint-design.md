# Design — PostToolUse session checkpoint (inspired by Pi's AgentHarness)

**Date:** 2026-08-17
**Status:** approved (awaiting an implementation plan)
**Scope:** `hooks/session-checkpoint` (new), `hooks/session-checkpoint.js` (new), `hooks/hooks.json`, `hooks/session-start`, `tests/*`

---

## 1. The problem

Pi's `AgentHarness` design commits atomically after every step (the "effect sandwich" — intent,
effect, settlement), so a crash mid-operation is recoverable by reading one register: exactly what
happened up to the last committed step is known, nothing more, nothing less.

harness-kit has no equivalent at the workflow layer. Its only durable state is what the agent
*chooses* to write: `feature_list.json.status`, `progress.md`, `session-handoff.md` — all updated by
convention, at "End of Session" or when the agent remembers to. If a session is cut off mid-BUILD
(context limit, disconnect, crash) before those files are touched, the next session's `hooks/session-start`
can only report the *last recorded* state (e.g. `status: in_progress`) — it has no way to know which
files were actually touched since then. The gap between "what `feature_list.json` says" and "what
actually happened on disk" is invisible.

## 2. Decisions already settled

| Question | Settled | Reason |
|---|---|---|
| Which tool calls to log | **Edit / Write / MultiEdit only** | These are the only tool calls that mutate files — the thing a stale handoff needs to reveal. `Bash` is excluded: too noisy (every `ls`/`cat` would log) and commands can carry secrets typed inline. |
| Where the log lives | **OS temp, keyed by a hash of the project's absolute path** — not `session_id` | A *new* Claude Code session (new `session_id`, e.g. reopened the next day) must still find the *previous* session's log for the same project. Keying by project path solves this without touching the repo or requiring a `.gitignore` change. Mirrors `hooks/verify-gate`'s existing marker directory (`${TMPDIR}/harness-kit-verify/`), just keyed differently. |
| How staleness is detected | **The log is self-anchoring**: the last entry whose `target` is `session-handoff.md` marks the last known-clean handoff. Everything after it is unreported. | `session-handoff.md` is itself an Edit/Write target, so it appears in the same log — no mtime comparison, no date parsing, no second source of truth needed. |
| Who blocks on this | **Nobody. Observational only.** | Unlike `verify-gate`, this hook never has a `deny` branch. It only informs; it never stops an Edit/Write from happening. |

**Deliberately NOT doing (YAGNI):**

- Logging `Bash` calls — rejected in scoping (see table above).
- Reconstructing *what changed* (diffs/undo) — out of scope. The log only answers "which files were
  touched," not "what changed in them." `git diff` already answers the second question once you know
  which files to look at.
- Cross-project aggregation, a dashboard, or any UI — this is a single JSONL file read by one hook.
- Persisting the log in the repo — rejected; temp matches the existing `verify-gate` marker precedent
  and needs no new `.gitignore` surface.

## 3. Data format

One JSON object per line, appended after every qualifying tool call:

```json
{"t":"2026-08-17T10:22:31.000Z","tool":"Edit","target":"src/foo.ts"}
```

- `t` — ISO-8601 timestamp.
- `tool` — `"Edit"` | `"Write"` | `"MultiEdit"`.
- `target` — the edited file's path, relative to the event's `cwd` (computed with `path.relative`,
  falling back to the raw `file_path` if it cannot be made relative — never throw over a path shape).

## 4. Write path — `hooks/session-checkpoint` + `hooks/session-checkpoint.js`

Mirrors `hooks/verify-gate` + `verify-gate.js` exactly: a thin bash wrapper (checks `node`, fails open
with a stderr warning if absent, `exec`s the `.js` file with stdin passed through — a heredoc cannot
be used here for the same reason documented in `verify-gate`: it would consume stdin before node can
read the event JSON) and a logic file that:

1. Reads the event JSON from stdin.
2. **Precondition: only logs inside a harness project.** Checks `feature_list.json` exists at
   `cwd` (matching `hooks/session-start`'s existing precondition). Not a harness project → exit 0,
   write nothing. This keeps the hook from polluting temp for every unrelated Claude Code project the
   user works in.
3. Computes the target path, appends one JSON line to
   `${TMPDIR:-/tmp}/harness-kit-verify/checkpoint-<sha1(absolute-project-path)>.jsonl`.
4. **A size safety net independent of the read-side truncation (§5):** if the file already has ≥500
   lines before appending, drop the oldest half before appending the new line. This bounds worst-case
   growth within a single very long session that never touches `session-handoff.md` — the read-side
   truncation in §5 only runs at `SessionStart`, so it cannot help mid-session.
5. Never denies anything; on any error (unreadable event JSON, unwritable temp dir), exit 0 silently.

## 5. Read path — extending `hooks/session-start`

No new hook event. The existing `SessionStart` hook already builds a `live_state` string via an
embedded `node -e` script (`hooks/session-start:31-64` in the current file). That script gains a
second block, gated behind the same `command -v node` check it already has:

1. Read `${TMPDIR:-/tmp}/harness-kit-verify/checkpoint-<sha1(absolute-project-path)>.jsonl` if it exists.
2. Parse each line as JSON. **A line that fails to parse is skipped, not fatal** — the same "torn
   final line" tolerance Pi's JSONL storage backend documents for exactly this failure mode (a hook
   killed mid-`appendFileSync`).
3. Find the **last** index `i` where `path.basename(entry.target) === "session-handoff.md"`.
   `i = -1` if no such entry exists yet (a brand-new project that has never had a handoff written).
4. `unreported = entries.slice(i + 1)`.
5. If `unreported.length > 0`: build one summary line, e.g.
   `!! 3 file(s) edited since the last session-handoff.md update: src/foo.ts (x2), src/bar.ts (x1)`,
   and append it to the injected context, in the same block as the existing `ACTIVE:` /
   `DEPS NOT DONE` lines. Silent when `unreported.length === 0` — matches the existing hook's behavior
   of staying quiet when there is nothing to report.
6. **Truncate on read, unconditionally:** rewrite the file to `entries.slice(Math.max(i, 0))` — drop
   everything strictly before the anchor (already fully superseded by that handoff), keep the anchor
   itself plus the just-reported tail (it stays "pending" until the *next* `session-handoff.md` write
   moves the anchor forward). No anchor found (`i === -1`) → nothing is dropped; nothing has been
   reported yet, there is nothing to consider stale.

This mirrors Pi's "cleanup is deletion" principle directly: the read-side is what performs the
cleanup, mechanically, on every session start — it does not depend on the agent remembering an
extra step, unlike the SHIP checklist's `git worktree remove` line.

## 6. Worked example

1. Session A edits `src/foo.ts` twice, `src/bar.ts` once, then updates `session-handoff.md`, then ends
   cleanly. Log: `[foo, foo, bar, session-handoff.md]`.
2. Session B starts. `hooks/session-start` finds the anchor at index 3 (the last entry). `unreported`
   is empty. No warning. Truncates to `[session-handoff.md]` (index 3 onward — just the anchor).
3. Session B edits `src/baz.ts`, then is killed by a context overflow before writing
   `session-handoff.md`. Log: `[session-handoff.md, baz]`.
4. Session C starts. Anchor is still at index 0 (`session-handoff.md`). `unreported = [baz]`. Prints:
   `!! 1 file(s) edited since the last session-handoff.md update: src/baz.ts (x1)`. Truncates to
   `[session-handoff.md, baz]` (nothing before the anchor to drop; `i = 0`).

## 7. Files to change — 4

| File | Work |
|---|---|
| `hooks/session-checkpoint` | new — bash wrapper, mirrors `hooks/verify-gate` |
| `hooks/session-checkpoint.js` | new — append logic (§4) |
| `hooks/hooks.json` | add a new `PostToolUse` group, matcher `Edit\|Write\|MultiEdit`, pointing at `session-checkpoint`. Does not touch the existing `verify-gate` group. |
| `hooks/session-start` | extend the embedded `node -e` script with the read/summarize/truncate logic (§5) |

**Tests (folded into `tests/run-tests.sh`, no new file):** feeding synthetic `PostToolUse` event JSON
into `hooks/session-checkpoint` (same pattern `tests/run-tests.sh` already uses for
`hooks/verify-gate post-bash` around line 280); asserting the log file is written with the right
shape; asserting the anchor/truncate/summary logic via `CLAUDE_PROJECT_DIR`-scoped `hooks/session-start`
invocations (same pattern already used for the existing "hook injects valid JSON..." assertions).

## 8. Completion criteria

- [ ] Editing a file via a simulated `PostToolUse` event appends exactly one well-formed JSON line.
- [ ] A project with no `feature_list.json` at `cwd` → the hook writes nothing.
- [ ] `SessionStart` after edits with no prior `session-handoff.md` entry → warns, lists the files.
- [ ] `SessionStart` after a `session-handoff.md` edit was the last entry → silent, no warning.
- [ ] After a `SessionStart` run, the log file no longer contains entries before the anchor.
- [ ] A corrupted/torn last line in the log does not crash `hooks/session-start`.
- [ ] `bash tests/run-tests.sh` green, with the new assertions counted.

## 9. Risks

**Never blocks — so it is easy to ignore.** Unlike `verify-gate`, there is no gate here, by design (§2).
The warning is informational; an agent under pressure could read past it. Mitigated the same way
`reversible: false` is: it is evidence surfaced automatically, not a decision made for the agent.

**Temp directory volatility.** A reboot or a `TMPDIR` clean between sessions loses the log — but at
that point the underlying Claude Code session is gone too (a new `session_id` either way in most such
cases), so the recovery scenario this addresses (a session cut off and resumed) is unaffected in
practice; only the rarer "machine rebooted mid-session, then resumed" case loses its checkpoint trail.
