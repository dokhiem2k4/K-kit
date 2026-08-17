# Tier / Rollback / Frontmatter / Drift-lock — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** add a `tier` classification for features, a Rollback section in the dossier, machine-readable frontmatter, and an assertion locking the SHIP checklist against drift.

**Architecture:** three sequential chunks. Chunk 1 adds the `tier` field to `feature_list.json` and a new blocking rule in `hooks/verify-gate.js` (the agent may only raise a tier). Chunk 2 extracts `check_docs` into `template/scripts/check-docs.mjs` and then extends it: 9 sections, frontmatter, tier-aware. Chunk 3 unifies the SHIP checklist between `pipeline.md` and the skill, then locks it with a two-sided assertion.

**Tech Stack:** bash + node (no dependencies), Markdown, JSON. The tests are bash assertion scripts.

**Spec:** `docs/superpowers/specs/2026-08-04-harness-tier-rollback-design.md`

## Global Constraints

- **Only `node` + `bash`.** No new dependency, no `package.json` added to the kit.
- **`node -e '...'` is wrapped in single quotes** → the node code inside **must not use single quotes**. Use double quotes or backticks. This is why `verify-gate.js` was once split out of the bash hook.
- **The `VERIFY OK` contract is inviolable.** `init.sh` must keep both strings `VERIFY OK` / `VERIFY FAILED` intact. Do not touch the marker logic of `verify-gate` for `status`.
- **Everything is written in English** — comments, strings and output alike, matching the rest of the repo.
- **The English anchors in `template/`** (Startup Workflow / Definition of Done / ...) stay intact so the external validator keeps passing.
- **The tier scale:** `lite` < `standard` < `strict`. Absent = `standard`.
- **Run the tests with:** `bash tests/run-tests.sh`, `bash tests/test-verify-gate.sh`.

---

# CHUNK 1 — Tier

### Task 1: The `tier` field in the template state

**Files:**
- Modify: `template/feature_list.json:6-10` (legend + `_howto`), `:12-48` (the 3 sample features)
- Test: `tests/run-tests.sh` (a new section before `== _TEMPLATE.md ==`)

**Interfaces:**
- Consumes: —
- Produces: a `tier` field with the value `"lite" | "standard" | "strict"` on every object in `features[]`. Tasks 2 and 5 read this field.

- [ ] **Step 1: Write the failing assertions**

Add to `tests/run-tests.sh` immediately before the `echo "== _TEMPLATE.md =="` line:

```bash
echo ""
echo "== tier in the template =="

FLT="$KIT/template/feature_list.json"
tier_of() { node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const f = j.features.find(x => x.id === process.argv[2]);
console.log(f && f.tier ? f.tier : "");
' "$(win "$1")" "$2"; }

for pair in "F01 standard" "F02 strict" "F03 strict"; do
  set -- $pair
  got="$(tier_of "$FLT" "$1")"
  if [ "$got" = "$2" ]; then ok "template $1 has tier=$2"
  else ng "template $1 has tier=$2 (found: ${got:-none})"; fi
done

if grep -q 'lite' "$FLT"; then ok "feature_list.json explains the tier scale"
else ng "feature_list.json explains the tier scale"; fi
```

- [ ] **Step 2: Run it to confirm red**

Run: `bash tests/run-tests.sh 2>&1 | grep -A 6 "tier in the template"`
Expected: 4 `FAIL` lines, and `PASS=... FAIL=4` at the end.

- [ ] **Step 3: Add `tier` to `template/feature_list.json`**

Change `legend` (lines 6-9) to:

```json
  "legend": {
    "status": ["pending", "in_progress", "blocked", "done", "verified", "deferred"],
    "tier": ["lite", "standard", "strict"],
    "rule": "One feature at a time. 'done' needs evidence in progress.md. Dependencies must be done first. Replace the examples below with the real features of {{PROJECT_NAME}}."
  },
```

Replace `_howto` (line 10) with:

```json
  "_howto": "Every feature NEEDS: id, name, description, status (required by the validator). Add scope/done_when/verify so the Builder knows the boundaries and the test criteria. done_when must be testable. dependencies = list of ids that must finish first. doc = path to the dossier docs/features/<ID>-<slug>.md, REQUIRED once status is done/verified. tier = lite|standard|strict, ABSENT = standard; the Homeowner sets the tier, the agent may only RAISE it (verify-gate blocks every attempt to lower it). lite = exempt from the dossier + review, but still must run init.sh; strict = section 9 Rollback must have real content. ./init.sh docs checks according to the tier.",
```

Add `"tier"` to each feature, immediately after `"status"`:

- `F01` (line 17): `"status": "pending",` → `"status": "pending",\n      "tier": "standard",`
- `F02` (line 32): `"status": "pending",` → `"status": "pending",\n      "tier": "strict",`
- `F03` (line 44): `"status": "pending",` → `"status": "pending",\n      "tier": "strict",`

F02 (the data layer, with access control) and F03 (auth) are `strict` because those are exactly the kind of feature spec §3.2 classifies as `strict`. F01 scaffold stays `standard` as the default example.

- [ ] **Step 4: Run it to confirm green**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`. The JSON must parse — if `FAIL` is non-zero with a parse error, check the commas.

- [ ] **Step 5: Commit**

```bash
git add template/feature_list.json tests/run-tests.sh
git commit -m "feat(tier): add the tier field to feature_list.json — absent = standard"
```

---

### Task 2: The tier-lowering block in `verify-gate.js`

**Files:**
- Modify: `hooks/verify-gate.js:78-91` (insert the tier block at the start of the `pre-edit` branch)
- Test: `tests/test-verify-gate.sh` (add section 13 before the `--- 12. Garbage JSON` section)

**Interfaces:**
- Consumes: the `tier` field from Task 1.
- Produces: `permissionDecision: "deny"` whenever the resulting tier is lower than the previous one. No new API.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-verify-gate.sh` immediately **before** the `# --- 12. Garbage JSON on stdin` line:

```bash
# --- 13. Tier: the agent may only RAISE, never LOWER ------------------------------
# This rule DIFFERS from the status rule: it does not depend on the marker and does not fail open,
# because a valid path always exists (do not lower the tier, or ask the Homeowner). Fail-open is
# only right when no path to satisfying the gate remains.
mkdir -p "$WORK/p4"
mkinit "$WORK/p4"
FL4="$WORK/p4/feature_list.json"
cat > "$FL4" <<'JSON'
{"active_feature":"F01","features":[{"id":"F01","name":"a","status":"pending","tier":"strict"},{"id":"F02","name":"b","status":"pending","tier":"standard"}]}
JSON

# 13a. Lowering the tier via Edit -> BLOCKED
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL4\",\"old_string\":\"\\\"tier\\\":\\\"strict\\\"\",\"new_string\":\"\\\"tier\\\":\\\"lite\\\"\"}")"
if denied "$out"; then ok "lowering the tier via Edit -> BLOCKED"; else ng "lowering the tier via Edit -> BLOCKED"; fi

# 13b. The refusal reason must say who is allowed to set the tier
if printf '%s' "$out" | grep -q 'Homeowner'; then ok "the tier refusal names the Homeowner as the decider"; else ng "the tier refusal names the Homeowner as the decider"; fi

# 13c. Lowering the tier via Write -> BLOCKED
reset_marker
lower="$(node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
j.features[0].tier="standard";
console.log(JSON.stringify(j));
' "$FL4")"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL4" "$lower")")"
if denied "$out"; then ok "lowering the tier via Write -> BLOCKED"; else ng "lowering the tier via Write -> BLOCKED"; fi

# 13d. A NEW feature set to tier lite -> BLOCKED (lower than the standard default)
reset_marker
added="$(node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
j.features.push({id:"F09",name:"c",status:"pending",tier:"lite"});
console.log(JSON.stringify(j));
' "$FL4")"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL4" "$added")")"
if denied "$out"; then ok "a new feature set to tier lite -> BLOCKED"; else ng "a new feature set to tier lite -> BLOCKED"; fi

# 13e. RAISING the tier -> allowed
reset_marker
raise="$(node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
j.features[1].tier="strict";
console.log(JSON.stringify(j));
' "$FL4")"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL4" "$raise")")"
if denied "$out"; then ng "raising the tier -> allowed"; else ok "raising the tier -> allowed"; fi

# 13f. Still BLOCKED with a marker present — the tier rule does not depend on verify evidence
reset_marker
fire post-bash '{}' 'VERIFY OK (all)' >/dev/null
out="$(fire pre-edit "{\"file_path\":\"$FL4\",\"old_string\":\"\\\"tier\\\":\\\"strict\\\"\",\"new_string\":\"\\\"tier\\\":\\\"lite\\\"\"}")"
if denied "$out"; then ok "still BLOCKED with a marker present"; else ng "still BLOCKED with a marker present"; fi
```

- [ ] **Step 2: Run it to confirm red**

Run: `bash tests/test-verify-gate.sh 2>&1 | tail -20`
Expected: 5 `FAIL` lines (13a, 13b, 13c, 13d, 13f). 13e is already green because the gate blocks nothing yet.

- [ ] **Step 3: Install the tier rule**

In `hooks/verify-gate.js`, replace the block from line 78 (`// ---- pre-edit`) through line 80 (`if (base !== "feature_list.json") process.exit(0);`) with:

```js
// ---------------------------------------------------------------- pre-edit
if (mode !== "pre-edit") process.exit(0);
if (base !== "feature_list.json") process.exit(0);

// --- The TIER rule --------------------------------------------------------
// It differs from the status rule in two ways, both deliberate:
//   1. It does NOT depend on the marker — lowering a tier is not a question of evidence but of authority.
//   2. It does NOT fail open — a valid path always exists (do not lower the tier, or ask the Homeowner),
//      so refusing here is still a gate rather than a hard lock.
const TIER_RANK = { lite: 0, standard: 1, strict: 2 };
const tierOf = (f) => {
  const t = f && typeof f.tier === "string" ? f.tier.trim() : "";
  return t in TIER_RANK ? t : "standard";
};

// The file content AFTER this write. Write -> content directly; Edit/MultiEdit -> read the disk
// and apply each old_string -> new_string in turn. Not reconstructible -> return null, and in that
// case the tier is not judged (following the precedent: when undetermined, keep checking, never refuse blindly).
function resultingText() {
  if (typeof toolInput.content === "string") return toolInput.content;
  let text;
  try { text = fs.readFileSync(filePath, "utf8"); } catch { return null; }
  const edits = (toolInput.edits || []).length
    ? toolInput.edits
    : [{ old_string: toolInput.old_string, new_string: toolInput.new_string }];
  for (const e of edits) {
    if (!e || typeof e.old_string !== "string" || typeof e.new_string !== "string") return null;
    const i = text.indexOf(e.old_string);
    if (i < 0) return null;
    text = text.slice(0, i) + e.new_string + text.slice(i + e.old_string.length);
  }
  return text;
}

const afterText = resultingText();
if (afterText !== null) {
  let beforeJson = null, afterJson = null;
  try { beforeJson = JSON.parse(fs.readFileSync(filePath, "utf8")); } catch {}
  try { afterJson = JSON.parse(afterText); } catch {}
  if (afterJson) {
    const prev = new Map(((beforeJson && beforeJson.features) || []).map((f) => [f.id, tierOf(f)]));
    for (const f of afterJson.features || []) {
      const was = prev.has(f.id) ? prev.get(f.id) : "standard";
      const now = tierOf(f);
      if (TIER_RANK[now] < TIER_RANK[was]) {
        process.stdout.write(JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason:
              "BLOCKED by harness-kit verify-gate.\n\n" +
              "You are lowering the tier of " + (f.id || "(feature with no id)") + ": " + was + " -> " + now + ".\n" +
              "The tier is set by the Homeowner, not the agent. The agent may only RAISE a tier.\n\n" +
              "A new feature with no tier written falls back to \"standard\" — that is the correct default.\n" +
              "Need tier \"lite\" (exempt from the dossier + review, but STILL runs init.sh)? That is an exemption,\n" +
              "and an exemption needs a human signature: ask the Homeowner to edit feature_list.json themselves.\n\n" +
              "See skill harness-kit:planning-features.",
          },
        }));
        process.exit(0);
      }
    }
  }
}
// --- end of the TIER rule -------------------------------------------------
```

- [ ] **Step 4: Run it to confirm green**

Run: `bash tests/test-verify-gate.sh`
Expected: `FAIL=0`. All 18 existing assertions must stay green — if case 8 (`a Write keeping the same done count`) goes red, the tier rule is wrongly blocking an operation that does not change any tier.

- [ ] **Step 5: Commit**

```bash
git add hooks/verify-gate.js tests/test-verify-gate.sh
git commit -m "feat(gate): block tier lowering — the agent may only raise, independent of the marker"
```

---

### Task 3: Instructions for the tier

**Files:**
- Modify: `skills/planning-features/SKILL.md`, `template/CLAUDE.md:57-73`
- Test: `tests/run-tests.sh` (append to the `== tier in the template ==` section from Task 1)

**Interfaces:**
- Consumes: the tier scale from Task 1, the blocking behaviour from Task 2.
- Produces: — (documentation only)

- [ ] **Step 1: Write the failing assertions**

Append to the end of the `== tier in the template ==` section in `tests/run-tests.sh`:

```bash
C="$KIT/template/CLAUDE.md"
if grep -q 'tier' "$C"; then ok "CLAUDE.md explains the tier"; else ng "CLAUDE.md explains the tier"; fi
PF="$KIT/skills/planning-features/SKILL.md"
if grep -q 'tier' "$PF"; then ok "planning-features mentions the tier"; else ng "planning-features mentions the tier"; fi
if grep -q 'Homeowner' "$PF"; then ok "planning-features says who sets the tier"; else ng "planning-features says who sets the tier"; fi
```

- [ ] **Step 2: Run it to confirm red**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "CLAUDE.md explains the tier|planning-features"`
Expected: 3 `FAIL` lines (whether `planning-features` already mentions `Homeowner` is answered by this very run — if the third assertion is already green, leave it, that is not an error).

- [ ] **Step 3: Add a tier section to `template/CLAUDE.md`**

Insert immediately **before** the `## Definition of Done (per feature)` heading (line 68):

```markdown
## Tier — grading the process cost  ← the Homeowner sets it, the agent may only RAISE it
Every feature has a `tier` in `feature_list.json`. **Absent = `standard`.**

| | `lite` | `standard` | `strict` |
|---|---|---|---|
| The relevant `init.sh` + secret grep | ✅ | ✅ | ✅ |
| Dossier | ❌ (one line of evidence in `progress.md`) | ✅ 9 sections | ✅ 9 sections |
| Section 9 Rollback | — | may be `—` | **must have real content** |
| `parallel-review` | ❌ | optional | ✅ |
| Security checklist | reduced (secret grep) | the relevant parts | full STRIDE |

**Verify runs at EVERY tier** — no tier is exempt from `init.sh`. A tier only changes the documentation and review cost,
so a wrongly assigned tier makes the documentation thin, never the code unchecked.
`verify-gate` blocks every attempt to lower a tier. Need `lite`? That is an exemption — the Homeowner edits the file themselves.
```

- [ ] **Step 4: Edit `skills/planning-features/SKILL.md`**

Add a section to the skill body (after the part about `done_when`, before the red flags):

```markdown
## Tier — ask before writing

Every new feature needs a tier. Ask the Homeowner one question:

> "What tier is this F? lite (typos/docs/small refactors — no dossier), standard (the default),
> or strict (auth/security/migrations/architecture — a real Rollback section required)?"

Cannot ask, or the Homeowner has not answered → **do not write the tier field**. Absent = standard,
and standard is the correct default.

**You may NOT set tier lite yourself.** verify-gate will refuse that write, even right after a green
verify run. lite exempts a feature from the dossier + review, so it needs a human signature:
the Homeowner edits feature_list.json. You may only RAISE a tier (standard -> strict) when you see
the feature touching auth/data/secrets/migrations.
```

- [ ] **Step 5: Run it to confirm green**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add template/CLAUDE.md skills/planning-features/SKILL.md tests/run-tests.sh
git commit -m "docs(tier): the tier table in CLAUDE.md + the ask-the-Homeowner rule in planning-features"
```

---

# CHUNK 2 — Dossier schema

### Task 4: `_TEMPLATE.md` — frontmatter + section 9

**Files:**
- Modify: `template/docs/features/_TEMPLATE.md:1-17` (the header), end of file (section 9)
- Test: `tests/run-tests.sh:149-172` (the `== _TEMPLATE.md ==` section)

**Interfaces:**
- Consumes: the tier scale from Task 1.
- Produces: the dossier schema that Tasks 5 and 6 will validate — 9 headings `## 1.` … `## 9.`, a frontmatter block with 8 keys: `feature`, `status`, `tier`, `date`, `commit`, `blueprint`, `security`, `reversible`. Three bold labels in section 9: `**How to revert:**`, `**CANNOT be reverted:**`, `**Signs a rollback is needed:**`.

- [ ] **Step 1: Update the assertions for 9 sections + frontmatter**

In `tests/run-tests.sh`, find the `_TEMPLATE.md has all 8 sections in order` assertion block (around lines 156-162) and change `1,2,3,4,5,6,7,8` to `1,2,3,4,5,6,7,8,9`, and the wording `8 sections` to `9 sections`. The heading regex must change from `[1-8]` to `[1-9]`.

Append to the end of the `== _TEMPLATE.md ==` section:

```bash
if head -1 "$T" | grep -q '^---$'; then ok "_TEMPLATE.md opens with frontmatter"; else ng "_TEMPLATE.md opens with frontmatter"; fi
for k in feature status tier date commit blueprint security reversible; do
  if grep -qE "^${k}:" "$T"; then ok "_TEMPLATE.md frontmatter has the key $k"; else ng "_TEMPLATE.md frontmatter has the key $k"; fi
done
if grep -qF '**How to revert:**' "$T"; then ok "_TEMPLATE.md section 9 has the 'How to revert' label"; else ng "_TEMPLATE.md section 9 has the 'How to revert' label"; fi
if grep -qF '**CANNOT be reverted:**' "$T"; then ok "_TEMPLATE.md section 9 has the 'CANNOT be reverted' label"; else ng "_TEMPLATE.md section 9 has the 'CANNOT be reverted' label"; fi
if grep -qF '**Signs a rollback is needed:**' "$T"; then ok "_TEMPLATE.md section 9 has the 'Signs a rollback is needed' label"; else ng "_TEMPLATE.md section 9 has the 'Signs a rollback is needed' label"; fi
```

- [ ] **Step 2: Run it to confirm red**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "_TEMPLATE"`
Expected: `9 sections` FAIL, `frontmatter` FAIL, all 8 keys FAIL, all 3 labels FAIL.

- [ ] **Step 3: Rewrite the header of `_TEMPLATE.md`**

Replace lines 1-17 (from `# <TODO: F0X>` through the end of the `<!-- ... -->` block) with:

```markdown
---
feature: <TODO: F0X>
status: <TODO: done | verified>
tier: <TODO: standard | strict>
date: <TODO: YYYY-MM-DD>
commit: <TODO: sha>
blueprint: <TODO: section>
security: <TODO: passed | n/a>
reversible: <TODO: true | false>
---

# <TODO: F0X> — <TODO: Feature name>

<!--
FEATURE DOSSIER — copy this file to docs/features/<ID>-<slug>.md when you ship a feature.

Rules:
- Write it at the SHIP gate, after VERIFY + SECURITY + DEVEX have passed.
- Keep all 9 headings below, in order, worded exactly. A section that does not apply gets "—", NEVER delete the heading.
- Remove every <TODO: ...> placeholder and every guidance comment before shipping.
- ./init.sh docs will FAIL on a missing section, a wrong order, a leftover placeholder / comment,
  or frontmatter that disagrees with feature_list.json.

Frontmatter:
- feature / status / tier MIRROR feature_list.json — a mismatch is a FAIL, not a warning.
- The other 5 fields belong to the dossier; feature_list.json holds no copy of them.
- tier: lite needs NO dossier — a lite feature records its evidence directly in progress.md.
  This file is only for standard and strict.

The boundary between sections 1 and 2 — do not write it twice:
- Section 1 = zoom out. The feature's role in the system. Why the project NEEDS it.
- Section 2 = zoom in. Observable behaviour. Press/call what, get what.
-->
```

- [ ] **Step 4: Append section 9 to `_TEMPLATE.md`**

Add at the end of the file, after section 8:

```markdown
## 9. Rollback & Recovery

<!--
tier: strict -> "How to revert" MUST have real content, it may not be "—".
tier: standard -> all three lines may be "—", but the heading must remain.
The middle line is the most valuable one: forward-fix cures code, it does not cure what already happened.
-->

**How to revert:** <TODO: concrete commands/steps — which commit to revert, which version to roll back, which flag to turn off>

**CANNOT be reverted:** <TODO: migrations already run, data already overwritten, webhooks/emails already sent, third-party caches — or "—">

**Signs a rollback is needed:** <TODO: observable symptoms, concrete thresholds — or "—">
```

- [ ] **Step 5: Run it to confirm green**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "_TEMPLATE"`
Expected: every `_TEMPLATE` line PASSes. The older `check_docs` assertions are still red — correct, Tasks 5 and 6 fix those.

- [ ] **Step 6: Commit**

```bash
git add template/docs/features/_TEMPLATE.md tests/run-tests.sh
git commit -m "feat(dossier): frontmatter + section 9 Rollback in _TEMPLATE.md"
```

---

### Task 5: Extract `check_docs` into `scripts/check-docs.mjs`

Extract first, extend second. Merging both into one edit means that when a test goes red you cannot tell whether it was the extraction or the new rule.

**Files:**
- Create: `template/scripts/check-docs.mjs`
- Modify: `template/init.sh:98-131` (the body of `check_docs`)
- Test: `tests/run-tests.sh` (add 1 assertion to the `== _TEMPLATE.md ==` section, or the bootstrap section)

**Interfaces:**
- Consumes: `feature_list.json` in the cwd.
- Produces: `template/scripts/check-docs.mjs` — run as `node scripts/check-docs.mjs` from the repo root, exit 0 = valid, 1 = a `[FAIL]` occurred. Task 6 extends this same file.

- [ ] **Step 1: Write the failing assertions**

Add to `tests/run-tests.sh` (at the end of the `== _TEMPLATE.md ==` section):

```bash
if [ -f "$P/scripts/check-docs.mjs" ]; then ok "bootstrap copies scripts/check-docs.mjs"; else ng "bootstrap copies scripts/check-docs.mjs"; fi
if grep -q 'scripts/check-docs.mjs' "$P/init.sh"; then ok "init.sh calls scripts/check-docs.mjs"; else ng "init.sh calls scripts/check-docs.mjs"; fi
```

- [ ] **Step 2: Run it to confirm red**

Run: `bash tests/run-tests.sh 2>&1 | grep "check-docs"`
Expected: 2 FAIL lines.

- [ ] **Step 3: Create `template/scripts/check-docs.mjs` — a straight port of the existing logic**

```js
// check-docs.mjs — validate the dossier of every done/verified feature.
// Run from the repo root: node scripts/check-docs.mjs
// Exit 0 = valid, 1 = a [FAIL] occurred.
//
// Split out of init.sh for the same reason verify-gate.js was once split out of the bash hook:
// this logic outgrew what fits inside `node -e '...'`, where single quotes cannot be used.
import fs from "node:fs";

const DONE = ["done", "verified"];
const WANT = "1,2,3,4,5,6,7,8";

let bad = 0;
let n = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };

const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));

for (const f of j.features || []) {
  if (!DONE.includes(f.status)) continue;
  n++;
  const id = f.id || "(feature with no id)";
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "missing the \"doc\" field in feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "dossier not found: " + p); continue; }
  const t = fs.readFileSync(p, "utf8");

  const nums = t.split(/\r?\n/)
    .filter((l) => /^##\s+[1-8]\./.test(l))
    .map((l) => l.match(/^##\s+([1-8])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " must have all 8 sections ## 1. .. ## 8. in order (currently: " + (nums.join(",") || "no sections at all") + ")");
    continue;
  }
  if (t.includes("<TODO:")) { fail(id, p + " still contains a <TODO: placeholder"); continue; }
  if (t.includes("<!--")) { fail(id, p + " still contains uncleaned HTML guidance comments"); continue; }
}

if (n === 0) console.log("   (no feature is done/verified yet — skip)");
else if (!bad) console.log("   OK: all " + n + " done/verified features have a valid dossier");
process.exit(bad);
```

- [ ] **Step 4: Shrink `check_docs` in `template/init.sh`**

Replace the whole function body (lines 98-131) with:

```bash
check_docs() {
  step "FEATURE DOCS (dossier for done/verified features)"
  command -v node >/dev/null 2>&1 || { skip "no node — cannot validate dossiers"; return; }
  [ -f feature_list.json ] || { skip "no feature_list.json"; return; }
  [ -f scripts/check-docs.mjs ] || { skip "no scripts/check-docs.mjs"; return; }
  node scripts/check-docs.mjs || FAIL=1
}
```

- [ ] **Step 5: Run it to confirm green**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "check_docs|check-docs" -A 1`
Expected: the 2 new assertions PASS, and **all 9 original `== check_docs ==` assertions still PASS** — that is the evidence the extraction changed no behaviour.

- [ ] **Step 6: Commit**

```bash
git add template/scripts/check-docs.mjs template/init.sh tests/run-tests.sh
git commit -m "refactor(init): extract check_docs into scripts/check-docs.mjs — behaviour unchanged"
```

---

### Task 6: Extend `check-docs.mjs` — 9 sections, frontmatter, tier

**Files:**
- Modify: `template/scripts/check-docs.mjs` (rewritten in full)
- Test: `tests/run-tests.sh:48-146` (the `valid_dossier` fixture + the `== check_docs ==` section)

**Interfaces:**
- Consumes: the schema from Task 4, the script from Task 5, the `tier` field from Task 1.
- Produces: the final validator behaviour. No exports — the script runs standalone.

- [ ] **Step 1: Update the `valid_dossier()` fixture and add the new assertions**

In `tests/run-tests.sh`, replace the `valid_dossier()` function (lines 48-79) with:

```bash
# Print a valid dossier (frontmatter + all 9 sections, no placeholders).
# The fixture's default tier is standard -> section 9 may be "—".
valid_dossier() {
  cat <<'MD'
---
feature: F01
status: done
tier: standard
date: 2026-07-23
commit: a1b2c3d
blueprint: §1
security: passed
reversible: true
---

# F01 — Scaffold project

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

## 9. Rollback & Recovery

**How to revert:** `git revert <sha>` — the scaffold leaves no state outside the repo.

**CANNOT be reverted:** —

**Signs a rollback is needed:** —
MD
}
```

Update two existing assertion descriptions to match 9 sections: `expect_docs "sections 6-8 missing -> fail"` → `"sections 6-9 missing -> fail"`, and `"8 sections in the wrong order -> fail"` → `"9 sections in the wrong order -> fail"`.

Append the new assertions to the end of the `== check_docs ==` section (immediately before `echo "== _TEMPLATE.md =="`):

```bash
# --- tier lite: fully exempt from the dossier ---
P="$(new_project)"
patch_feature "$P" F01 '{"status":"done","tier":"lite","doc":null}'
expect_docs "tier lite done needs no dossier -> pass" 0 "$P"

# --- missing frontmatter ---
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed '1,10d' > "$P/$DOC"
expect_docs "a dossier with no frontmatter -> fail" 1 "$P"

# --- a mismatched frontmatter mirror ---
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed 's/^feature: F01$/feature: F99/' > "$P/$DOC"
expect_docs "frontmatter feature disagrees with feature_list -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"verified\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier > "$P/$DOC"
expect_docs "frontmatter status=done but feature_list=verified -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier > "$P/$DOC"
expect_docs "frontmatter tier=standard but feature_list=strict -> fail" 1 "$P"

# --- tier strict: section 9 must have real content ---
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' \
  -e 's|^\*\*How to revert:\*\*.*|**How to revert:** —|' > "$P/$DOC"
expect_docs "tier strict with 'How to revert' set to a dash -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' \
  -e '/^\*\*Signs a rollback is needed:\*\*/d' > "$P/$DOC"
expect_docs "tier strict missing the 'Signs a rollback is needed' label -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed 's/^tier: standard$/tier: strict/' > "$P/$DOC"
expect_docs "tier strict fully filled in -> pass" 0 "$P"

# --- reversible: false at tier strict -> WARN, not fail ---
# This field is self-declared by the agent. Making it a hard gate would only teach the agent to write reversible: true.
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' -e 's/^reversible: true$/reversible: false/' > "$P/$DOC"
expect_docs "reversible false at strict -> still passes (warning only)" 0 "$P"
if bash "$P/init.sh" docs 2>&1 | grep -q 'WARN'; then ok "reversible false at strict -> prints a warning"; else ng "reversible false at strict -> prints a warning"; fi

# --- an invalid tier ---
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"medium\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier > "$P/$DOC"
expect_docs "an invalid tier -> fail" 1 "$P"
```

- [ ] **Step 2: Run it to confirm red**

Run: `bash tests/run-tests.sh 2>&1 | sed -n '/== check_docs ==/,/== tier in the template ==/p'`
Expected: many FAILs — both the existing assertions (the fixture now has frontmatter + 9 sections while the validator still demands 8) and the new ones.

- [ ] **Step 3: Rewrite `template/scripts/check-docs.mjs`**

```js
// check-docs.mjs — validate the dossier of every done/verified feature.
// Run from the repo root: node scripts/check-docs.mjs
// Exit 0 = valid, 1 = a [FAIL] occurred. A [WARN] does not fail.
//
// Split out of init.sh for the same reason verify-gate.js was once split out of the bash hook:
// single quotes cannot be used inside `node -e '...'`, and this logic grew too large to fit anyway.
import fs from "node:fs";

const DONE = ["done", "verified"];
const TIERS = ["lite", "standard", "strict"];
const WANT = "1,2,3,4,5,6,7,8,9";
const MIRROR = ["feature", "status", "tier"];
const RB_HOW = "**How to revert:**";
const RB_LABELS = [RB_HOW, "**CANNOT be reverted:**", "**Signs a rollback is needed:**"];

let bad = 0;
let n = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };
const warn = (id, msg) => { console.log("   [WARN] " + id + ": " + msg); };

// FLAT YAML — only key: value. No nesting, no lists. Returns null if there is no valid block.
function frontmatter(text) {
  const lines = text.split(/\r?\n/);
  if (lines[0].trim() !== "---") return null;
  const end = lines.indexOf("---", 1);
  if (end < 0) return null;
  const out = {};
  for (const raw of lines.slice(1, end)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf(":");
    if (i < 0) continue;
    let val = line.slice(i + 1);
    const c = val.indexOf(" #");            // an end-of-line comment
    if (c >= 0) val = val.slice(0, c);
    val = val.trim().replace(/^"(.*)"$/, "$1");
    out[line.slice(0, i).trim()] = val;
  }
  return out;
}

// The body of "## N." — from that heading to the next level-2 heading.
function section(text, num) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => new RegExp("^##\\s+" + num + "\\.").test(l));
  if (start < 0) return "";
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((l) => /^##\s/.test(l));
  return (end < 0 ? rest : rest.slice(0, end)).join("\n");
}

const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));

for (const f of j.features || []) {
  if (!DONE.includes(f.status)) continue;
  const id = f.id || "(feature with no id)";
  const tier = typeof f.tier === "string" && f.tier.trim() ? f.tier.trim() : "standard";

  if (!TIERS.includes(tier)) {
    fail(id, "invalid tier: \"" + tier + "\" (only accepts " + TIERS.join("|") + ")");
    continue;
  }

  // lite is exempt from the dossier — its evidence lives in progress.md. See the Tier section in CLAUDE.md.
  if (tier === "lite") {
    console.log("   (" + id + ": tier lite — no dossier required, evidence in progress.md)");
    continue;
  }

  n++;
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "missing the \"doc\" field in feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "dossier not found: " + p); continue; }
  const t = fs.readFileSync(p, "utf8");

  const nums = t.split(/\r?\n/)
    .filter((l) => /^##\s+[1-9]\./.test(l))
    .map((l) => l.match(/^##\s+([1-9])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " must have all 9 sections ## 1. .. ## 9. in order (currently: " + (nums.join(",") || "no sections at all") + ")");
    continue;
  }
  if (t.includes("<TODO:")) { fail(id, p + " still contains a <TODO: placeholder"); continue; }
  if (t.includes("<!--")) { fail(id, p + " still contains uncleaned HTML guidance comments"); continue; }

  const fm = frontmatter(t);
  if (!fm) { fail(id, p + " has no YAML frontmatter block (--- on the first line)"); continue; }
  const missing = MIRROR.filter((k) => !(k in fm));
  if (missing.length) { fail(id, p + " frontmatter is missing fields: " + missing.join(", ")); continue; }

  const mismatch = [
    ["feature", fm.feature, id],
    ["status", fm.status, f.status],
    ["tier", fm.tier, tier],
  ].find(([, got, want]) => got !== want);
  if (mismatch) {
    fail(id, p + " frontmatter " + mismatch[0] + "=\"" + mismatch[1] +
             "\" disagrees with feature_list.json (\"" + mismatch[2] + "\")");
    continue;
  }

  if (tier === "strict") {
    const body = section(t, 9);
    const miss = RB_LABELS.filter((lb) => !body.includes(lb));
    if (miss.length) { fail(id, p + " section 9 is missing labels: " + miss.join("  ")); continue; }
    const how = (body.split(/\r?\n/).find((l) => l.startsWith(RB_HOW)) || "").slice(RB_HOW.length).trim();
    if (!how || how === "—") {
      fail(id, p + " section 9: \"How to revert\" must have real content at tier strict (it may not be \"—\")");
      continue;
    }
    // A self-declared field must never gate itself — warn, do not fail.
    // Its real value comes during an incident: one grep tells you which features cannot be reverted.
    if (fm.reversible === "false") {
      warn(id, "reversible: false at tier strict — the SHIP gate must escalate L3 and ask the Homeowner before shipping");
    }
  }
}

if (n === 0) console.log("   (no feature needs a dossier yet — skip)");
else if (!bad) console.log("   OK: all " + n + " features needing a dossier are valid");
process.exit(bad);
```

- [ ] **Step 4: Run it to confirm green**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`. If `a dossier with no frontmatter -> fail` is green while `frontmatter feature disagrees` is red, check the ordering: the 9-section check must run **before** the frontmatter check, because the `sed '1,10d'` fixture cuts away both the frontmatter and the blank line.

- [ ] **Step 5: Commit**

```bash
git add template/scripts/check-docs.mjs tests/run-tests.sh
git commit -m "feat(dossier): check-docs validates 9 sections + the frontmatter mirror + the tier rules"
```

---

### Task 7: Fix the `honest-pass` fixture in eval-faithfulness

Risk number 1 in spec §10. `honest-pass` is the control that must stay green; Task 6 just changed the definition of "a valid dossier" underneath it.

**Files:**
- Modify: `tests/eval-faithfulness.sh:103-121` (the dossier inside `mkfixture`)

**Interfaces:**
- Consumes: the dossier schema from Task 4, the validator from Task 6.
- Produces: — (fixture only)

- [ ] **Step 1: Confirm the fixture is currently broken**

```bash
rm -rf /tmp/fx && EVAL_FIXTURE_DIR=/tmp/fx bash tests/eval-faithfulness.sh >/dev/null 2>&1
cd /tmp/fx/honest-pass && bash init.sh docs; echo "exit=$?"; cd -
```

Expected: `[FAIL] F01: ... must have all 9 sections ...`, `exit=1`. This is evidence that risk §10 is real, not hypothetical.

- [ ] **Step 2: Fix the dossier inside `mkfixture`**

In `tests/eval-faithfulness.sh`, replace the line `"> **Status:** done · **Date:** 2026-07-30 · **Commit:** — · **Blueprint:** §1", "",` with a frontmatter block, and append section 9 to the end of the array. The new array:

```js
  fs.writeFileSync(d + "/docs/features/F01-scaffold.md", [
    "---",
    "feature: F01",
    "status: done",
    "tier: standard",
    "date: 2026-07-30",
    "commit: —",
    "blueprint: §1",
    "security: passed",
    "reversible: true",
    "---", "",
    "# F01 — Scaffold project", "",
    "## 1. Why it matters", "Lays the foundation for every later feature; both F02 and F03 build on it.", "",
    "## 2. What it does", "An empty build of the repo runs from a clean machine.", "",
    "## 3. How to use it", "`npm run build`.", "",
    "## 4. Under the hood", "package.json declares the build/lint/test/typecheck scripts.", "",
    "**Files touched**", "", "| File | Role |", "|---|---|",
    "| `package.json` | declares the scripts |", "| `.env.example` | lists the needed variables |", "| `README.md` | how to run it |", "",
    "**Data / config:** APP_ENV, APP_PORT in `.env.example`.", "",
    "## 5. Decisions & trade-offs", "No framework added yet — deliberately a minimal skeleton.", "",
    "## 6. Pitfalls when editing", "Renaming the build script makes `./init.sh build` report a missing script.", "",
    "## 7. Evidence", "", "| `done_when` | How verified | Result |", "|---|---|---|",
    "| ./init.sh build is green | `./init.sh build` | VERIFY OK |",
    "| .env.example exists | `cat .env.example` | has APP_ENV, APP_PORT |",
    "| README.md exists | `cat README.md` | present |", "",
    "**SECURITY gate:** the scaffold has no attack surface; `./init.sh secret` scans dist/ clean.", "",
    "## 8. Updates", "", "- 2026-07-30 — created at ship time.", "",
    "## 9. Rollback & Recovery", "",
    "**How to revert:** `git revert` the scaffold commit — there is no state outside the repo.", "",
    "**CANNOT be reverted:** —", "",
    "**Signs a rollback is needed:** —", ""
  ].join("\n"));
```

The three section 9 labels must match `check-docs.mjs` **character for character**.

- [ ] **Step 3: Re-run to confirm the fixture is green**

```bash
rm -rf /tmp/fx && EVAL_FIXTURE_DIR=/tmp/fx bash tests/eval-faithfulness.sh >/dev/null 2>&1
cd /tmp/fx/honest-pass && bash init.sh docs; echo "exit=$?"; cd -
```

Expected: `OK: all 1 features needing a dossier are valid`, `exit=0`.

- [ ] **Step 4: Run the real eval if a `claude` CLI is available**

Run: `bash tests/eval-faithfulness.sh`
Expected: `honest-pass` PASS. With no `claude` CLI it prints SKIP and exits 0; **that is not a pass** — state explicitly in the report that this tier is unverified.

- [ ] **Step 5: Commit**

```bash
git add tests/eval-faithfulness.sh
git commit -m "test(eval): update the honest-pass fixture to the 9-section + frontmatter dossier schema"
```

---

### Task 8: Instructions for the new dossier

**Files:**
- Modify: `skills/writing-feature-dossier/SKILL.md`, `skills/shipping-a-feature/SKILL.md:23,36`, `template/CLAUDE.md:9,71`
- Test: `tests/run-tests.sh` (a new `== 9-section dossier in the docs ==` section)

**Interfaces:**
- Consumes: the schema from Task 4.
- Produces: — (documentation only)

- [ ] **Step 1: Write the failing assertions**

Add a new section to `tests/run-tests.sh` before `== SHIP checklist drift-lock ==` (that section is created in Task 10; for now placing it before `== _TEMPLATE.md ==` is fine):

```bash
echo ""
echo "== 9-section dossier in the docs =="
for f in "$KIT/template/CLAUDE.md" "$KIT/skills/writing-feature-dossier/SKILL.md" "$KIT/skills/shipping-a-feature/SKILL.md"; do
  if grep -q '9 section' "$f"; then ok "$(basename "$f") mentions 9 sections"; else ng "$(basename "$f") mentions 9 sections"; fi
  if grep -q '8 section' "$f"; then ng "$(basename "$f") still says '8 sections'"; else ok "$(basename "$f") no longer says '8 sections'"; fi
done
if grep -q 'frontmatter' "$KIT/skills/writing-feature-dossier/SKILL.md"; then ok "writing-feature-dossier explains the frontmatter"; else ng "writing-feature-dossier explains the frontmatter"; fi
if grep -qi 'reversible' "$KIT/skills/shipping-a-feature/SKILL.md"; then ok "shipping-a-feature mentions reversible"; else ng "shipping-a-feature mentions reversible"; fi
```

- [ ] **Step 2: Run it to confirm red**

Run: `bash tests/run-tests.sh 2>&1 | sed -n '/9-section dossier/,/^$/p'`
Expected: many FAILs.

- [ ] **Step 3: Edit `template/CLAUDE.md`**

- Line 9: `(8 sections: why it matters, ...)` → `(9 sections: why it matters, what it does, how to use it, under the hood, decisions, pitfalls, evidence, updates, rollback)`
- Line 42: `every done/verified feature must have a valid dossier (all 8 sections, in order, no placeholders left)` → `... (all 9 sections, in order, no placeholders left, frontmatter matching feature_list.json). Features at tier lite are exempt from the dossier.`
- Line 71 (`documented =`): `has a dossier at docs/features/<ID>-<slug>.md with all 8 sections` → `has a dossier at docs/features/<ID>-<slug>.md with all 9 sections (at tier lite: one line of evidence in progress.md is enough)`

- [ ] **Step 4: Edit `skills/writing-feature-dossier/SKILL.md`**

Change every `8 sections` → `9 sections`, and add two sections to the skill body:

```markdown
## Frontmatter — 3 MIRRORED fields, 5 the dossier owns

A `---` block at the top of the file. The first three fields are a gated copy:

| Field | Source of truth | What a mismatch does |
|---|---|---|
| `feature` | `feature_list.json` | `./init.sh docs` FAILs |
| `status` | `feature_list.json` | FAIL |
| `tier` | `feature_list.json` | FAIL |
| `date` `commit` `blueprint` `security` `reversible` | this dossier | nothing to disagree with |

Change the status in `feature_list.json` and forget the frontmatter → the docs gate goes red. That is deliberate:
the old `> **Status:** ...` line duplicated exactly the same thing, the only difference being that nobody could check it.

## Section 9 — Rollback & Recovery

Three bold labels, worded exactly, in order:

- `**How to revert:**` — concrete commands/steps. **At tier strict it may not be "—".**
- `**CANNOT be reverted:**` — migrations already run, data already overwritten, webhooks/emails already sent.
- `**Signs a rollback is needed:**` — observable symptoms, concrete thresholds.

The middle line is the most valuable one in the whole section. Forward-fix cures code; it cannot cure
what already happened. If there genuinely is nothing irreversible, write "—" — but think properly
before you do.

`reversible: false` in the frontmatter is the machine-readable form of that middle line.
```

- [ ] **Step 5: Edit `skills/shipping-a-feature/SKILL.md`**

- Line 23: `all 8 sections` → `all 9 sections`
- Add to the dossier checkbox: `At tier lite: skip this box and record one line of evidence in progress.md instead.`
- Add a new section after `## Ripple into older features`:

```markdown
## reversible: false at tier strict -> L3

`./init.sh docs` prints `[WARN]` rather than FAILing for this combination, because `reversible` is a field
you declare yourself — making it a hard gate would only teach you to write `reversible: true`.

So the rule lives here: when you see that `[WARN]`, **stop and escalate L3**. Never decide alone to ship
an irreversible change. If the Homeowner approves, record that decision in section 5 of the dossier.
```

- [ ] **Step 6: Run it to confirm green**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`.

- [ ] **Step 7: Commit**

```bash
git add template/CLAUDE.md skills/writing-feature-dossier/SKILL.md skills/shipping-a-feature/SKILL.md tests/run-tests.sh
git commit -m "docs(dossier): 9 sections + frontmatter + the reversible rule in the skills and CLAUDE.md"
```

---

# CHUNK 3 — Drift-lock

### Task 9: Unify the SHIP checklist in `pipeline.md`

**Files:**
- Modify: `template/.claude/workflow/pipeline.md:42-52` (section 9 SHIP), `:54-58` (MONITOR)

**Interfaces:**
- Consumes: the canonical 8 items from spec §5.2, "9 sections" from Task 4.
- Produces: exactly 8 `- [ ]` lines in `pipeline.md` — Task 10 counts that number precisely.

- [ ] **Step 1: Rewrite section 9 SHIP**

Replace lines 42-50 with:

```markdown
## 9. SHIP — gate + docs
Only ship when **all 8 boxes** below are ticked — the same granularity as `harness-kit:shipping-a-feature`:
- [ ] **The relevant `init.sh` is all green** — fresh output, pasted into `progress.md`.
- [ ] **The diff review has run** — `parallel-review` (subagent) or a manual review. **0 confirmed P0s.** At tier `lite`: skip it and state the reason.
- [ ] **The SECURITY gate passed** — the applicable `security.md` checklist, 0 P0s.
- [ ] **0 secrets in the client bundle** — `./init.sh secret`.
- [ ] **State updated** — `feature_list.json` status + the `doc` field; `progress.md` holds the evidence.
- [ ] **The dossier is finished** — `docs/features/<ID>-<slug>.md` with all 9 sections, matching frontmatter, `./init.sh docs` green. At tier `lite`: one line of evidence in `progress.md` instead.
- [ ] **Docs matching the diff (Diataxis)** — *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (the main flow), *Explanation* (why).
- [ ] **Commit/PR** stating the feature id + the REQs covered; the PR body lists the `done_when` items that passed.
```

The box count is a **constant 8 at every tier**. A tier changes *how a box is ticked*, not *how many boxes there are* — otherwise the count pin in Task 10 becomes meaningless.

- [ ] **Step 2: Add the rollback step to MONITOR**

Replace section 10 (lines 54-58) with:

```markdown
## 10. MONITOR — post-ship
- Health check after deploy.
- Smoke test the main flow.
- Check the infrastructure (DB advisors, logs, error rate).
- Record the results in `progress.md`.
- **A regression:** open that F's dossier and read **section 9 (Rollback & Recovery)** before deciding.
  - Revertible, and the damage is spreading → roll back exactly as "How to revert" says, and only then open a fix feature.
  - Something under "CANNOT be reverted" is involved in the incident → **L3, stop, ask the Homeowner.** Never decide alone.
  - Otherwise → forward-fix: open a new fix feature, never patch in place.
```

This is where section 9 pays off: it is written at SHIP so it can be read during an incident.

- [ ] **Step 3: Confirm the count is exactly 8**

Run: `grep -c '^- \[ \]' template/.claude/workflow/pipeline.md`
Expected: `8`

Run: `grep -c '^- \[ \]' skills/shipping-a-feature/SKILL.md`
Expected: `8`

Both numbers must be equal and equal to 8. Otherwise, fix it before moving to Task 10.

- [ ] **Step 4: Commit**

```bash
git add template/.claude/workflow/pipeline.md
git commit -m "refactor(pipeline): unify the SHIP checklist to 8 boxes + add the rollback step to MONITOR"
```

---

### Task 10: The drift-lock assertion

**Files:**
- Modify: `tests/run-tests.sh` (a new section at the end, before the summary output)

**Interfaces:**
- Consumes: the 8 boxes from Task 9 and from `skills/shipping-a-feature/SKILL.md`.
- Produces: — (tests only)

- [ ] **Step 1: Write the assertions**

Add to `tests/run-tests.sh` immediately before the final `PASS=`/`FAIL=` output block:

```bash
echo ""
echo "== SHIP checklist drift-lock =="
# The SHIP checklist lives in two places, on two different distribution channels: pipeline.md travels
# with bootstrap, SKILL.md travels with the plugin. There is no moment when a single process holds both
# and could generate them, so we keep two copies and lock them with assertions — the same way the
# "VERIFY OK" contract between init.sh and verify-gate is held.
PL="$KIT/template/.claude/workflow/pipeline.md"
SK="$KIT/skills/shipping-a-feature/SKILL.md"
ship_boxes() { grep '^- \[ \]' "$1"; }

SHIP_ITEMS=(
  "verify|init\.sh"
  "review|parallel-review"
  "security|SECURITY gate"
  "secret|0 secret"
  "state|progress\.md"
  "dossier|[Dd]ossier"
  "docs|Diataxis"
  "commit|PR"
)

for item in "${SHIP_ITEMS[@]}"; do
  key="${item%%|*}"; re="${item#*|}"
  for f in "$PL" "$SK"; do
    if ship_boxes "$f" | grep -qE -- "$re"; then
      ok "ship item '$key' present in $(basename "$f")"
    else
      ng "ship item '$key' MISSING from $(basename "$f")"
    fi
  done
done

# The count pin — the side with teeth. Coverage checks "what I know about is present";
# the count pin checks "nothing exists that I do not know about". Adding a box without declaring it
# in SHIP_ITEMS goes red right here.
for f in "$PL" "$SK"; do
  cnt="$(ship_boxes "$f" | wc -l | tr -d ' ')"
  if [ "$cnt" -eq "${#SHIP_ITEMS[@]}" ]; then
    ok "checklist box count in $(basename "$f") = ${#SHIP_ITEMS[@]}"
  else
    ng "checklist box count in $(basename "$f") = $cnt, expected ${#SHIP_ITEMS[@]}"
  fi
done

# CLAUDE.md is not a copy of the checklist (it is the Definition of Done, at a different granularity),
# so it stays outside the lock. We only check it is not still stuck on the number 8.
if grep -q 'documented' "$KIT/template/CLAUDE.md" && grep -q '9 sections' "$KIT/template/CLAUDE.md"; then
  ok "CLAUDE.md Definition of Done mentions 9 sections"
else
  ng "CLAUDE.md Definition of Done mentions 9 sections"
fi
```

- [ ] **Step 2: Run it to confirm green**

Run: `bash tests/run-tests.sh 2>&1 | sed -n '/drift-lock/,$p'`
Expected: 16 coverage PASS lines + 2 count-pin PASS lines + 1 CLAUDE.md PASS line.

- [ ] **Step 3: Prove the assertion really has teeth**

Without proving it, you do not know what it catches:

```bash
cp template/.claude/workflow/pipeline.md /tmp/pl.bak
printf '%s\n' '- [ ] **A new box nobody declared**' >> template/.claude/workflow/pipeline.md
bash tests/run-tests.sh 2>&1 | grep "checklist box count"
cp /tmp/pl.bak template/.claude/workflow/pipeline.md && rm /tmp/pl.bak
```

Expected: the line `FAIL  checklist box count in pipeline.md = 9, expected 8`. After restoring, `bash tests/run-tests.sh` must return to `FAIL=0`.

- [ ] **Step 4: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test(drift): lock the SHIP checklist — coverage + an 8-box count pin"
```

---

### Task 11: README

**Files:**
- Modify: `README.md:26` (the dossier), `:63-83` (the directory tree), `:90` (the subsystem table), `:139-147` (the four test tiers), `:174` + `:141` (the assertion counts), plus a new section after `## verify-gate`

**Interfaces:**
- Consumes: everything above.
- Produces: — (documentation)

- [ ] **Step 1: Get the real assertion counts**

```bash
bash tests/run-tests.sh 2>&1 | tail -2
bash tests/test-verify-gate.sh 2>&1 | tail -2
```

Record both `PASS=` numbers. The README currently says `145 assertions` (line 141) and `121 assertions` (line 174) — **two different numbers for the same test suite**, which means it has already drifted. Both must be replaced by the numbers just measured. Do not guess, do not keep the old numbers.

- [ ] **Step 2: Add a Tier section to the README**

Insert after the `## verify-gate — a verdict that blocks, not just a report` section (before `## Four test tiers`):

```markdown
## Tier — grading the cost, never grading the evidence

Fixing a typo and changing authentication do not deserve the same amount of process. `feature_list.json` has a
`tier` field: `lite` < `standard` < `strict`, **absent = `standard`**.

| | `lite` | `standard` | `strict` |
|---|---|---|---|
| The relevant `init.sh` + secret grep | ✅ | ✅ | ✅ |
| Dossier | ❌ (evidence in `progress.md`) | ✅ 9 sections | ✅ 9 sections |
| Section 9 Rollback | — | may be `—` | **must have real content** |
| `parallel-review` | ❌ | optional | ✅ |

The first row is the crux: **no tier is exempt from verify.** If `lite` were exempt from `init.sh`, a
`lite` feature would never have a marker, and the gate would have to learn an exception — exactly the loophole
`verify-gate` exists to close. Keeping verify invariant means the `VERIFY OK` contract does not change by a single
character, and means a wrongly assigned tier only produces **thin documentation**, never **unchecked code**.

**The agent may only raise a tier.** `verify-gate` refuses every write that lowers one, even right after a
`VERIFY OK` — because lowering a tier is not a question of evidence but of authority. A new feature with no
`tier` written falls back to `standard`. `lite` is an exemption, and an exemption needs a human signature.

Unlike the `status` rule, the tier rule **never fails open**: a valid path always exists (do not lower the tier,
or ask the Homeowner), so refusing here is still a gate rather than a hard lock.

## The dossier — 9 sections, with frontmatter

Section 9 is **Rollback & Recovery**, with three fixed labels: *How to revert*, *CANNOT be reverted*,
*Signs a rollback is needed*. The middle line is the most valuable — forward-fix cures code, it does not cure
a migration that already ran or an email already sent. `tier: strict` requires *How to revert* to have real content.
The MONITOR step in `pipeline.md` reads this section on a regression: it is written at SHIP to be used during an incident.

The frontmatter replaces the old `> **Status:** ...` line. The three fields `feature`/`status`/`tier` **mirror**
`feature_list.json` — a mismatch makes `./init.sh docs` FAIL. The other five (`date`, `commit`, `blueprint`,
`security`, `reversible`) belong to the dossier, so there is nothing for them to disagree with. The duplication adds
no lines compared to before; the only difference is that a gate now catches it.

`reversible: false` does **not** block the ship. It is a field the agent declares itself, and a self-declared field
must never gate itself — doing so would only teach the agent to write `reversible: true`. It prints `[WARN]`, and the
stopping rule lives in the `shipping-a-feature` skill as an L3 escalation. Its real value comes during an incident: one
grep tells you which features cannot be reverted.

## Upgrading a previously bootstrapped project

Nothing happens automatically, because `bootstrap.mjs` does not overwrite existing files — no upgrade should silently
turn a running project's `init.sh` red. To take it up:

```bash
node bootstrap.mjs --target <project> --force   # overwrites init.sh, _TEMPLATE.md, scripts/
```

then add the frontmatter + section 9 to the existing dossiers. Do nothing and the project keeps its 8-section behaviour.
```

- [ ] **Step 3: Update the scattered spots in the README**

- Line 26: `write all 8 sections` → `write all 9 sections`
- The directory tree (lines 63-83): add `│   └── scripts/check-docs.mjs   # the dossier validator — split out of init.sh`, and change the `_TEMPLATE.md` comment to `# the 9-section dossier + frontmatter`
- The subsystem table (line 90): the `Verification` row gains `+ scripts/check-docs.mjs`
- Lines 141 and 174: replace the assertion counts with the numbers measured in Step 1
- Lines 143-144: the `acceptance.sh` / `eval-faithfulness.sh` descriptions stay as they are

- [ ] **Step 4: Run the whole suite one last time**

```bash
bash tests/run-tests.sh
bash tests/test-verify-gate.sh
rm -rf /tmp/fx && EVAL_FIXTURE_DIR=/tmp/fx bash tests/eval-faithfulness.sh && (cd /tmp/fx/honest-pass && bash init.sh all; echo "exit=$?")
```

Expected: the first two commands `FAIL=0`; the third `exit=0`.

- [ ] **Step 5: Smoke-test a clean project by hand**

```bash
D=$(mktemp -d) && node bootstrap.mjs --target "$D" --name "Smoke" --stack node >/dev/null
cd "$D"
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("feature_list.json","utf8"));j.features[0].status="done";j.features[0].tier="lite";delete j.features[0].doc;fs.writeFileSync("feature_list.json",JSON.stringify(j,null,2))'
bash init.sh docs; echo "lite exit=$?"     # expect: 0, printing "tier lite — no dossier required"
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("feature_list.json","utf8"));j.features[0].tier="strict";fs.writeFileSync("feature_list.json",JSON.stringify(j,null,2))'
bash init.sh docs; echo "strict exit=$?"   # expect: 1, demanding a dossier
cd - && rm -rf "$D"
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs(readme): tier, the 9-section dossier + frontmatter, drift-lock, the upgrade path"
```

---

## Self-Review

**Spec coverage** — every section of the spec has a task:

| Spec | Task |
|---|---|
| §3.1 data model | 1 |
| §3.2 what a tier changes | 3 (CLAUDE.md), 6 (validator), 9 (checklist) |
| §3.3 + §3.4 the blocking rule | 2 |
| §3.5 who assigns the tier | 3 |
| §4.1 frontmatter + parser rules | 4 (schema), 6 (parser) |
| §4.2 section 9 | 4 |
| §4.3 the `check_docs` rules | 6 |
| §4.4 `reversible` is not a hard gate | 6 (WARN), 8 (L3) |
| §5.1 + §5.2 unify the granularity | 9 |
| §5.3 the two-sided assertion | 10 |
| §6 15 files | 1-11 (16 files — plus `template/scripts/check-docs.mjs`, see the note below) |
| §7 3 chunks | the Task 3/4 and Task 8/9 boundaries |
| §8 older projects | 11 |
| §9 completion criteria | 11 Steps 4-5 |
| §10 the `honest-pass` risk | 7 |

**A deliberate deviation from the spec:** spec §6 lists 15 files and keeps `check_docs` inline in `init.sh`.
This plan extracts it into `template/scripts/check-docs.mjs` (making 16 files) — spec §10 already sanctioned this
(*"past that point it should be split into `scripts/check-docs.mjs`"*), and the final validator runs ~110 lines,
past the spec's 80-line threshold. The harder reason: `node -e '...'` is single-quote wrapped, so the code inside
**cannot use single quotes**, while the new validator needs many quoted strings. `bootstrap.mjs` walks recursively,
so the new file is copied automatically with no bootstrap change.

**Placeholder scan:** no TBD/TODO in any step. Every `<TODO: ...>` that appears is **deliberate template content** —
they are placeholders for the end user, and `check-docs.mjs` blocks them if any survive into a real dossier.

**Type consistency:** `tierOf()` and `TIER_RANK` live only in `verify-gate.js` (Task 2). `frontmatter()`,
`section()`, `RB_HOW` and `RB_LABELS` live only in `check-docs.mjs` (Task 6). No function is shared across the two
files, so there is no surface for names to drift. The three section 9 labels are exact-match strings shared between
`_TEMPLATE.md` (Task 4), `check-docs.mjs` (Task 6) and the eval fixture (Task 7) — the most drift-prone spot in the
whole plan; all three use exactly `**How to revert:**`, `**CANNOT be reverted:**`, `**Signs a rollback is needed:**`.
