#!/usr/bin/env bash
# Verification runner — {{PROJECT_NAME}}
# Usage: ./init.sh [scaffold|build|secret|docs|lang|all]   (default: all)
# CUSTOMIZE: edit the CONFIG variables + the check_build/check_secret functions for your stack.
# Fail-fast: build/typecheck hard errors stop inside their own target (set -e semantics);
# the runner aggregates FAIL so the remaining checks still get reported.
set -uo pipefail
cd "$(dirname "$0")"
TARGET="${1:-all}"
FAIL=0
SKIPPED=0
step() { echo ""; echo "==> $1"; }
# Checks that could not run must be counted — an all-SKIP run must never read as "everything was checked".
skip() { echo "   (SKIP: $1)"; SKIPPED=$((SKIPPED + 1)); }

# ---- CONFIG (edit per project) ----------------------------------------------
# Directories holding code that runs on the client (the bundle must contain NO secrets):
# web dist, extension dist, mobile build...
CLIENT_DIRS=("dist" "build" "web/.next" "extension/dist")
# Secret patterns that must never leak into a client bundle:
SECRET_REGEX='service_role|BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|xox[baprs]-'
# -----------------------------------------------------------------------------

check_scaffold() {
  step "SCAFFOLD"
  [ -f package.json ] && echo "   package.json: OK" || echo "   (no package.json yet — edit this if your stack differs)"
  [ -f .env.example ] && echo "   .env.example: OK" || echo "   (no .env.example yet)"
  [ -f README.md ]    && echo "   README.md: OK"    || echo "   (no README.md yet)"
}

# Does package.json have a script called <name>?
# Do NOT infer this from the exit code of `npm run <name>`: that returns non-zero both when the
# script is MISSING and when the script ran and failed. Conflating those two is exactly how one
# red lint run slips past the gate with nobody noticing.
has_script() {
  node -e '
const p = require("./package.json");
process.exit((p.scripts && p.scripts[process.argv[1]]) ? 0 : 1);
' "$1" 2>/dev/null
}

# run_script <name> [required]
#   script missing -> SKIP (counted), unless required=yes, then FAIL
#   script fails   -> FAIL, and PRINT THE OUTPUT VERBATIM (do not swallow stderr — you need to know why)
run_script() {
  local name="$1" required="${2:-no}"
  if ! command -v node >/dev/null 2>&1; then skip "no node — cannot tell whether package.json has a \"$name\" script"; return; fi
  if ! has_script "$name"; then
    if [ "$required" = "yes" ]; then echo "   [FAIL] missing \"$name\" script in package.json"; FAIL=1
    else skip "no \"$name\" script in package.json"; fi
    return
  fi
  echo "   -> npm run $name"
  if npm run --silent "$name"; then echo "   OK: $name"; else echo "   [FAIL] $name"; FAIL=1; fi
}

# CUSTOMIZE: switch to your stack's real build/test commands (npm/pnpm/cargo/go/gradle/dotnet...)
check_build() {
  step "BUILD / TYPECHECK / LINT / TEST"
  if [ ! -f package.json ]; then
    skip "not a node project — CUSTOMIZE check_build for your stack"
    echo "   (no command ran — this is NOT a pass)"
    return
  fi

  run_script lint

  # typecheck: prefer the project's own script; if there is none, use the LOCAL tsc when a tsconfig exists.
  # Do not use `npx --yes tsc`: it downloads typescript from the network, which is slow and may differ
  # from the project's own version.
  if has_script typecheck; then
    run_script typecheck
  elif [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ]; then
    echo "   -> node_modules/.bin/tsc --noEmit"
    if node_modules/.bin/tsc --noEmit; then echo "   OK: typecheck (tsc)"; else echo "   [FAIL] typecheck (tsc)"; FAIL=1; fi
  else
    skip "no \"typecheck\" script and no local tsc"
  fi

  run_script build yes   # build is required: if it does not build, it cannot be done
  run_script test
}

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

# Every done/verified feature must have a dossier at docs/features/<ID>-<slug>.md with all 8 sections.
check_docs() {
  step "FEATURE DOCS (dossier for done/verified features)"
  command -v node >/dev/null 2>&1 || { skip "no node — cannot validate dossiers"; return; }
  [ -f feature_list.json ] || { skip "no feature_list.json"; return; }
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

# Invariant: every artifact in this repo is written in English. See CLAUDE.md, section "Language".
#
# WHAT THIS CAN AND CANNOT SEE. It detects Vietnamese *diacritic* characters, which no English text
# uses, so a hit is unambiguous. Vietnamese written WITHOUT diacritics is plain ASCII and no grep can
# separate it from identifiers or abbreviations. So a green result is evidence of one half of the
# rule, never proof of the whole of it — do not read it as "the repo is English".
#
# Scans EVERY text file rather than an allowlist of extensions. An allowlist silently ignores
# Dockerfile, Makefile, *.rst, *.toml and whatever nobody thought of; the exclusion is by directory
# and by actual binary content (a NUL byte), not by filename.
# CUSTOMIZE: directories never scanned, and the size ceiling for a single file.
LANG_SKIP_DIRS=".git node_modules dist build .next out target vendor coverage .venv __pycache__ .tmp-tests"
LANG_MAX_KB=512
check_lang() {
  step "LANGUAGE (English-only invariant)"
  command -v node >/dev/null 2>&1 || { skip "no node — cannot check the language invariant"; return; }

  node -e '
const fs = require("fs");
const path = require("path");
const SKIP = new Set(process.argv[1].split(" ").filter(Boolean));
const MAXB = parseInt(process.argv[2], 10) * 1024;
// Extensions that are binary by definition. Everything else is read and sniffed for a NUL byte,
// so an unknown text format is scanned rather than skipped.
const BIN = new Set([".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".pdf", ".zip", ".gz", ".tgz",
                     ".woff", ".woff2", ".ttf", ".otf", ".eot", ".mp3", ".mp4", ".mov", ".wasm",
                     ".so", ".dylib", ".dll", ".exe", ".class", ".jar", ".bin"]);
// Vietnamese-distinctive code points: the Latin Extended Additional block (U+1EA0-U+1EF9, in practice
// only Vietnamese uses it), the letters a-breve / d-stroke / o-horn / u-horn, and the circumflex vowels.
// Written as \u escapes on purpose: spelling the characters out would make this very line the first
// thing the check reports.
const VN = new RegExp("[\\u1EA0-\\u1EF9\\u0102\\u0103\\u0110\\u0111"
                   + "\\u01A0\\u01A1\\u01AF\\u01B0\\u00C2\\u00E2\\u00CA\\u00EA\\u00D4\\u00F4]");
const hits = [];
const walk = (dir) => {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isSymbolicLink()) continue;
    if (e.isDirectory()) { if (!SKIP.has(e.name)) walk(p); continue; }
    if (BIN.has(path.extname(e.name).toLowerCase())) continue;
    let buf;
    try {
      if (fs.statSync(p).size > MAXB) continue;
      buf = fs.readFileSync(p);
    } catch { continue; }
    if (buf.includes(0)) continue;                       // binary whatever the name says
    buf.toString("utf8").split(/\r?\n/).forEach((line, i) => {
      if (VN.test(line)) hits.push(p.replace(/^\.[\\\/]/, "") + ":" + (i + 1) + ": " + line.trim().slice(0, 90));
    });
  }
};
walk(".");
if (hits.length) {
  console.log("   [FAIL] non-English text in " + hits.length + " line(s):");
  for (const h of hits.slice(0, 15)) console.log("      " + h);
  if (hits.length > 15) console.log("      ... and " + (hits.length - 15) + " more");
  console.log("   Everything this repo contains is written in English. See CLAUDE.md, section \"Language\".");
  process.exit(1);
}
console.log("   OK: 0 lines with non-English diacritics (does NOT prove the whole invariant)");
' "$LANG_SKIP_DIRS" "$LANG_MAX_KB" || FAIL=1

  # Commit messages are artifacts too, and the rule names them explicitly.
  # Only messages NOT YET PUSHED are checked. Published history cannot be corrected without a
  # force-push, so scanning it would turn init.sh permanently red on adoption for something nobody
  # is allowed to fix — the same reason bootstrap.mjs never overwrites an existing file.
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    skip "not a git repository — commit messages not checked"
  elif [ "$(git rev-parse --show-toplevel 2>/dev/null)" != "$PWD" ]; then
    # This project sits INSIDE someone else's repository. Its commits are not ours to judge:
    # scanning them would report a parent project's history as this project's violation.
    skip "project is nested inside another git repository — commit messages not checked"
  elif ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    skip "branch has no upstream — cannot tell pushed from unpushed commits, messages not checked"
  else
    node -e '
const VN = new RegExp("[\\u1EA0-\\u1EF9\\u0102\\u0103\\u0110\\u0111"
                   + "\\u01A0\\u01A1\\u01AF\\u01B0\\u00C2\\u00E2\\u00CA\\u00EA\\u00D4\\u00F4]");
const bad = process.argv[1].split(/\r?\n/).filter((l) => VN.test(l));
if (bad.length) {
  console.log("   [FAIL] non-English text in " + bad.length + " unpushed commit message line(s):");
  for (const b of bad.slice(0, 10)) console.log("      " + b.trim().slice(0, 100));
  console.log("   Reword them before pushing: git rebase -i @{u}");
  process.exit(1);
}
console.log("   OK: unpushed commit messages are English");
' "$(git log --format='%h %s%n%b' '@{u}..HEAD' 2>/dev/null)" || FAIL=1
  fi
}

case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  docs)     check_docs ;;
  lang)     : ;;                 # nothing extra — the unconditional run below is the whole target
  all)      check_scaffold; check_build; check_secret; check_docs ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac

# The language invariant is repo-wide, not feature-scoped, so it runs on EVERY target rather than
# only under `all`.
#
# This is not tidiness, it closes a measured hole. verify-gate sets its marker on ANY output
# containing "VERIFY OK". While lang ran only under `all`, an agent could run `./init.sh build`,
# mint a marker from that, and write status done with non-English text still sitting in the repo —
# the same class of loophole ("go green on something narrow, then claim done") that verify-gate
# exists to close, just on a different axis. Running it on every target removes the narrow path.
check_lang

# ==== CONTRACT WITH verify-gate — DO NOT CHANGE THE TWO STRINGS BELOW ==================
# hooks/verify-gate reads this file's output to know that a verify run happened and how it went:
#   "VERIFY OK"     -> set the marker, allow writing status done into feature_list.json
#   "VERIFY FAILED" -> clear the marker
# Changing or removing these two strings blinds the gate. The gate will notice and LET THROUGH
# (with a warning on stderr) rather than hard-locking the session — but at that point it no longer
# protects anything. tests/run-tests.sh has assertions pinning both strings.
# =======================================================================================
echo ""
if [ "$FAIL" -ne 0 ]; then
  echo "VERIFY FAILED ($TARGET)"
elif [ "$SKIPPED" -gt 0 ]; then
  # Green but incomplete. Say so plainly, so an all-SKIP run never gets pasted into
  # progress.md as "all green" evidence.
  echo "VERIFY OK ($TARGET) — but $SKIPPED check(s) were SKIPped, so NOT everything was checked."
  echo "Before marking done: either make those checks runnable, or run them by hand and paste the output."
else
  echo "VERIFY OK ($TARGET) — all checks ran."
fi
exit $FAIL
