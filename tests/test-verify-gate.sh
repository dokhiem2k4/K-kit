#!/usr/bin/env bash
# Test verify-gate — feed event JSON straight into the hook's stdin and read the decision back.
# No LLM session is opened, so this runs in CI and can be run as many times as you like.
#
# This gate refuses the user's write operations, so it must be tested harder than the rest:
# one false positive here hard-locks the working session.

set -uo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"
GATE="$KIT/hooks/verify-gate"

PASSED=0
FAILED=0
ok() { echo "  PASS  $1"; PASSED=$((PASSED + 1)); }
ng() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/verify-gate-test.XXXXXX")"
MARKERS="${TMPDIR:-/tmp}/harness-kit-verify"
trap 'rm -rf "$WORK"' EXIT

SID="test-$$"
reset_marker() { rm -f "$MARKERS/$SID" 2>/dev/null; }

# fire <mode> <json-tool_input> [tool_response]
fire() {
  local mode="$1" tool_input="$2" resp="${3:-}"
  node -e '
const [sid, ti, resp] = process.argv.slice(1);
process.stdout.write(JSON.stringify({
  session_id: sid, hook_event_name: "x", cwd: process.cwd(),
  tool_name: "Edit", tool_input: JSON.parse(ti), tool_response: resp,
}));
' "$SID" "$tool_input" "$resp" | bash "$GATE" "$mode" 2>/dev/null
}

denied() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }

# Every fixture needs an init.sh able to print "VERIFY OK": ever since the gate checks the contract
# before refusing, a project without init.sh is LET THROUGH (by design). A fixture missing init.sh
# would make every "must block" case fail — and that would be a bad fixture, not a bad gate.
mkinit() { printf '#!/usr/bin/env bash\necho "VERIFY OK (all)"\n' > "$1/init.sh"; }

FL="$WORK/feature_list.json"
mkinit "$WORK"
cat > "$FL" <<'JSON'
{"active_feature":"F01","features":[{"id":"F01","name":"a","status":"pending"},{"id":"F02","name":"b","status":"pending"}]}
JSON

echo "== verify-gate =="

# --- 1. Not verified yet -> writing done must be BLOCKED --------------------------
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"\\\"status\\\": \\\"pending\\\"\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ok "not verified -> writing done is BLOCKED"; else ng "not verified -> writing done is BLOCKED"; fi

# The refusal reason must be complete enough for the agent to act on, not a curt one-liner.
if printf '%s' "$out" | grep -q 'VERIFY OK' && printf '%s' "$out" | grep -q 'init.sh'; then
  ok "the refusal reason says what to run"
else
  ng "the refusal reason says what to run"
fi

# --- 2. After a VERIFY OK -> let through -------------------------------------------
reset_marker
fire post-bash '{}' 'VERIFY OK (all) — all checks ran.' >/dev/null
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"\\\"status\\\": \\\"pending\\\"\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ng "with a VERIFY OK -> let through"; else ok "with a VERIFY OK -> let through"; fi

# --- 3. VERIFY FAILED must CLEAR the marker ----------------------------------------
# If we only set and never cleared, an agent could go green once, break everything, and keep write access.
reset_marker
fire post-bash '{}' 'VERIFY OK (all)' >/dev/null
fire post-bash '{}' 'VERIFY FAILED (build)' >/dev/null
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ok "VERIFY FAILED clears the marker -> blocked again"; else ng "VERIFY FAILED clears the marker -> blocked again"; fi

# --- 4. Editing code after verify -> the marker must be cleared ---------------------
# This is the main loophole: run verify green first, edit code after, then mark done.
reset_marker
fire post-bash '{}' 'VERIFY OK (all)' >/dev/null
fire post-edit "{\"file_path\":\"$WORK/src/app.js\"}" >/dev/null
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ok "editing code after verify -> marker cleared, blocked again"; else ng "editing code after verify -> marker cleared, blocked again"; fi

# --- 5. Editing a STATE file must NOT clear the marker -----------------------------
# progress.md and the dossier are exactly what MUST be written right before marking done. Clearing
# the marker here would make the gate block the very workflow it demands.
for f in progress.md docs/features/F01-scaffold.md; do
  reset_marker
  fire post-bash '{}' 'VERIFY OK (all)' >/dev/null
  fire post-edit "{\"file_path\":\"$WORK/$f\"}" >/dev/null
  out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
  if denied "$out"; then ng "editing $f must NOT clear the marker"; else ok "editing $f must NOT clear the marker"; fi
done

# --- 6. Not touching feature_list.json -> never blocked ----------------------------
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$WORK/src/app.js\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ng "a file other than feature_list.json is not blocked"; else ok "a file other than feature_list.json is not blocked"; fi

# --- 7. Writing a status that is not done -> not blocked ---------------------------
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"in_progress\\\"\"}")"
if denied "$out"; then ng "writing status in_progress is not blocked"; else ok "writing status in_progress is not blocked"; fi

# --- 8. A Write that rewrites the same state -> not blocked ------------------------
# Reformatting the JSON without adding any done is not a new claim.
# The file must actually be named feature_list.json, in its own directory. The first version named it
# fl2.json, so the hook skipped it exactly as designed — case 8 went falsely green and case 9 falsely red.
mkdir -p "$WORK/p2"
mkinit "$WORK/p2"
FL2="$WORK/p2/feature_list.json"
cat > "$FL2" <<'JSON'
{"active_feature":"F02","features":[{"id":"F01","name":"a","status":"done"},{"id":"F02","name":"b","status":"pending"}]}
JSON
reset_marker
same="$(node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))))' "$FL2")"
out="$(fire pre-edit "$(node -e '
const fs=require("fs");
console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}));
' "$FL2" "$same")")"
if denied "$out"; then ng "a Write keeping the same done count -> not blocked"; else ok "a Write keeping the same done count -> not blocked"; fi

# --- 9. A Write that ADDS a done feature -> must block -----------------------------
reset_marker
more="$(node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
j.features[1].status="done";
console.log(JSON.stringify(j));
' "$FL2")"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL2" "$more")")"
if denied "$out"; then ok "a Write adding a done feature -> blocked"; else ng "a Write adding a done feature -> blocked"; fi

# --- 10. The marker is keyed per session -------------------------------------------
# Another session running verify must not grant write access to this one.
reset_marker
SID_OTHER="other-$$"; ( SID="$SID_OTHER"; fire post-bash '{}' 'VERIFY OK (all)' >/dev/null )
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
rm -f "$MARKERS/$SID_OTHER" 2>/dev/null
if denied "$out"; then ok "another session's marker does not unlock this session"; else ng "another session's marker does not unlock this session"; fi

# --- 11. A broken VERIFY OK contract -> the gate must LET THROUGH, never hard-lock --
# This is the most dangerous hole in the marker design: the gate has no other way to know that verify
# succeeded. If init.sh stops printing "VERIFY OK", the marker is never set and the gate silently flips
# from fail-open to fail-closed — blocking every write of done with nobody understanding why.
mkdir -p "$WORK/p3"
FL3="$WORK/p3/feature_list.json"
cp "$FL" "$FL3"
EDIT3="{\"file_path\":\"$FL3\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}"

# 11a. no init.sh -> must not block
reset_marker
out="$(fire pre-edit "$EDIT3")"
if denied "$out"; then ng "no init.sh -> gate lets through (no hard lock)"; else ok "no init.sh -> gate lets through (no hard lock)"; fi

# 11b. init.sh exists but does NOT print "VERIFY OK" -> must not block, and must warn
reset_marker
printf '#!/usr/bin/env bash
echo "everything is fine"
' > "$WORK/p3/init.sh"
err="$(printf '%s' "$(node -e '
const [sid, ti] = process.argv.slice(1);
process.stdout.write(JSON.stringify({session_id: sid, tool_input: JSON.parse(ti)}));
' "$SID" "$EDIT3")" | bash "$GATE" pre-edit 2>&1 >/dev/null)"
out="$(fire pre-edit "$EDIT3")"
if denied "$out"; then ng "init.sh does not print VERIFY OK -> gate lets through"; else ok "init.sh does not print VERIFY OK -> gate lets through"; fi
if printf '%s' "$err" | grep -q 'contract'; then ok "broken contract -> warning on stderr"; else ng "broken contract -> warning on stderr (got: ${err:-empty})"; fi

# 11c. init.sh DOES print "VERIFY OK" -> the gate goes back to working normally
reset_marker
printf '#!/usr/bin/env bash
echo "VERIFY OK (all)"
' > "$WORK/p3/init.sh"
out="$(fire pre-edit "$EDIT3")"
if denied "$out"; then ok "init.sh has VERIFY OK -> gate blocks as usual"; else ng "init.sh has VERIFY OK -> gate blocks as usual"; fi

# 11d. running init.sh with neither VERIFY OK nor FAILED in the output -> warn that the contract broke
err="$(node -e '
process.stdout.write(JSON.stringify({
  session_id: process.argv[1],
  tool_input: { command: "./init.sh all" },
  tool_response: "everything is fine",
}));
' "$SID" | bash "$GATE" post-bash 2>&1 >/dev/null)"
if printf '%s' "$err" | grep -q 'VERIFY OK'; then ok "init.sh run with no VERIFY OK/FAILED -> warns immediately"; else ng "init.sh run with no VERIFY OK/FAILED -> warns immediately"; fi

# --- 12. Garbage JSON on stdin -> must not explode, must not block -----------------
out="$(printf 'not json' | bash "$GATE" pre-edit 2>/dev/null)"
if [ -z "$out" ]; then ok "garbage stdin -> silently let through (no session lock)"; else ng "garbage stdin -> silently let through"; fi

reset_marker
echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
