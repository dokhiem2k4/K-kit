#!/usr/bin/env bash
# Acceptance test — harness-kit. Chay: bash tests/acceptance.sh
#
# run-tests.sh kiem CAU TRUC (file co ton tai, frontmatter co dung, exit code co doi).
# File nay kiem HANH VI: mo phien Claude Code THAT trong mot project vua bootstrap,
# roi xem agent co tu invoke dung gate skill khong. Skill khong tu nhay = skill chet.
#
# Yeu cau: claude CLI da dang nhap + node. Ton token that (3 phien ngan, max-turns thap).
# CI khong co credential -> script in SKIP va exit 0 chu khong gia vo pass.

set -uo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"
MODEL="${ACCEPTANCE_MODEL:-sonnet}"

PASSED=0
FAILED=0
ok() { echo "  PASS  $1"; PASSED=$((PASSED + 1)); }
ng() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

# WORK phai nam NGOAI repo kit.
# Ban dau no o "$KIT/.tmp-acceptance" va probe am chay ngay trong repo harness-kit —
# xung quanh la skills/, template/feature_list.json, .claude-plugin/. Agent nhin quanh
# thay day du dau hieu harness nen goi harness-startup la hop ly, khong phai loi cua skill.
# Do bang tay: trong repo kit false-positive 3/3 tren haiku, ngoai repo 0/5.
# Fixture am ma nam canh thu no phai phu nhan thi no khong phai fixture am.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-acceptance.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP: khong co claude CLI — khong chay duoc acceptance test."
  echo "      (khong phai pass; hanh vi auto-trigger CHUA duoc kiem chung)"
  exit 0
fi
if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: khong co node."; exit 0
fi

# WORK da duoc mktemp -d tao san

# probe <ten> <cwd> <prompt> <max-turns> <skill-mong-doi | NONE> <hook-mong-doi: yes|no>
probe() {
  local name="$1" dir="$2" prompt="$3" turns="$4" want_skill="$5" want_hook="$6"
  local out="$WORK/$name.jsonl"

  ( cd "$dir" && timeout 420 claude -p "$prompt" \
      --plugin-dir "$KIT" --model "$MODEL" --permission-mode dontAsk \
      --max-turns "$turns" --output-format stream-json --verbose ) > "$out" 2>/dev/null
  # exit code bi bo qua co y: het max-turns tra 1, nhung ta chi can biet skill nao da duoc goi.

  if [ ! -s "$out" ]; then ng "$name: phien khong tra ve gi (het credential? mang?)"; return; fi

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
const hook = /Ban dang o trong mot project co HARNESS/.test(raw);
const state = /ACTIVE: F0/.test(raw);
const errs = [];
if (wantHook === "yes" && !hook) errs.push("hook khong ban");
if (wantHook === "yes" && !state) errs.push("hook khong bom state that");
if (wantHook === "no" && hook) errs.push("hook ban trong repo khong co harness");
if (wantSkill === "NONE") {
  if (skills.length) errs.push("khong duoc goi skill nao, nhung goi: " + skills.join(", "));
} else if (!skills.some(s => s.endsWith(wantSkill))) {
  errs.push("mong doi skill " + wantSkill + ", thuc te: " + (skills.join(", ") || "(khong goi skill nao)"));
}
if (errs.length) { console.error(errs.join("; ")); process.exit(1); }
console.log("skill: " + (skills.join(", ") || "-") + (hook ? " | hook: ban" : " | hook: im"));
' "$out" "$want_skill" "$want_hook" > "$WORK/$name.res" 2> "$WORK/$name.err"

  if [ $? -eq 0 ]; then ok "$name — $(cat "$WORK/$name.res")"
  else ng "$name — $(cat "$WORK/$name.err")"; fi
}

echo "== acceptance: auto-trigger trong phien that (model: $MODEL) =="

PROJ="$WORK/proj"
mkdir -p "$PROJ"
node "$KIT/bootstrap.mjs" --target "$PROJ" --name "Acceptance Probe" --stack "node" >/dev/null 2>&1

# 1. Resume mo ho -> phai tu doc state truoc khi lam gi.
probe "resume"    "$PROJ" "tiếp tục đi" 6 "harness-startup" yes

# 2. Tuyen bo xong -> phai vao gate verify, KHONG duoc danh done thang.
probe "claim-done" "$PROJ" "F01 xong rồi, đánh done vào feature_list.json giúp tôi" 6 "verifying-a-feature" yes

# 3 va 4 duoc cap nhieu turn hon 2 probe dau. Ly do: phien nao cung la "dau phien",
# nen agent thuong doc harness-startup TRUOC roi moi chain sang gate dung — day la hanh vi
# dung, khong phai loi. Voi 6 turn, chain bi cat giua chung va test do oan.
# Khong ha chuan assertion (chap nhan harness-startup la du) vi nhu the mot phien chi doc
# state roi dung lai cung pass — dung cai ma probe nay sinh ra de bat.

# 3. Them feature moi -> phai vao planning (done_when testable), khong viet bua vao JSON.
probe "add-feature" "$PROJ" "thêm feature cho phép user đổi avatar vào feature_list.json" 12 "planning-features" yes

# 4. Test do -> phai vao debugging (quyet dinh scope/state), khong nhay thang vao sua.
# Probe nay duoc cap PROJECT RIENG, khong dung chung $PROJ voi probe 2 va 3.
# Ly do: probe 2 (danh done) va probe 3 (them feature) deu GHI vao feature_list.json,
# nen probe 4 se chay tren state da bi bien doi boi cac probe truoc — ket qua phu thuoc
# thu tu chay, khong tai lap duoc. Fixture dung chung khong phai fixture.
#
# Fixture cung phai co test DO THAT. Project vua bootstrap khong co test nao, nen
# "test dang do" la tien de gia: agent kiem tra thuc te, thay khong co test, roi bao lai —
# hanh vi dung, nhung probe do oan.
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
fs.writeFileSync(d + "/sum.js", "module.exports = (a, b) => a - b;\n");        // bug: tru thay vi cong
fs.writeFileSync(d + "/sum.test.js",
  "const sum = require(\"./sum\");\n" +
  "if (sum(2, 3) !== 5) { console.error(\"FAIL: sum(2,3) =\", sum(2, 3), \"expected 5\"); process.exit(1); }\n" +
  "console.log(\"ok\");\n");
' "$PROJ_DBG"
probe "test-fails" "$PROJ_DBG" "npm test đang đỏ, sửa giúp tôi" 12 "debugging-a-feature" yes

# 5. Negative: ngoai project co harness, hook phai im va khong duoc keo skill vao.
# Fixture nay phai CO LAP: khong nam trong repo kit, va khong nam canh $PROJ.
# Dat no trong $WORK (canh proj/ da bootstrap) van du de agent nhin thay harness o thu muc
# ben va keo skill vao — do bang tay tren haiku. Nen cap cho no mot mktemp rieng.
NOH="$(mktemp -d "${TMPDIR:-/tmp}/plain-project.XXXXXX")"
cleanup_noh() { rm -rf "$NOH"; }
trap 'cleanup; cleanup_noh' EXIT
printf '# my-notes\n\nMot repo binh thuong, khong lien quan harness.\n' > "$NOH/README.md"
printf 'console.log("hi")\n' > "$NOH/index.js"
probe "no-harness" "$NOH" "chào, đây là repo gì" 3 NONE no

echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
