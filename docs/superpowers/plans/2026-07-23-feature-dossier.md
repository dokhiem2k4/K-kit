# Feature Dossier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every feature in the harness, once shipped, leaves behind exactly one 8-section Markdown file (the dossier), enforced by a mechanical check inside `init.sh`.

**Architecture:** add one template file (`template/docs/features/_TEMPLATE.md`), one new verification target (`./init.sh docs`) that parses `feature_list.json` with `node -e`, and wire the rule into the 4 existing instruction/state files. No new dependency, no external script. The tests are a bash suite that bootstraps a throwaway project and asserts the exit code of `init.sh`.

**Tech Stack:** Bash (Git Bash on Windows), Node.js (CommonJS, no dependencies), Markdown, JSON.

**Spec:** `docs/superpowers/specs/2026-07-23-feature-dossier-design.md`

## Global Constraints

- Every change lives inside `harness-kit/`: `template/**`, `README.md`, `tests/**`. Do **not** touch `bootstrap.mjs` (its `walk()` already copies new files).
- The dossier path convention, used verbatim everywhere: `docs/features/<ID>-<slug>.md` (slug = the kebab-case of `name`).
- The source template: `docs/features/_TEMPLATE.md` — its name starts with `_` and no feature points at it, so it is never scanned.
- A dossier has **exactly 8 level-2 headings**, in order, worded exactly:
  `## 1. Why it matters` · `## 2. What it does` · `## 3. How to use it` · `## 4. Under the hood` · `## 5. Decisions & trade-offs` · `## 6. Pitfalls when editing` · `## 7. Evidence` · `## 8. Updates`
- A section that does not apply gets `—`; the heading is **never deleted**.
- The only placeholder marker: `<TODO: ...>`. Guidance comments use `<!-- ... -->`. The check greps for exactly those two strings, `<TODO:` and `<!--`; **never** a generic `<...>`.
- The check applies only to features whose `status` ∈ `{done, verified}`. Other statuses are skipped.
- No `node` available → print a SKIP line, do **not** set FAIL and do **not** print "OK".
- Keep the existing English anchors in `CLAUDE.md` (`Startup Workflow`, `Verification Commands`, `Definition of Done`, `End of Session`) so `validate-harness.mjs` still scores 100/100.
- JS inside `node -e '...'` (a bash single-quoted string) **must contain no single quotes** — use double quotes and concatenate with `+`.

---

### Task 0: Initialize a git repo for harness-kit

`harness-kit` is **not yet a git repo**, so the commit steps in later tasks would fail. This task establishes the baseline.

**Files:**
- Create: `.gitignore`

**Interfaces:**
- Produces: a git repo with a baseline commit; `.tmp-tests/` ignored (task 1 uses that directory as its test sandbox).

- [ ] **Step 1: Confirm it is not a repo yet**

```bash
cd "<path>/harness-kit"
git rev-parse --is-inside-work-tree 2>&1
```

Expected: `fatal: not a git repository (or any of the parent directories): .git`

If the command prints `true` → skip steps 2–3, just create `.gitignore` and commit.

- [ ] **Step 2: Create `.gitignore`**

```
.tmp-tests/
node_modules/
```

- [ ] **Step 3: Init + baseline commit**

```bash
git init
git add -A
git commit -m "chore: baseline harness-kit before adding the feature dossier"
```

Expected: the commit succeeds, listing `bootstrap.mjs`, `README.md`, `template/*`, `docs/superpowers/*`, `.gitignore`.

---

### Task 1: The `docs` target in `init.sh` + the test suite

This is the core: the mechanical check. Write the tests first (9 scenarios), watch them fail, then implement.

**Files:**
- Create: `tests/run-tests.sh`
- Modify: `template/init.sh` (add `check_docs()`; update the usage line at the top; update the `case` at the bottom)

**Interfaces:**
- Consumes: the `bootstrap.mjs` CLI (`--target <dir> --name <str> --stack <str>`); `template/feature_list.json` with a `features[]` array carrying `id`/`status`.
- Produces:
  - A bash function `check_docs()` in `init.sh`, using the existing `FAIL` variable and `step()` function.
  - A new CLI target: `./init.sh docs`; `docs` included in the `all` branch.
  - Exit codes: `0` = every done/verified feature has a valid dossier (or no feature is done yet), `1` = a violation exists.
  - `tests/run-tests.sh` with helpers reused by later tasks: `ok`, `ng`, `new_project`, `patch_feature`, `valid_dossier`, `expect_docs`, `win`.

- [ ] **Step 1: Write the test suite (it will fail)**

Create `tests/run-tests.sh`:

```bash
#!/usr/bin/env bash
# Test suite — harness-kit. Run: bash tests/run-tests.sh
# Requires: bash + node. Each scenario bootstraps a throwaway project into .tmp-tests/ then asserts the exit code.
set -uo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"

PASSED=0
FAILED=0
N=0

cleanup() { rm -rf "$KIT/.tmp-tests"; }
trap cleanup EXIT

ok() { echo "  PASS  $1"; PASSED=$((PASSED + 1)); }
ng() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

# Convert a POSIX path -> the form node understands on Windows (Git Bash). Elsewhere: unchanged.
win() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}

# Bootstrap a throwaway project and print its POSIX path.
new_project() {
  N=$((N + 1))
  local d="$KIT/.tmp-tests/p$N"
  rm -rf "$d"
  mkdir -p "$d"
  node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$d")" \
    --name "Test Project" --stack "node" >/dev/null 2>&1
  echo "$d"
}

# patch_feature <proj> <feature-id> <json-object>   — merged into the feature; a null value deletes the field.
patch_feature() {
  node -e '
const fs = require("fs");
const [p, id, patch] = process.argv.slice(1);
const file = p + "/feature_list.json";
const j = JSON.parse(fs.readFileSync(file, "utf8"));
const ft = j.features.find(x => x.id === id);
Object.assign(ft, JSON.parse(patch));
for (const k of Object.keys(ft)) if (ft[k] === null) delete ft[k];
fs.writeFileSync(file, JSON.stringify(j, null, 2));
' "$(win "$1")" "$2" "$3"
}

# Print a valid dossier (all 8 sections, no placeholders).
valid_dossier() {
  cat <<'MD'
# F01 — Scaffold project

> **Status:** done · **Date:** 2026-07-23 · **Commit:** a1b2c3d · **Blueprint:** §1

## 1. Why it matters
Lays the foundation for every later feature; both F02 and F03 build on it.

## 2. What it does
An empty build of the repo runs from a clean machine.

## 3. How to use it
`npm install && npm run build`

## 4. Under the hood
`package.json` — declares the build/lint/test scripts.

## 5. Decisions & trade-offs
Chose npm over pnpm for simplicity; no monorepo tooling added.

## 6. Pitfalls when editing
Renaming the build script means updating `init.sh` too.

## 7. Evidence
`./init.sh scaffold` → VERIFY OK (scaffold).

## 8. Updates
2026-07-23 — created.
MD
}

# expect_docs <description> <expected-exit-code> <proj>
expect_docs() {
  local desc="$1" want="$2" proj="$3" got
  bash "$proj/init.sh" docs >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ng "$desc (exit=$got, want=$want)"; fi
}

# expect_all <description> <expected-exit-code> <proj>
expect_all() {
  local desc="$1" want="$2" proj="$3" got
  bash "$proj/init.sh" all >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ng "$desc (exit=$got, want=$want)"; fi
}

DOC="docs/features/F01-scaffold.md"

echo "== check_docs =="

P="$(new_project)"
expect_docs "no feature done yet -> pass" 0 "$P"

P="$(new_project)"
patch_feature "$P" F01 '{"status":"done","doc":null}'
expect_docs "done but missing the doc field -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
rm -f "$P/$DOC"
expect_docs "doc points at a nonexistent file -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed '/^## 6\./,$d' > "$P/$DOC"
expect_docs "sections 6-8 missing -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^## 2\./## X./' -e 's/^## 8\./## 2./' -e 's/^## X\./## 8./' > "$P/$DOC"
expect_docs "8 sections in the wrong order -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
{ valid_dossier; echo "<TODO: fill in this part>"; } > "$P/$DOC"
expect_docs "a <TODO: placeholder is left -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
{ valid_dossier; printf '%s\n' "<!-- guidance not removed -->"; } > "$P/$DOC"
expect_docs "an HTML comment is left -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier > "$P/$DOC"
expect_docs "a valid dossier -> pass" 0 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"verified\",\"doc\":\"$DOC\"}"
rm -f "$P/$DOC"
expect_all "status verified with no dossier -> ./init.sh all fails" 1 "$P"

echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
if [ "$FAILED" -eq 0 ]; then exit 0; else exit 1; fi
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd "<path>/harness-kit"
bash tests/run-tests.sh
```

Expected: `FAIL` on every scenario expecting exit 1 — because `init.sh` does not know the `docs` target yet, falls into the `*)` branch and exits **2**. The summary line `FAIL=` must be > 0, exit code 1.

- [ ] **Step 3: Add `check_docs()` to `template/init.sh`**

Insert it immediately **after** `check_secret()` (before `case "$TARGET" in`):

```bash
# Every done/verified feature must have a dossier at docs/features/<ID>-<slug>.md with all 8 sections.
check_docs() {
  step "FEATURE DOCS (dossier for done/verified features)"
  command -v node >/dev/null 2>&1 || { echo "   (no node — SKIP, cannot validate)"; return; }
  [ -f feature_list.json ] || { echo "   (no feature_list.json — skip)"; return; }
  node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));
const DONE = ["done", "verified"];
const WANT = "1,2,3,4,5,6,7,8";
let bad = 0, n = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };
for (const f of (j.features || [])) {
  if (!DONE.includes(f.status)) continue;
  n++;
  const id = f.id || "(feature with no id)";
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "missing the \"doc\" field in feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "dossier not found: " + p); continue; }
  const t = fs.readFileSync(p, "utf8");
  const nums = t.split(/\r?\n/)
    .filter(l => /^##\s+[1-8]\./.test(l))
    .map(l => l.match(/^##\s+([1-8])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " must have all 8 sections ## 1. .. ## 8. in order (currently: " + (nums.join(",") || "no sections at all") + ")");
    continue;
  }
  if (t.indexOf("<TODO:") >= 0) { fail(id, p + " still contains a <TODO: placeholder"); continue; }
  if (t.indexOf("<!--") >= 0) { fail(id, p + " still contains uncleaned HTML guidance comments"); continue; }
}
if (n === 0) console.log("   (no feature is done/verified yet — skip)");
else if (!bad) console.log("   OK: all " + n + " done/verified features have a valid dossier");
process.exit(bad);
' || FAIL=1
}
```

- [ ] **Step 4: Wire `docs` into the dispatcher**

In `template/init.sh`, change the `case` block (currently lines 52-58) to:

```bash
case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  docs)     check_docs ;;
  all)      check_scaffold; check_build; check_secret; check_docs ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac
```

And update the usage line at the top of the file (line 3):

```bash
# Usage: ./init.sh [scaffold|build|secret|docs|all]   (default: all)
```

- [ ] **Step 5: Run the tests to confirm they pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=9  FAIL=0`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add tests/run-tests.sh template/init.sh
git commit -m "feat(init.sh): add the docs target — check dossiers for done/verified features"
```

---

### Task 2: The dossier template `_TEMPLATE.md`

**Files:**
- Create: `template/docs/features/_TEMPLATE.md`
- Modify: `tests/run-tests.sh` (append a `== _TEMPLATE.md ==` block at the end, **before** the summary `echo ""` / `PASS=` block)

**Interfaces:**
- Consumes: the `new_project`, `ok`, `ng`, `expect_docs` helpers from Task 1.
- Produces: the file agents copy when writing a dossier; the single source defining the 8 headings + the section 1 vs section 2 boundary.

- [ ] **Step 1: Add the template tests (they will fail)**

Insert into `tests/run-tests.sh` immediately before the summary block's `echo ""` line:

```bash
echo ""
echo "== _TEMPLATE.md =="

P="$(new_project)"
T="$P/docs/features/_TEMPLATE.md"

if [ -f "$T" ]; then ok "bootstrap copies docs/features/_TEMPLATE.md"; else ng "bootstrap copies docs/features/_TEMPLATE.md"; fi

nums="$(grep -E '^##[[:space:]]+[1-8]\.' "$T" 2>/dev/null \
  | sed -E 's/^##[[:space:]]+([1-8])\..*/\1/' | tr '\n' ',' | sed 's/,$//')"
if [ "$nums" = "1,2,3,4,5,6,7,8" ]; then
  ok "_TEMPLATE.md has all 8 sections in order"
else
  ng "_TEMPLATE.md has all 8 sections in order (currently: ${nums:-none})"
fi

if grep -q '<TODO:' "$T" 2>/dev/null; then ok "_TEMPLATE.md uses the <TODO: marker"; else ng "_TEMPLATE.md is missing the <TODO: marker"; fi
if grep -q '<!--' "$T" 2>/dev/null; then ok "_TEMPLATE.md carries guidance comments"; else ng "_TEMPLATE.md is missing guidance comments"; fi
if grep -q 'zoom out' "$T" 2>/dev/null && grep -q 'zoom in' "$T" 2>/dev/null; then
  ok "_TEMPLATE.md explains the section 1 vs section 2 boundary"
else
  ng "_TEMPLATE.md explains the section 1 vs section 2 boundary"
fi

expect_docs "_TEMPLATE.md is not scanned (no feature points at it) -> pass" 0 "$P"
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bash tests/run-tests.sh
```

Expected: 5 new `FAIL` lines in the `== _TEMPLATE.md ==` block (the file does not exist yet). The last scenario still passes.

- [ ] **Step 3: Create `template/docs/features/_TEMPLATE.md`**

A note while writing it: **never write the HTML comment terminator inside the comment itself** (it would close the comment early).

```markdown
# <TODO: F0X> — <TODO: Feature name>

> **Status:** <TODO: done | verified> · **Date:** <TODO: YYYY-MM-DD> · **Commit:** <TODO: sha> · **Blueprint:** <TODO: section>

<!--
FEATURE DOSSIER — copy this file to docs/features/<ID>-<slug>.md when you ship a feature.

Rules:
- Write it at the SHIP gate, after VERIFY + SECURITY + DEVEX have passed.
- Keep all 8 headings below, in order, worded exactly. A section that does not apply gets "—", NEVER delete the heading.
- Remove every <TODO: ...> placeholder and every guidance comment before shipping.
- ./init.sh docs will FAIL on a missing section, a wrong order, or a leftover placeholder / comment.

The boundary between sections 1 and 2 — do not write it twice:
- Section 1 = zoom out. The feature's role in the system. Why the project NEEDS it.
- Section 2 = zoom in. Observable behaviour. Press/call what, get what.
-->

## 1. Why it matters

<TODO: What role does this F play in the bigger picture? What does it unlock (which features build on it —
check `dependencies` in feature_list.json, in both directions)? What would the project lack without it?
Which REQ / Blueprint section does it cover?>

## 2. What it does

<TODO: Observable behaviour, concretely. What the user presses or calls, and what comes back.>

## 3. How to use it

<TODO: Concrete steps, endpoint, screen, or command. With a real example — request → response if it is an API.>

## 4. Under the hood

<TODO: The main flow A → B → C.>

**Files touched**

| File | Role |
|---|---|
| `<TODO: path>` | <TODO: one line> |

**Data / config:** <TODO: tables, schema, env vars needed — or "—">

## 5. Decisions & trade-offs

<TODO: What was chosen, what was dropped, why. What was DELIBERATELY not done (out of scope), so nobody later mistakes it for an oversight.>

## 6. Pitfalls when editing

<TODO: What breaks easily, invariants to preserve, hidden dependencies. What anyone editing this file needs to know first.>

## 7. Evidence

| `done_when` | How verified | Result |
|---|---|---|
| <TODO: criterion> | <TODO: command / action> | <TODO: pass + summary> |

**SECURITY gate:** <TODO: the result of the applicable security.md checklist>
The full output lives in `progress.md`; this is only a summary.

## 8. Updates

- <TODO: YYYY-MM-DD> — created at ship time.
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=15  FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add template/docs/features/_TEMPLATE.md tests/run-tests.sh
git commit -m "feat(template): add _TEMPLATE.md — the 8-section dossier for every feature"
```

---

### Task 3: The `doc` field in `feature_list.json`

**Files:**
- Modify: `template/feature_list.json` (add `"doc"` to F01/F02/F03; extend `_howto`)
- Modify: `tests/run-tests.sh` (add a `== feature_list.json ==` block)

**Interfaces:**
- Consumes: `check_docs()` from Task 1, which reads the `f.doc` field.
- Produces: every sample feature carrying a `doc` matching `^docs/features/<ID>-[a-z0-9-]+\.md$`.

- [ ] **Step 1: Add the tests (they will fail)**

Insert into `tests/run-tests.sh` before the summary block:

```bash
echo ""
echo "== feature_list.json =="

P="$(new_project)"

missing="$(node -e '
const j = require(process.argv[1] + "/feature_list.json");
console.log(j.features.filter(f => !f.doc).map(f => f.id).join(","));
' "$(win "$P")")"
if [ -z "$missing" ]; then ok "every sample feature has a doc field"; else ng "features missing doc: $missing"; fi

wrong="$(node -e '
const j = require(process.argv[1] + "/feature_list.json");
const bad = j.features.filter(f => !new RegExp("^docs/features/" + f.id + "-[a-z0-9-]+\\.md$").test(f.doc || ""));
console.log(bad.map(f => f.id).join(","));
' "$(win "$P")")"
if [ -z "$wrong" ]; then ok "doc follows the docs/features/<ID>-<slug>.md convention"; else ng "doc breaks the convention: $wrong"; fi

noverify="$(node -e '
const j = require(process.argv[1] + "/feature_list.json");
const bad = j.features.filter(f => !(f.verify || []).includes("./init.sh docs"));
console.log(bad.map(f => f.id).join(","));
' "$(win "$P")")"
if [ -z "$noverify" ]; then ok "sample features have ./init.sh docs in verify"; else ng "missing ./init.sh docs in verify: $noverify"; fi

hint="$(node -e '
const j = require(process.argv[1] + "/feature_list.json");
console.log(String(j._howto || "").includes("doc") ? "yes" : "no");
' "$(win "$P")")"
if [ "$hint" = "yes" ]; then ok "_howto explains the doc field"; else ng "_howto explains the doc field"; fi
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bash tests/run-tests.sh
```

Expected: `FAIL` on "every sample feature has a doc field" (listing `F01,F02,F03`), "doc follows the convention", "sample features have ./init.sh docs in verify", and "_howto explains the doc field".

- [ ] **Step 3: Edit `template/feature_list.json`**

Replace the current `_howto` string with (one line):

```json
  "_howto": "Every feature NEEDS: id, name, description, status (required by the validator). Add scope/done_when/verify so the Builder knows the boundaries and the test criteria. done_when must be testable. dependencies = list of ids that must finish first. doc = path to the dossier docs/features/<ID>-<slug>.md, REQUIRED once status is done/verified — ./init.sh docs checks for all 8 sections, in order, with no placeholders left.",
```

Add a `"doc"` field to each feature, immediately after `"status"`:

- F01: `"doc": "docs/features/F01-scaffold.md",`
- F02: `"doc": "docs/features/F02-data-layer.md",`
- F03: `"doc": "docs/features/F03-auth.md",`

F01 after the edit, for example:

```json
    {
      "id": "F01",
      "name": "Scaffold project",
      "description": "Stand up the project skeleton ({{STACK}}): directory structure per the Blueprint + .env.example + README. An empty build passes.",
      "dependencies": [],
      "status": "pending",
      "doc": "docs/features/F01-scaffold.md",
      "scope": ["directory structure per the Blueprint", ".env.example (lists every secret/config)", "README.md", "build/lint/test config"],
      "done_when": [
        "dependencies install cleanly",
        "the skeleton build passes",
        ".env.example lists every variable needed"
      ],
      "verify": ["./init.sh scaffold", "./init.sh docs"]
    },
```

Add `"./init.sh docs"` to the `verify` array of F01, F02 and F03.

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=19  FAIL=0`, exit 0. (The features are still `pending`, so `check_docs` skips them — no dossier file demanded.)

- [ ] **Step 5: Commit**

```bash
git add template/feature_list.json tests/run-tests.sh
git commit -m "feat(state): add the doc field to feature_list.json — pointing at the dossier"
```

---

### Task 4: Wire the rule into `CLAUDE.md` and `pipeline.md`

**Files:**
- Modify: `template/CLAUDE.md` (Source of truth, Startup Workflow, Verification Commands, Definition of Done, End of Session)
- Modify: `template/.claude/workflow/pipeline.md` (section 9 SHIP, Checkpoint gates)
- Modify: `tests/run-tests.sh` (add an `== instruction wiring ==` block)

**Interfaces:**
- Consumes: the `./init.sh docs` target (Task 1), the path convention + template (Task 2), the `doc` field (Task 3).
- Produces: the rule in writing, so the agent knows **when** to write a dossier and **what** blocks the ship.

- [ ] **Step 1: Add the tests (they will fail)**

Insert into `tests/run-tests.sh` before the summary block:

```bash
echo ""
echo "== instruction wiring =="

C="$KIT/template/CLAUDE.md"
PL="$KIT/template/.claude/workflow/pipeline.md"

has() { # has <description> <file> <pattern>
  if grep -qF "$3" "$2" 2>/dev/null; then ok "$1"; else ng "$1 (not found: $3)"; fi
}

has "CLAUDE.md points at docs/features/"        "$C"  "docs/features/"
has "CLAUDE.md mentions _TEMPLATE.md"           "$C"  "_TEMPLATE.md"
has "CLAUDE.md carries the ./init.sh docs command" "$C" "./init.sh docs"
has "CLAUDE.md DoD has a documented tier"       "$C"  "documented"
has "pipeline.md SHIP mentions the dossier"     "$PL" "dossier"
has "pipeline.md carries the ./init.sh docs command" "$PL" "./init.sh docs"
has "pipeline.md has the rule for updating an old F" "$PL" "section 8"

# The English anchors must stay intact (validate-harness.mjs relies on them)
for a in "Startup Workflow" "Verification Commands" "Definition of Done" "End of Session"; do
  has "CLAUDE.md keeps the anchor: $a" "$C" "$a"
done
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bash tests/run-tests.sh
```

Expected: the first 7 lines of the block FAIL (the last 4 anchors already pass, they exist already).

- [ ] **Step 3: Edit `template/CLAUDE.md`**

**3a.** In the `## Source of truth` section, insert after the `- **State:** ...` line:

```markdown
- **Feature dossier:** `docs/features/<ID>-<slug>.md` — the record of each shipped feature (8 sections: why it matters, what it does, how to use it, under the hood, decisions, pitfalls, evidence, updates). The path lives in the `doc` field in `feature_list.json`. Template: `docs/features/_TEMPLATE.md`.
```

**3b.** In `## Startup Workflow`, insert a new item 4 and renumber the last one to 5:

```markdown
4. **About to edit a feature that is already `done`?** Read its dossier (the `doc` field in `feature_list.json`) BEFORE touching any code — section 4 (under the hood) and section 6 (pitfalls) save a whole session of rediscovery.
5. **One feature at a time.** When it is finished → run verify → update the state → write the dossier → SHIP gate.
```

**3c.** In `## Verification Commands`, insert after the `./init.sh <target>` line:

```markdown
- `./init.sh docs` — every `done`/`verified` feature must have a valid dossier (all 8 sections, in order, no placeholders left). Included in `./init.sh all`.
```

**3d.** In `## Definition of Done`, insert after the `secured = ...` line:

```markdown
- `documented` = has a dossier at `docs/features/<ID>-<slug>.md` with all 8 sections, the `doc` field pointing at it, and `./init.sh docs` green.
```

**3e.** In `## End of Session`, change item 1 to:

```markdown
1. Update `feature_list.json` status + `doc` + `progress.md` (Current State + evidence). Anything just shipped → its dossier is already written.
```

- [ ] **Step 4: Edit `template/.claude/workflow/pipeline.md`**

**4a.** In `## 9. SHIP — gate + docs`, add a checkbox to the list (immediately before the `**Docs (Diataxis)**` line):

```markdown
- [ ] The **feature dossier** `docs/features/<ID>-<slug>.md` is finished, all 8 sections present, `feature_list.json` has the `doc` field, `./init.sh docs` is **green**. Start from `docs/features/_TEMPLATE.md`.
```

**4b.** Immediately after section 9's checkbox list, add:

```markdown
**Ripple:** if the feature being shipped **changes the behaviour of an older F**, you must add a dated line to **section 8 (Updates)** of that older F's dossier — inside this SHIP, never deferred. A dossier that drifts from the code is worse than no dossier.
```

**4c.** In `## Checkpoint gates (never skipped)`, change the `SHIP→next` line:

```markdown
- **SHIP→next:** state updated + evidence + docs in sync + **the feature dossier written** (`./init.sh docs` green).
```

- [ ] **Step 5: Run the tests to confirm they pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=30  FAIL=0`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add template/CLAUDE.md template/.claude/workflow/pipeline.md tests/run-tests.sh
git commit -m "feat(harness): wire the dossier rule into CLAUDE.md + the pipeline SHIP gate"
```

---

### Task 5: `README.md` + end-to-end verification

**Files:**
- Modify: `README.md`
- Modify: `tests/run-tests.sh` (add a `== README + e2e ==` block)

**Interfaces:**
- Consumes: all of Tasks 1-4.
- Produces: the complete kit; confirmation that `validate-harness.mjs` still scores 100/100.

- [ ] **Step 1: Add the tests (they will fail)**

Insert into `tests/run-tests.sh` before the summary block:

```bash
echo ""
echo "== README + e2e =="

R="$KIT/README.md"
if grep -qF "_TEMPLATE.md" "$R"; then ok "README lists _TEMPLATE.md in the directory tree"; else ng "README lists _TEMPLATE.md"; fi
if grep -qF "dossier" "$R"; then ok "README explains the dossier"; else ng "README explains the dossier"; fi

# bootstrap --dry-run must list the new template file
P="$KIT/.tmp-tests/dry"
rm -rf "$P"; mkdir -p "$P"
if node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "Dry" --dry-run 2>&1 \
   | grep -qE 'docs[\\/]features[\\/]_TEMPLATE\.md'; then
  ok "bootstrap --dry-run lists docs/features/_TEMPLATE.md"
else
  ng "bootstrap --dry-run lists docs/features/_TEMPLATE.md"
fi

# ./init.sh all must run the FEATURE DOCS block
P="$(new_project)"
if bash "$P/init.sh" all 2>&1 | grep -qF "FEATURE DOCS"; then
  ok "./init.sh all does run check_docs"
else
  ng "./init.sh all does run check_docs"
fi
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bash tests/run-tests.sh
```

Expected: the first 2 lines of the block FAIL (the README says nothing yet); the last 2 already pass from Tasks 1-2.

- [ ] **Step 3: Edit `README.md`**

**3a.** In the "Layout of the kit" tree, add to the `template/` part (after the `init.sh` line):

```
    ├── docs/features/
    │   └── _TEMPLATE.md      # the 8-section dossier — copy it when you finish shipping a feature
```

**3b.** In the "5 subsystems" table, change the State row:

```markdown
| State | `feature_list.json`, `progress.md`, `docs/features/<ID>-<slug>.md` | which feature, whether it is done, the evidence, and the **dossier** describing each shipped feature |
```

**3c.** In "After bootstrapping — adapt it to the project", add after item 6:

```markdown
7. **Dossiers** — nothing to fill in up front. Each time you ship an F, copy `docs/features/_TEMPLATE.md` to `docs/features/<ID>-<slug>.md`, write all 8 sections, and point the `doc` field in `feature_list.json` at it. `./init.sh docs` blocks the ship if it is missing.
```

And renumber the current "Audit" item (7) to 8.

**3d.** In "Notes", change the node-requirement line to:

```markdown
- Requires `node` (for bootstrap + `./init.sh docs`) + `bash` (to run `init.sh`; use Git Bash on Windows). With no `node`, `check_docs` prints SKIP rather than faking a pass.
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=34  FAIL=0`, exit 0.

- [ ] **Step 5: Run the validator — it must stay at 100/100**

```bash
cd "<path>/harness-kit"
rm -rf .tmp-tests/audit && mkdir -p .tmp-tests/audit
W() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
node "$(W "$PWD/bootstrap.mjs")" --target "$(W "$PWD/.tmp-tests/audit")" --name "Audit Project" --stack "node"
node "$(W "<path-to-harness-creator>/scripts/validate-harness.mjs")" \
     --target "$(W "$PWD/.tmp-tests/audit")"
rm -rf .tmp-tests
```

Expected: a total score of **100/100** across the 5 subsystems (instructions, state, verification, scope, lifecycle).

If the score drops: read the report to see which subsystem lost points and check the English anchors in `CLAUDE.md` (Task 4 Step 1 already has tests pinning all 4 anchors) — fix, then re-run Steps 4 and 5.

- [ ] **Step 6: Commit**

```bash
git add README.md tests/run-tests.sh
git commit -m "docs(readme): update the layout + the State subsystem for the feature dossier"
```

---

## Final check (after Task 5)

- [ ] `bash tests/run-tests.sh` → `PASS=34  FAIL=0`, exit 0
- [ ] `node bootstrap.mjs --target <empty dir> --name X --dry-run` lists `docs/features/_TEMPLATE.md`
- [ ] `validate-harness.mjs` → 100/100
- [ ] `git log --oneline` → 6 commits (baseline + 5 tasks)
- [ ] `git status` clean
