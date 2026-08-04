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

# --- 14. Fix round 1: the bugs an adversarial review found in the TIER rule --------
# The review fired 30 adversarial events straight at the hook and confirmed 5 bugs by execution
# (not by reading the code and guessing). Every assertion below must go RED if its corresponding
# patch is reverted.

# --- 14a/14b. Bug 1 (CRITICAL): JSON that is well-formed but wrongly shaped — an array with a
# null element, or "features" being an object instead of an array — used to make .map/for...of
# throw an UNCAUGHT TypeError, killing the hook (non-zero exit, printing nothing). And because the
# tier rule runs BEFORE the status rule, the status rule never ran either. After the fix: the hook
# must not die, AND the status rule below must still block a write that adds status done.
mkdir -p "$WORK/p6"
mkinit "$WORK/p6"
FL6="$WORK/p6/feature_list.json"
cat > "$FL6" <<'JSON'
{"active_feature":"F01","features":[{"id":"F01","status":"pending"},{"id":"F02","status":"pending"}]}
JSON

reset_marker
crash1="$(node -e '
console.log(JSON.stringify({active_feature:"F01",features:[null,{id:"F01",status:"done"},{id:"F02",status:"pending"}]}));
')"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL6" "$crash1")")"
if denied "$out"; then ok "a null element in features -> the hook survives and the status rule still blocks"; else ng "a null element in features -> the hook survives and the status rule still blocks"; fi

reset_marker
crash2="$(node -e '
console.log(JSON.stringify({active_feature:"F01",features:{a:{id:"F01",status:"done"}}}));
')"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL6" "$crash2")")"
if denied "$out"; then ok "features as an object rather than an array -> the hook survives and the status rule still blocks"; else ng "features as an object rather than an array -> the hook survives and the status rule still blocks"; fi

# --- 14c/14d. Bug 2 (IMPORTANT): the PREVIOUS tier is unreadable (the file on disk is broken, or
# empty) -> no tier judgement at all, even when the new write faithfully preserves a legitimate
# "lite" feature. "The previous tier is unknown" is not "the tier was lowered".
mkdir -p "$WORK/p7"
mkinit "$WORK/p7"
FL7="$WORK/p7/feature_list.json"
printf '{"active_feature":"F01","features":[{"id":"F01","tier":"lite","status":"pending"' > "$FL7"
reset_marker
repaired="$(node -e '
console.log(JSON.stringify({active_feature:"F01",features:[{id:"F01",tier:"lite",status:"pending"},{id:"F02",tier:"standard",status:"pending"}]}));
')"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL7" "$repaired")")"
if denied "$out"; then ng "repairing a broken JSON file on disk while keeping tier lite -> not blocked"; else ok "repairing a broken JSON file on disk while keeping tier lite -> not blocked"; fi

mkdir -p "$WORK/p7e"
mkinit "$WORK/p7e"
FL7E="$WORK/p7e/feature_list.json"
: > "$FL7E"
reset_marker
full="$(node -e '
console.log(JSON.stringify({active_feature:"F01",features:[{id:"F01",tier:"lite",status:"pending"}]}));
')"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL7E" "$full")")"
if denied "$out"; then ng "empty file on disk, writing a tier lite feature -> not blocked (previous tier unknown)"; else ok "empty file on disk, writing a tier lite feature -> not blocked (previous tier unknown)"; fi

# --- 14e. Bug 3 (IMPORTANT): renaming an id (renumbering features while replanning) without any
# real tier change must NOT count as lowering a tier. F03 (tier lite) becomes F93, still tier lite.
mkdir -p "$WORK/p8"
mkinit "$WORK/p8"
FL8="$WORK/p8/feature_list.json"
cat > "$FL8" <<'JSON'
{"active_feature":"F03","features":[{"id":"F03","name":"c","tier":"lite","status":"pending"},{"id":"F04","name":"d","tier":"standard","status":"pending"}]}
JSON
reset_marker
renamed="$(node -e '
console.log(JSON.stringify({active_feature:"F93",features:[{id:"F93",name:"c",tier:"lite",status:"pending"},{id:"F04",name:"d",tier:"standard",status:"pending"}]}));
')"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL8" "$renamed")")"
if denied "$out"; then ng "renaming id F03 -> F93 with tier lite unchanged -> not blocked"; else ok "renaming id F03 -> F93 with tier lite unchanged -> not blocked"; fi

# --- 14f/14g/14h. Bug 4 (IMPORTANT): a tier impersonating a property inherited from
# Object.prototype (toString/constructor/valueOf) used to make "t in TIER_RANK" wrongly return true,
# after which TIER_RANK[t] returned A FUNCTION, and "function < number" is always NaN — slipping past
# every comparison. After the fix (hasOwnProperty) these bogus values must fall back to "standard" —
# lower than the previous "strict" — so this MUST now be a blocked downgrade.
mkdir -p "$WORK/p9"
mkinit "$WORK/p9"
FL9="$WORK/p9/feature_list.json"
cat > "$FL9" <<'JSON'
{"active_feature":"F01","features":[{"id":"F01","name":"a","tier":"strict","status":"pending"}]}
JSON
for bogus in toString constructor valueOf; do
  reset_marker
  poisoned="$(node -e '
const t = process.argv[1];
console.log(JSON.stringify({active_feature:"F01",features:[{id:"F01",name:"a",tier:t,status:"pending"}]}));
' "$bogus")"
  out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL9" "$poisoned")")"
  if denied "$out"; then ok "bogus tier $bogus -> blocked (falls back to standard, lower than strict)"; else ng "bogus tier $bogus -> blocked (falls back to standard, lower than strict)"; fi
done

# --- 14i/14j. Bug 6 (MINOR): the tier comparison must be case-insensitive.
mkdir -p "$WORK/p9b"
mkinit "$WORK/p9b"
FL9B="$WORK/p9b/feature_list.json"
cat > "$FL9B" <<'JSON'
{"active_feature":"F01","features":[{"id":"F01","name":"a","status":"pending"}]}
JSON
reset_marker
upperLite="$(node -e '
console.log(JSON.stringify({active_feature:"F01",features:[{id:"F01",name:"a",tier:"LITE",status:"pending"}]}));
')"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL9B" "$upperLite")")"
if denied "$out"; then ok "an uppercase LITE tier -> still blocked (standard default -> lite)"; else ng "an uppercase LITE tier -> still blocked (standard default -> lite)"; fi

reset_marker
upperStrict="$(node -e '
console.log(JSON.stringify({active_feature:"F01",features:[{id:"F01",name:"a",tier:"STRICT",status:"pending"}]}));
')"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL9" "$upperStrict")")"
if denied "$out"; then ng "changing only the case of STRICT (no real tier change) -> not blocked"; else ok "changing only the case of STRICT (no real tier change) -> not blocked"; fi

# --- 14k. Bug 5 (IMPORTANT): an Edit with replace_all:true must replace EVERY occurrence, not just
# the first one indexOf finds. F01.name and F02.tier are both "strict"; replacing them all with
# "lite" must expose F02 as a genuine downgrade.
mkdir -p "$WORK/p5"
mkinit "$WORK/p5"
FL5="$WORK/p5/feature_list.json"
cat > "$FL5" <<'JSON'
{"active_feature":"F01","features":[{"id":"F01","name":"strict","tier":"standard","status":"pending"},{"id":"F02","name":"b","tier":"strict","status":"pending"}]}
JSON
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL5\",\"old_string\":\"strict\",\"new_string\":\"lite\",\"replace_all\":true}")"
if denied "$out"; then ok "Edit replace_all:true replaces every occurrence -> detects F02 being downgraded"; else ng "Edit replace_all:true replaces every occurrence -> detects F02 being downgraded"; fi

# --- 14l. Check that MultiEdit (the "edits" array) is applied in order by resultingText().
reset_marker
multiedit="$(node -e '
console.log(JSON.stringify({
  file_path: process.argv[1],
  edits: [
    { old_string: "\"tier\":\"strict\"", new_string: "\"tier\":\"standard\"" },
    { old_string: "\"name\":\"b\"", new_string: "\"name\":\"bb\"" }
  ]
}));
' "$FL4")"
out="$(fire pre-edit "$multiedit")"
if denied "$out"; then ok "MultiEdit (the edits array) applied in order -> detects F01 being downgraded"; else ng "MultiEdit (the edits array) applied in order -> detects F01 being downgraded"; fi

# --- 14m/14n. The two fall-through paths of resultingText(): old_string not found on disk, and a
# post-write result that does not parse as JSON. Both must fall through to the normal status rule
# (which creates no done here), never blocked on tier grounds.
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL4\",\"old_string\":\"DOES_NOT_EXIST_XYZ\",\"new_string\":\"\\\"tier\\\":\\\"lite\\\"\"}")"
if denied "$out"; then ng "old_string not found on disk -> falls through, not blocked"; else ok "old_string not found on disk -> falls through, not blocked"; fi

reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL4\",\"content\":\"not valid json {{{\"}")"
if denied "$out"; then ng "the written result does not parse as JSON -> falls through, not blocked"; else ok "the written result does not parse as JSON -> falls through, not blocked"; fi

# --- 14o. A regression guard for bug 2: reformatting (changing nothing real) a file that already
# holds a tier "lite" feature must NOT be blocked.
mkdir -p "$WORK/p11"
mkinit "$WORK/p11"
FL11="$WORK/p11/feature_list.json"
cat > "$FL11" <<'JSON'
{"active_feature":"F05","features":[{"id":"F05","name":"e","tier":"lite","status":"pending"}]}
JSON
reset_marker
reformatted="$(node -e '
const j = { active_feature: "F05", features: [ { id: "F05", name: "e", tier: "lite", status: "pending" } ] };
console.log(JSON.stringify(j, null, 2));
')"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL11" "$reformatted")")"
if denied "$out"; then ng "reformatting a file holding a tier lite feature, changing nothing -> not blocked"; else ok "reformatting a file holding a tier lite feature, changing nothing -> not blocked"; fi

# --- 12. Garbage JSON on stdin -> must not explode, must not block -----------------
out="$(printf 'not json' | bash "$GATE" pre-edit 2>/dev/null)"
if [ -z "$out" ]; then ok "garbage stdin -> silently let through (no session lock)"; else ng "garbage stdin -> silently let through"; fi

reset_marker
echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
