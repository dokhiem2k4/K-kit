#!/usr/bin/env bash
# Test suite — harness-kit. Chay: bash tests/run-tests.sh
# Yeu cau: bash + node. Moi scenario bootstrap mot project tam vao .tmp-tests/ roi assert exit code.
set -uo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"

PASSED=0
FAILED=0

cleanup() { rm -rf "$KIT/.tmp-tests"; }
trap cleanup EXIT

ok() { echo "  PASS  $1"; PASSED=$((PASSED + 1)); }
ng() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

# Doi duong dan POSIX -> dang node hieu tren Windows (Git Bash). Ngoai Windows: giu nguyen.
win() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}

# Bootstrap mot project tam, in ra duong dan POSIX cua no.
# Dung mktemp chu khong dung bien dem: ham nay luon chay trong $(...) nen subshell,
# bien dem tang trong subshell se khong giu duoc -> moi project se trung duong dan.
new_project() {
  mkdir -p "$KIT/.tmp-tests"
  local d
  d="$(mktemp -d "$KIT/.tmp-tests/pXXXXXX")"
  node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$d")" \
    --name "Test Project" --stack "node" >/dev/null 2>&1
  echo "$d"
}

# patch_feature <proj> <feature-id> <json-object>   — merge vao feature; gia tri null = xoa field.
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

# In ra mot dossier hop le (du 8 muc, khong placeholder).
valid_dossier() {
  cat <<'MD'
# F01 — Scaffold project

> **Status:** done · **Ngày:** 2026-07-23 · **Commit:** a1b2c3d · **Blueprint:** §1

## 1. Ý nghĩa với dự án
Đặt nền cho mọi feature sau; F02 và F03 đều dựa vào nó.

## 2. Làm được gì
Repo build rỗng chạy được từ máy sạch.

## 3. Cách dùng
`npm install && npm run build`

## 4. Bên trong
`package.json` — khai báo script build/lint/test.

## 5. Quyết định & trade-off
Chọn npm thay pnpm cho đơn giản; không thêm monorepo tooling.

## 6. Cạm bẫy khi sửa
Đổi tên script build phải đổi luôn `init.sh`.

## 7. Bằng chứng
`./init.sh scaffold` → VERIFY OK (scaffold).

## 8. Cập nhật
2026-07-23 — tạo mới.
MD
}

# expect_docs <mo-ta> <exit-code-mong-doi> <proj>
expect_docs() {
  local desc="$1" want="$2" proj="$3" got
  bash "$proj/init.sh" docs >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ng "$desc (exit=$got, mong=$want)"; fi
}

# expect_all <mo-ta> <exit-code-mong-doi> <proj>
expect_all() {
  local desc="$1" want="$2" proj="$3" got
  bash "$proj/init.sh" all >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ng "$desc (exit=$got, mong=$want)"; fi
}

DOC="docs/features/F01-scaffold.md"

echo "== check_docs =="

P="$(new_project)"
expect_docs "chua feature nao done -> pass" 0 "$P"

P="$(new_project)"
patch_feature "$P" F01 '{"status":"done","doc":null}'
expect_docs "done nhung thieu field doc -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
rm -f "$P/$DOC"
expect_docs "doc tro toi file khong ton tai -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed '/^## 6\./,$d' > "$P/$DOC"
expect_docs "thieu muc 6-8 -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^## 2\./## X./' -e 's/^## 8\./## 2./' -e 's/^## X\./## 8./' > "$P/$DOC"
expect_docs "8 muc sai thu tu -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
{ valid_dossier; echo "<TODO: dien not phan nay>"; } > "$P/$DOC"
expect_docs "con placeholder <TODO: -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
{ valid_dossier; printf '%s\n' "<!-- huong dan chua xoa -->"; } > "$P/$DOC"
expect_docs "con chu thich HTML -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier > "$P/$DOC"
expect_docs "dossier hop le -> pass" 0 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"verified\",\"doc\":\"$DOC\"}"
rm -f "$P/$DOC"
expect_all "status verified thieu dossier -> ./init.sh all fail" 1 "$P"

echo ""
echo "== _TEMPLATE.md =="

P="$(new_project)"
T="$P/docs/features/_TEMPLATE.md"

if [ -f "$T" ]; then ok "bootstrap copy docs/features/_TEMPLATE.md"; else ng "bootstrap copy docs/features/_TEMPLATE.md"; fi

nums="$(grep -E '^##[[:space:]]+[1-8]\.' "$T" 2>/dev/null \
  | sed -E 's/^##[[:space:]]+([1-8])\..*/\1/' | tr '\n' ',' | sed 's/,$//')"
if [ "$nums" = "1,2,3,4,5,6,7,8" ]; then
  ok "_TEMPLATE.md du 8 muc dung thu tu"
else
  ng "_TEMPLATE.md 8 muc dung thu tu (dang co: ${nums:-khong co})"
fi

if grep -q '<TODO:' "$T" 2>/dev/null; then ok "_TEMPLATE.md dung marker <TODO:"; else ng "_TEMPLATE.md thieu marker <TODO:"; fi
if grep -q '<!--' "$T" 2>/dev/null; then ok "_TEMPLATE.md co chu thich huong dan"; else ng "_TEMPLATE.md thieu chu thich huong dan"; fi
if grep -q 'zoom out' "$T" 2>/dev/null && grep -q 'zoom in' "$T" 2>/dev/null; then
  ok "_TEMPLATE.md giai thich ranh gioi muc 1 vs muc 2"
else
  ng "_TEMPLATE.md giai thich ranh gioi muc 1 vs muc 2"
fi

expect_docs "_TEMPLATE.md khong bi quet (khong feature nao tro toi) -> pass" 0 "$P"

echo ""
echo "== feature_list.json =="

P="$(new_project)"

missing="$(node -e '
const j = require(process.argv[1] + "/feature_list.json");
console.log(j.features.filter(f => !f.doc).map(f => f.id).join(","));
' "$(win "$P")")"
if [ -z "$missing" ]; then ok "moi feature mau co field doc"; else ng "feature thieu doc: $missing"; fi

wrong="$(node -e '
const j = require(process.argv[1] + "/feature_list.json");
const bad = j.features.filter(f => !new RegExp("^docs/features/" + f.id + "-[a-z0-9-]+\\.md$").test(f.doc || ""));
console.log(bad.map(f => f.id).join(","));
' "$(win "$P")")"
if [ -z "$wrong" ]; then ok "doc dung quy uoc docs/features/<ID>-<slug>.md"; else ng "doc sai quy uoc: $wrong"; fi

noverify="$(node -e '
const j = require(process.argv[1] + "/feature_list.json");
const bad = j.features.filter(f => !(f.verify || []).includes("./init.sh docs"));
console.log(bad.map(f => f.id).join(","));
' "$(win "$P")")"
if [ -z "$noverify" ]; then ok "feature mau co ./init.sh docs trong verify"; else ng "thieu ./init.sh docs trong verify: $noverify"; fi

hint="$(node -e '
const j = require(process.argv[1] + "/feature_list.json");
console.log(String(j._howto || "").includes("doc") ? "yes" : "no");
' "$(win "$P")")"
if [ "$hint" = "yes" ]; then ok "_howto giai thich field doc"; else ng "_howto giai thich field doc"; fi

echo ""
echo "== instruction wiring =="

C="$KIT/template/CLAUDE.md"
PL="$KIT/template/.claude/workflow/pipeline.md"

has() { # has <mo-ta> <file> <pattern>
  if grep -qF "$3" "$2" 2>/dev/null; then ok "$1"; else ng "$1 (khong thay: $3)"; fi
}

has "CLAUDE.md tro toi docs/features/"        "$C"  "docs/features/"
has "CLAUDE.md nhac _TEMPLATE.md"             "$C"  "_TEMPLATE.md"
has "CLAUDE.md co lenh ./init.sh docs"        "$C"  "./init.sh docs"
has "CLAUDE.md DoD co bac documented"         "$C"  "documented"
has "pipeline.md SHIP nhac dossier"           "$PL" "dossier"
has "pipeline.md co lenh ./init.sh docs"      "$PL" "./init.sh docs"
has "pipeline.md co luat cap nhat F cu"       "$PL" "mục 8"

# Anchor tieng Anh phai con nguyen (validate-harness.mjs dua vao day)
for a in "Startup Workflow" "Verification Commands" "Definition of Done" "End of Session"; do
  has "CLAUDE.md giu anchor: $a" "$C" "$a"
done

echo ""
echo "== README + e2e =="

R="$KIT/README.md"
if grep -qF "_TEMPLATE.md" "$R"; then ok "README liet ke _TEMPLATE.md trong cay thu muc"; else ng "README liet ke _TEMPLATE.md"; fi
if grep -qF "dossier" "$R"; then ok "README giai thich dossier"; else ng "README giai thich dossier"; fi

# Luu y: gom output vao bien roi moi grep. Neu pipe thang vao `grep -q`, grep thoat som
# -> lenh dau pipe an SIGPIPE -> `set -o pipefail` bao non-zero, test fail oan.

# bootstrap --dry-run phai liet ke file template moi
P="$KIT/.tmp-tests/dry"
rm -rf "$P"; mkdir -p "$P"
out="$(node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "Dry" --dry-run 2>&1)"
if printf '%s' "$out" | grep -qE 'docs[\\/]features[\\/]_TEMPLATE\.md'; then
  ok "bootstrap --dry-run liet ke docs/features/_TEMPLATE.md"
else
  ng "bootstrap --dry-run liet ke docs/features/_TEMPLATE.md"
fi

# ./init.sh all phai chay khoi FEATURE DOCS
P="$(new_project)"
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "FEATURE DOCS"; then
  ok "./init.sh all co chay check_docs"
else
  ng "./init.sh all co chay check_docs"
fi

echo ""
echo "== check_build: script fail phai chan gate =="

# Truoc day `npm run lint 2>/dev/null || echo "(no lint script)"` gop hai truong hop khac han
# nhau lam mot: script THIEU va script CHAY-ROI-FAIL. Ket qua la lint do van di qua gate.
# Nhom test nay khoa lai hanh vi do.

# mkpkg <proj> <json-scripts>  — viet package.json voi scripts cho truoc
mkpkg() {
  node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1] + "/package.json",
  JSON.stringify({ name: "t", private: true, scripts: JSON.parse(process.argv[2]) }, null, 2));
' "$(win "$1")" "$2"
}

# Baseline: build xanh, khong co lint/test -> phai PASS nhung bao SKIP.
P="$(new_project)"
mkpkg "$P" '{"build":"node -e \"0\""}'
out="$(bash "$P/init.sh" build 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "build xanh -> exit 0"; else ng "build xanh -> exit 0 (rc=$rc)"; fi
if printf '%s' "$out" | grep -qF 'SKIP: khong co script "lint"'; then
  ok "thieu lint -> bao SKIP (khong gia vo pass)"
else
  ng "thieu lint -> bao SKIP"
fi
if printf '%s' "$out" | grep -qF 'check bi SKIP'; then
  ok "summary noi ro con check bi SKIP"
else
  ng "summary noi ro con check bi SKIP"
fi

# Hard case: lint FAIL. Truoc kia bi nuot thanh "(no lint script)" va gate van xanh.
P="$(new_project)"
mkpkg "$P" '{"lint":"node -e \"process.exit(1)\"","build":"node -e \"0\""}'
out="$(bash "$P/init.sh" build 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then ok "lint FAIL -> gate do (exit != 0)"; else ng "lint FAIL -> gate do (exit=$rc — lint do van qua duoc gate!)"; fi
if printf '%s' "$out" | grep -qF '[FAIL] lint'; then ok "lint FAIL -> in ro [FAIL] lint"; else ng "lint FAIL -> in ro [FAIL] lint"; fi

# typecheck FAIL cung phai chan.
P="$(new_project)"
mkpkg "$P" '{"typecheck":"node -e \"process.exit(1)\"","build":"node -e \"0\""}'
if bash "$P/init.sh" build >/dev/null 2>&1; then ng "typecheck FAIL -> gate do"; else ok "typecheck FAIL -> gate do"; fi

# test FAIL cung phai chan (DoD noi 'lint + typecheck + build + test pass').
P="$(new_project)"
mkpkg "$P" '{"build":"node -e \"0\"","test":"node -e \"process.exit(1)\""}'
if bash "$P/init.sh" build >/dev/null 2>&1; then ng "test FAIL -> gate do"; else ok "test FAIL -> gate do"; fi

# build la bat buoc: thieu script build -> FAIL, khong phai SKIP.
P="$(new_project)"
mkpkg "$P" '{"lint":"node -e \"0\""}'
out="$(bash "$P/init.sh" build 2>&1)"
if printf '%s' "$out" | grep -qF 'thieu script "build"'; then ok "thieu build -> FAIL (khong phai SKIP)"; else ng "thieu build -> FAIL"; fi

# Khong co package.json: SKIP that tha, va KHONG duoc bao "moi check deu chay".
P="$(new_project)"
out="$(bash "$P/init.sh" build 2>&1)"
if printf '%s' "$out" | grep -qF 'KHONG phai pass'; then ok "khong co package.json -> noi ro day khong phai pass"; else ng "khong co package.json -> noi ro day khong phai pass"; fi
if printf '%s' "$out" | grep -qF 'moi check deu chay'; then ng "khong duoc bao 'moi check deu chay' khi da SKIP"; else ok "khong bao 'moi check deu chay' khi da SKIP"; fi

echo ""
echo "== plugin: skills =="

# Moi skill phai co frontmatter hop le. `name` phai khop ten thu muc (Claude Code resolve
# skill theo do); `description` la thu quyet dinh skill co auto-trigger hay khong — thieu no
# thi skill nam tren dia va khong bao gio duoc goi.
SKILL_COUNT=0
for d in "$KIT"/skills/*/; do
  s="$d/SKILL.md"
  base="$(basename "$d")"
  SKILL_COUNT=$((SKILL_COUNT + 1))
  if [ ! -f "$s" ]; then ng "skills/$base co SKILL.md"; continue; fi

  # frontmatter phai mo o dong 1 va dong o mot dong `---` sau do
  if [ "$(head -1 "$s")" = "---" ] && [ "$(sed -n '2,12p' "$s" | grep -c '^---$')" -ge 1 ]; then
    ok "skills/$base: frontmatter dong/mo dung"
  else
    ng "skills/$base: frontmatter dong/mo dung"
  fi

  fm_name="$(sed -n '2,12p' "$s" | sed -n 's/^name: *//p' | head -1)"
  if [ "$fm_name" = "$base" ]; then ok "skills/$base: name khop ten thu muc"
  else ng "skills/$base: name khop ten thu muc (thay: '$fm_name')"; fi

  fm_desc="$(sed -n '2,12p' "$s" | sed -n 's/^description: *//p' | head -1)"
  if [ "${#fm_desc}" -ge 40 ]; then ok "skills/$base: description du dai de trigger (${#fm_desc} ky tu)"
  else ng "skills/$base: description du dai de trigger (${#fm_desc} ky tu, can >=40)"; fi

  # Anti-rationalization: day la thu phan biet skill voi mot to checklist.
  if grep -qiE '^\| Ban nghi \| Thuc te \|' "$s"; then ok "skills/$base: co bang red flags"
  else ng "skills/$base: co bang red flags"; fi

  # Guard chong false-positive. Acceptance test da bat duoc ca: hook im dung nhung agent
  # van keo skill vao mot repo khong co harness, vi description qua rong.
  # Hang rao 1: dieu kien tien quyet phai nam trong description (agent doc no truoc than skill).
  case "$fm_desc" in
    *"feature_list.json"*) ok "skills/$base: description co dieu kien tien quyet" ;;
    *) ng "skills/$base: description co dieu kien tien quyet" ;;
  esac
  # Hang rao 2: than skill phai tu thoat khi khong co harness.
  if grep -qF '<PRECONDITION>' "$s"; then ok "skills/$base: than skill co bail-out"
  else ng "skills/$base: than skill co bail-out"; fi
done

if [ "$SKILL_COUNT" -ge 6 ]; then ok "co >=6 gate skill (thay $SKILL_COUNT)"; else ng "co >=6 gate skill (thay $SKILL_COUNT)"; fi

# using-harness phai route toi moi skill con lai — no la thu duy nhat duoc hook bom vao,
# nen skill nao khong duoc nhac o day thi thuc te khong ai tim ra.
U="$KIT/skills/using-harness/SKILL.md"
missing_route=""
for d in "$KIT"/skills/*/; do
  base="$(basename "$d")"
  [ "$base" = "using-harness" ] && continue
  grep -qF "$base" "$U" || missing_route="$missing_route $base"
done
if [ -z "$missing_route" ]; then ok "using-harness route toi moi skill con lai"
else ng "using-harness thieu route toi:$missing_route"; fi

echo ""
echo "== plugin: manifest + hook =="

if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$(win "$KIT/.claude-plugin/plugin.json")" 2>/dev/null; then
  ok "plugin.json parse duoc"
else
  ng "plugin.json parse duoc"
fi
if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$(win "$KIT/hooks/hooks.json")" 2>/dev/null; then
  ok "hooks.json parse duoc"
else
  ng "hooks.json parse duoc"
fi
if [ -x "$KIT/hooks/session-start" ]; then ok "hooks/session-start co quyen exec (filesystem)"; else ng "hooks/session-start co quyen exec (filesystem)"; fi

# Bit tren filesystem cua may ban KHONG dam bao bit do vao git. Repo nay tung co
# core.fileMode=false, `chmod +x` khong duoc ghi nhan, va git luu 100644 — nguoi clone
# ve se co mot hook khong chay duoc, trong khi test o may goc van xanh.
# Nen phai kiem mode trong INDEX, khong phai tren dia.
if git -C "$KIT" rev-parse --git-dir >/dev/null 2>&1; then
  for f in hooks/session-start tests/run-tests.sh tests/acceptance.sh template/init.sh; do
    mode="$(git -C "$KIT" ls-files -s "$f" 2>/dev/null | awk '{print $1}')"
    if [ "$mode" = "100755" ]; then ok "git index: $f la 100755"
    else ng "git index: $f la '$mode' (can 100755 — nguoi clone se khong chay duoc)"; fi
  done
else
  skip_note="khong phai git repo"
  echo "  (SKIP: khong phai git repo — khong kiem duoc mode trong index)"
fi

# Hook phai IM LANG ngoai project co harness — day la khac biet so voi bom vo dieu kien.
NOHARNESS="$KIT/.tmp-tests/noharness"
rm -rf "$NOHARNESS"; mkdir -p "$NOHARNESS"
out="$(CLAUDE_PROJECT_DIR="$NOHARNESS" bash "$KIT/hooks/session-start" 2>&1)"
if [ -z "$out" ]; then ok "hook im lang trong repo khong co harness"; else ng "hook im lang trong repo khong co harness (in ra: $out)"; fi

# Trong project co harness: phai ra JSON hop le, chua skill va state that.
P="$(new_project)"
out="$(CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | node -e '
let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
  const j = JSON.parse(s);
  const ctx = j.hookSpecificOutput?.additionalContext ?? j.additionalContext;
  if (typeof ctx !== "string" || !ctx.length) throw new Error("khong co additionalContext");
  if (!ctx.includes("using-harness")) throw new Error("khong bom skill using-harness");
  if (!ctx.includes("ACTIVE: F01")) throw new Error("khong bom state that (active feature)");
  if (!ctx.includes("done_when")) throw new Error("khong bom done_when");
});' 2>/dev/null; then
  ok "hook bom JSON hop le + skill + state that (ACTIVE F01, done_when)"
else
  ng "hook bom JSON hop le + skill + state that"
fi

# Hook phai canh bao khi dependency chua xong — day la thu chan overreach ngay dau phien.
P2="$(new_project)"
patch_feature "$P2" "F03" '{"status":"pending"}'
node -e '
const fs=require("fs");const f=process.argv[1]+"/feature_list.json";
const j=JSON.parse(fs.readFileSync(f,"utf8"));j.active_feature="F03";
fs.writeFileSync(f,JSON.stringify(j,null,2));' "$(win "$P2")"
out="$(CLAUDE_PROJECT_DIR="$P2" CLAUDE_PLUGIN_ROOT="$KIT" bash "$KIT/hooks/session-start" 2>&1)"
if printf '%s' "$out" | grep -qF 'DEPS CHUA XONG'; then
  ok "hook canh bao dependency chua xong"
else
  ng "hook canh bao dependency chua xong"
fi

echo ""
echo "== bootstrap --with-skills =="

P="$KIT/.tmp-tests/skills-dry"
rm -rf "$P"; mkdir -p "$P"
out="$(node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "S" --with-skills --dry-run 2>&1)"
if printf '%s' "$out" | grep -qE '\.claude[\\/]skills[\\/]using-harness[\\/]SKILL\.md'; then
  ok "--with-skills liet ke .claude/skills/using-harness/SKILL.md"
else
  ng "--with-skills liet ke .claude/skills/using-harness/SKILL.md"
fi

# Khong co --with-skills thi KHONG duoc do skill vao project (mac dinh la plugin route).
P="$KIT/.tmp-tests/noskills-dry"
rm -rf "$P"; mkdir -p "$P"
out="$(node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "S" --dry-run 2>&1)"
if printf '%s' "$out" | grep -qF '.claude/skills'; then
  ng "mac dinh khong copy skills vao project"
else
  ok "mac dinh khong copy skills vao project"
fi

# Copy that (khong dry-run) phai ra file doc duoc.
P="$KIT/.tmp-tests/skills-real"
rm -rf "$P"; mkdir -p "$P"
node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "S" --with-skills >/dev/null 2>&1
if [ -f "$P/.claude/skills/verifying-a-feature/SKILL.md" ]; then
  ok "--with-skills copy that ra .claude/skills/"
else
  ng "--with-skills copy that ra .claude/skills/"
fi

echo ""
echo "== CLAUDE.md wiring toi skills =="
# Duyet skills/ thay vi liet ke tay: them skill moi ma quen noi vao CLAUDE.md thi test do,
# khong im lang bo qua nhu danh sach cung.
for d in "$KIT"/skills/*/; do
  s="$(basename "$d")"
  [ "$s" = "using-harness" ] && continue   # meta skill, hook bom vao, khong can route trong CLAUDE.md
  has "CLAUDE.md route toi skill: $s" "$C" "$s"
done

echo ""
echo "PASS=$PASSED  FAIL=$FAILED"
if [ "$FAILED" -eq 0 ]; then exit 0; else exit 1; fi
