# State Compaction & Drift-Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound `progress.md`'s per-session read cost regardless of project age, and remove the one piece of harness state that duplicates `feature_list.json.active_feature` without anything checking it — both mechanically enforced through `init.sh`, matching how every other harness-kit rule with teeth already works.

**Architecture:** A new validator script (`scripts/check-state.mjs`, wired into a new `./init.sh state` target) enforces that any `done`/`verified` feature's Log entry in `progress.md` is either archived into a new `progress-archive.md` or left as a one-line tagged pointer. Two template files (`progress.md`, `session-handoff.md`) lose a duplicated free-text field in favor of a static line pointing at `feature_list.json.active_feature`. The SHIP checklist gains a 9th box (worktree cleanup), which requires updating the existing drift-lock assertion in `tests/run-tests.sh` in the same task.

**Tech Stack:** Node.js (`.mjs`, no dependencies — matches `check-docs.mjs`/`check-lang.mjs`), Bash (`init.sh`, `tests/run-tests.sh`), Markdown templates.

## Global Constraints

- No new dependency — harness-kit needs only `node` + `bash`. (Spec §4.3, matching the precedent in `check-docs.mjs:6`.)
- A missing validator script must `[FAIL]`, never `SKIP` — a counted SKIP still prints `VERIFY OK` and hands back a bypass. (Spec §4.3, matching `template/init.sh:107-113` / `:127-132`.)
- `bootstrap.mjs` needs **no changes** — it recursively walks `template/` (`bootstrap.mjs:70-78`), so any new file placed under `template/` is picked up automatically.
- Every new/changed artifact is English only (existing repo-wide invariant, checked by `check-lang.mjs`).
- The SHIP checklist must stay at an **equal box count in both `pipeline.md` and `shipping-a-feature/SKILL.md`** — the drift-lock assertion in `tests/run-tests.sh:1013-1044` enforces this and must be updated in the same commit that changes either checklist (Spec §6, §11).
- `"Recommended Next Step"` in `progress.md`/`session-handoff.md` is explicitly **not** touched by this plan (Spec §2 YAGNI) — do not remove or merge it.

---

### Task 1: `check-state.mjs` validator + `./init.sh state` target

**Files:**
- Create: `template/scripts/check-state.mjs`
- Modify: `template/init.sh:3` (usage comment), after `check_docs()` (currently `template/init.sh:101-114`), and the `case` dispatch (`template/init.sh:153-160`)
- Test: `tests/run-tests.sh` (new section, add near the end, after the `== SHIP checklist drift-lock ==` section at `tests/run-tests.sh:1004-1048` — append before the final `PASS=$PASSED  FAIL=$FAILED` block at line 1051)

**Interfaces:**
- Consumes: `feature_list.json` (`features[].id`, `features[].status`), `progress.md` (raw text)
- Produces: exit code 0 (pass) / 1 (fail) from `node scripts/check-state.mjs`; stdout messages prefixed `   [FAIL] <id>:` on failure, `   (nothing to archive yet)` when there is nothing to check, `   OK: <n> shipped feature(s)...` on a clean pass. The fixed tag string later tasks and the checker both rely on: `(shipped — see progress-archive.md)`.

- [ ] **Step 1: Write the failing tests in `tests/run-tests.sh`**

Insert this new section immediately before the final `echo ""` / `echo "PASS=$PASSED  FAIL=$FAILED"` block at the end of the file (currently lines 1050-1053):

```bash
echo ""
echo "== check_state: progress.md compaction for shipped features =="

expect_state() {
  local desc="$1" want="$2" proj="$3" got
  bash "$proj/init.sh" state >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ng "$desc (exit=$got, want=$want)"; fi
}

P="$(new_project)"
expect_state "no done features yet -> pass" 0 "$P"
out="$(bash "$P/init.sh" state 2>&1)"
if printf '%s' "$out" | grep -qF 'nothing to archive yet'; then
  ok "no done features -> says nothing to archive yet"
else
  ng "no done features -> says nothing to archive yet"
fi

P="$(new_project)"
patch_feature "$P" F01 '{"status":"done"}'
printf '%s\n' '### 2026-08-17 — F01: Scaffold project' >> "$P/progress.md"
expect_state "a shipped feature with an untagged Log entry -> fail" 1 "$P"
out="$(bash "$P/init.sh" state 2>&1)"
if printf '%s' "$out" | grep -qF 'F01'; then ok "the failure names the feature id"; else ng "the failure names the feature id"; fi

P="$(new_project)"
patch_feature "$P" F01 '{"status":"done"}'
printf '%s\n' '### 2026-08-17 — F01: Scaffold project (shipped — see progress-archive.md)' >> "$P/progress.md"
expect_state "a shipped feature with a tagged pointer -> pass" 0 "$P"

P="$(new_project)"
patch_feature "$P" F01 '{"status":"pending"}'
printf '%s\n' '### 2026-08-17 — F01: Scaffold project' >> "$P/progress.md"
expect_state "an in-progress feature's Log entry is never required to be tagged -> pass" 0 "$P"

P="$(new_project)"
mv "$P/scripts/check-state.mjs" "$P/scripts/check-state.mjs.bak"
expect_state "a missing validator fails rather than skipping -> fail" 1 "$P"
mv "$P/scripts/check-state.mjs.bak" "$P/scripts/check-state.mjs"
expect_state "restoring the validator makes it green again" 0 "$P"

P="$(new_project)"
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "STATE ("; then ok "./init.sh all does run check_state"; else ng "./init.sh all does run check_state"; fi
```

- [ ] **Step 2: Run the suite to confirm the new section fails**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: the new `== check_state ==` lines all print `FAIL` (there is no `state` target yet, so `bash "$proj/init.sh" state` exits 2 with `unknown target: state`, and `check-state.mjs` does not exist to move for the missing-validator case).

- [ ] **Step 3: Write `template/scripts/check-state.mjs`**

```js
// check-state.mjs — validate that progress.md does not carry a full, untagged Log entry for a
// feature that has already shipped (done/verified). A shipped feature's entry must be moved into
// progress-archive.md, leaving a one-line pointer in progress.md tagged with SHIPPED_TAG. This
// keeps progress.md bounded by "features currently in flight," not by the project's age.
// Run from the repo root: node scripts/check-state.mjs
// Exit 0 = valid, 1 = a [FAIL] occurred.
import fs from "node:fs";

const DONE = ["done", "verified"];
const SHIPPED_TAG = "(shipped — see progress-archive.md)";

let bad = 0;
let checked = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };

const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));
const progress = fs.existsSync("progress.md") ? fs.readFileSync("progress.md", "utf8") : "";
const lines = progress.split(/\r?\n/);

for (const f of j.features || []) {
  if (!DONE.includes(f.status)) continue;
  const id = f.id;
  if (typeof id !== "string" && typeof id !== "number") continue;

  // The heading convention is "### <date> — <id>: <title>". A trailing colon after the id keeps
  // "F1" from matching inside "F10" — the id must be followed immediately by ":".
  const marker = "— " + id + ":";
  const headingLines = lines.filter((l) => l.startsWith("###") && l.includes(marker));
  if (headingLines.length === 0) continue; // already archived away entirely, or never had an entry

  checked++;
  const untagged = headingLines.filter((l) => !l.includes(SHIPPED_TAG));
  if (untagged.length > 0) {
    fail(
      id,
      "progress.md still carries a full Log entry after shipping — move it into progress-archive.md " +
      "and leave a pointer line ending in \"" + SHIPPED_TAG + "\" (found: \"" + untagged[0].trim() + "\")",
    );
  }
}

if (checked === 0) console.log("   (nothing to archive yet)");
else if (!bad) console.log("   OK: " + checked + " shipped feature(s) with a Log entry are all archived or pointer-tagged");
process.exit(bad);
```

- [ ] **Step 4: Wire `check_state` into `template/init.sh`**

Modify the usage comment on line 3:

```bash
# Usage: ./init.sh [scaffold|build|secret|docs|lang|all]   (default: all)
```
→
```bash
# Usage: ./init.sh [scaffold|build|secret|docs|state|lang|all]   (default: all)
```

Add a new function immediately after `check_docs()` (which ends at `template/init.sh:114`, right before the `check_lang` comment block that currently starts at line 116):

```bash
# Every done/verified feature's Log entry in progress.md must be archived into progress-archive.md
# once shipped (a one-line pointer left behind). Rules live in scripts/check-state.mjs; this
# function only decides whether to run it.
check_state() {
  step "STATE (progress.md compaction for shipped features)"
  command -v node >/dev/null 2>&1 || { skip "no node — cannot validate progress.md compaction"; return; }
  [ -f feature_list.json ] || { skip "no feature_list.json"; return; }
  # A missing validator FAILs rather than SKIPs, for the same reason check_docs does: a counted
  # SKIP still prints VERIFY OK, handing back the bypass the gate exists to remove.
  if [ ! -f scripts/check-state.mjs ]; then
    echo "   [FAIL] scripts/check-state.mjs is missing — the state validator was removed"
    echo "   Restore it (bootstrap --force) or delete check_state from this file deliberately."
    FAIL=1
    return
  fi
  node scripts/check-state.mjs || FAIL=1
}
```

Update the `case` dispatch (`template/init.sh:153-160`):

```bash
case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  docs)     check_docs ;;
  lang)     : ;;                 # nothing extra — the unconditional run below is the whole target
  all)      check_scaffold; check_build; check_secret; check_docs ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac
```
→
```bash
case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  docs)     check_docs ;;
  state)    check_state ;;
  lang)     : ;;                 # nothing extra — the unconditional run below is the whole target
  all)      check_scaffold; check_build; check_secret; check_docs; check_state ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac
```

- [ ] **Step 5: Run the suite to confirm the new section passes**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: every line under `== check_state: progress.md compaction for shipped features ==` prints `PASS`, and `FAIL=0` at the very end (assuming no other section was already red).

- [ ] **Step 6: Commit**

```bash
git add template/scripts/check-state.mjs template/init.sh tests/run-tests.sh
git commit -m "feat(state): add check-state.mjs + ./init.sh state — progress.md compaction gate"
```

---

### Task 2: `progress-archive.md` template + Log heading convention in `progress.md`

**Files:**
- Create: `template/progress-archive.md`
- Modify: `template/progress.md:20-22` (the `## Log (newest first)` section)
- Test: `tests/run-tests.sh` — extend the `== README + e2e ==` section (the existing dry-run block at `tests/run-tests.sh:596-604`) and append a small new block to the `== check_state ==` section added in Task 1

**Interfaces:**
- Consumes: nothing new
- Produces: the file `progress-archive.md` at the root of every bootstrapped project; the documented Log heading convention `### {{DATE}} — <ID>: <title>` and its tagged form `### {{DATE}} — <ID>: <title> (shipped — see progress-archive.md)`, which `check-state.mjs` (Task 1) already expects verbatim.

- [ ] **Step 1: Write the failing tests**

In `tests/run-tests.sh`, find the existing dry-run block (currently lines 596-604):

```bash
# bootstrap --dry-run must list the new template files
P="$KIT/.tmp-tests/dry"
rm -rf "$P"; mkdir -p "$P"
out="$(node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "Dry" --dry-run 2>&1)"
if printf '%s' "$out" | grep -qE 'docs[\\/]features[\\/]_TEMPLATE\.md'; then
  ok "bootstrap --dry-run lists docs/features/_TEMPLATE.md"
else
  ng "bootstrap --dry-run lists docs/features/_TEMPLATE.md"
fi
```

Add immediately after it (still inside the same section, before the next `# ./init.sh all must run the FEATURE DOCS block` comment):

```bash
if printf '%s' "$out" | grep -qF 'progress-archive.md'; then
  ok "bootstrap --dry-run lists progress-archive.md"
else
  ng "bootstrap --dry-run lists progress-archive.md"
fi

P="$(new_project)"
if [ -f "$P/progress-archive.md" ]; then ok "bootstrap copies progress-archive.md"; else ng "bootstrap copies progress-archive.md"; fi
if grep -qF 'shipped — see progress-archive.md' "$P/progress.md"; then
  ok "progress.md documents the shipped-pointer tag verbatim"
else
  ng "progress.md documents the shipped-pointer tag verbatim"
fi
```

- [ ] **Step 2: Run the suite to confirm these new assertions fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -A2 "progress-archive"`
Expected: all three new assertions print `FAIL` (the file and the convention text do not exist yet).

- [ ] **Step 3: Create `template/progress-archive.md`**

```markdown
# Progress Archive — {{PROJECT_NAME}}

> Full Log entries for shipped features, moved out of progress.md to keep it bounded as the
> project grows. The durable record of a shipped feature is its dossier
> (`docs/features/<ID>-<slug>.md`, sections 7-8); this file is a secondary, chronological
> reference for old evidence you do not want to open a dossier to find.
>
> `progress.md` keeps a one-line pointer for each entry moved here:
> `### {{DATE}} — <ID>: <title> (shipped — see progress-archive.md)`.
```

- [ ] **Step 4: Document the convention in `template/progress.md`**

Current `## Log (newest first)` section (`template/progress.md:20-22`):

```markdown
## Log (newest first)
### {{DATE}} — Harness setup
- Stood up the harness from the harness-kit template. No product code yet.
```

Replace with:

```markdown
## Log (newest first)
Each entry tied to a feature carries its id in the heading: `### {{DATE}} — <ID>: <title>`. Once
that feature ships (status done/verified + dossier written), move the full entry into
`progress-archive.md` and replace it here with a one-line pointer:
`### {{DATE}} — <ID>: <title> (shipped — see progress-archive.md)`.
`./init.sh state` fails if a shipped feature's entry is still here untagged.

### {{DATE}} — Harness setup
- Stood up the harness from the harness-kit template. No product code yet.
```

- [ ] **Step 5: Run the suite to confirm the new assertions pass**

Run: `bash tests/run-tests.sh 2>&1 | grep -A2 "progress-archive"`
Expected: all three assertions print `PASS`.

- [ ] **Step 6: Commit**

```bash
git add template/progress-archive.md template/progress.md tests/run-tests.sh
git commit -m "feat(state): add progress-archive.md template + document the Log heading convention"
```

---

### Task 3: Remove the duplicated active-feature field

**Files:**
- Modify: `template/progress.md:1-8` (the header + `## Current State` block)
- Modify: `template/session-handoff.md:1-15` (the header + `## Where things stand` block)
- Test: `tests/run-tests.sh` (new section, appended after the section added in Task 2)

**Interfaces:**
- Consumes: nothing
- Produces: a static reference line in both files (no field left to fill in or drift): `` Active feature: see `feature_list.json.active_feature` `` — text only, no other task depends on its exact wording, only on the absence of the old field name.

- [ ] **Step 1: Write the failing tests**

Append to `tests/run-tests.sh` (after the block added in Task 2):

```bash
echo ""
echo "== active-feature de-duplication =="

P="$(new_project)"
if grep -qF 'Current Objective / Active feature' "$P/progress.md"; then
  ng "progress.md no longer has a fillable Active-feature field"
else
  ok "progress.md no longer has a fillable Active-feature field"
fi
if grep -qF 'feature_list.json.active_feature' "$P/progress.md"; then
  ok "progress.md points at feature_list.json.active_feature instead"
else
  ng "progress.md points at feature_list.json.active_feature instead"
fi

if grep -qF 'Current Objective / Active feature' "$P/session-handoff.md"; then
  ng "session-handoff.md no longer has a fillable Active-feature field"
else
  ok "session-handoff.md no longer has a fillable Active-feature field"
fi
if grep -qF 'feature_list.json.active_feature' "$P/session-handoff.md"; then
  ok "session-handoff.md points at feature_list.json.active_feature instead"
else
  ng "session-handoff.md points at feature_list.json.active_feature instead"
fi

# "Recommended Next Step" is a judgment call, not raw data — it must survive untouched (spec YAGNI).
if grep -qF 'Recommended Next Step' "$P/progress.md" && grep -qF 'Recommended Next Step' "$P/session-handoff.md"; then
  ok "Recommended Next Step is untouched in both files"
else
  ng "Recommended Next Step is untouched in both files"
fi
```

- [ ] **Step 2: Run the suite to confirm the new section fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "active-feature"`
Expected: the two "no longer has a fillable" assertions and the two "points at" assertions print `FAIL` (the old field is still there, the new line is not). The "Recommended Next Step" assertion prints `PASS` already (untouched).

- [ ] **Step 3: Edit `template/progress.md`**

Current header + Current State block (`template/progress.md:1-11`):

```markdown
# Progress — {{PROJECT_NAME}}

> Update this whenever a feature changes state. `done` must come with **evidence** (command/test output).

## Current State
- **Last Updated:** {{DATE}}.
- **Phase:** BLUEPRINT finished → ready to BUILD.  _(update as you progress)_
- **Current Objective / Active feature:** `F01` (pending).
- **What has been built:** nothing yet (the repo only has the harness).
- **Blockers:** _(list what is waiting on the Homeowner — keys, decisions...)_
- **Recommended Next Step:** scaffold per the Blueprint → `./init.sh scaffold`.
```

Replace with:

```markdown
# Progress — {{PROJECT_NAME}}

> Update this whenever a feature changes state. `done` must come with **evidence** (command/test output).
> Active feature: see `feature_list.json.active_feature` — also surfaced automatically by the
> SessionStart hook at the top of every session.

## Current State
- **Last Updated:** {{DATE}}.
- **Phase:** BLUEPRINT finished → ready to BUILD.  _(update as you progress)_
- **What has been built:** nothing yet (the repo only has the harness).
- **Blockers:** _(list what is waiting on the Homeowner — keys, decisions...)_
- **Recommended Next Step:** scaffold per the Blueprint → `./init.sh scaffold`.
```

- [ ] **Step 4: Edit `template/session-handoff.md`**

Current file:

```markdown
# Session Handoff — {{PROJECT_NAME}}

> Read this file at the start of a session. Update it at the end, before stopping.

## Quick context
- Blueprint: `{{BLUEPRINT_PATH}}`.
- Harness: `CLAUDE.md` (invariants), `feature_list.json` (state), `.claude/workflow/` (pipeline + security + subagents).
- Verify: `./init.sh <target>`.

## Where things stand (restart markers)
- **Last Updated:** {{DATE}}.
- **Current Objective / Active feature:** F01 (not started).
- **Recommended Next Step:** scaffold per the Blueprint → `./init.sh scaffold`.
- **Blockers:** _(keys/decisions waiting on the Homeowner)_
- **Files:** harness files at the root + `.claude/`; no product files yet.
```

Replace the `## Where things stand` block with:

```markdown
## Where things stand (restart markers)
- **Last Updated:** {{DATE}}.
- **Active feature:** see `feature_list.json.active_feature` — also surfaced automatically by the SessionStart hook.
- **Recommended Next Step:** scaffold per the Blueprint → `./init.sh scaffold`.
- **Blockers:** _(keys/decisions waiting on the Homeowner)_
- **Files:** harness files at the root + `.claude/`; no product files yet.
```

(The `## Quick context` and `## Pending decisions` / `## Next Session` sections are unchanged.)

- [ ] **Step 5: Run the suite to confirm the new section passes**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "active-feature"`
Expected: all five assertions print `PASS`.

- [ ] **Step 6: Commit**

```bash
git add template/progress.md template/session-handoff.md tests/run-tests.sh
git commit -m "refactor(state): remove the duplicated active-feature field from progress.md and session-handoff.md"
```

---

### Task 4: Worktree cleanup — SHIP checklist (9th box) + drift-lock update

**Files:**
- Modify: `template/.claude/workflow/pipeline.md:42-55` (SHIP section)
- Modify: `skills/shipping-a-feature/SKILL.md:16-27` (SHIP checklist)
- Modify: `tests/run-tests.sh:1013-1022` (the `SHIP_ITEMS` array)
- Modify: `README.md` (the drift-lock section's box-count text)

**Interfaces:**
- Consumes: nothing
- Produces: a 9th SHIP-checklist box present verbatim (containing the literal substring `git worktree remove`) in both `pipeline.md` and `shipping-a-feature/SKILL.md`; the `SHIP_ITEMS` array in `tests/run-tests.sh` gains a matching 9th entry so both the coverage loop and the count-pin loop (`tests/run-tests.sh:1024-1044`) check 9 instead of 8.

- [ ] **Step 1: Write the failing test — update `SHIP_ITEMS` first**

In `tests/run-tests.sh`, find (lines 1013-1022):

```bash
SHIP_ITEMS=(
  "verify|init\.sh"
  "review|review"
  "security|SECURITY gate"
  "secret|0 secret"
  "state|progress\.md"
  "dossier|[Dd]ossier"
  "docs|Diataxis"
  "commit|PR"
)
```

Replace with:

```bash
SHIP_ITEMS=(
  "verify|init\.sh"
  "review|review"
  "security|SECURITY gate"
  "secret|0 secret"
  "state|progress\.md"
  "dossier|[Dd]ossier"
  "docs|Diataxis"
  "worktree|git worktree remove"
  "commit|PR"
)
```

This is the test change: the existing coverage loop (`tests/run-tests.sh:1024-1033`) will now look for a `worktree` box matching `git worktree remove` in both files, and the count-pin loop (`tests/run-tests.sh:1036-1044`) will now require exactly 9 `- [ ]` lines in each file.

- [ ] **Step 2: Run the suite to confirm this fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "ship item 'worktree'|checklist box count"`
Expected: both `ship item 'worktree' MISSING from pipeline.md` and `... SKILL.md`, plus both count-pin lines print `FAIL` (count is still 8, want 9).

- [ ] **Step 3: Add the worktree box to `template/.claude/workflow/pipeline.md`**

Current SHIP section (`template/.claude/workflow/pipeline.md:42-55`):

```markdown
## 9. SHIP — gate + docs
Only ship when **all 8 boxes** are ticked — same granularity as `harness-kit:shipping-a-feature`,
so the two copies can be compared mechanically rather than by eye:
- [ ] **The relevant `init.sh` is all green** — fresh output, pasted into `progress.md`.
- [ ] **The diff review has run** — `parallel-review` (subagent) or a manual review. **0 confirmed P0s.** Tier `lite`: skip it and state the reason.
- [ ] **The SECURITY gate passed** — the applicable `security.md` checklist, 0 P0s.
- [ ] **0 secrets in the client bundle** — `./init.sh secret`.
- [ ] **State updated** — `feature_list.json` status + the `doc` field; `progress.md` holds the evidence.
- [ ] **The dossier is finished** — `docs/features/<ID>-<slug>.md`, all 9 sections, frontmatter matching `feature_list.json`, `./init.sh docs` green. Tier `lite`: one line of evidence in `progress.md` instead. Start from `docs/features/_TEMPLATE.md`.
- [ ] **Docs (Diataxis)** matching the diff: *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (the main flow), *Explanation* (why).
- [ ] **Commit/PR** stating the feature id + the REQs covered; the PR body lists the `done_when` items that passed.

The box count is a **constant 8 at every tier**. A tier changes *how* a box is ticked, never *how many*
there are — otherwise the count could not be pinned, and an item could be dropped without anything noticing.
```

Replace with:

```markdown
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
```

- [ ] **Step 4: Add the worktree box to `skills/shipping-a-feature/SKILL.md`**

Current checklist (`skills/shipping-a-feature/SKILL.md:16-27`):

```markdown
## The SHIP checklist — every item needs evidence

- [ ] **The relevant part of `./init.sh` is all green** — fresh output, pasted into `progress.md`.
- [ ] **The diff review has run** — `Workflow({ name:'parallel-review' })` if opted in, or spawn an `Agent` review by hand. **0 confirmed P0s.**
- [ ] **The SECURITY gate passed** — `harness-kit:security-gate` has run, every applicable P0 green.
- [ ] **0 secrets in the client bundle** — `./init.sh secret`.
- [ ] **State updated** — `feature_list.json` status + the `doc` field; `progress.md` holds the evidence.
- [ ] **The dossier is finished** — `docs/features/<ID>-<slug>.md` with all 9 sections and a frontmatter matching `feature_list.json`, `./init.sh docs` green. At tier `lite`: tick this with one line of evidence in `progress.md` instead, and say why. See `harness-kit:writing-feature-dossier`.
- [ ] **Docs matching the diff (Diataxis)** — *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (the main flow), *Explanation* (why). Only write the parts the diff actually touches.
- [ ] **Commit/PR** carrying the feature id + the REQs covered; the PR body lists the `done_when` items that passed.

**Any** box still empty → do not ship. There is no "ship now, tick later".
```

Replace with:

```markdown
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
```

- [ ] **Step 5: Update the box-count text in `README.md`**

Find (in the `## Drift-lock on the SHIP checklist` section):

```markdown
- **coverage** — each of the 8 canonical items matches in *both* files
- **a count pin** — each file has exactly 8 checkboxes
```

Replace with:

```markdown
- **coverage** — each of the 9 canonical items matches in *both* files
- **a count pin** — each file has exactly 9 checkboxes
```

Leave the sentence `"It had already drifted (6 boxes against 8) before anyone noticed."` unchanged — it describes a historical event, not the current count.

- [ ] **Step 6: Run the suite to confirm everything passes**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "ship item|checklist box count"`
Expected: all `ship item '...'` lines print `PASS` (9 keys × 2 files = 18 lines), and both `checklist box count in pipeline.md = 9` / `... SKILL.md = 9` print `PASS`.

- [ ] **Step 7: Commit**

```bash
git add template/.claude/workflow/pipeline.md skills/shipping-a-feature/SKILL.md tests/run-tests.sh README.md
git commit -m "feat(ship): add worktree cleanup as the 9th SHIP box, update the drift-lock to match"
```

---

### Task 5: Wire the remaining instructions (`shipping-a-feature`, `CLAUDE.md`, `README.md`)

**Files:**
- Modify: `skills/shipping-a-feature/SKILL.md` (`## End of Session` section)
- Modify: `template/CLAUDE.md` (`## Source of truth` and `## Verification Commands` sections)
- Modify: `README.md` (`## Layout of the kit` tree, the 5-subsystems table, the assertion-count line)
- Test: `tests/run-tests.sh` (new small section)

**Interfaces:**
- Consumes: the fixed tag string from Task 1/2 (`(shipped — see progress-archive.md)`), the `./init.sh state` target name from Task 1
- Produces: nothing new consumed elsewhere — this task is documentation-only wiring, verified by grep-based assertions in the existing style.

- [ ] **Step 1: Write the failing tests**

Append to `tests/run-tests.sh` (after the section added in Task 3):

```bash
echo ""
echo "== instruction wiring: state compaction =="

CST="$KIT/template/CLAUDE.md"
SFT="$KIT/skills/shipping-a-feature/SKILL.md"

has "CLAUDE.md mentions progress-archive.md"     "$CST" "progress-archive.md"
has "CLAUDE.md carries the ./init.sh state command" "$CST" "./init.sh state"
has "shipping-a-feature End-of-Session mentions archiving" "$SFT" "progress-archive.md"

R="$KIT/README.md"
has "README lists progress-archive.md in the directory tree" "$R" "progress-archive.md"
has "README lists check-state.mjs in the directory tree"     "$R" "check-state.mjs"
has "README's subsystems table mentions the state target"    "$R" "check-state.mjs"
```

(The `has()` helper already exists in `tests/run-tests.sh`, defined at line 568 as `has() { # has <description> <file> <pattern> ... }` — reuse it, do not redefine it.)

- [ ] **Step 2: Run the suite to confirm the new section fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "instruction wiring: state"`
Expected: all six assertions print `FAIL`.

- [ ] **Step 3: Edit `skills/shipping-a-feature/SKILL.md` — End of Session**

Current (`skills/shipping-a-feature/SKILL.md:63-73`):

```markdown
## End of Session — so the next session restarts clean

Before ending the session, even if the feature is unfinished:

1. **`feature_list.json`** — a status matching reality + the `doc` field if you just shipped.
2. **`progress.md`** — Current State + evidence (command output, not a summary).
3. **`session-handoff.md`** — Blockers, Files touched, **Recommended Next Step**.
   The Next Step must be concrete enough that the next session can act immediately: file names, command names, feature ids.
   "Continue F03" is not a next step.
4. **Memory** — record in the harness memory whatever **cannot be derived from the code**: architectural decisions that emerged, pitfalls hit, trade-offs chosen and why. Do not restate what the code already says.
```

Replace step 2 with:

```markdown
2. **`progress.md`** — Current State + evidence (command output, not a summary). If a feature shipped this session, move its Log entry into `progress-archive.md` and leave a one-line pointer tagged `(shipped — see progress-archive.md)` — `./init.sh state` checks this.
```

(Steps 1, 3, 4 are unchanged.)

- [ ] **Step 4: Edit `template/CLAUDE.md` — Source of truth**

Find:

```markdown
- **State:** `feature_list.json` (which feature is active, what is done) + `progress.md`.
```

Replace with:

```markdown
- **State:** `feature_list.json` (which feature is active, what is done) + `progress.md` (work in flight) + `progress-archive.md` (shipped feature history, moved out of `progress.md` to keep it bounded).
```

- [ ] **Step 5: Edit `template/CLAUDE.md` — Verification Commands**

Find:

```markdown
- `./init.sh docs` — every `done`/`verified` feature must have a valid dossier (all 9 sections, in order, no placeholders, frontmatter matching `feature_list.json`). Features at tier `lite` are exempt from the dossier. Included in `./init.sh all`.
- A feature is only `done` when the relevant verify commands are **all green**; paste the output into `progress.md` as evidence.
```

Insert a new bullet between them:

```markdown
- `./init.sh docs` — every `done`/`verified` feature must have a valid dossier (all 9 sections, in order, no placeholders, frontmatter matching `feature_list.json`). Features at tier `lite` are exempt from the dossier. Included in `./init.sh all`.
- `./init.sh state` — every `done`/`verified` feature's Log entry in `progress.md` must be archived into `progress-archive.md`, with a one-line pointer left behind. Keeps session start-up cost bounded by features currently in flight, not by the project's age. Included in `./init.sh all`.
- A feature is only `done` when the relevant verify commands are **all green**; paste the output into `progress.md` as evidence.
```

- [ ] **Step 6: Edit `README.md` — Layout of the kit**

Find:

```
├── template/                 # what gets poured into the project
│   ├── CLAUDE.md             # instructions: startup, invariants, DoD, subagents
│   ├── feature_list.json     # state: features + deps + done_when
│   ├── progress.md           # state: current + evidence
│   ├── session-handoff.md    # lifecycle: resuming across sessions
│   ├── init.sh               # verification: build/test + secret grep + dossier + language
│   ├── scripts/
│   │   ├── check-docs.mjs    # dossier validator: 9 sections, frontmatter mirror, tier rules
│   │   ├── check-lang.mjs    # the English-only validator
│   │   └── lang-words.txt    # this project's own vocabulary (ships empty)
│   ├── docs/features/
│   │   └── _TEMPLATE.md      # the 9-section dossier — copy it when you finish shipping a feature
│   └── .claude/
│       ├── workflow/         # docs: pipeline, security, subagents
│       └── workflows/        # runnable: adversarial-verify, parallel-review, parallel-build
```

Replace with:

```
├── template/                 # what gets poured into the project
│   ├── CLAUDE.md             # instructions: startup, invariants, DoD, subagents
│   ├── feature_list.json     # state: features + deps + done_when
│   ├── progress.md           # state: current + evidence (Log bounded — shipped entries move out)
│   ├── progress-archive.md   # state: archived Log entries for shipped features
│   ├── session-handoff.md    # lifecycle: resuming across sessions
│   ├── init.sh               # verification: build/test + secret grep + dossier + state + language
│   ├── scripts/
│   │   ├── check-docs.mjs    # dossier validator: 9 sections, frontmatter mirror, tier rules
│   │   ├── check-state.mjs   # progress.md compaction validator: shipped features must be archived
│   │   ├── check-lang.mjs    # the English-only validator
│   │   └── lang-words.txt    # this project's own vocabulary (ships empty)
│   ├── docs/features/
│   │   └── _TEMPLATE.md      # the 9-section dossier — copy it when you finish shipping a feature
│   └── .claude/
│       ├── workflow/         # docs: pipeline, security, subagents
│       └── workflows/        # runnable: adversarial-verify, parallel-review, parallel-build
```

- [ ] **Step 7: Edit `README.md` — the 5 subsystems table**

Find:

```markdown
| Subsystem | File | Role |
|---|---|---|
| Instructions | `CLAUDE.md` | the startup path, invariants, definition of done |
| State | `feature_list.json`, `progress.md`, `docs/features/<ID>-<slug>.md` | which feature, whether it is done, the evidence, and the **dossier** describing each shipped feature |
| Verification | `init.sh` + `scripts/check-docs.mjs` + `scripts/check-lang.mjs` | the commands that must run before done + the secret grep + `docs` + `lang` |
| Scope | `feature_list.json` deps + done_when | guards against overreach and half-finished work |
| Lifecycle | `session-handoff.md` + End-of-Session | the next session restarts clean |
```

Replace with:

```markdown
| Subsystem | File | Role |
|---|---|---|
| Instructions | `CLAUDE.md` | the startup path, invariants, definition of done |
| State | `feature_list.json`, `progress.md`, `progress-archive.md`, `docs/features/<ID>-<slug>.md` | which feature, whether it is done, the evidence (current + archived), and the **dossier** describing each shipped feature |
| Verification | `init.sh` + `scripts/check-docs.mjs` + `scripts/check-state.mjs` + `scripts/check-lang.mjs` | the commands that must run before done + the secret grep + `docs` + `state` + `lang` |
| Scope | `feature_list.json` deps + done_when | guards against overreach and half-finished work |
| Lifecycle | `session-handoff.md` + End-of-Session | the next session restarts clean |
```

- [ ] **Step 8: Run the suite to confirm the new section passes, and capture the final assertion count**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: `FAIL=0`, and the final `PASS=<N>` line shows a number greater than the count `README.md` currently advertises. Note the printed `N`.

- [ ] **Step 9: Update the assertion count in `README.md`**

Find (in the `## Four test tiers` section):

```markdown
bash tests/run-tests.sh                # structure  — 243 assertions, costs no tokens
```

Replace `243` with the exact `N` captured in Step 8.

- [ ] **Step 10: Run the full suite one final time**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`, exit code 0.

- [ ] **Step 11: Commit**

```bash
git add skills/shipping-a-feature/SKILL.md template/CLAUDE.md README.md tests/run-tests.sh
git commit -m "docs(state): wire progress-archive.md and ./init.sh state into CLAUDE.md, shipping-a-feature, README"
```

---

## Completion checklist (matches spec §10)

- [ ] `bash tests/run-tests.sh` green, assertion count in `README.md` matches the real total.
- [ ] A fresh bootstrap: `progress.md` and `session-handoff.md` contain the static reference line, not a fillable Active-feature field.
- [ ] Marking a feature done/verified, then running `./init.sh state` with its Log entry still untagged → `[FAIL]`; tagging it (or moving it to `progress-archive.md` and leaving the pointer) → the same run passes.
- [ ] `./init.sh` with no done/verified features at all → `state` prints "(nothing to archive yet)", not a FAIL and not a SKIP miscounted as one.
- [ ] The SHIP-checklist drift-lock (`pipeline.md` vs `shipping-a-feature/SKILL.md`) asserts an exact match at count 9.
