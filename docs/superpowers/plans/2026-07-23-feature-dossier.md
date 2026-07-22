# Feature Dossier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mỗi feature trong harness khi ship xong để lại đúng một file Markdown (dossier) 8 mục, được ép bằng check cơ học trong `init.sh`.

**Architecture:** Thêm một file template (`template/docs/features/_TEMPLATE.md`), một target verification mới (`./init.sh docs`) parse `feature_list.json` bằng `node -e`, và nối luật vào 4 file instruction/state có sẵn. Không thêm dependency, không thêm script ngoài. Test là một bash suite bootstrap project tạm rồi assert exit code của `init.sh`.

**Tech Stack:** Bash (Git Bash trên Windows), Node.js (CommonJS, không dependency), Markdown, JSON.

**Spec:** `docs/superpowers/specs/2026-07-23-feature-dossier-design.md`

## Global Constraints

- Mọi thay đổi nằm trong `harness-kit/`: `template/**`, `README.md`, `tests/**`. **Không** sửa `bootstrap.mjs` (hàm `walk()` đã tự copy file mới).
- Quy ước đường dẫn dossier, dùng nguyên văn ở mọi nơi: `docs/features/<ID>-<slug>.md` (slug = kebab-case của `name`).
- Template gốc: `docs/features/_TEMPLATE.md` — tên bắt đầu bằng `_`, không feature nào trỏ tới nên không bị check quét.
- Dossier có **đúng 8 heading cấp 2**, đúng thứ tự, đúng chữ:
  `## 1. Ý nghĩa với dự án` · `## 2. Làm được gì` · `## 3. Cách dùng` · `## 4. Bên trong` · `## 5. Quyết định & trade-off` · `## 6. Cạm bẫy khi sửa` · `## 7. Bằng chứng` · `## 8. Cập nhật`
- Mục không áp dụng ghi `—`, **không xoá heading**.
- Marker placeholder duy nhất: `<TODO: ...>`. Chú thích hướng dẫn dùng `<!-- ... -->`. Check grep đúng hai chuỗi `<TODO:` và `<!--`; **không** grep `<...>` chung chung.
- Check chỉ áp dụng cho feature có `status` ∈ `{done, verified}`. Các status khác bỏ qua.
- Không có `node` → in dòng SKIP, **không** set FAIL và **không** in "OK".
- Nội dung tiếng Việt; giữ anchor tiếng Anh sẵn có trong `CLAUDE.md` (`Startup Workflow`, `Verification Commands`, `Definition of Done`, `End of Session`) để `validate-harness.mjs` vẫn 100/100.
- Code JS trong `node -e '...'` (bash single-quote) **không được chứa dấu nháy đơn** — dùng nháy kép và nối chuỗi bằng `+`.

---

### Task 0: Khởi tạo git repo cho harness-kit

`harness-kit` hiện **chưa phải git repo** nên các bước commit ở task sau sẽ fail. Task này dựng baseline.

**Files:**
- Create: `.gitignore`

**Interfaces:**
- Produces: git repo có commit baseline; `.tmp-tests/` bị ignore (task 1 dùng thư mục này làm sandbox test).

- [ ] **Step 1: Xác nhận chưa phải repo**

```bash
cd "C:/Users/ADMIN/OneDrive/Máy tính/harness-kit"
git rev-parse --is-inside-work-tree 2>&1
```

Expected: `fatal: not a git repository (or any of the parent directories): .git`

Nếu lệnh in `true` → bỏ qua Step 2-3, chỉ tạo `.gitignore` rồi commit.

- [ ] **Step 2: Tạo `.gitignore`**

```
.tmp-tests/
node_modules/
```

- [ ] **Step 3: Init + commit baseline**

```bash
git init
git add -A
git commit -m "chore: baseline harness-kit truoc khi them feature dossier"
```

Expected: commit thành công, liệt kê `bootstrap.mjs`, `README.md`, `template/*`, `docs/superpowers/*`, `.gitignore`.

---

### Task 1: Target `docs` trong `init.sh` + test suite

Đây là phần cốt lõi: check cơ học. Viết test trước (9 scenario), chạy cho fail, rồi implement.

**Files:**
- Create: `tests/run-tests.sh`
- Modify: `template/init.sh` (thêm `check_docs()`; sửa dòng usage ở đầu file; sửa `case` ở cuối file)

**Interfaces:**
- Consumes: `bootstrap.mjs` CLI (`--target <dir> --name <str> --stack <str>`); `template/feature_list.json` có mảng `features[]` với `id`/`status`.
- Produces:
  - Hàm bash `check_docs()` trong `init.sh`, dùng biến `FAIL` và hàm `step()` sẵn có.
  - Target CLI mới: `./init.sh docs`; `docs` nằm trong nhánh `all`.
  - Exit code: `0` = mọi feature done/verified có dossier hợp lệ (hoặc chưa feature nào done), `1` = có vi phạm.
  - `tests/run-tests.sh` với các helper mà task sau tái dùng: `ok`, `ng`, `new_project`, `patch_feature`, `valid_dossier`, `expect_docs`, `win`.

- [ ] **Step 1: Viết test suite (sẽ fail)**

Tạo `tests/run-tests.sh`:

```bash
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
echo "PASS=$PASSED  FAIL=$FAILED"
if [ "$FAILED" -eq 0 ]; then exit 0; else exit 1; fi
```

- [ ] **Step 2: Chạy test để xác nhận fail**

```bash
cd "C:/Users/ADMIN/OneDrive/Máy tính/harness-kit"
bash tests/run-tests.sh
```

Expected: `FAIL` ở các scenario mong exit 1 — vì `init.sh` chưa biết target `docs`, nó rơi vào nhánh `*)` và exit **2**. Dòng tổng kết `FAIL=` phải > 0, exit code 1.

- [ ] **Step 3: Thêm `check_docs()` vào `template/init.sh`**

Chèn ngay **sau** hàm `check_secret()` (trước `case "$TARGET" in`):

```bash
# Moi feature done/verified phai co dossier docs/features/<ID>-<slug>.md du 8 muc.
check_docs() {
  step "FEATURE DOCS (dossier cho feature done/verified)"
  command -v node >/dev/null 2>&1 || { echo "   (khong co node — SKIP, khong xac nhan duoc)"; return; }
  [ -f feature_list.json ] || { echo "   (khong co feature_list.json — skip)"; return; }
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
  const id = f.id || "(feature khong co id)";
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "thieu field \"doc\" trong feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "khong tim thay dossier " + p); continue; }
  const t = fs.readFileSync(p, "utf8");
  const nums = t.split(/\r?\n/)
    .filter(l => /^##\s+[1-8]\./.test(l))
    .map(l => l.match(/^##\s+([1-8])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " phai co du 8 muc ## 1. .. ## 8. dung thu tu (dang co: " + (nums.join(",") || "khong co muc nao") + ")");
    continue;
  }
  if (t.indexOf("<TODO:") >= 0) { fail(id, p + " con placeholder <TODO:"); continue; }
  if (t.indexOf("<!--") >= 0) { fail(id, p + " con chu thich huong dan HTML chua xoa"); continue; }
}
if (n === 0) console.log("   (chua feature nao done/verified — skip)");
else if (!bad) console.log("   OK: " + n + " feature done/verified deu co dossier hop le");
process.exit(bad);
' || FAIL=1
}
```

- [ ] **Step 4: Nối `docs` vào dispatcher**

Trong `template/init.sh`, sửa khối `case` (hiện ở dòng 52-58) thành:

```bash
case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  docs)     check_docs ;;
  all)      check_scaffold; check_build; check_secret; check_docs ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac
```

Và sửa dòng usage ở đầu file (dòng 3):

```bash
# Dung: ./init.sh [scaffold|build|secret|docs|all]   (mac dinh: all)
```

- [ ] **Step 5: Chạy test để xác nhận pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=9  FAIL=0`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add tests/run-tests.sh template/init.sh
git commit -m "feat(init.sh): them target docs — check dossier cho feature done/verified"
```

---

### Task 2: Template dossier `_TEMPLATE.md`

**Files:**
- Create: `template/docs/features/_TEMPLATE.md`
- Modify: `tests/run-tests.sh` (thêm khối test `== _TEMPLATE.md ==` vào cuối, **trước** khối tổng kết `echo ""` / `PASS=`)

**Interfaces:**
- Consumes: helper `new_project`, `ok`, `ng`, `expect_docs` từ Task 1.
- Produces: file template mà agent copy ra khi viết dossier; là nguồn duy nhất định nghĩa 8 heading + ranh giới mục 1 vs mục 2.

- [ ] **Step 1: Thêm test cho template (sẽ fail)**

Chèn vào `tests/run-tests.sh` ngay trước dòng `echo ""` của khối tổng kết:

```bash
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
```

- [ ] **Step 2: Chạy test để xác nhận fail**

```bash
bash tests/run-tests.sh
```

Expected: 5 dòng `FAIL` mới trong khối `== _TEMPLATE.md ==` (file chưa tồn tại). Scenario cuối vẫn PASS.

- [ ] **Step 3: Tạo `template/docs/features/_TEMPLATE.md`**

Lưu ý khi soạn: **không được viết chuỗi kết thúc chú thích HTML bên trong chính chú thích đó** (sẽ đóng comment sớm).

```markdown
# <TODO: F0X> — <TODO: Tên feature>

> **Status:** <TODO: done | verified> · **Ngày:** <TODO: YYYY-MM-DD> · **Commit:** <TODO: sha> · **Blueprint:** <TODO: mục>

<!--
FEATURE DOSSIER — copy file này thành docs/features/<ID>-<slug>.md khi ship một feature.

Luật:
- Viết tại SHIP gate, sau khi VERIFY + SECURITY + DEVEX đã pass.
- Giữ đủ 8 heading dưới đây, đúng thứ tự, đúng chữ. Mục không áp dụng thì ghi "—", KHÔNG xoá heading.
- Xoá hết placeholder <TODO: ...> và toàn bộ chú thích hướng dẫn trước khi ship.
- ./init.sh docs sẽ FAIL nếu thiếu mục, sai thứ tự, hoặc còn sót placeholder / chú thích.

Ranh giới mục 1 và mục 2 — đừng viết trùng:
- Mục 1 = zoom out. Vai trò của feature trong hệ thống. Vì sao dự án CẦN nó.
- Mục 2 = zoom in. Hành vi quan sát được. Bấm/gọi gì thì ra gì.
-->

## 1. Ý nghĩa với dự án

<TODO: F này đóng vai trò gì trong bức tranh chung? Nó unlock được gì (feature nào dựa vào nó — xem
`dependencies` trong feature_list.json, cả chiều xuôi lẫn chiều ngược)? Không có nó thì dự án thiếu gì?
Cover REQ / mục nào của Blueprint?>

## 2. Làm được gì

<TODO: Hành vi quan sát được, cụ thể. Người dùng bấm gì / gọi gì thì nhận lại gì.>

## 3. Cách dùng

<TODO: Bước cụ thể, endpoint, màn hình, hoặc lệnh. Kèm ví dụ thật — request → response nếu là API.>

## 4. Bên trong

<TODO: Luồng chính A → B → C.>

**Files touched**

| File | Vai trò |
|---|---|
| `<TODO: path>` | <TODO: 1 dòng> |

**Data / config:** <TODO: bảng, schema, biến env cần thiết — hoặc "—">

## 5. Quyết định & trade-off

<TODO: Chọn gì, bỏ gì, vì sao. Cái gì CỐ Ý không làm (out of scope) để người sau khỏi tưởng là thiếu sót.>

## 6. Cạm bẫy khi sửa

<TODO: Chỗ dễ vỡ, invariant phải giữ, phụ thuộc ngầm. Ai sửa file này cần biết gì trước.>

## 7. Bằng chứng

| `done_when` | Cách verify | Kết quả |
|---|---|---|
| <TODO: tiêu chí> | <TODO: lệnh / thao tác> | <TODO: pass + tóm tắt> |

**SECURITY gate:** <TODO: kết quả checklist security.md áp dụng>
Output đầy đủ nằm ở `progress.md`; ở đây chỉ tóm tắt.

## 8. Cập nhật

- <TODO: YYYY-MM-DD> — tạo mới khi ship.
```

- [ ] **Step 4: Chạy test để xác nhận pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=15  FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add template/docs/features/_TEMPLATE.md tests/run-tests.sh
git commit -m "feat(template): them _TEMPLATE.md — dossier 8 muc cho moi feature"
```

---

### Task 3: Field `doc` trong `feature_list.json`

**Files:**
- Modify: `template/feature_list.json` (thêm `"doc"` cho F01/F02/F03; bổ sung `_howto`)
- Modify: `tests/run-tests.sh` (thêm khối `== feature_list.json ==`)

**Interfaces:**
- Consumes: `check_docs()` từ Task 1 đọc field `f.doc`.
- Produces: mỗi feature mẫu có `doc` đúng quy ước `^docs/features/<ID>-[a-z0-9-]+\.md$`.

- [ ] **Step 1: Thêm test (sẽ fail)**

Chèn vào `tests/run-tests.sh` trước khối tổng kết:

```bash
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
```

- [ ] **Step 2: Chạy test để xác nhận fail**

```bash
bash tests/run-tests.sh
```

Expected: `FAIL` ở "moi feature mau co field doc" (liệt kê `F01,F02,F03`), "doc dung quy uoc", "feature_list.json co field doc", "_howto giai thich field doc".

- [ ] **Step 3: Sửa `template/feature_list.json`**

Thay chuỗi `_howto` hiện tại bằng (một dòng, giữ nguyên style không dấu của file này):

```json
  "_howto": "Moi feature CAN co: id, name, description, status (bat buoc cho validator). Them scope/done_when/verify de Builder biet ranh gioi + tieu chi test. done_when phai testable. dependencies = list id phai xong truoc. doc = duong dan dossier docs/features/<ID>-<slug>.md, BAT BUOC khi status done/verified — ./init.sh docs se check du 8 muc, dung thu tu, khong con placeholder.",
```

Thêm field `"doc"` vào từng feature, đặt ngay sau `"status"`:

- F01: `"doc": "docs/features/F01-scaffold.md",`
- F02: `"doc": "docs/features/F02-data-layer.md",`
- F03: `"doc": "docs/features/F03-auth.md",`

Ví dụ F01 sau khi sửa:

```json
    {
      "id": "F01",
      "name": "Scaffold project",
      "description": "Dung skeleton du an ({{STACK}}): cau truc thu muc theo Blueprint + .env.example + README. Build rong pass.",
      "dependencies": [],
      "status": "pending",
      "doc": "docs/features/F01-scaffold.md",
      "scope": ["cau truc thu muc theo Blueprint", ".env.example (liet ke moi secret/config)", "README.md", "config build/lint/test"],
      "done_when": [
        "cai dependencies sach",
        "build skeleton pass",
        ".env.example liet ke du moi bien can"
      ],
      "verify": ["./init.sh scaffold", "./init.sh docs"]
    },
```

Thêm `"./init.sh docs"` vào mảng `verify` của cả F01, F02, F03.

- [ ] **Step 4: Chạy test để xác nhận pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=19  FAIL=0`, exit 0. (Feature vẫn `pending` nên `check_docs` skip — không đòi file dossier.)

- [ ] **Step 5: Commit**

```bash
git add template/feature_list.json tests/run-tests.sh
git commit -m "feat(state): them field doc vao feature_list.json — tro toi dossier"
```

---

### Task 4: Nối luật vào `CLAUDE.md` và `pipeline.md`

**Files:**
- Modify: `template/CLAUDE.md` (Source of truth, Startup Workflow, Verification Commands, Definition of Done, End of Session)
- Modify: `template/.claude/workflow/pipeline.md` (mục 9 SHIP, Checkpoint gates)
- Modify: `tests/run-tests.sh` (thêm khối `== instruction wiring ==`)

**Interfaces:**
- Consumes: target `./init.sh docs` (Task 1), quy ước đường dẫn + template (Task 2), field `doc` (Task 3).
- Produces: luật thành văn để agent biết **khi nào** viết dossier và **cái gì chặn ship**.

- [ ] **Step 1: Thêm test (sẽ fail)**

Chèn vào `tests/run-tests.sh` trước khối tổng kết:

```bash
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
has "pipeline.md co luat cap nhat F cu"       "$PL" "muc 8"

# Anchor tieng Anh phai con nguyen (validate-harness.mjs dua vao day)
for a in "Startup Workflow" "Verification Commands" "Definition of Done" "End of Session"; do
  has "CLAUDE.md giu anchor: $a" "$C" "$a"
done
```

- [ ] **Step 2: Chạy test để xác nhận fail**

```bash
bash tests/run-tests.sh
```

Expected: 7 dòng FAIL đầu khối (4 anchor cuối vẫn PASS vì đã có sẵn).

- [ ] **Step 3: Sửa `template/CLAUDE.md`**

**3a.** Trong mục `## Source of truth`, chèn sau dòng `- **State:** ...`:

```markdown
- **Feature dossier:** `docs/features/<ID>-<slug>.md` — hồ sơ từng feature đã ship (8 mục: ý nghĩa với dự án, làm được gì, cách dùng, bên trong, quyết định, cạm bẫy, bằng chứng, cập nhật). Đường dẫn nằm ở field `doc` trong `feature_list.json`. Template: `docs/features/_TEMPLATE.md`.
```

**3b.** Trong `## Startup Workflow`, chèn thành mục 4 mới và đánh số lại mục cuối thành 5:

```markdown
4. **Sắp sửa một feature đã `done`?** Đọc dossier của nó (`doc` trong `feature_list.json`) TRƯỚC khi đụng code — mục 4 (bên trong) và mục 6 (cạm bẫy) tiết kiệm cả phiên dò lại.
5. **One feature at a time** (làm 1 feature một lúc). Xong → chạy verify → cập nhật state → viết dossier → SHIP gate.
```

**3c.** Trong `## Verification Commands`, chèn sau dòng `./init.sh <target>`:

```markdown
- `./init.sh docs` — mọi feature `done`/`verified` phải có dossier hợp lệ (đủ 8 mục, đúng thứ tự, hết placeholder). Nằm trong `./init.sh all`.
```

**3d.** Trong `## Definition of Done`, chèn sau dòng `secured = ...`:

```markdown
- `documented` = có dossier `docs/features/<ID>-<slug>.md` đủ 8 mục, field `doc` đã trỏ đúng, `./init.sh docs` xanh.
```

**3e.** Trong `## End of Session`, sửa mục 1 thành:

```markdown
1. Cập nhật `feature_list.json` status + `doc` + `progress.md` (Current State + bằng chứng). Feature nào vừa ship → dossier đã viết xong.
```

- [ ] **Step 4: Sửa `template/.claude/workflow/pipeline.md`**

**4a.** Trong `## 9. SHIP — gate + docs`, thêm checkbox vào danh sách (đặt ngay trước dòng `**Docs (Diataxis)**`):

```markdown
- [ ] **Feature dossier** `docs/features/<ID>-<slug>.md` viết xong, đủ 8 mục, `feature_list.json` có field `doc`, `./init.sh docs` **xanh**. Bắt đầu từ `docs/features/_TEMPLATE.md`.
```

**4b.** Ngay sau danh sách checkbox của mục 9, thêm đoạn:

```markdown
**Lan tỏa:** nếu feature đang ship **đổi hành vi của một F cũ**, phải thêm một dòng có ngày vào **mục 8 (Cập nhật)** trong dossier của F cũ đó — làm ngay trong SHIP này, không để nợ. Dossier lệch với code còn tệ hơn không có dossier.
```

**4c.** Trong `## Checkpoint gates (không bỏ qua)`, sửa dòng `SHIP→next`:

```markdown
- **SHIP→next:** state cập nhật + bằng chứng + docs sync + **dossier feature đã ghi** (`./init.sh docs` xanh).
```

- [ ] **Step 5: Chạy test để xác nhận pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=30  FAIL=0`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add template/CLAUDE.md template/.claude/workflow/pipeline.md tests/run-tests.sh
git commit -m "feat(harness): noi luat dossier vao CLAUDE.md + pipeline SHIP gate"
```

---

### Task 5: `README.md` + kiểm chứng end-to-end

**Files:**
- Modify: `README.md`
- Modify: `tests/run-tests.sh` (thêm khối `== README + e2e ==`)

**Interfaces:**
- Consumes: toàn bộ Task 1-4.
- Produces: bộ kit hoàn chỉnh; xác nhận `validate-harness.mjs` vẫn 100/100.

- [ ] **Step 1: Thêm test (sẽ fail)**

Chèn vào `tests/run-tests.sh` trước khối tổng kết:

```bash
echo ""
echo "== README + e2e =="

R="$KIT/README.md"
if grep -qF "_TEMPLATE.md" "$R"; then ok "README liet ke _TEMPLATE.md trong cay thu muc"; else ng "README liet ke _TEMPLATE.md"; fi
if grep -qF "dossier" "$R"; then ok "README giai thich dossier"; else ng "README giai thich dossier"; fi

# bootstrap --dry-run phai liet ke file template moi
P="$KIT/.tmp-tests/dry"
rm -rf "$P"; mkdir -p "$P"
if node "$(win "$KIT/bootstrap.mjs")" --target "$(win "$P")" --name "Dry" --dry-run 2>&1 \
   | grep -qE 'docs[\\/]features[\\/]_TEMPLATE\.md'; then
  ok "bootstrap --dry-run liet ke docs/features/_TEMPLATE.md"
else
  ng "bootstrap --dry-run liet ke docs/features/_TEMPLATE.md"
fi

# ./init.sh all phai chay khoi FEATURE DOCS
P="$(new_project)"
if bash "$P/init.sh" all 2>&1 | grep -qF "FEATURE DOCS"; then
  ok "./init.sh all co chay check_docs"
else
  ng "./init.sh all co chay check_docs"
fi
```

- [ ] **Step 2: Chạy test để xác nhận fail**

```bash
bash tests/run-tests.sh
```

Expected: 2 dòng FAIL đầu khối (README chưa nhắc gì); 2 dòng sau đã PASS từ Task 1-2.

- [ ] **Step 3: Sửa `README.md`**

**3a.** Trong cây "Cấu trúc bộ kit", thêm vào phần `template/` (sau dòng `init.sh`):

```
    ├── docs/features/
    │   └── _TEMPLATE.md      # dossier 8 mục — copy khi ship xong 1 feature
```

**3b.** Trong bảng "5 subsystem", sửa dòng State:

```markdown
| State | `feature_list.json`, `progress.md`, `docs/features/<ID>-<slug>.md` | feature nào, done chưa, bằng chứng, và **dossier** mô tả từng feature đã ship |
```

**3c.** Trong "Sau khi bootstrap — chỉnh cho khớp đề tài", thêm sau mục 6:

```markdown
7. **Dossier** — không phải điền trước. Mỗi lần ship xong một F, copy `docs/features/_TEMPLATE.md` thành `docs/features/<ID>-<slug>.md`, viết đủ 8 mục, trỏ field `doc` trong `feature_list.json`. `./init.sh docs` chặn ship nếu thiếu.
```

Và đánh số lại mục "Audit" hiện tại (7) thành 8.

**3d.** Trong "Ghi chú", sửa dòng yêu cầu node thành:

```markdown
- Yêu cầu `node` (bootstrap + `./init.sh docs`) + `bash` (chạy `init.sh`; Windows dùng Git Bash). Không có `node` thì `check_docs` in SKIP chứ không giả vờ pass.
```

- [ ] **Step 4: Chạy test để xác nhận pass**

```bash
bash tests/run-tests.sh
```

Expected: `PASS=34  FAIL=0`, exit 0.

- [ ] **Step 5: Chạy validator — phải giữ 100/100**

```bash
cd "C:/Users/ADMIN/OneDrive/Máy tính/harness-kit"
rm -rf .tmp-tests/audit && mkdir -p .tmp-tests/audit
W() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
node "$(W "$PWD/bootstrap.mjs")" --target "$(W "$PWD/.tmp-tests/audit")" --name "Audit Project" --stack "node"
node "$(W "C:/Users/ADMIN/.claude/skills/harness-creator/scripts/validate-harness.mjs")" \
     --target "$(W "$PWD/.tmp-tests/audit")"
rm -rf .tmp-tests
```

Expected: điểm tổng **100/100** trên 5 subsystem (instructions, state, verification, scope, lifecycle).

Nếu tụt điểm: đọc report xem subsystem nào mất điểm, đối chiếu anchor tiếng Anh trong `CLAUDE.md` (Task 4 Step 1 đã có test giữ 4 anchor) — sửa rồi chạy lại Step 4 + Step 5.

- [ ] **Step 6: Commit**

```bash
git add README.md tests/run-tests.sh
git commit -m "docs(readme): cap nhat cau truc + subsystem State cho feature dossier"
```

---

## Kiểm tra cuối (sau Task 5)

- [ ] `bash tests/run-tests.sh` → `PASS=34  FAIL=0`, exit 0
- [ ] `node bootstrap.mjs --target <dir trống> --name X --dry-run` liệt kê `docs/features/_TEMPLATE.md`
- [ ] `validate-harness.mjs` → 100/100
- [ ] `git log --oneline` → 6 commit (baseline + 5 task)
- [ ] `git status` sạch
