#!/usr/bin/env bash
# Verification runner — {{PROJECT_NAME}}
# Usage: ./init.sh [scaffold|build|secret|docs|state|lang|all]   (default: all)
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

# Every done/verified feature must have a dossier at docs/features/<ID>-<slug>.md.
# The rules live in scripts/check-docs.mjs; this function only decides whether to run it.
check_docs() {
  step "FEATURE DOCS (dossier for done/verified features)"
  command -v node >/dev/null 2>&1 || { skip "no node — cannot validate dossiers"; return; }
  [ -f feature_list.json ] || { skip "no feature_list.json"; return; }
  # A missing validator FAILs rather than SKIPs, for the same reason check_lang does: a counted SKIP
  # still prints VERIFY OK, which mints a marker and hands back the bypass the gate exists to remove.
  if [ ! -f scripts/check-docs.mjs ]; then
    echo "   [FAIL] scripts/check-docs.mjs is missing — the dossier validator was removed"
    echo "   Restore it (bootstrap --force) or delete check_docs from this file deliberately."
    FAIL=1
    return
  fi
  node scripts/check-docs.mjs || FAIL=1
}

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

# Invariant: every artifact in this repo is written in English. See CLAUDE.md, section "Language".
# The detection itself lives in scripts/check-lang.mjs; this function decides WHAT gets checked.
# CUSTOMIZE: directories never scanned, and the size ceiling for a single file.
LANG_SKIP_DIRS=".git node_modules dist build .next out target vendor coverage .venv __pycache__ .tmp-tests"
LANG_MAX_KB=512
check_lang() {
  step "LANGUAGE (English-only invariant)"
  command -v node >/dev/null 2>&1 || { skip "no node — cannot check the language invariant"; return; }
  # A missing validator FAILs rather than SKIPs. A missing `node` is the environment's doing, so that
  # fails open; a missing scripts/check-lang.mjs means part of the harness was deleted, and a counted
  # SKIP would still print VERIFY OK — handing back the exact bypass this check exists to remove.
  if [ ! -f scripts/check-lang.mjs ]; then
    echo "   [FAIL] scripts/check-lang.mjs is missing — the language validator was removed"
    echo "   Restore it (bootstrap --force) or delete check_lang from this file deliberately."
    FAIL=1
    return
  fi

  node scripts/check-lang.mjs files "$LANG_SKIP_DIRS" "$LANG_MAX_KB" || FAIL=1

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
    node scripts/check-lang.mjs messages "$(git log --format='%h %s%n%b' '@{u}..HEAD' 2>/dev/null)" || FAIL=1
  fi
}

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
