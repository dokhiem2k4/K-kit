# Session Checkpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the next session mechanical evidence of which files were touched since the last `session-handoff.md` update, so a session cut off mid-BUILD (context limit, disconnect) is recoverable beyond "status was in_progress."

**Architecture:** A new `PostToolUse` hook (`hooks/session-checkpoint` + `.js`) appends one breadcrumb line per Edit/Write/MultiEdit to a project-keyed temp JSONL log. `hooks/session-start` (already the place `feature_list.json`'s live state gets injected every session) is extended to read that log, find the last `session-handoff.md` entry as an anchor, warn about anything after it, and truncate the log down to the anchor — mechanically, on every session start, no agent action required.

**Tech Stack:** Bash (wrapper, matching `hooks/verify-gate`'s exact shape) + Node.js (`.js` logic file + the embedded `node -e` block already inside `hooks/session-start`) — no new dependency.

## Global Constraints

- **Only `Edit`, `Write`, `MultiEdit` are logged.** `Bash` is excluded entirely — too noisy, and
  commands can carry secrets typed inline. (Spec §2)
- **The log lives in OS temp**, keyed by `sha1(path.resolve(project_dir)).slice(0,16)` — **not**
  `session_id`. A new Claude Code session for the same project must find the previous session's log.
  Directory: `${TMPDIR:-/tmp}/harness-kit-verify/checkpoint-<hash>.jsonl` — the same marker directory
  `hooks/verify-gate` already uses, just a different filename prefix. (Spec §2)
- **Observational only — never denies anything.** No `deny` branch anywhere in this feature. On any
  error (unreadable event JSON, unwritable temp dir, malformed log line), fail open and continue
  silently — never block the tool call it fires after, never break `hooks/session-start`. (Spec §2, §4.5)
- **Only logs inside a harness project** — gate on `feature_list.json` existing at the event's `cwd`,
  matching `hooks/session-start`'s existing precondition. Keeps this hook from polluting temp for every
  unrelated Claude Code project. (Spec §4.2)
- **Self-anchoring, no mtime, no date parsing.** Staleness is detected by finding the last log entry
  whose `target` is `session-handoff.md` — that file is itself a logged Edit/Write target, so the log
  anchors on itself. (Spec §2)
- Exact data format per line: `{"t":"<ISO-8601>","tool":"Edit"|"Write"|"MultiEdit","target":"<path
  relative to cwd>"}`. (Spec §3)

---

### Task 1: Write path — `hooks/session-checkpoint` logger

**Files:**
- Create: `hooks/session-checkpoint` (bash wrapper)
- Create: `hooks/session-checkpoint.js` (append logic)
- Modify: `hooks/hooks.json` (new `PostToolUse` group)
- Modify: `tests/run-tests.sh` (new section; also add `hooks/session-checkpoint` to the existing
  git-index-mode assertion loop)

**Interfaces:**
- Consumes: the `PostToolUse` event JSON on stdin — confirmed fields (verified against the official
  Claude Code hooks docs during this plan's own research, not assumed): `cwd` (string), `tool_name`
  (string, e.g. `"Edit"`), `tool_input` (object; `tool_input.file_path` for Edit/Write/MultiEdit — the
  same field `hooks/verify-gate.js`'s `pre-edit` mode already reads successfully today).
- Produces: `${TMPDIR:-/tmp}/harness-kit-verify/checkpoint-<hash>.jsonl`, one JSON line per qualifying
  tool call, in the exact shape Task 2 will read: `{"t":ISO,"tool":"Edit"|"Write"|"MultiEdit","target":relpath}`.
  The hash function (`sha1(path.resolve(projectDir)).slice(0,16)`, hex) must match exactly what Task 2
  computes from `PROJECT_DIR` — same algorithm, same slice length, both tasks compute it independently
  so this is the one detail that must not drift between them.

- [ ] **Step 1: Write the failing tests in `tests/run-tests.sh`**

Append this new section immediately before the final `echo ""` / `echo "PASS=$PASSED  FAIL=$FAILED"`
block at the very end of the file:

```bash
echo ""
echo "== session-checkpoint: write path (PostToolUse) =="

checkpoint_hash() {
  node -e 'const c=require("crypto");const path=require("path");console.log(c.createHash("sha1").update(path.resolve(process.argv[1])).digest("hex").slice(0,16))' "$1"
}
checkpoint_file() {
  echo "${TMPDIR:-/tmp}/harness-kit-verify/checkpoint-$(checkpoint_hash "$1").jsonl"
}
# fire_checkpoint <proj> <tool_name> <absolute-file-path>
fire_checkpoint() {
  node -e '
process.stdout.write(JSON.stringify({cwd: process.argv[1], tool_name: process.argv[2],
  tool_input: {file_path: process.argv[3]}}));
' "$1" "$2" "$3" | bash "$KIT/hooks/session-checkpoint" >/dev/null 2>&1
}

P="$(new_project)"
CF="$(checkpoint_file "$P")"
rm -f "$CF"
fire_checkpoint "$P" "Edit" "$P/src/foo.ts"
if [ -f "$CF" ]; then ok "session-checkpoint writes a log file"; else ng "session-checkpoint writes a log file"; fi
if grep -qF '"tool":"Edit"' "$CF" 2>/dev/null && grep -qF '"target":"src/foo.ts"' "$CF" 2>/dev/null; then
  ok "the log line has the right tool + relative target"
else
  ng "the log line has the right tool + relative target"
fi

NH="$KIT/.tmp-tests/nh-checkpoint"
rm -rf "$NH"; mkdir -p "$NH"
NHF="$(checkpoint_file "$NH")"
rm -f "$NHF"
fire_checkpoint "$NH" "Edit" "$NH/foo.txt"
if [ -f "$NHF" ]; then ng "no feature_list.json -> nothing written"; else ok "no feature_list.json -> nothing written"; fi
rm -rf "$NH"

P="$(new_project)"
CF2="$(checkpoint_file "$P")"
rm -f "$CF2"
fire_checkpoint "$P" "Bash" "$P/foo.txt"
if [ -f "$CF2" ]; then ng "Bash calls are never logged"; else ok "Bash calls are never logged"; fi

P="$(new_project)"
CF3="$(checkpoint_file "$P")"
mkdir -p "${TMPDIR:-/tmp}/harness-kit-verify"
node -e '
const fs = require("fs");
const lines = [];
for (let i = 0; i < 500; i++) lines.push(JSON.stringify({t:"2020-01-01T00:00:00.000Z",tool:"Edit",target:"f"+i+".ts"}));
fs.writeFileSync(process.argv[1], lines.join("\n") + "\n");
' "$CF3"
fire_checkpoint "$P" "Edit" "$P/new.ts"
lc="$(wc -l < "$CF3" | tr -d ' ')"
if [ "$lc" -gt 0 ] && [ "$lc" -le 251 ]; then
  ok "500-line cap halves the log before appending (now $lc lines)"
else
  ng "500-line cap halves the log before appending (got $lc lines, want 1-251)"
fi

if node -e '
const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const groups = (j.hooks || {}).PostToolUse || [];
const found = groups.some(g => g.matcher === "Edit|Write|MultiEdit" &&
  (g.hooks || []).some(h => /session-checkpoint/.test(h.command || "")));
process.exit(found ? 0 : 1);
' "$KIT/hooks/hooks.json" 2>/dev/null; then
  ok "hooks.json registers PostToolUse Edit|Write|MultiEdit -> session-checkpoint"
else
  ng "hooks.json registers PostToolUse Edit|Write|MultiEdit -> session-checkpoint"
fi
```

Also extend the existing git-index-mode loop (find it by searching for
`for f in hooks/session-start tests/run-tests.sh tests/acceptance.sh template/init.sh; do`):

```bash
  for f in hooks/session-start tests/run-tests.sh tests/acceptance.sh template/init.sh; do
```
→
```bash
  for f in hooks/session-start hooks/session-checkpoint tests/run-tests.sh tests/acceptance.sh template/init.sh; do
```

- [ ] **Step 2: Run the suite to confirm the new section fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "session-checkpoint\|500-line cap\|Bash calls"`
Expected: every new assertion fails. `hooks/session-checkpoint` does not exist yet — `bash "$KIT/hooks/session-checkpoint"` errors with "No such file or directory" on stderr (swallowed by `>/dev/null 2>&1` in `fire_checkpoint`), so no file is ever written and every `[ -f ... ]` check reports `ng`. The git-index-mode check for `hooks/session-checkpoint` also fails (`git ls-files -s` returns nothing for a file that does not exist, so `mode` is empty, not `100755`).

- [ ] **Step 3: Write `hooks/session-checkpoint.js`**

```js
// session-checkpoint.js — append a breadcrumb line after every Edit/Write/MultiEdit.
// Invoked by hooks/session-checkpoint: node session-checkpoint.js <marker-dir> < event.json
//
// Reads the PostToolUse event JSON from stdin. Writes ONE JSON line to a project-keyed log:
//   {"t": ISO timestamp, "tool": "Edit"|"Write"|"MultiEdit", "target": relative file path}
//
// Never denies anything — this hook only observes. Any error (unreadable event JSON, unwritable
// temp dir) exits 0 silently; a checkpoint log is a convenience, not a gate.
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const markerDir = process.argv[2];

let inp = {};
try { inp = JSON.parse(fs.readFileSync(0, "utf8")); } catch { process.exit(0); }

const cwd = String(inp.cwd || process.cwd());
const toolName = String(inp.tool_name || "");
const toolInput = inp.tool_input || {};

// Precondition: only log inside a harness project. Keeps this hook from polluting temp for every
// unrelated Claude Code project the user works in.
if (!fs.existsSync(path.join(cwd, "feature_list.json"))) process.exit(0);

if (!["Edit", "Write", "MultiEdit"].includes(toolName)) process.exit(0);

const filePath = String(toolInput.file_path || "");
if (!filePath) process.exit(0);

let target = filePath;
try {
  const rel = path.relative(cwd, filePath);
  if (rel) target = rel;
} catch { /* keep the raw path */ }

const hash = crypto.createHash("sha1").update(path.resolve(cwd)).digest("hex").slice(0, 16);
const logFile = path.join(markerDir, "checkpoint-" + hash + ".jsonl");

const line = JSON.stringify({ t: new Date().toISOString(), tool: toolName, target });

// Size safety net: the read-side truncation in hooks/session-start only runs at SessionStart, so a
// single very long session that never touches session-handoff.md could otherwise grow this file
// without bound. Cap it here too, independently.
try {
  let existing = [];
  if (fs.existsSync(logFile)) {
    existing = fs.readFileSync(logFile, "utf8").split("\n").filter(Boolean);
  }
  if (existing.length >= 500) existing = existing.slice(Math.floor(existing.length / 2));
  existing.push(line);
  fs.writeFileSync(logFile, existing.join("\n") + "\n");
} catch { /* best-effort — never block the edit that just happened */ }

process.exit(0);
```

- [ ] **Step 4: Write `hooks/session-checkpoint` (bash wrapper)**

```bash
#!/usr/bin/env bash
# session-checkpoint — appends a breadcrumb after every Edit/Write/MultiEdit, so a later session
# can tell which files were touched since the last session-handoff.md update.
#
# Registered in hooks/hooks.json under PostToolUse, matcher "Edit|Write|MultiEdit".
#
# Observational only: never denies anything, never blocks the tool call it fires after. The log
# lives in temp, keyed by a hash of the project's absolute path (not session_id) — a NEW Claude
# Code session for the SAME project must still find the PREVIOUS session's log.
#
# FAIL OPEN: with no node available the hook writes nothing and warns on stderr.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "harness-kit session-checkpoint: no node — checkpoint logging is NOT active in this session." >&2
  exit 0
fi

MARKER_DIR="${TMPDIR:-/tmp}/harness-kit-verify"
mkdir -p "$MARKER_DIR" 2>/dev/null || exit 0

# stdin (the event JSON) goes straight into node, same reason hooks/verify-gate does this: a
# heredoc would take over stdin and node could no longer read the event.
exec node "$SCRIPT_DIR/session-checkpoint.js" "$MARKER_DIR"
```

Make it executable:

```bash
chmod +x hooks/session-checkpoint
```

- [ ] **Step 5: Wire it into `hooks/hooks.json`**

Find the `PostToolUse` array's second group (the existing `Edit|Write|MultiEdit` matcher that calls
`verify-gate post-edit`):

```json
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/verify-gate\" post-edit",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ]
  }
}
```

Replace the closing of that array (add a new group after it, before `]` closes `PostToolUse`):

```json
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/verify-gate\" post-edit",
            "shell": "bash",
            "async": false
          }
        ]
      },
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

(Two separate groups sharing the same matcher — this does not touch the existing `verify-gate` group
at all, matching the spec's explicit decision to keep them independent.)

- [ ] **Step 6: Run the suite to confirm the new section passes**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "session-checkpoint\|500-line cap\|Bash calls\|git index"`
Expected: every new assertion prints `PASS`, including `git index: hooks/session-checkpoint is 100755`
— note this specific one only turns green after Step 7 stages the file with its executable bit, since
`git ls-files -s` reads the **index**, not the working-tree permission bit.

- [ ] **Step 7: Commit**

```bash
git add hooks/session-checkpoint hooks/session-checkpoint.js hooks/hooks.json tests/run-tests.sh
git commit -m "feat(checkpoint): add hooks/session-checkpoint — log Edit/Write/MultiEdit breadcrumbs"
```

---

### Task 2: Read path — `hooks/session-start` summary + truncate

**Files:**
- Modify: `hooks/session-start` (the embedded `node -e` block that builds `live_state`)
- Modify: `tests/run-tests.sh` (new section)

**Interfaces:**
- Consumes: `${TMPDIR:-/tmp}/harness-kit-verify/checkpoint-<hash>.jsonl` written by Task 1, in the
  exact shape `{"t":...,"tool":...,"target":...}` per line. Computes the same hash Task 1 computes
  (`sha1(path.resolve(projectDir)).slice(0,16)`) — this must not drift from Task 1's formula.
- Produces: an additional block appended to the existing `live_state` string that
  `hooks/session-start` already injects into `additionalContext` — visible to every existing test
  that reads that context (must not break the assertions already checking for `"ACTIVE: F01"`,
  `"using-harness"`, etc.). Also mutates the checkpoint log file on disk (truncation), a side effect
  with no return value.

- [ ] **Step 1: Write the failing tests in `tests/run-tests.sh`**

Append this new section right after the one added in Task 1:

```bash
echo ""
echo "== session-checkpoint: read path (SessionStart summary + truncate) =="

P="$(new_project)"
CF4="$(checkpoint_file "$P")"
rm -f "$CF4"
out="$(CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | grep -qF "since the last session-handoff.md update"; then
  ng "no checkpoint log at all -> no warning"
else
  ok "no checkpoint log at all -> no warning"
fi

P="$(new_project)"
CF5="$(checkpoint_file "$P")"
mkdir -p "${TMPDIR:-/tmp}/harness-kit-verify"
printf '%s\n' \
  '{"t":"2026-08-17T09:00:00.000Z","tool":"Edit","target":"src/foo.ts"}' \
  '{"t":"2026-08-17T09:05:00.000Z","tool":"Write","target":"session-handoff.md"}' \
  > "$CF5"
out="$(CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | grep -qF "since the last session-handoff.md update"; then
  ng "last entry IS session-handoff.md -> no warning"
else
  ok "last entry IS session-handoff.md -> no warning"
fi
after_lc="$(wc -l < "$CF5" | tr -d ' ')"
if [ "$after_lc" -eq 1 ]; then
  ok "clean handoff -> log truncated down to just the anchor"
else
  ng "clean handoff -> log truncated down to just the anchor (got $after_lc lines, want 1)"
fi

P="$(new_project)"
CF6="$(checkpoint_file "$P")"
printf '%s\n' \
  '{"t":"2026-08-17T09:00:00.000Z","tool":"Write","target":"session-handoff.md"}' \
  '{"t":"2026-08-17T09:10:00.000Z","tool":"Edit","target":"src/baz.ts"}' \
  > "$CF6"
out="$(CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | grep -qF "since the last session-handoff.md update"; then
  ok "an edit after the last handoff -> warns"
else
  ng "an edit after the last handoff -> warns"
fi
if printf '%s' "$out" | grep -qF "src/baz.ts"; then
  ok "the warning names the touched file"
else
  ng "the warning names the touched file"
fi
after_lc2="$(wc -l < "$CF6" | tr -d ' ')"
if [ "$after_lc2" -eq 2 ]; then
  ok "a stale handoff -> log keeps the anchor plus the unreported tail"
else
  ng "a stale handoff -> log keeps the anchor plus the unreported tail (got $after_lc2 lines, want 2)"
fi

P="$(new_project)"
CF7="$(checkpoint_file "$P")"
printf '%s\n' \
  '{"t":"2026-08-17T09:00:00.000Z","tool":"Edit","target":"src/torn.ts"' \
  > "$CF7"
out="$(CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | node -e '
let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{ try { JSON.parse(s); process.exit(0); } catch { process.exit(1); } });
' 2>/dev/null; then
  ok "a torn/corrupted last line does not crash session-start (still valid JSON out)"
else
  ng "a torn/corrupted last line does not crash session-start"
fi

# Existing behavior must survive: the checkpoint block must not break what session-start already
# injects (regression guard for the assertions already covering this at earlier lines in this file).
P="$(new_project)"
out="$(CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | node -e '
let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
  const j = JSON.parse(s);
  const ctx = j.hookSpecificOutput?.additionalContext ?? j.additionalContext;
  if (!ctx.includes("ACTIVE: F01")) throw new Error("regression: lost the ACTIVE line");
});' 2>/dev/null; then
  ok "the checkpoint block does not break the existing live-state injection"
else
  ng "the checkpoint block does not break the existing live-state injection"
fi
```

- [ ] **Step 2: Run the suite to confirm the new section fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "checkpoint log\|last entry\|edit after\|torn/corrupted\|does not break"`
Expected: the "no checkpoint log -> no warning" and "the checkpoint block does not break..." cases
already pass trivially (nothing new exists yet to break anything or warn about); every other new
assertion fails — no summary is ever produced, and the log files are never truncated (line counts
stay at their seeded values: 2 for `CF5`, not 1; `CF6` unchanged).

- [ ] **Step 3: Extend `hooks/session-start`**

Add `MARKER_DIR` right after the existing `PROJECT_DIR` line:

```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
```
→
```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
MARKER_DIR="${TMPDIR:-/tmp}/harness-kit-verify"
```

Replace the entire embedded `node -e` block (from `live_state="$(node -e '` through the closing
`' "$PROJECT_DIR" 2>&1)"`) with:

```bash
  live_state="$(node -e '
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const projectDir = process.argv[1];
const markerDir = process.argv[2];
const out = [];
try {
  const j = JSON.parse(fs.readFileSync(projectDir + "/feature_list.json", "utf8"));
  const fs_ = j.features || [];
  const active = fs_.find(f => f.id === j.active_feature) || null;
  const count = (s) => fs_.filter(f => f.status === s).length;
  out.push("Project: " + (j.project || "?") + "  |  Blueprint: " + (j.blueprint || "?"));
  out.push("Feature board: " + fs_.length + " total — " +
    ["done","verified","in_progress","blocked","pending","deferred"]
      .map(s => count(s) + " " + s).filter(x => !x.startsWith("0 ")).join(", "));
  if (active) {
    out.push("ACTIVE: " + active.id + " (" + active.status + ") — " + (active.name || ""));
    const dw = active.done_when || [];
    if (dw.length) out.push("  done_when: " + dw.map(c => "\n    - " + c).join(""));
    const v = active.verify || [];
    if (v.length) out.push("  verify: " + v.join(" ; "));
    const deps = (active.dependencies || []).filter(id => {
      const d = fs_.find(f => f.id === id);
      return !d || !["done","verified"].includes(d.status);
    });
    if (deps.length) out.push("  !! DEPS NOT DONE: " + deps.join(", ") + " — do not start " + active.id);
  } else {
    out.push("ACTIVE: (active_feature points at no feature — fix feature_list.json first)");
  }
  const undocumented = fs_.filter(f => ["done","verified"].includes(f.status) && !f.doc);
  if (undocumented.length) out.push("!! Features done but missing the doc field: " + undocumented.map(f => f.id).join(", "));
} catch (e) {
  out.push("(feature_list.json unreadable: " + e.message + ")");
}

// --- Session checkpoint: files touched since the last session-handoff.md update -----
// Written by hooks/session-checkpoint after every Edit/Write/MultiEdit. Self-anchoring: the log
// itself carries an entry for session-handoff.md whenever it was written, so the LAST such entry
// marks the last known-clean handoff — no mtime comparison, no date parsing needed.
try {
  const hash = crypto.createHash("sha1").update(path.resolve(projectDir)).digest("hex").slice(0, 16);
  const cpFile = path.join(markerDir, "checkpoint-" + hash + ".jsonl");
  if (fs.existsSync(cpFile)) {
    const lines = fs.readFileSync(cpFile, "utf8").split("\n").filter(Boolean);
    const entries = [];
    for (const l of lines) { try { entries.push(JSON.parse(l)); } catch { /* torn line — skip it */ } }
    let anchor = -1;
    for (let k = 0; k < entries.length; k++) {
      if (path.basename(String(entries[k].target || "")) === "session-handoff.md") anchor = k;
    }
    const unreported = entries.slice(anchor + 1);
    if (unreported.length > 0) {
      const counts = new Map();
      for (const e of unreported) counts.set(e.target, (counts.get(e.target) || 0) + 1);
      const list = [...counts.entries()].map(([f, n]) => f + " (x" + n + ")").join(", ");
      out.push("!! " + unreported.length + " file(s) edited since the last session-handoff.md update: " + list);
      out.push("   The last session may have ended without a clean handoff — verify progress.md/session-handoff.md still reflect reality.");
    }
    // Cleanup is deletion, mechanical, on every session start: drop everything strictly before the
    // anchor (already superseded by that handoff); no anchor found -> nothing dropped yet.
    const kept = entries.slice(Math.max(anchor, 0));
    fs.writeFileSync(cpFile, kept.map(e => JSON.stringify(e)).join("\n") + (kept.length ? "\n" : ""));
  }
} catch { /* best-effort — never break session start over a checkpoint log problem */ }

console.log(out.join("\n"));
' "$PROJECT_DIR" "$MARKER_DIR" 2>&1)"
fi
```

(The `fi` at the end closes the pre-existing `if command -v node >/dev/null 2>&1; then` guard — this
whole block, checkpoint logic included, only runs when `node` is available, matching the existing
fail-open behavior for the rest of `hooks/session-start`.)

- [ ] **Step 4: Run the suite to confirm the new section passes**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "checkpoint log\|last entry\|edit after\|torn/corrupted\|does not break"`
Expected: every assertion in this section prints `PASS`.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start tests/run-tests.sh
git commit -m "feat(checkpoint): hooks/session-start reads, summarizes, and truncates the checkpoint log"
```

---

## Completion checklist (matches spec §8)

- [ ] Editing a file via a simulated `PostToolUse` event appends exactly one well-formed JSON line.
- [ ] A project with no `feature_list.json` at `cwd` → the hook writes nothing.
- [ ] `SessionStart` after edits with no prior `session-handoff.md` entry → warns, lists the files.
- [ ] `SessionStart` after a `session-handoff.md` edit was the last entry → silent, no warning.
- [ ] After a `SessionStart` run, the log file no longer contains entries before the anchor.
- [ ] A corrupted/torn last line in the log does not crash `hooks/session-start`.
- [ ] `bash tests/run-tests.sh` green, with the new assertions counted.
