#!/usr/bin/env bash
# Acceptance test — harness-kit. Run: bash tests/acceptance.sh
#
# run-tests.sh checks STRUCTURE (does the file exist, is the frontmatter right, did the exit code change).
# This file checks BEHAVIOUR: it opens a REAL Claude Code session inside a freshly bootstrapped project
# and watches whether the agent invokes the right gate skill on its own. A skill that never fires is a dead skill.
#
# Requires: a logged-in claude CLI + node. Costs real tokens (3 short sessions, low max-turns).
# CI has no credentials -> the script prints SKIP and exits 0 rather than faking a pass.

set -uo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"
MODEL="${ACCEPTANCE_MODEL:-sonnet}"

PASSED=0
FAILED=0
ok() { echo "  PASS  $1"; PASSED=$((PASSED + 1)); }
ng() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

# WORK must live OUTSIDE the kit repo.
# It originally sat at "$KIT/.tmp-acceptance", so the negative probe ran inside the harness-kit repo
# itself — surrounded by skills/, template/feature_list.json, .claude-plugin/. The agent looked around,
# saw every sign of a harness, and calling harness-startup was reasonable — not the skill's fault.
# Measured by hand: inside the kit repo, 3/3 false positives on haiku; outside it, 0/5.
# A negative fixture sitting next to the very thing it must deny is not a negative fixture.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-acceptance.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP: no claude CLI — cannot run the acceptance test."
  echo "      (this is not a pass; the auto-trigger behaviour is UNVERIFIED)"
  exit 0
fi
if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: no node."; exit 0
fi

# WORK was already created by mktemp -d

# probe <name> <cwd> <prompt> <max-turns> <expected-skill | NONE> <expected-hook: yes|no>
probe() {
  local name="$1" dir="$2" prompt="$3" turns="$4" want_skill="$5" want_hook="$6"
  local out="$WORK/$name.jsonl"

  ( cd "$dir" && timeout 420 claude -p "$prompt" \
      --plugin-dir "$KIT" --model "$MODEL" --permission-mode dontAsk \
      --max-turns "$turns" --output-format stream-json --verbose ) > "$out" 2>/dev/null
  # The exit code is ignored on purpose: hitting max-turns returns 1, but all we need to know
  # is which skill got invoked.

  if [ ! -s "$out" ]; then ng "$name: the session returned nothing (out of credit? network?)"; return; fi

  node -e '
const fs = require("fs");
const [p, wantSkill, wantHook] = process.argv.slice(1);
const raw = fs.readFileSync(p, "utf8");
const skills = [];
for (const line of raw.trim().split("\n")) {
  let e; try { e = JSON.parse(line) } catch { continue }
  const m = e.message;
  if (!m || !Array.isArray(m.content)) continue;
  for (const c of m.content) if (c.type === "tool_use" && c.name === "Skill") skills.push(c.input.skill);
}
const hook = /You are inside a project that has a HARNESS/.test(raw);
const state = /ACTIVE: F0/.test(raw);
const errs = [];
if (wantHook === "yes" && !hook) errs.push("the hook did not fire");
if (wantHook === "yes" && !state) errs.push("the hook did not inject the real state");
if (wantHook === "no" && hook) errs.push("the hook fired in a repo with no harness");
if (wantSkill === "NONE") {
  if (skills.length) errs.push("no skill should have been invoked, but got: " + skills.join(", "));
} else if (!skills.some(s => s.endsWith(wantSkill))) {
  errs.push("expected skill " + wantSkill + ", actual: " + (skills.join(", ") || "(no skill invoked)"));
}
if (errs.length) { console.error(errs.join("; ")); process.exit(1); }
console.log("skill: " + (skills.join(", ") || "-") + (hook ? " | hook: fired" : " | hook: quiet"));
' "$out" "$want_skill" "$want_hook" > "$WORK/$name.res" 2> "$WORK/$name.err"

  if [ $? -eq 0 ]; then ok "$name — $(cat "$WORK/$name.res")"
  else ng "$name — $(cat "$WORK/$name.err")"; fi
}

echo "== acceptance: auto-trigger in a real session (model: $MODEL) =="

PROJ="$WORK/proj"
mkdir -p "$PROJ"
node "$KIT/bootstrap.mjs" --target "$PROJ" --name "Acceptance Probe" --stack "node" >/dev/null 2>&1

# 1. A vague resume -> must read the state before doing anything.
probe "resume"    "$PROJ" "carry on" 6 "harness-startup" yes

# 2. A claim that it is finished -> must enter the verify gate, must NOT write done straight away.
probe "claim-done" "$PROJ" "F01 is finished, mark it done in feature_list.json for me" 6 "verifying-a-feature" yes

# Probes 3 and 4 get more turns than the first two. Reason: every session is a "start of session", so
# the agent usually reads harness-startup FIRST and only then chains into the right gate — which is
# correct behaviour, not a bug. With 6 turns the chain gets cut off midway and the test fails unfairly.
# We do NOT lower the assertion (accepting harness-startup as sufficient), because then a session that
# merely reads the state and stops would also pass — exactly what this probe exists to catch.

# 3. Adding a new feature -> must enter planning (testable done_when), not scribble into the JSON.
probe "add-feature" "$PROJ" "add a feature letting users change their avatar to feature_list.json" 12 "planning-features" yes

# 4. A failing test -> must enter debugging (decide scope/state), not jump straight to fixing.
# This probe gets its OWN PROJECT, it does not share $PROJ with probes 2 and 3.
# Reason: probe 2 (mark done) and probe 3 (add feature) both WRITE to feature_list.json, so probe 4
# would run against state mutated by the earlier probes — the result would depend on run order and
# would not reproduce. A shared fixture is not a fixture.
#
# The fixture also needs a GENUINELY FAILING test. A freshly bootstrapped project has no tests at all,
# so "the test is failing" would be a false premise: the agent checks, finds no test, and reports back —
# correct behaviour, but the probe would fail unfairly.
PROJ_DBG="$WORK/proj-dbg"
mkdir -p "$PROJ_DBG"
node "$KIT/bootstrap.mjs" --target "$PROJ_DBG" --name "Debug Probe" --stack "node" >/dev/null 2>&1
node -e '
const fs = require("fs");
const d = process.argv[1];
fs.writeFileSync(d + "/package.json", JSON.stringify({
  name: "debug-probe", private: true,
  scripts: { build: "node -e \"0\"", test: "node sum.test.js" }
}, null, 2));
fs.writeFileSync(d + "/sum.js", "module.exports = (a, b) => a - b;\n");        // bug: minus instead of plus
fs.writeFileSync(d + "/sum.test.js",
  "const sum = require(\"./sum\");\n" +
  "if (sum(2, 3) !== 5) { console.error(\"FAIL: sum(2,3) =\", sum(2, 3), \"expected 5\"); process.exit(1); }\n" +
  "console.log(\"ok\");\n");
' "$PROJ_DBG"
probe "test-fails" "$PROJ_DBG" "npm test is red, fix it for me" 12 "debugging-a-feature" yes

# 5. Negative: outside a harness project the hook must stay quiet and no skill may be pulled in.
# This fixture must be ISOLATED: not inside the kit repo, and not next to $PROJ.
# Putting it in $WORK (beside the already-bootstrapped proj/) was still enough for the agent to spot the
# harness in the neighbouring directory and pull the skill in — measured by hand on haiku. So it gets
# its own mktemp.
NOH="$(mktemp -d "${TMPDIR:-/tmp}/plain-project.XXXXXX")"
cleanup_noh() { rm -rf "$NOH"; }
trap 'cleanup; cleanup_noh' EXIT
printf '# my-notes\n\nAn ordinary repo, nothing to do with the harness.\n' > "$NOH/README.md"
printf 'console.log("hi")\n' > "$NOH/index.js"
probe "no-harness" "$NOH" "hi, what repo is this" 3 NONE no

echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
