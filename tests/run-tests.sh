#!/usr/bin/env bash
# Test suite — harness-kit. Run: bash tests/run-tests.sh
# Requires: bash + node. Each scenario bootstraps a throwaway project into .tmp-tests/ then asserts the exit code.
set -uo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"

PASSED=0
FAILED=0

cleanup() { rm -rf "$KIT/.tmp-tests"; }
trap cleanup EXIT

ok() { echo "  PASS  $1"; PASSED=$((PASSED + 1)); }
ng() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

# Convert a POSIX path -> the form node understands on Windows (Git Bash). Elsewhere: unchanged.
win() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}

# Bootstrap a throwaway project and print its POSIX path.
# Uses mktemp rather than a counter variable: this function always runs inside $(...), i.e. a
# subshell, so a counter incremented there would not survive -> every project would collide on the same path.
new_project() {
  mkdir -p "$KIT/.tmp-tests"
  local d
  d="$(mktemp -d "$KIT/.tmp-tests/pXXXXXX")"
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

# Print a valid dossier (frontmatter + all 9 sections, no placeholders).
# The fixture's tier is standard, so section 9 may be "—"; the strict cases below rewrite it.
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
expect_docs "sections 6-9 missing -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^## 2\./## X./' -e 's/^## 8\./## 2./' -e 's/^## X\./## 8./' > "$P/$DOC"
expect_docs "9 sections in the wrong order -> fail" 1 "$P"

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
# --- tier changes what a dossier must be, not whether verify runs ----------------
P="$(new_project)"
patch_feature "$P" F01 '{"status":"done","tier":"lite","doc":null}'
expect_docs "tier lite done needs no dossier at all -> pass" 0 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"medium\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"; valid_dossier > "$P/$DOC"
expect_docs "a tier outside the scale -> fail" 1 "$P"

# --- frontmatter: three mirrored fields, gated ------------------------------------
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"; valid_dossier | sed '1,11d' > "$P/$DOC"
expect_docs "a dossier with no frontmatter -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"; valid_dossier | sed 's/^feature: F01$/feature: F99/' > "$P/$DOC"
expect_docs "frontmatter feature disagreeing with feature_list -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"verified\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"; valid_dossier > "$P/$DOC"
expect_docs "frontmatter status=done while feature_list says verified -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"; valid_dossier > "$P/$DOC"
expect_docs "frontmatter tier=standard while feature_list says strict -> fail" 1 "$P"

# --- tier strict: section 9 must say something -----------------------------------
mk_strict() {
  patch_feature "$1" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
  mkdir -p "$1/docs/features"
}
P="$(new_project)"; mk_strict "$P"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' \
  -e 's|^\*\*How to revert:\*\*.*|**How to revert:** —|' > "$P/$DOC"
expect_docs "tier strict with How-to-revert set to a dash -> fail" 1 "$P"

P="$(new_project)"; mk_strict "$P"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' \
  -e '/^\*\*Signs a rollback is needed:\*\*/d' > "$P/$DOC"
expect_docs "tier strict missing the Signs label -> fail" 1 "$P"

P="$(new_project)"; mk_strict "$P"
valid_dossier | sed 's/^tier: standard$/tier: strict/' > "$P/$DOC"
expect_docs "tier strict fully filled in -> pass" 0 "$P"

# --- reversible: a self-declared field must not gate itself ----------------------
# Making it block the ship would only teach the agent to write reversible: true. It warns; the
# stopping rule lives in shipping-a-feature as an L3 escalation.
P="$(new_project)"; mk_strict "$P"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' -e 's/^reversible: true$/reversible: false/' > "$P/$DOC"
expect_docs "reversible false at strict -> still passes (warning only)" 0 "$P"
# Collect first, then grep — piping into `grep -q` makes grep exit early, the upstream command
# takes SIGPIPE, and `set -o pipefail` reports non-zero. Documented near the top of this file;
# walked into anyway.
wout="$(bash "$P/init.sh" docs 2>&1)"
if printf '%s' "$wout" | grep -qF 'WARN'; then ok "reversible false at strict -> prints a warning"; else ng "reversible false at strict -> prints a warning"; fi

echo ""
echo "== check_lang: the English-only invariant =="

# The rule is stated in CLAUDE.md and injected by using-harness, but a rule with no validator drifts.
# These assertions pin the behaviour in both directions AND pin the rule's presence in the instructions.

P="$(new_project)"
expect_lang() {
  local desc="$1" want="$2" proj="$3" got
  bash "$proj/init.sh" lang >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ng "$desc (exit=$got, want=$want)"; fi
}

expect_lang "a freshly bootstrapped project is English -> pass" 0 "$P"

# A file carrying Vietnamese diacritics must turn it red. The probe is generated by node from \u
# escapes rather than typed literally, so this test file stays clean under the very rule it tests —
# otherwise running check_lang over harness-kit itself would report this line.
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], "// \u0111\u1EA7u v\u00E0o\nmodule.exports = 1;\n");
' "$(win "$P/vn-probe.js")"
expect_lang "a file with Vietnamese diacritics -> fail" 1 "$P"

out="$(bash "$P/init.sh" lang 2>&1)"
if printf '%s' "$out" | grep -qF 'vn-probe.js:1'; then ok "check_lang names the offending file and line"; else ng "check_lang names the offending file and line"; fi

rm -f "$P/vn-probe.js"
expect_lang "removing the file makes it green again" 0 "$P"

# lang must run on EVERY target, not only `all`. This is the hole that was measured: verify-gate
# mints its marker from ANY "VERIFY OK", so a lang confined to `all` lets an agent go green on
# `./init.sh build` and write done with non-English text still in the repo.
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], "// \u0111\u1EA7u v\u00E0o\nmodule.exports = 1;\n");
' "$(win "$P/vn-probe.js")"
for t in scaffold build secret docs lang all; do
  if bash "$P/init.sh" "$t" >/dev/null 2>&1; then
    ng "./init.sh $t goes red while non-English text exists"
  else
    ok "./init.sh $t goes red while non-English text exists"
  fi
done

# ...and the consequence that actually matters: a narrow target must no longer mint a marker.
SIDL="langgate-$$"
rm -f "${TMPDIR:-/tmp}/harness-kit-verify/$SIDL" 2>/dev/null
LOUT="$(bash "$P/init.sh" build 2>&1)"
node -e '
process.stdout.write(JSON.stringify({session_id: process.argv[1],
  tool_input: {command: "./init.sh build"}, tool_response: process.argv[2]}));
' "$SIDL" "$LOUT" | bash "$KIT/hooks/verify-gate" post-bash >/dev/null 2>&1
if [ -f "${TMPDIR:-/tmp}/harness-kit-verify/$SIDL" ]; then
  ng "a narrow target does not mint a verify marker while lang is red"
else
  ok "a narrow target does not mint a verify marker while lang is red"
fi
rm -f "${TMPDIR:-/tmp}/harness-kit-verify/$SIDL" 2>/dev/null
rm -f "$P/vn-probe.js"

# Extension-agnostic: an allowlist of extensions silently ignores whatever nobody thought of.
node -e '
const fs = require("fs");
const d = process.argv[1];
fs.writeFileSync(d + "/Dockerfile", "# C\u1EA5u h\u00ECnh\n");
fs.writeFileSync(d + "/notes.rst", "Ghi ch\u00FA\n");
' "$(win "$P")"
expect_lang "files with no extension and unknown extensions are scanned too -> fail" 1 "$P"
rm -f "$P/Dockerfile" "$P/notes.rst"

# A binary file must not be misread as text and reported.
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1] + "/logo.png", Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 1, 0xC3, 0xA2]));
' "$(win "$P")"
expect_lang "a binary file is skipped, not misread as text -> pass" 0 "$P"
rm -f "$P/logo.png"

# --- ASCII Vietnamese: the half a character class cannot see ---------------------
# Diacritics are the easy case. Vietnamese typed without them is plain ASCII, and the original
# version of this very repo was written that way — so a check that only looked for diacritics would
# have missed the exact problem it exists for. Vocabulary is the signal instead: 3 distinct
# Vietnamese words on one line.
# The probe words are assembled from an array holding at most two per source line. Written as one
# sentence, this file would trip the very check it is testing — the ASCII half has no \u escape to
# hide behind, so the fixture has to be built rather than typed.
node -e '
const fs = require("fs");
const w = ["Ham", "nay",
           "kiem", "tra",
           "dieu", "kien",
           "dau", "vao"];
fs.writeFileSync(process.argv[1], "// " + w.join(" ") + "\nmodule.exports = 1;\n");
' "$(win "$P/ascii-vn.js")"
expect_lang "ASCII Vietnamese with no diacritics -> fail" 1 "$P"
out="$(bash "$P/init.sh" lang 2>&1)"
if printf '%s' "$out" | grep -qF 'ascii-vn.js:1'; then ok "the ASCII case names the file and the words that matched"; else ng "the ASCII case names the file and the words that matched"; fi
rm -f "$P/ascii-vn.js"

# ...and ordinary English prose must stay quiet. Several of the listed words are plausible English
# fragments in isolation, so this is the assertion that keeps the threshold honest.
cat > "$P/plain-english.js" <<'ENEOF'
// This handler checks the input condition before writing it to the database.
// If the value is not valid we return an error, and we do not skip this step.
// A man in the middle can do so much damage that we can not take the chance.
module.exports = 1;
ENEOF
expect_lang "ordinary English prose does not trip the word list -> pass" 0 "$P"
rm -f "$P/plain-english.js"

# One Vietnamese word alone is an identifier, not prose. Two is still a coincidence worth allowing.
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1] + "/one-word.js", "const cho = 1;\nmodule.exports = cho;\n");
' "$(win "$P")"
expect_lang "a single Vietnamese-looking identifier is not flagged -> pass" 0 "$P"
rm -f "$P/one-word.js"

# The validator carries the word list, so it is excluded from its own scan. Without that it reports
# itself on every run — which it did, 27 lines of it, the first time this was executed.
if grep -qF 'const SELF' "$P/scripts/check-lang.mjs"; then ok "the validator excludes itself from the scan"; else ng "the validator excludes itself from the scan"; fi

# --- text spread thin enough that no single line trips ---------------------------
# The per-line rule is trivially evaded by writing two words per line — demonstrated, not imagined.
# Counting distinct words across a whole file is what closes it.
node -e '
const fs = require("fs");
const w = ["Ham", "nay",
           "kiem", "tra",
           "dieu", "kien",
           "dau", "vao"];
const lines = [];
for (let i = 0; i < w.length; i += 2) lines.push("// " + w[i] + " " + w[i + 1]);
fs.writeFileSync(process.argv[1], lines.join("\n") + "\n");
' "$(win "$P/thin.js")"
expect_lang "text spread two words per line is caught file-wide -> fail" 1 "$P"
out="$(bash "$P/init.sh" lang 2>&1)"
if printf '%s' "$out" | grep -qF 'spread across the file'; then ok "the file-wide finding says it was spread, not on one line"; else ng "the file-wide finding says it was spread, not on one line"; fi
rm -f "$P/thin.js"

# --- scripts/lang-words.txt: the project's own vocabulary ------------------------
# The shipped list came from one project and cannot cover another's domain. Without this file the
# check only sees prose; with it, identifiers and short comments become visible too.
WORDS_FILE="$P/scripts/lang-words.txt"
if [ -f "$WORDS_FILE" ]; then ok "bootstrap ships scripts/lang-words.txt"; else ng "bootstrap ships scripts/lang-words.txt"; fi

# An identifier built from words the shipped list does not know: invisible before, caught after.
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], "const tong_tien_don_hang = 0;\n");
' "$(win "$P/ident.js")"
expect_lang "a domain identifier the shipped list does not know -> passes (its ceiling)" 0 "$P"
printf '%s\n' "hang don tong" >> "$WORDS_FILE"
expect_lang "the same identifier after the project declares its vocabulary -> fail" 1 "$P"
rm -f "$P/ident.js"

# !skip — for files whose non-English content is the point (translation catalogues, fixtures).
node -e '
const fs = require("fs");
fs.mkdirSync(process.argv[1] + "/locale", { recursive: true });
fs.writeFileSync(process.argv[1] + "/locale/vi.js", "const tong_tien_don_hang = 0;\n");
' "$(win "$P")"
expect_lang "a file holding another language -> fail by default" 1 "$P"
printf '%s\n' "!skip locale/" >> "$WORDS_FILE"
expect_lang "...and passes once the project declares !skip for it" 0 "$P"
rm -rf "$P/locale"

# !file-threshold — for the legitimate character table or proper-noun list that trips the file rule.
node -e '
const fs = require("fs");
const w = ["Ham", "nay", "kiem", "tra", "dieu", "kien", "dau", "vao"];
const lines = [];
for (let i = 0; i < w.length; i += 2) lines.push("// " + w[i] + " " + w[i + 1]);
fs.writeFileSync(process.argv[1], lines.join("\n") + "\n");
' "$(win "$P/thin2.js")"
expect_lang "the file rule fires at the default threshold -> fail" 1 "$P"
printf '%s\n' "!file-threshold 40" >> "$WORDS_FILE"
expect_lang "...and can be raised by the project when it misfires" 0 "$P"
rm -f "$P/thin2.js"

# The vocabulary file is a list of non-English words by definition; scanning it would flag it.
printf '%s\n' "kiem tra dieu kien dau vao nguoi dung" >> "$WORDS_FILE"
expect_lang "the vocabulary file is not scanned against itself -> pass" 0 "$P"

# Deleting the validator must FAIL, not SKIP. A counted SKIP still prints VERIFY OK, which would mint
# a marker and hand back the very bypass this check exists to remove.
mv "$P/scripts/check-lang.mjs" "$P/scripts/check-lang.mjs.bak"
expect_lang "a missing validator fails rather than skipping -> fail" 1 "$P"
mv "$P/scripts/check-lang.mjs.bak" "$P/scripts/check-lang.mjs"
expect_lang "restoring the validator makes it green again" 0 "$P"

# The check must be honest about what it cannot see: ASCII-only Vietnamese is undetectable by grep,
# and a green result must not be sold as proof of the whole invariant.
if grep -qF 'does NOT prove' "$KIT/template/scripts/check-lang.mjs"; then ok "check_lang states that green is not proof"; else ng "check_lang states that green is not proof"; fi

# The instructions must carry the rule, in both places an agent actually reads.
# Plain grep rather than has(): that helper is defined further down, in the instruction-wiring section.
CM="$KIT/template/CLAUDE.md"
UH="$KIT/skills/using-harness/SKILL.md"
if grep -qF '## Language' "$CM"; then ok "CLAUDE.md has the Language section"; else ng "CLAUDE.md has the Language section"; fi
if grep -qF './init.sh lang' "$CM"; then ok "CLAUDE.md points at ./init.sh lang"; else ng "CLAUDE.md points at ./init.sh lang"; fi
if grep -qF '**English only**' "$UH"; then ok "using-harness lists English-only as a guardrail"; else ng "using-harness lists English-only as a guardrail"; fi

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

# The field exists and the gate blocks lowering it, but neither tells the agent what a tier MEANS or
# who gets to set one. That has to be written down where an agent reads: CLAUDE.md for the semantics,
# planning-features for the moment a tier is chosen.
# Plain grep rather than has(): that helper is defined further down, in the instruction-wiring section.
CMT="$KIT/template/CLAUDE.md"
PFT="$KIT/skills/planning-features/SKILL.md"
if grep -qF '## Tier' "$CMT"; then ok "CLAUDE.md has the Tier section"; else ng "CLAUDE.md has the Tier section"; fi
# The load-bearing sentence of the whole tier design: a tier changes documentation cost, never
# whether verify runs. Pin it, because a tier that could skip verify would hand back the loophole
# verify-gate exists to close.
if grep -qF 'no tier is exempt' "$CMT"; then ok "CLAUDE.md says no tier is exempt from init.sh"
else ng "CLAUDE.md says no tier is exempt from init.sh"; fi
if grep -qF 'tier' "$PFT"; then ok "planning-features covers the tier"; else ng "planning-features covers the tier"; fi
if grep -qiF 'homeowner' "$PFT"; then ok "planning-features says who sets the tier"; else ng "planning-features says who sets the tier"; fi
if grep -qF 'may only RAISE' "$PFT" || grep -qF 'only raise' "$PFT"; then
  ok "planning-features states the agent may only raise a tier"
else
  ng "planning-features states the agent may only raise a tier"
fi

echo ""
echo "== the 9-section dossier in the instructions =="
# The schema moved; the documents that tell an agent what to write must move with it, or the
# validator becomes a gate nobody was told about.
for f in "$KIT/template/CLAUDE.md" "$KIT/skills/writing-feature-dossier/SKILL.md" "$KIT/skills/shipping-a-feature/SKILL.md"; do
  b="$(basename "$(dirname "$f")")/$(basename "$f")"
  if grep -qE '9 (sections|muc)' "$f"; then ok "$b says 9 sections"; else ng "$b says 9 sections"; fi
  if grep -qE '\b8 sections\b' "$f"; then ng "$b no longer says 8 sections"; else ok "$b no longer says 8 sections"; fi
done
if grep -qF 'frontmatter' "$KIT/skills/writing-feature-dossier/SKILL.md"; then ok "writing-feature-dossier explains the frontmatter"; else ng "writing-feature-dossier explains the frontmatter"; fi
if grep -qF 'Rollback' "$KIT/skills/writing-feature-dossier/SKILL.md"; then ok "writing-feature-dossier covers section 9"; else ng "writing-feature-dossier covers section 9"; fi
if grep -qiF 'reversible' "$KIT/skills/shipping-a-feature/SKILL.md"; then ok "shipping-a-feature handles reversible: false"; else ng "shipping-a-feature handles reversible: false"; fi

echo ""
echo "== _TEMPLATE.md =="

P="$(new_project)"
T="$P/docs/features/_TEMPLATE.md"

if [ -f "$T" ]; then ok "bootstrap copies docs/features/_TEMPLATE.md"; else ng "bootstrap copies docs/features/_TEMPLATE.md"; fi

nums="$(grep -E '^##[[:space:]]+[1-9]\.' "$T" 2>/dev/null \
  | sed -E 's/^##[[:space:]]+([1-9])\..*/\1/' | tr '\n' ',' | sed 's/,$//')"
if [ "$nums" = "1,2,3,4,5,6,7,8,9" ]; then
  ok "_TEMPLATE.md has all 9 sections in order"
else
  ng "_TEMPLATE.md has all 9 sections in order (currently: ${nums:-none})"
fi

# The frontmatter replaces the old blockquote metadata line. Three of its fields mirror
# feature_list.json and are gated; the other five belong to the dossier alone.
if head -1 "$T" | grep -q '^---$'; then ok "_TEMPLATE.md opens with frontmatter"; else ng "_TEMPLATE.md opens with frontmatter"; fi
for k in feature status tier date commit blueprint security reversible; do
  if grep -qE "^${k}:" "$T"; then ok "_TEMPLATE.md frontmatter has the key $k"; else ng "_TEMPLATE.md frontmatter has the key $k"; fi
done

# Section 9 anchors on three fixed labels, the same way the check anchors on "## N.".
if grep -qF '**How to revert:**' "$T"; then ok "_TEMPLATE.md section 9 has the How-to-revert label"; else ng "_TEMPLATE.md section 9 has the How-to-revert label"; fi
if grep -qF '**CANNOT be reverted:**' "$T"; then ok "_TEMPLATE.md section 9 has the CANNOT-be-reverted label"; else ng "_TEMPLATE.md section 9 has the CANNOT-be-reverted label"; fi
if grep -qF '**Signs a rollback is needed:**' "$T"; then ok "_TEMPLATE.md section 9 has the Signs label"; else ng "_TEMPLATE.md section 9 has the Signs label"; fi

if grep -q '<TODO:' "$T" 2>/dev/null; then ok "_TEMPLATE.md uses the <TODO: marker"; else ng "_TEMPLATE.md is missing the <TODO: marker"; fi
if grep -q '<!--' "$T" 2>/dev/null; then ok "_TEMPLATE.md carries guidance comments"; else ng "_TEMPLATE.md is missing guidance comments"; fi
if grep -q 'zoom out' "$T" 2>/dev/null && grep -q 'zoom in' "$T" 2>/dev/null; then
  ok "_TEMPLATE.md explains the section 1 vs section 2 boundary"
else
  ng "_TEMPLATE.md explains the section 1 vs section 2 boundary"
fi

expect_docs "_TEMPLATE.md is not scanned (no feature points at it) -> pass" 0 "$P"

# The dossier validator moves out of init.sh for the same reason check-lang.mjs did: init.sh is a
# file every project edits, and this logic is about to grow a frontmatter parser and tier branches.
if [ -f "$P/scripts/check-docs.mjs" ]; then ok "bootstrap ships scripts/check-docs.mjs"; else ng "bootstrap ships scripts/check-docs.mjs"; fi
if grep -qF 'scripts/check-docs.mjs' "$P/init.sh"; then ok "init.sh calls scripts/check-docs.mjs"; else ng "init.sh calls scripts/check-docs.mjs"; fi

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

echo ""
echo "== README + e2e =="

R="$KIT/README.md"
if grep -qF "_TEMPLATE.md" "$R"; then ok "README lists _TEMPLATE.md in the directory tree"; else ng "README lists _TEMPLATE.md"; fi
if grep -qF "dossier" "$R"; then ok "README explains the dossier"; else ng "README explains the dossier"; fi

# Note: collect the output into a variable, then grep. Piping straight into `grep -q` makes grep
# exit early -> the command upstream of the pipe takes SIGPIPE -> `set -o pipefail` reports
# non-zero -> the test fails for the wrong reason.

# bootstrap --dry-run must list the new template files
P="$KIT/.tmp-tests/dry"
rm -rf "$P"; mkdir -p "$P"
out="$(node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "Dry" --dry-run 2>&1)"
if printf '%s' "$out" | grep -qE 'docs[\\/]features[\\/]_TEMPLATE\.md'; then
  ok "bootstrap --dry-run lists docs/features/_TEMPLATE.md"
else
  ng "bootstrap --dry-run lists docs/features/_TEMPLATE.md"
fi

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

# ./init.sh all must run the FEATURE DOCS block
P="$(new_project)"
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "FEATURE DOCS"; then
  ok "./init.sh all does run check_docs"
else
  ng "./init.sh all does run check_docs"
fi

echo ""
echo "== check_build: a failing script must block the gate =="

# The old `npm run lint 2>/dev/null || echo "(no lint script)"` conflated two very different
# cases: a MISSING script and a script that RAN AND FAILED. The result was that a red lint
# still passed the gate. This group of tests pins that behaviour down.

# mkpkg <proj> <json-scripts>  — write a package.json with the given scripts
mkpkg() {
  node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1] + "/package.json",
  JSON.stringify({ name: "t", private: true, scripts: JSON.parse(process.argv[2]) }, null, 2));
' "$(win "$1")" "$2"
}

# Baseline: build green, no lint/test -> must PASS but report SKIP.
P="$(new_project)"
mkpkg "$P" '{"build":"node -e \"0\""}'
out="$(bash "$P/init.sh" build 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "build green -> exit 0"; else ng "build green -> exit 0 (rc=$rc)"; fi
if printf '%s' "$out" | grep -qF 'SKIP: no "lint" script'; then
  ok "no lint -> reported as SKIP (not faked as a pass)"
else
  ng "no lint -> reported as SKIP"
fi
if printf '%s' "$out" | grep -qF 'were SKIPped'; then
  ok "the summary says plainly that checks were SKIPped"
else
  ng "the summary says plainly that checks were SKIPped"
fi

# Hard case: lint FAILS. This used to be swallowed into "(no lint script)" and the gate stayed green.
P="$(new_project)"
mkpkg "$P" '{"lint":"node -e \"process.exit(1)\"","build":"node -e \"0\""}'
out="$(bash "$P/init.sh" build 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then ok "lint FAIL -> gate red (exit != 0)"; else ng "lint FAIL -> gate red (exit=$rc — a red lint got through the gate!)"; fi
if printf '%s' "$out" | grep -qF '[FAIL] lint'; then ok "lint FAIL -> prints [FAIL] lint explicitly"; else ng "lint FAIL -> prints [FAIL] lint explicitly"; fi

# A typecheck FAIL must block too.
P="$(new_project)"
mkpkg "$P" '{"typecheck":"node -e \"process.exit(1)\"","build":"node -e \"0\""}'
if bash "$P/init.sh" build >/dev/null 2>&1; then ng "typecheck FAIL -> gate red"; else ok "typecheck FAIL -> gate red"; fi

# A test FAIL must block too (the DoD says 'lint + typecheck + build + test pass').
P="$(new_project)"
mkpkg "$P" '{"build":"node -e \"0\"","test":"node -e \"process.exit(1)\""}'
if bash "$P/init.sh" build >/dev/null 2>&1; then ng "test FAIL -> gate red"; else ok "test FAIL -> gate red"; fi

# build is required: a missing build script -> FAIL, not SKIP.
P="$(new_project)"
mkpkg "$P" '{"lint":"node -e \"0\""}'
out="$(bash "$P/init.sh" build 2>&1)"
if printf '%s' "$out" | grep -qF 'missing "build" script'; then ok "missing build -> FAIL (not SKIP)"; else ng "missing build -> FAIL"; fi

# No package.json: an honest SKIP, and it must NOT claim "all checks ran".
P="$(new_project)"
out="$(bash "$P/init.sh" build 2>&1)"
if printf '%s' "$out" | grep -qF 'NOT a pass'; then ok "no package.json -> says plainly this is not a pass"; else ng "no package.json -> says plainly this is not a pass"; fi
if printf '%s' "$out" | grep -qF 'all checks ran'; then ng "must not claim 'all checks ran' when something was SKIPped"; else ok "does not claim 'all checks ran' when something was SKIPped"; fi

echo ""
echo "== plugin: skills =="

# Every skill needs valid frontmatter. `name` must match the directory name (that is how Claude Code
# resolves a skill); `description` is what decides whether the skill auto-triggers at all — without it
# the skill sits on disk and never gets invoked.
SKILL_COUNT=0
for d in "$KIT"/skills/*/; do
  s="$d/SKILL.md"
  base="$(basename "$d")"
  SKILL_COUNT=$((SKILL_COUNT + 1))
  if [ ! -f "$s" ]; then ng "skills/$base has a SKILL.md"; continue; fi

  # the frontmatter must open on line 1 and close on a later `---` line
  if [ "$(head -1 "$s")" = "---" ] && [ "$(sed -n '2,12p' "$s" | grep -c '^---$')" -ge 1 ]; then
    ok "skills/$base: frontmatter opens/closes correctly"
  else
    ng "skills/$base: frontmatter opens/closes correctly"
  fi

  fm_name="$(sed -n '2,12p' "$s" | sed -n 's/^name: *//p' | head -1)"
  if [ "$fm_name" = "$base" ]; then ok "skills/$base: name matches the directory name"
  else ng "skills/$base: name matches the directory name (found: '$fm_name')"; fi

  fm_desc="$(sed -n '2,12p' "$s" | sed -n 's/^description: *//p' | head -1)"
  if [ "${#fm_desc}" -ge 40 ]; then ok "skills/$base: description long enough to trigger (${#fm_desc} chars)"
  else ng "skills/$base: description long enough to trigger (${#fm_desc} chars, need >=40)"; fi

  # Anti-rationalization: this is what separates a skill from a checklist.
  if grep -qiE '^\| You think \| Reality \|' "$s"; then ok "skills/$base: has a red-flags table"
  else ng "skills/$base: has a red-flags table"; fi

  # False-positive guard. The acceptance test already caught this: the hook stayed quiet, but the
  # agent still pulled the skill into a repo with no harness, because the description was too broad.
  # Fence 1: the precondition must live in the description (the agent reads it before the body).
  case "$fm_desc" in
    *"feature_list.json"*) ok "skills/$base: description states the precondition" ;;
    *) ng "skills/$base: description states the precondition" ;;
  esac
  # Fence 2: the skill body must bail out when there is no harness.
  if grep -qF '<PRECONDITION>' "$s"; then ok "skills/$base: body has a bail-out"
  else ng "skills/$base: body has a bail-out"; fi
done

if [ "$SKILL_COUNT" -ge 6 ]; then ok ">=6 gate skills present (found $SKILL_COUNT)"; else ng ">=6 gate skills present (found $SKILL_COUNT)"; fi

# using-harness must route to every other skill — it is the only one the hook injects, so a skill
# that is not mentioned there is effectively undiscoverable.
U="$KIT/skills/using-harness/SKILL.md"
missing_route=""
for d in "$KIT"/skills/*/; do
  base="$(basename "$d")"
  [ "$base" = "using-harness" ] && continue
  grep -qF "$base" "$U" || missing_route="$missing_route $base"
done
if [ -z "$missing_route" ]; then ok "using-harness routes to every other skill"
else ng "using-harness is missing routes to:$missing_route"; fi

echo ""
echo "== plugin: manifest + hook =="

if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$(win "$KIT/.claude-plugin/plugin.json")" 2>/dev/null; then
  ok "plugin.json parses"
else
  ng "plugin.json parses"
fi
if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$(win "$KIT/hooks/hooks.json")" 2>/dev/null; then
  ok "hooks.json parses"
else
  ng "hooks.json parses"
fi

# marketplace.json is what enables `/plugin marketplace add <repo>`. Without it the kit can only be
# installed by hand with --plugin-dir, and the whole auto-trigger story depends on the user
# remembering to do that every session.
MP="$KIT/.claude-plugin/marketplace.json"
if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$(win "$MP")" 2>/dev/null; then
  ok "marketplace.json parses"
else
  ng "marketplace.json parses"
fi
# Name and version must MATCH plugin.json. If they drift, the install points at the wrong cache dir.
if node -e '
const fs = require("fs");
const [mp, pj] = process.argv.slice(1);
const m = JSON.parse(fs.readFileSync(mp, "utf8"));
const p = JSON.parse(fs.readFileSync(pj, "utf8"));
const entry = (m.plugins || []).find(x => x.name === p.name);
if (!entry) throw new Error("marketplace.json has no plugin named " + p.name);
if (entry.version !== p.version) throw new Error("version mismatch: " + entry.version + " vs " + p.version);
if (!entry.source) throw new Error("missing the source field");
' "$(win "$MP")" "$(win "$KIT/.claude-plugin/plugin.json")" 2>/dev/null; then
  ok "marketplace.json matches plugin.json (name + version + source)"
else
  ng "marketplace.json matches plugin.json (name + version + source)"
fi
if [ -x "$KIT/hooks/session-start" ]; then ok "hooks/session-start is executable (filesystem)"; else ng "hooks/session-start is executable (filesystem)"; fi

# The bit on your machine's filesystem does NOT guarantee the bit went into git. This repo once had
# core.fileMode=false, so `chmod +x` was ignored and git stored 100644 — anyone cloning it got a hook
# that would not run, while the tests on the original machine stayed green.
# So check the mode in the INDEX, not on disk.
if git -C "$KIT" rev-parse --git-dir >/dev/null 2>&1; then
  for f in hooks/session-start hooks/session-checkpoint hooks/usage-ledger tests/run-tests.sh tests/acceptance.sh template/init.sh; do
    mode="$(git -C "$KIT" ls-files -s "$f" 2>/dev/null | awk '{print $1}')"
    if [ "$mode" = "100755" ]; then ok "git index: $f is 100755"
    else ng "git index: $f is '$mode' (needs 100755 — anyone cloning could not run it)"; fi
  done
else
  skip_note="not a git repo"
  echo "  (SKIP: not a git repo — cannot check modes in the index)"
fi

# The hook must stay QUIET outside a harness project — that is the difference from injecting unconditionally.
NOHARNESS="$KIT/.tmp-tests/noharness"
rm -rf "$NOHARNESS"; mkdir -p "$NOHARNESS"
out="$(CLAUDE_PROJECT_DIR="$NOHARNESS" bash "$KIT/hooks/session-start" 2>&1)"
if [ -z "$out" ]; then ok "hook stays quiet in a repo with no harness"; else ng "hook stays quiet in a repo with no harness (printed: $out)"; fi

# Inside a harness project: it must emit valid JSON containing the skill and the real state.
P="$(new_project)"
out="$(CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | node -e '
let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
  const j = JSON.parse(s);
  const ctx = j.hookSpecificOutput?.additionalContext ?? j.additionalContext;
  if (typeof ctx !== "string" || !ctx.length) throw new Error("no additionalContext");
  if (!ctx.includes("using-harness")) throw new Error("did not inject the using-harness skill");
  if (!ctx.includes("ACTIVE: F01")) throw new Error("did not inject the real state (active feature)");
  if (!ctx.includes("done_when")) throw new Error("did not inject done_when");
});' 2>/dev/null; then
  ok "hook injects valid JSON + the skill + the real state (ACTIVE F01, done_when)"
else
  ng "hook injects valid JSON + the skill + the real state"
fi

# The hook must warn when a dependency is unfinished — that is what stops overreach at the very start of a session.
P2="$(new_project)"
patch_feature "$P2" "F03" '{"status":"pending"}'
node -e '
const fs=require("fs");const f=process.argv[1]+"/feature_list.json";
const j=JSON.parse(fs.readFileSync(f,"utf8"));j.active_feature="F03";
fs.writeFileSync(f,JSON.stringify(j,null,2));' "$(win "$P2")"
out="$(CLAUDE_PROJECT_DIR="$P2" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | grep -qF 'DEPS NOT DONE'; then
  ok "hook warns about an unfinished dependency"
else
  ng "hook warns about an unfinished dependency"
fi

echo ""
echo "== bootstrap --with-skills =="

P="$KIT/.tmp-tests/skills-dry"
rm -rf "$P"; mkdir -p "$P"
out="$(node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "S" --with-skills --dry-run 2>&1)"
if printf '%s' "$out" | grep -qE '\.claude[\\/]skills[\\/]using-harness[\\/]SKILL\.md'; then
  ok "--with-skills lists .claude/skills/using-harness/SKILL.md"
else
  ng "--with-skills lists .claude/skills/using-harness/SKILL.md"
fi

# Without --with-skills the skills must NOT be dumped into the project (the plugin route is the default).
P="$KIT/.tmp-tests/noskills-dry"
rm -rf "$P"; mkdir -p "$P"
out="$(node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "S" --dry-run 2>&1)"
if printf '%s' "$out" | grep -qF '.claude/skills'; then
  ng "by default skills are not copied into the project"
else
  ok "by default skills are not copied into the project"
fi

# A real copy (not dry-run) must produce readable files.
P="$KIT/.tmp-tests/skills-real"
rm -rf "$P"; mkdir -p "$P"
node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "S" --with-skills >/dev/null 2>&1
if [ -f "$P/.claude/skills/verifying-a-feature/SKILL.md" ]; then
  ok "--with-skills really copies into .claude/skills/"
else
  ng "--with-skills really copies into .claude/skills/"
fi

echo ""
echo "== CLAUDE.md wiring to the skills =="
# Walk skills/ instead of hardcoding a list: adding a new skill and forgetting to wire it into
# CLAUDE.md makes this test fail, rather than being silently ignored as a fixed list would.
for d in "$KIT"/skills/*/; do
  s="$(basename "$d")"
  [ "$s" = "using-harness" ] && continue   # meta skill, injected by the hook, needs no route in CLAUDE.md
  has "CLAUDE.md routes to skill: $s" "$C" "$s"
done

echo ""
echo "== verify-gate: hook registration =="

# The gate only works if it is REGISTERED on all 3 events. Without post-bash the marker is never set
# and the gate blocks every write of done — broken in the worst possible direction.
HJ="$KIT/hooks/hooks.json"
for pair in "PreToolUse:pre-edit" "PostToolUse:post-bash" "PostToolUse:post-edit"; do
  ev="${pair%%:*}"; mode="${pair##*:}"
  if node -e '
const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const groups = (j.hooks || {})[process.argv[2]] || [];
// the real command is:  "${CLAUDE_PLUGIN_ROOT}/hooks/verify-gate" pre-edit
// so there is a closing quote between the script name and the mode. Do not match a
// contiguous "verify-gate <mode>" string.
const re = new RegExp("verify-gate\"?\\s+" + process.argv[3] + "\\b");
const found = groups.some(g => (g.hooks || []).some(h => re.test(h.command || "")));
process.exit(found ? 0 : 1);
' "$HJ" "$ev" "$mode" 2>/dev/null; then
    ok "hooks.json registers $ev -> verify-gate $mode"
  else
    ng "hooks.json registers $ev -> verify-gate $mode"
  fi
done

if [ -x "$KIT/hooks/verify-gate" ]; then ok "hooks/verify-gate is executable"; else ng "hooks/verify-gate is executable"; fi

# --- The init.sh <-> verify-gate contract ---------------------------------------------
# The gate has no way to know a verify run succeeded other than these two strings.
# Changing or deleting them unnoticed is the most dangerous hole in the marker design.
I="$KIT/template/init.sh"
has "init.sh prints the contract string VERIFY OK"     "$I" "VERIFY OK"
has "init.sh prints the contract string VERIFY FAILED" "$I" "VERIFY FAILED"
has "init.sh states that this is the contract with the gate" "$I" "CONTRACT WITH verify-gate"
has "verify-gate reads the right contract string"      "$KIT/hooks/verify-gate.js" 'const CONTRACT = "VERIFY OK"'

# Check BEHAVIOUR, not just file contents: init.sh must ACTUALLY print that string when it runs.
# An intact comment with a changed echo still breaks the contract.
P="$(new_project)"
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1] + "/package.json",
  JSON.stringify({ name: "t", private: true, scripts: { build: "node -e \"0\"" } }, null, 2));
' "$(win "$P")"
out="$(bash "$P/init.sh" build 2>&1)"
if printf '%s' "$out" | grep -qF "VERIFY OK"; then ok "a real init.sh run (with SKIPs) -> prints VERIFY OK"; else ng "a real init.sh run (with SKIPs) -> prints VERIFY OK"; fi

# init.sh has TWO branches that print VERIFY OK: "N check(s) were SKIPped" and "all checks ran".
# The case above only touches the first. A mutation test showed that changing just the second branch
# to "ALL GREEN" left all 143 assertions green — the contract broken with nobody noticing.
# So there must be a case where every check runs (0 SKIP) to cover the other branch.
P2="$(new_project)"
node -e '
const fs = require("fs");
const d = process.argv[1];
fs.writeFileSync(d + "/package.json", JSON.stringify({ name: "t", private: true, scripts: {
  build: "node -e \"0\"", lint: "node -e \"0\"", test: "node -e \"0\"", typecheck: "node -e \"0\"",
}}, null, 2));
fs.mkdirSync(d + "/dist", { recursive: true });          // give check_secret something to scan
fs.writeFileSync(d + "/dist/bundle.js", "console.log(1)\n");
' "$(win "$P2")"
# check_lang also inspects unpushed commit messages, and skips (counted!) when it cannot tell pushed
# from unpushed. So a 0-SKIP fixture now needs a real repo of its own with an upstream — without it
# this case can never reach 0 SKIP and would stop covering the "all checks ran" branch at all.
(
  cd "$P2" || exit 0
  git init -q 2>/dev/null || exit 0
  git -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -c user.email=t@t -c user.name=t commit -qm "chore: fixture baseline" >/dev/null 2>&1
  git branch -q upstream-stub 2>/dev/null
  git branch -q --set-upstream-to=upstream-stub >/dev/null 2>&1
)
out="$(bash "$P2/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "VERIFY OK"; then ok "init.sh with 0 SKIP -> still prints VERIFY OK"; else ng "init.sh with 0 SKIP -> still prints VERIFY OK"; fi
if printf '%s' "$out" | grep -qF "all checks ran"; then ok "init.sh with 0 SKIP -> reports that all checks ran"; else ng "init.sh with 0 SKIP -> reports that all checks ran"; fi
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1] + "/package.json",
  JSON.stringify({ name: "t", private: true, scripts: { build: "node -e \"process.exit(1)\"" } }, null, 2));
' "$(win "$P")"
out="$(bash "$P/init.sh" build 2>&1)"
if printf '%s' "$out" | grep -qF "VERIFY FAILED"; then ok "a failing init.sh -> prints VERIFY FAILED"; else ng "a failing init.sh -> prints VERIFY FAILED"; fi

# The gate must SELF-CHECK the contract before refusing. Without that step, an edited init.sh
# silently flips the gate from fail-open to fail-closed.
if grep -qF 'contractHolds' "$KIT/hooks/verify-gate.js"; then
  ok "verify-gate checks the contract before refusing"
else
  ng "verify-gate checks the contract before refusing — without it an edited init.sh hard-locks the session"
fi
for f in hooks/verify-gate tests/test-verify-gate.sh; do
  mode="$(git -C "$KIT" ls-files -s "$f" 2>/dev/null | awk '{print $1}')"
  if [ "$mode" = "100755" ] || [ -z "$mode" ]; then ok "git index: $f is 100755"
  else ng "git index: $f is '$mode' (needs 100755)"; fi
done

# Fail-open is a deliberate choice and must stay: a broken gate that blocks every write is worse
# than no gate at all. If someone flips it to fail-closed, this test must go red.
if grep -qF 'the gate is NOT active in this session' "$KIT/hooks/verify-gate"; then
  ok "verify-gate fails open when node is missing (with a warning on stderr)"
else
  ng "verify-gate fails open when node is missing"
fi

echo ""
echo "== eval tier: faithfulness =="

E="$KIT/tests/eval-faithfulness.sh"
if [ -f "$E" ]; then ok "tests/eval-faithfulness.sh exists"; else ng "tests/eval-faithfulness.sh exists"; fi

# The control probe is the only thing stopping the eval from rewarding indiscriminate refusal. A suite
# made only of "refuse" probes scores 100% even for a skill that refuses everything and does nothing.
if grep -qF 'expect === "accept"' "$E" || grep -qE 'probe "honest-pass"' "$E"; then
  ok "eval has a control probe (honest-pass)"
else
  ng "eval has a control probe (honest-pass) — without it 'always refuse' scores 100%"
fi

# Evidence must be read from DISK and from tool_result, never from what the agent claims.
if grep -qF 'feature_list.json", "utf8"' "$E"; then ok "eval reads status from the file on disk"; else ng "eval reads status from the file on disk"; fi
if grep -qF 'c.type === "tool_result"' "$E"; then ok "eval reads grounding from tool_result"; else ng "eval reads grounding from tool_result"; fi

# The counted subject must be fixed. Reading active_feature would point at the wrong feature once the
# agent finishes F01 and moves the pointer to F02.
if grep -qF 'const TARGET = "F01"' "$E"; then ok "eval counts a fixed feature, not active_feature"; else ng "eval counts a fixed feature"; fi

# A mode that exercises the fixtures without opening an LLM session — fixture checks must be cheap.
if grep -qF 'EVAL_FIXTURE_DIR' "$E"; then ok "eval has a fixture-only mode (checking fixtures costs no tokens)"; else ng "eval has a fixture-only mode"; fi

# dontAsk blocks ./init.sh while still allowing ls/echo -> the eval would measure permissions rather than fabrication.
if grep -qF 'bypassPermissions' "$E"; then ok "eval uses bypassPermissions (dontAsk would block ./init.sh)"; else ng "eval uses bypassPermissions"; fi

mode="$(git -C "$KIT" ls-files -s tests/eval-faithfulness.sh 2>/dev/null | awk '{print $1}')"
if [ "$mode" = "100755" ] || [ -z "$mode" ]; then ok "git index: eval-faithfulness.sh is 100755"
else ng "git index: eval-faithfulness.sh is '$mode' (needs 100755)"; fi

echo ""
echo "== SHIP checklist drift-lock =="
# The SHIP checklist lives in two places on two distribution channels: pipeline.md travels with
# bootstrap, SKILL.md travels with the plugin. No single process ever holds both, so they cannot be
# generated from one source — they are kept as two copies and locked with assertions, the same way
# the "VERIFY OK" contract between init.sh and verify-gate is kept.
PLS="$KIT/template/.claude/workflow/pipeline.md"
SKS="$KIT/skills/shipping-a-feature/SKILL.md"
ship_boxes() { grep '^- \[ \]' "$1"; }

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

for item in "${SHIP_ITEMS[@]}"; do
  key="${item%%|*}"; re="${item#*|}"
  for f in "$PLS" "$SKS"; do
    if ship_boxes "$f" | grep -qE -- "$re"; then
      ok "ship item '$key' present in $(basename "$f")"
    else
      ng "ship item '$key' MISSING from $(basename "$f")"
    fi
  done
done

# The count pin is the side with teeth. Coverage checks "what I know about is present"; the count
# checks "nothing exists that I do not know about". Add a box without declaring it here -> red.
for f in "$PLS" "$SKS"; do
  cnt="$(ship_boxes "$f" | wc -l | tr -d ' ')"
  if [ "$cnt" -eq "${#SHIP_ITEMS[@]}" ]; then
    ok "checklist box count in $(basename "$f") = ${#SHIP_ITEMS[@]}"
  else
    ng "checklist box count in $(basename "$f") = $cnt, expected ${#SHIP_ITEMS[@]}"
  fi
done

# CLAUDE.md is deliberately outside the lock: it carries the Definition of Done, a different
# granularity, not a third copy of this checklist. Only its section count is pinned.
if grep -qF '9 sections' "$KIT/template/CLAUDE.md"; then ok "CLAUDE.md DoD says 9 sections"; else ng "CLAUDE.md DoD says 9 sections"; fi

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

echo ""
echo "== check_worktree: merged worktrees are surfaced as a WARN, never a FAIL =="

# Give the fixture its OWN git repo. .tmp-tests/ sits inside harness-kit's own working tree (it is
# gitignored, but gitignored is not the same as "outside the repo"), so without this,
# `git rev-parse --show-toplevel` from inside the fixture would resolve to harness-kit's OWN root,
# and check_worktree would report harness-kit's real (still uncleaned) .worktrees/feat-tier-rollback
# instead of the fixture's own state. Same reason the 0-SKIP fixture earlier in this file needed its
# own `git init -q`.
init_git_project() {
  local p="$1"
  ( cd "$p" && git init -q \
      && git -c user.email=t@t -c user.name=t add -A \
      && git -c user.email=t@t -c user.name=t commit -qm "init" >/dev/null )
}

P="$(new_project)"
init_git_project "$P"
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "no merged worktree left uncleaned"; then
  ok "no worktrees beyond the current one -> OK, no warning"
else
  ng "no worktrees beyond the current one -> OK, no warning"
fi
rc=0; bash "$P/init.sh" all >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "no worktrees -> exit 0"; else ng "no worktrees -> exit 0 (rc=$rc)"; fi

P="$(new_project)"
init_git_project "$P"
( cd "$P" && git branch -q feat-done && git worktree add -q .worktrees/feat-done feat-done >/dev/null 2>&1 )
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "[WARN] merged worktree(s) not yet cleaned up"; then
  ok "a merged, present worktree -> WARN"
else
  ng "a merged, present worktree -> WARN"
fi
if printf '%s' "$out" | grep -qF "feat-done"; then
  ok "the warning names the branch"
else
  ng "the warning names the branch"
fi
rc=0; bash "$P/init.sh" all >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "a merged worktree -> still exit 0 (never blocks)"; else ng "a merged worktree -> still exit 0 (rc=$rc)"; fi
if printf '%s' "$out" | grep -qF "VERIFY OK"; then ok "a merged worktree -> VERIFY OK still prints"; else ng "a merged worktree -> VERIFY OK still prints"; fi

P="$(new_project)"
init_git_project "$P"
( cd "$P" && git worktree add -q -b feat-wip .worktrees/feat-wip >/dev/null 2>&1 \
    && cd .worktrees/feat-wip \
    && echo "x" > newfile.txt \
    && git -c user.email=t@t -c user.name=t add -A \
    && git -c user.email=t@t -c user.name=t commit -qm "wip" >/dev/null )
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "[WARN] merged worktree(s)"; then
  ng "an unmerged (active) worktree -> no warning"
else
  ok "an unmerged (active) worktree -> no warning"
fi

if grep -qF "check_worktree" "$KIT/template/init.sh"; then
  ok "init.sh defines check_worktree"
else
  ng "init.sh defines check_worktree"
fi
if grep -qF "check_state; check_worktree" "$KIT/template/init.sh"; then
  ok "the all target runs check_worktree"
else
  ng "the all target runs check_worktree"
fi

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

echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
if [ "$FAILED" -eq 0 ]; then exit 0; else exit 1; fi
