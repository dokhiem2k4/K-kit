#!/usr/bin/env bash
# Test suite — harness-kit. Chay: bash tests/run-tests.sh
# Yeu cau: bash + node. Moi scenario bootstrap mot project tam vao .tmp-tests/ roi assert exit code.
set -uo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"

PASSED=0
FAILED=0
N=0

cleanup() { rm -rf "$KIT/.tmp-tests"; }
trap cleanup EXIT

ok() { echo "  PASS  $1"; PASSED=$((PASSED + 1)); }
ng() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

# Doi duong dan POSIX -> dang node hieu tren Windows (Git Bash). Ngoai Windows: giu nguyen.
win() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}

# Bootstrap mot project tam, in ra duong dan POSIX cua no.
new_project() {
  N=$((N + 1))
  local d="$KIT/.tmp-tests/p$N"
  rm -rf "$d"
  mkdir -p "$d"
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
echo "PASS=$PASSED  FAIL=$FAILED"
if [ "$FAILED" -eq 0 ]; then exit 0; else exit 1; fi
