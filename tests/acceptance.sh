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

WORK="$KIT/.tmp-acceptance"
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

mkdir -p "$WORK"

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

# 3. Negative: ngoai project co harness, hook phai im va khong duoc keo skill vao.
NOH="$WORK/noharness"
mkdir -p "$NOH"; echo "hi" > "$NOH/README.md"
probe "no-harness" "$NOH" "chào, đây là repo gì" 3 NONE no

echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
