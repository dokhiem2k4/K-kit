# Usage Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give harness-kit an append-only, per-session token-usage record — closing the gap where nothing today answers "how many tokens has this project cost so far," mirroring Pi's `AgentHarness` usage ledger.

**Architecture:** A new `Stop` hook (`hooks/usage-ledger` + `.js`) sums every `message.usage` object found in the turn's `transcript_path` and appends one cumulative-snapshot row to `.claude/usage-ledger.jsonl` on every agent turn. A shipped `template/.gitignore` covers the path for fresh bootstraps; `check_secret` in `template/init.sh` gets a mechanical, WARN-only fallback for projects whose own pre-existing `.gitignore` bootstrap could not touch.

**Tech Stack:** Bash (wrapper, matching `hooks/verify-gate`'s shape) + Node.js (`.js` logic) — no new dependency.

## Global Constraints

- **Hook event: `Stop`.** Fires after every agent turn — frequent enough that a crash mid-*next*
  turn still leaves the ledger current as of the last *completed* turn. (Spec §3)
- **`Stop` supports no `matcher` field** — confirmed against the official Claude Code hooks
  documentation during this plan's own research (`UserPromptSubmit`, `PostToolBatch`, `Stop`, and
  others are matcher-less; a present-but-unused `matcher` key is silently ignored). The `hooks.json`
  group for `Stop` omits `matcher` entirely, keeping the same `{ "hooks": [...] }` wrapper shape every
  other event in this file already uses.
- **Row semantics: cumulative snapshot per `Stop`, never a delta.** A session with 40 `Stop` events
  produces 40 rows, each superseding the last for that `sessionId`. No cursor, no double-counting
  risk. (Spec §3, §4)
- **Storage: in the repo, gitignored — `.claude/usage-ledger.jsonl`.** Not temp (unlike the
  session-checkpoint log) — this has standing analytical value across the whole project lifetime.
  (Spec §3)
- **Graceful degradation is load-bearing.** If zero `message.usage` objects are found in the
  transcript at all, write nothing — never a row of zeros, never a crash. The transcript's usage
  schema is empirically confirmed but **not a documented public contract**; this is the hook's
  only defense if that shape ever changes. (Spec §2, §4 step 4)
- **Tokens only — no dollar cost.** No model-price table exists in this codebase and none is added
  here. (Spec §3 YAGNI)
- **`.gitignore` coverage is layered, never assumed:** ship a default for fresh bootstraps
  (`template/.gitignore`) **and** a mechanical `[WARN]`-only check in `check_secret` for the projects
  that default cannot reach (an existing `.gitignore` bootstrap skipped). Never `[FAIL]` — a missing
  `.gitignore` line is a hygiene issue, not proof the current feature's code is wrong. (Spec §5)
- **Never denies anything.** No `deny` branch anywhere in this feature — same posture as
  `session-checkpoint` and `check_worktree`.

---

### Task 1: `hooks/usage-ledger` — sum transcript usage, append one row per `Stop`

**Files:**
- Create: `hooks/usage-ledger` (bash wrapper)
- Create: `hooks/usage-ledger.js` (sum + append logic)
- Modify: `hooks/hooks.json` (new `Stop` group)
- Modify: `tests/run-tests.sh` (new section; also add `hooks/usage-ledger` to the existing
  git-index-mode assertion loop)

**Interfaces:**
- Consumes: the `Stop` event JSON on stdin — fields `cwd`, `session_id`, `transcript_path` (all
  already relied on elsewhere in this codebase: `cwd`/`session_id` by `hooks/verify-gate.js`,
  `transcript_path` confirmed present on `Stop` by the official hooks docs during this plan's own
  research). Reads the file at `transcript_path`: JSONL, each line optionally shaped
  `{"message":{"usage":{"input_tokens":N,"output_tokens":N,"cache_read_input_tokens":N,"cache_creation_input_tokens":N}}}`
  (empirically confirmed against a real transcript during the spec's research — not from docs).
- Produces: `<cwd>/.claude/usage-ledger.jsonl`, one row per `Stop` event where at least one usage
  object was found:
  `{"t":ISO,"sessionId":string,"input":N,"output":N,"cacheRead":N,"cacheCreation":N}`.
  No other task in this plan reads this file (Task 2 only checks whether the *file exists* and
  whether it is *gitignored* — it never parses its content), so this row shape is not a
  cross-task contract, only an internal one.

- [ ] **Step 1: Write the failing tests in `tests/run-tests.sh`**

Append this new section immediately before the final `echo ""` / `echo "PASS=$PASSED  FAIL=$FAILED"`
block at the very end of the file:

```bash
echo ""
echo "== usage-ledger: write path (Stop) =="

# fire_usage <proj> <transcript-path> <session-id>
fire_usage() {
  node -e '
process.stdout.write(JSON.stringify({cwd: process.argv[1], transcript_path: process.argv[2], session_id: process.argv[3]}));
' "$1" "$2" "$3" | bash "$KIT/hooks/usage-ledger" >/dev/null 2>&1
}

mkdir -p "$KIT/.tmp-tests"
TR="$KIT/.tmp-tests/transcript-known.jsonl"
node -e '
const fs = require("fs");
const lines = [
  JSON.stringify({message:{usage:{input_tokens:10,output_tokens:20,cache_read_input_tokens:30,cache_creation_input_tokens:40}}}),
  JSON.stringify({message:{usage:{input_tokens:1,output_tokens:2,cache_read_input_tokens:3,cache_creation_input_tokens:4}}}),
  JSON.stringify({message:{role:"user"}}),
];
fs.writeFileSync(process.argv[1], lines.join("\n") + "\n");
' "$TR"

P="$(new_project)"
LEDGER="$P/.claude/usage-ledger.jsonl"
rm -f "$LEDGER"
fire_usage "$P" "$TR" "sess-known"
if [ -f "$LEDGER" ]; then ok "usage-ledger writes a row"; else ng "usage-ledger writes a row"; fi
if grep -qF '"input":11' "$LEDGER" 2>/dev/null && grep -qF '"output":22' "$LEDGER" 2>/dev/null \
   && grep -qF '"cacheRead":33' "$LEDGER" 2>/dev/null && grep -qF '"cacheCreation":44' "$LEDGER" 2>/dev/null; then
  ok "the row sums usage across every message correctly (10+1, 20+2, 30+3, 40+4)"
else
  ng "the row sums usage across every message correctly"
fi
if grep -qF '"sessionId":"sess-known"' "$LEDGER" 2>/dev/null; then ok "the row carries the session id"; else ng "the row carries the session id"; fi

TR2="$KIT/.tmp-tests/transcript-nousage.jsonl"
printf '%s\n' '{"message":{"role":"user","content":"hi"}}' '{"not":"an assistant message"}' > "$TR2"
P="$(new_project)"
LEDGER2="$P/.claude/usage-ledger.jsonl"
rm -f "$LEDGER2"
fire_usage "$P" "$TR2" "sess-nousage"
if [ -f "$LEDGER2" ]; then ng "a transcript with no usage objects -> nothing written"; else ok "a transcript with no usage objects -> nothing written"; fi

NH="$KIT/.tmp-tests/nh-usage"
rm -rf "$NH"; mkdir -p "$NH"
NHLEDGER="$NH/.claude/usage-ledger.jsonl"
fire_usage "$NH" "$TR" "sess-noharness"
if [ -f "$NHLEDGER" ]; then ng "no feature_list.json -> nothing written"; else ok "no feature_list.json -> nothing written"; fi
rm -rf "$NH"

if node -e '
const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const groups = (j.hooks || {}).Stop || [];
const found = groups.some(g => (g.hooks || []).some(h => /usage-ledger/.test(h.command || "")));
process.exit(found ? 0 : 1);
' "$KIT/hooks/hooks.json" 2>/dev/null; then
  ok "hooks.json registers Stop -> usage-ledger"
else
  ng "hooks.json registers Stop -> usage-ledger"
fi
```

Also extend the existing git-index-mode loop (find it by searching for
`for f in hooks/session-start hooks/session-checkpoint tests/run-tests.sh`):

```bash
  for f in hooks/session-start hooks/session-checkpoint tests/run-tests.sh tests/acceptance.sh template/init.sh; do
```
→
```bash
  for f in hooks/session-start hooks/session-checkpoint hooks/usage-ledger tests/run-tests.sh tests/acceptance.sh template/init.sh; do
```

- [ ] **Step 2: Run the suite to confirm the new section fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "usage-ledger"`
Expected: every new assertion fails — `hooks/usage-ledger` does not exist yet, so `fire_usage` writes
nothing and every `[ -f ... ]` check reports `ng`; the `hooks.json` registration check also fails.

- [ ] **Step 3: Write `hooks/usage-ledger.js`**

```js
// usage-ledger.js — append a cumulative token-usage snapshot after every agent turn.
// Invoked by hooks/usage-ledger: node usage-ledger.js < event.json
//
// Reads the Stop event JSON from stdin (fields: cwd, session_id, transcript_path). Sums every
// message.usage object found in the transcript and appends ONE row to .claude/usage-ledger.jsonl —
// a running total as of now, not a delta. A session with 40 Stop events produces 40 rows, each
// superseding the last for that sessionId.
//
// Never denies anything. Any error, or a transcript with zero usage objects, writes nothing and
// exits 0 silently — a silent ledger is an honest signal (the expected shape disappeared), not a
// crash or a row of fabricated zeros.
const fs = require("fs");
const path = require("path");

let inp = {};
try { inp = JSON.parse(fs.readFileSync(0, "utf8")); } catch { process.exit(0); }

const cwd = String(inp.cwd || process.cwd());
const sessionId = String(inp.session_id || "");
const transcriptPath = String(inp.transcript_path || "");

// Precondition: only track usage inside a harness project.
if (!fs.existsSync(path.join(cwd, "feature_list.json"))) process.exit(0);
if (!transcriptPath || !fs.existsSync(transcriptPath)) process.exit(0);

let lines;
try { lines = fs.readFileSync(transcriptPath, "utf8").split("\n").filter(Boolean); } catch { process.exit(0); }

const totals = { input: 0, output: 0, cacheRead: 0, cacheCreation: 0 };
let sawUsage = false;

for (const l of lines) {
  let entry;
  try { entry = JSON.parse(l); } catch { continue; } // a transcript being actively written to can end mid-line
  const usage = entry && entry.message && entry.message.usage;
  if (!usage || typeof usage !== "object") continue;
  sawUsage = true;
  totals.input += Number(usage.input_tokens) || 0;
  totals.output += Number(usage.output_tokens) || 0;
  totals.cacheRead += Number(usage.cache_read_input_tokens) || 0;
  totals.cacheCreation += Number(usage.cache_creation_input_tokens) || 0;
}

// Graceful degradation: if the transcript's expected usage shape has disappeared (a schema change
// this hook has no contract against), write nothing rather than a row of fabricated zeros.
if (!sawUsage) process.exit(0);

const row = JSON.stringify({
  t: new Date().toISOString(),
  sessionId,
  input: totals.input,
  output: totals.output,
  cacheRead: totals.cacheRead,
  cacheCreation: totals.cacheCreation,
});

try {
  const ledgerDir = path.join(cwd, ".claude");
  fs.mkdirSync(ledgerDir, { recursive: true });
  fs.appendFileSync(path.join(ledgerDir, "usage-ledger.jsonl"), row + "\n");
} catch { /* best-effort — never crash the Stop event over a ledger write failure */ }

process.exit(0);
```

- [ ] **Step 4: Write `hooks/usage-ledger` (bash wrapper)**

```bash
#!/usr/bin/env bash
# usage-ledger — appends a cumulative token-usage snapshot after every agent turn (Stop event).
#
# Registered in hooks/hooks.json under Stop (Stop supports no matcher — see hooks.json comment).
#
# Reads transcript_path (given in the event JSON), sums every message.usage object found, and
# appends ONE row representing this session's running total as of now — not a delta.
#
# The transcript's usage schema is NOT a documented public contract (verified empirically against
# a real transcript, not found in official docs). If the expected shape ever disappears, this hook
# writes nothing rather than wrong numbers — see usage-ledger.js.
#
# FAIL OPEN: with no node available the hook writes nothing and warns on stderr.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "harness-kit usage-ledger: no node — usage tracking is NOT active in this session." >&2
  exit 0
fi

# stdin (the event JSON) goes straight into node, same reason hooks/verify-gate does this: a
# heredoc would take over stdin and node could no longer read the event.
exec node "$SCRIPT_DIR/usage-ledger.js"
```

Make it executable:

```bash
chmod +x hooks/usage-ledger
```

- [ ] **Step 5: Wire it into `hooks/hooks.json`**

Find the closing of the `PostToolUse` array (added by the session-checkpoint plan):

```json
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-checkpoint\"",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ]
  }
}
```

Replace with a new top-level `Stop` key added after `PostToolUse` closes:

```json
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-checkpoint\"",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/usage-ledger\"",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ]
  }
}
```

(No `matcher` key on the `Stop` group — `Stop` supports none, and the docs confirm a present-but-
unused one is simply ignored, so omitting it is both correct and clearer than a misleading empty
string.)

- [ ] **Step 6: Run the suite to confirm the new section passes**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "usage-ledger\|git index"`
Expected: every new assertion prints `PASS`, including
`git index: hooks/usage-ledger is 100755` — that one only turns green once Step 7 stages the file
with its executable bit (`git ls-files -s` reads the index, not the working-tree permission bit).

- [ ] **Step 7: Commit**

```bash
git add hooks/usage-ledger hooks/usage-ledger.js hooks/hooks.json tests/run-tests.sh
git commit -m "feat(usage): add hooks/usage-ledger — cumulative token-usage snapshots per Stop event"
```

---

### Task 2: `.gitignore` coverage — shipped default + mechanical fallback

**Files:**
- Create: `template/.gitignore`
- Modify: `template/init.sh:85-97` (`check_secret`, restructured to always run the ledger-coverage
  check regardless of the client-bundle scan outcome)
- Modify: `tests/run-tests.sh` (new section)

**Interfaces:**
- Consumes: `.claude/usage-ledger.jsonl`'s mere *existence* on disk (never its content — Task 1's row
  shape is not read here) and `git check-ignore`'s exit code.
- Produces: nothing consumed by another task — this is the last task in the plan.

- [ ] **Step 1: Write the failing tests in `tests/run-tests.sh`**

Append this new section immediately after the one added in Task 1 (still before the final
`PASS=$PASSED  FAIL=$FAILED` block):

```bash
echo ""
echo "== usage-ledger: .gitignore coverage (check_secret) =="

# Reuses init_git_project(), already defined earlier in this file by the check_worktree tests —
# needed for the same reason: .tmp-tests/ sits inside harness-kit's own working tree, so without a
# repo of its own, git check-ignore would resolve against harness-kit's OWN .gitignore instead of
# the fixture's.

P="$(new_project)"
init_git_project "$P"
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "usage-ledger.jsonl exists but is not gitignored"; then
  ng "ledger file does not exist yet -> no warning"
else
  ok "ledger file does not exist yet -> no warning"
fi

# Simulates the real case this check exists for: a project that already had its OWN .gitignore
# before adopting harness-kit, so bootstrap.mjs's non-clobbering rule skipped ours (bootstrap.mjs:97).
P="$(new_project)"
rm -f "$P/.gitignore"
init_git_project "$P"
mkdir -p "$P/.claude"
echo '{"t":"x"}' > "$P/.claude/usage-ledger.jsonl"
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "usage-ledger.jsonl exists but is not gitignored"; then
  ok "ledger exists + no .gitignore coverage -> WARN"
else
  ng "ledger exists + no .gitignore coverage -> WARN"
fi
rc=0; bash "$P/init.sh" all >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "the .gitignore warning never blocks (still exit 0)"; else ng "the .gitignore warning never blocks (rc=$rc)"; fi

P="$(new_project)"
init_git_project "$P"
if [ -f "$P/.gitignore" ]; then ok "bootstrap ships a .gitignore"; else ng "bootstrap ships a .gitignore"; fi
if grep -qF '.claude/usage-ledger.jsonl' "$P/.gitignore" 2>/dev/null; then
  ok "the shipped .gitignore covers the ledger path"
else
  ng "the shipped .gitignore covers the ledger path"
fi
mkdir -p "$P/.claude"
echo '{"t":"x"}' > "$P/.claude/usage-ledger.jsonl"
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "usage-ledger.jsonl exists but is not gitignored"; then
  ng "a project whose .gitignore already covers it -> no warning"
else
  ok "a project whose .gitignore already covers it -> no warning"
fi
```

- [ ] **Step 2: Run the suite to confirm the new section fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "gitignore\|ledger exists\|ledger file does not exist"`
Expected: `"ledger file does not exist yet -> no warning"` and `"the .gitignore warning never
blocks"` already pass trivially (nothing exists yet to warn about, and a green run always exits 0);
every other new assertion fails — `template/.gitignore` does not exist yet (bootstrap ships no
`.gitignore` at all, so the "bootstrap ships a .gitignore" / "covers the ledger path" checks fail),
and `check_secret` has no ledger-coverage logic yet so the WARN case never fires.

- [ ] **Step 3: Create `template/.gitignore`**

```
.claude/usage-ledger.jsonl
```

- [ ] **Step 4: Extend `check_secret` in `template/init.sh`**

Current function (`template/init.sh:84-97`):

```bash
# P0 invariant: the client bundle must NOT leak secrets.
check_secret() {
  step "SECRET LEAK: grep client bundle"
  local found=0 scanned=0
  for d in "${CLIENT_DIRS[@]}"; do
    [ -d "$d" ] || continue
    scanned=1
    if grep -RniE "$SECRET_REGEX" "$d" 2>/dev/null; then
      echo "   [FAIL] SECRET in $d — must NOT ship"; found=1
    fi
  done
  [ "$scanned" -eq 0 ] && { skip "no client bundle to scan yet (${CLIENT_DIRS[*]})"; return; }
  [ "$found" -eq 1 ] && FAIL=1 || echo "   OK: 0 secrets in the client bundle"
}
```

Replace with:

```bash
# P0 invariant: the client bundle must NOT leak secrets.
check_secret() {
  step "SECRET LEAK: grep client bundle"
  local found=0 scanned=0
  for d in "${CLIENT_DIRS[@]}"; do
    [ -d "$d" ] || continue
    scanned=1
    if grep -RniE "$SECRET_REGEX" "$d" 2>/dev/null; then
      echo "   [FAIL] SECRET in $d — must NOT ship"; found=1
    fi
  done
  if [ "$scanned" -eq 0 ]; then
    skip "no client bundle to scan yet (${CLIENT_DIRS[*]})"
  elif [ "$found" -eq 1 ]; then
    FAIL=1
  else
    echo "   OK: 0 secrets in the client bundle"
  fi

  # The usage ledger (.claude/usage-ledger.jsonl) must never reach a commit — it is local session
  # cost data, not something the harness ships. WARN, not FAIL: a missing .gitignore line is a
  # hygiene issue, not proof the current feature's code is wrong (same reasoning as check_worktree).
  # Always runs, regardless of which client-bundle branch above fired — this check is independent
  # of whether there was a client bundle to scan at all.
  if [ -f .claude/usage-ledger.jsonl ] && command -v git >/dev/null 2>&1 \
     && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if ! git check-ignore -q .claude/usage-ledger.jsonl 2>/dev/null; then
      echo "   [WARN] .claude/usage-ledger.jsonl exists but is not gitignored — add it to .gitignore"
    fi
  fi
}
```

(The rewrite from `[ "$scanned" -eq 0 ] && { skip ...; return; }` to an `if/elif/else` is required,
not cosmetic: the original `return` would skip the new ledger-coverage check whenever there was no
client bundle yet, which is exactly the common case for a freshly bootstrapped project — the check
must run every time `check_secret` runs, independent of the client-bundle outcome.)

- [ ] **Step 5: Run the suite to confirm the new section passes**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "gitignore\|ledger exists\|ledger file does not exist"`
Expected: every assertion in this section prints `PASS`.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`.

- [ ] **Step 7: Commit**

```bash
git add template/.gitignore template/init.sh tests/run-tests.sh
git commit -m "feat(usage): ship template/.gitignore + a check_secret WARN for uncovered usage-ledger.jsonl"
```

---

## Completion checklist (matches spec §8)

- [ ] A synthetic transcript with known token counts, run through `hooks/usage-ledger` on a simulated
      `Stop` event, appends exactly one row whose sums match by hand-calculation.
- [ ] A transcript with no `usage` objects at all → no row is written, no crash.
- [ ] A non-harness project (no `feature_list.json`) → no row is written.
- [ ] A fresh bootstrap ships `.claude/usage-ledger.jsonl` already covered by `template/.gitignore`.
- [ ] A project with a pre-existing `.gitignore` that does *not* cover the ledger path, once the
      ledger file exists on disk → `./init.sh secret` (or `all`) prints `[WARN]`, never `[FAIL]`.
- [ ] `bash tests/run-tests.sh` green, with the new assertions counted.

Note: as with `check_worktree`'s "not a git repository" branch, this plan does not add a dedicated
test for `check_secret`'s ledger-coverage check when run **outside any git repository at all** — every
fixture under `.tmp-tests/` is, by construction, already inside harness-kit's own git working tree
unless explicitly given its own via `init_git_project`, so a "truly not a git repository" fixture
cannot be constructed without changing how `tests/run-tests.sh` itself is invoked.
