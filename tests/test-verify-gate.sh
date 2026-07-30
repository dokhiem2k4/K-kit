#!/usr/bin/env bash
# Test verify-gate — bom JSON su kien thang vao stdin cua hook, doc quyet dinh tra ve.
# Khong mo phien LLM nao, nen chay duoc trong CI va chay duoc bao nhieu lan cung duoc.
#
# Gate nay tu choi thao tac ghi cua nguoi dung, nen no phai bi kiem ky hon phan con lai:
# mot false-positive o day khoa cung phien lam viec.

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

# Moi fixture phai co init.sh in duoc "VERIFY OK": tu khi gate kiem hop dong truoc khi
# tu choi, mot project khong co init.sh se duoc CHO QUA (dung thiet ke). Fixture thieu
# init.sh thi moi ca "phai chan" deu do — va do la fixture sai, khong phai gate sai.
mkinit() { printf '#!/usr/bin/env bash\necho "VERIFY OK (all)"\n' > "$1/init.sh"; }

FL="$WORK/feature_list.json"
mkinit "$WORK"
cat > "$FL" <<'JSON'
{"active_feature":"F01","features":[{"id":"F01","name":"a","status":"pending"},{"id":"F02","name":"b","status":"pending"}]}
JSON

echo "== verify-gate =="

# --- 1. Chua verify -> ghi done phai bi CHAN -------------------------------------
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"\\\"status\\\": \\\"pending\\\"\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ok "chua verify -> ghi done bi CHAN"; else ng "chua verify -> ghi done bi CHAN"; fi

# Ly do tu choi phai day du de agent sua duoc, khong phai mot cau cut ngui.
if printf '%s' "$out" | grep -q 'VERIFY OK' && printf '%s' "$out" | grep -q 'init.sh'; then
  ok "ly do tu choi noi ro phai chay gi"
else
  ng "ly do tu choi noi ro phai chay gi"
fi

# --- 2. Sau khi co VERIFY OK -> cho qua ------------------------------------------
reset_marker
fire post-bash '{}' 'VERIFY OK (all) — moi check deu chay.' >/dev/null
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"\\\"status\\\": \\\"pending\\\"\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ng "co VERIFY OK -> cho qua"; else ok "co VERIFY OK -> cho qua"; fi

# --- 3. VERIFY FAILED phai HUY marker --------------------------------------------
# Neu chi set ma khong huy, agent chay xanh mot lan roi lam vo moi thu van con quyen ghi.
reset_marker
fire post-bash '{}' 'VERIFY OK (all)' >/dev/null
fire post-bash '{}' 'VERIFY FAILED (build)' >/dev/null
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ok "VERIFY FAILED huy marker -> chan lai"; else ng "VERIFY FAILED huy marker -> chan lai"; fi

# --- 4. Sua code sau khi verify -> marker phai bi huy -----------------------------
# Day la duong lach chinh: chay verify xanh truoc, sua code sau, roi danh done.
reset_marker
fire post-bash '{}' 'VERIFY OK (all)' >/dev/null
fire post-edit "{\"file_path\":\"$WORK/src/app.js\"}" >/dev/null
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ok "sua code sau verify -> marker huy, chan lai"; else ng "sua code sau verify -> marker huy, chan lai"; fi

# --- 5. Sua file STATE khong duoc huy marker --------------------------------------
# progress.md/dossier la thu PHAI ghi ngay truoc khi danh done. Huy marker o day se
# lam gate tu chan dung quy trinh ma no yeu cau.
for f in progress.md docs/features/F01-scaffold.md; do
  reset_marker
  fire post-bash '{}' 'VERIFY OK (all)' >/dev/null
  fire post-edit "{\"file_path\":\"$WORK/$f\"}" >/dev/null
  out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
  if denied "$out"; then ng "sua $f KHONG duoc huy marker"; else ok "sua $f KHONG duoc huy marker"; fi
done

# --- 6. Khong dung toi feature_list.json -> khong bao gio chan ---------------------
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$WORK/src/app.js\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
if denied "$out"; then ng "file khac feature_list.json khong bi chan"; else ok "file khac feature_list.json khong bi chan"; fi

# --- 7. Ghi thu khong phai done -> khong chan --------------------------------------
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"in_progress\\\"\"}")"
if denied "$out"; then ng "ghi status in_progress khong bi chan"; else ok "ghi status in_progress khong bi chan"; fi

# --- 8. Write ghi lai nguyen trang thai cu -> khong chan ---------------------------
# Format lai JSON ma khong them done nao thi khong phai mot tuyen bo moi.
# Phai dat dung ten feature_list.json trong mot thu muc rieng. Lan dau dat ten fl2.json
# nen hook bo qua dung theo thiet ke, va ca 8 xanh gia con ca 9 do oan.
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
if denied "$out"; then ng "Write giu nguyen so feature done -> khong chan"; else ok "Write giu nguyen so feature done -> khong chan"; fi

# --- 9. Write THEM mot feature done -> phai chan -----------------------------------
reset_marker
more="$(node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
j.features[1].status="done";
console.log(JSON.stringify(j));
' "$FL2")"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL2" "$more")")"
if denied "$out"; then ok "Write them feature done -> chan"; else ng "Write them feature done -> chan"; fi

# --- 10. Marker khoa theo session -------------------------------------------------
# Phien khac chay verify khong duoc cap quyen ghi cho phien nay.
reset_marker
SID_OTHER="other-$$"; ( SID="$SID_OTHER"; fire post-bash '{}' 'VERIFY OK (all)' >/dev/null )
out="$(fire pre-edit "{\"file_path\":\"$FL\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}")"
rm -f "$MARKERS/$SID_OTHER" 2>/dev/null
if denied "$out"; then ok "marker cua phien khac khong mo khoa cho phien nay"; else ng "marker cua phien khac khong mo khoa cho phien nay"; fi

# --- 11. Hop dong VERIFY OK bi vo -> gate phai CHO QUA, khong duoc khoa cung ------
# Day la lo hong nguy hiem nhat cua thiet ke marker: gate khong co cach nao khac de biet
# verify da thanh cong. Neu init.sh khong con in "VERIFY OK", marker khong bao gio duoc dat
# va gate am tham chuyen tu fail-open thanh fail-closed — chan sach moi thao tac ghi done
# ma khong ai hieu tai sao.
mkdir -p "$WORK/p3"
FL3="$WORK/p3/feature_list.json"
cp "$FL" "$FL3"
EDIT3="{\"file_path\":\"$FL3\",\"old_string\":\"pending\",\"new_string\":\"\\\"status\\\": \\\"done\\\"\"}"

# 11a. khong co init.sh -> khong duoc chan
reset_marker
out="$(fire pre-edit "$EDIT3")"
if denied "$out"; then ng "khong co init.sh -> gate cho qua (khong khoa cung)"; else ok "khong co init.sh -> gate cho qua (khong khoa cung)"; fi

# 11b. co init.sh nhung KHONG in "VERIFY OK" -> khong duoc chan, va phai canh bao
reset_marker
printf '#!/usr/bin/env bash
echo "everything is fine"
' > "$WORK/p3/init.sh"
err="$(printf '%s' "$(node -e '
const [sid, ti] = process.argv.slice(1);
process.stdout.write(JSON.stringify({session_id: sid, tool_input: JSON.parse(ti)}));
' "$SID" "$EDIT3")" | bash "$GATE" pre-edit 2>&1 >/dev/null)"
out="$(fire pre-edit "$EDIT3")"
if denied "$out"; then ng "init.sh khong in VERIFY OK -> gate cho qua"; else ok "init.sh khong in VERIFY OK -> gate cho qua"; fi
if printf '%s' "$err" | grep -q 'hop dong'; then ok "hop dong vo -> canh bao ra stderr"; else ng "hop dong vo -> canh bao ra stderr (thay: ${err:-rong})"; fi

# 11c. init.sh CO in "VERIFY OK" -> gate lam viec binh thuong tro lai
reset_marker
printf '#!/usr/bin/env bash
echo "VERIFY OK (all)"
' > "$WORK/p3/init.sh"
out="$(fire pre-edit "$EDIT3")"
if denied "$out"; then ok "init.sh co VERIFY OK -> gate chan lai nhu thuong"; else ng "init.sh co VERIFY OK -> gate chan lai nhu thuong"; fi

# 11d. chay init.sh ma output khong co VERIFY OK/FAILED -> canh bao hop dong vo
err="$(node -e '
process.stdout.write(JSON.stringify({
  session_id: process.argv[1],
  tool_input: { command: "./init.sh all" },
  tool_response: "everything is fine",
}));
' "$SID" | bash "$GATE" post-bash 2>&1 >/dev/null)"
if printf '%s' "$err" | grep -q 'VERIFY OK'; then ok "chay init.sh khong ra VERIFY OK/FAILED -> canh bao ngay"; else ng "chay init.sh khong ra VERIFY OK/FAILED -> canh bao ngay"; fi

# --- 12. JSON rac tren stdin -> khong duoc no, khong duoc chan --------------------
out="$(printf 'not json' | bash "$GATE" pre-edit 2>/dev/null)"
if [ -z "$out" ]; then ok "stdin rac -> im lang cho qua (khong khoa phien)"; else ng "stdin rac -> im lang cho qua"; fi

reset_marker
echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
