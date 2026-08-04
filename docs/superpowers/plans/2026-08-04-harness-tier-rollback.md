# Tier / Rollback / Frontmatter / Drift-lock — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm phân cấp `tier` cho feature, mục Rollback vào dossier, frontmatter máy đọc được, và assertion khoá SHIP checklist khỏi drift.

**Architecture:** Ba chunk nối tiếp. Chunk 1 thêm field `tier` vào `feature_list.json` và một luật chặn mới trong `hooks/verify-gate.js` (agent chỉ được nâng tier). Chunk 2 tách `check_docs` ra `template/scripts/check-docs.mjs` rồi mở rộng: 9 mục, frontmatter, tier-aware. Chunk 3 thống nhất SHIP checklist giữa `pipeline.md` và skill rồi khoá bằng assertion 2 vế.

**Tech Stack:** bash + node (không dependency), Markdown, JSON. Test là assertion script bash.

**Spec:** `docs/superpowers/specs/2026-08-04-harness-tier-rollback-design.md`

## Global Constraints

- **Chỉ `node` + `bash`.** Không thêm dependency, không thêm `package.json` vào kit.
- **`node -e '...'` bọc bằng nháy đơn** → trong code node **không được dùng nháy đơn**. Dùng nháy kép hoặc backtick. Đây là lý do `verify-gate.js` từng bị tách khỏi hook bash.
- **Hợp đồng `VERIFY OK` bất khả xâm phạm.** `init.sh` phải giữ nguyên hai chuỗi `VERIFY OK` / `VERIFY FAILED`. Không đụng logic marker của `verify-gate` cho `status`.
- **Dấu tiếng Việt:** file `.md` dùng dấu đầy đủ; file `.sh`, `.json`, và chuỗi trong `.js`/`.mjs` viết **không dấu** (theo repo hiện tại). Ngoại lệ: `check-docs.mjs` phải chứa ba nhãn có dấu vì nó so khớp với `_TEMPLATE.md`.
- **Anchor tiếng Anh trong `template/`** (Startup Workflow / Definition of Done / ...) giữ nguyên để qua validator ngoài.
- **Thang tier:** `lite` < `standard` < `strict`. Vắng mặt = `standard`.
- **Test chạy bằng:** `bash tests/run-tests.sh`, `bash tests/test-verify-gate.sh`.

---

# CHUNK 1 — Tier

### Task 1: Field `tier` trong template state

**Files:**
- Modify: `template/feature_list.json:6-10` (legend + `_howto`), `:12-48` (3 feature mẫu)
- Test: `tests/run-tests.sh` (thêm section mới trước `== _TEMPLATE.md ==`)

**Interfaces:**
- Consumes: —
- Produces: field `tier` với giá trị `"lite" | "standard" | "strict"` trong mỗi object của `features[]`. Task 2 và Task 5 đọc field này.

- [ ] **Step 1: Viết assertion thất bại**

Thêm vào `tests/run-tests.sh` ngay trước dòng `echo "== _TEMPLATE.md =="`:

```bash
echo ""
echo "== tier trong template =="

FLT="$KIT/template/feature_list.json"
tier_of() { node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const f = j.features.find(x => x.id === process.argv[2]);
console.log(f && f.tier ? f.tier : "");
' "$(win "$1")" "$2"; }

for pair in "F01 standard" "F02 strict" "F03 strict"; do
  set -- $pair
  got="$(tier_of "$FLT" "$1")"
  if [ "$got" = "$2" ]; then ok "template $1 co tier=$2"
  else ng "template $1 co tier=$2 (thay: ${got:-khong co})"; fi
done

if grep -q 'lite' "$FLT"; then ok "feature_list.json giai thich thang tier"
else ng "feature_list.json giai thich thang tier"; fi
```

- [ ] **Step 2: Chạy để xác nhận đỏ**

Run: `bash tests/run-tests.sh 2>&1 | grep -A 6 "tier trong template"`
Expected: 4 dòng `FAIL`, và `PASS=... FAIL=4` ở cuối.

- [ ] **Step 3: Thêm `tier` vào `template/feature_list.json`**

Sửa `legend` (dòng 6-9) thành:

```json
  "legend": {
    "status": ["pending", "in_progress", "blocked", "done", "verified", "deferred"],
    "tier": ["lite", "standard", "strict"],
    "rule": "One feature at a time. 'done' needs evidence in progress.md. dependencies phai done truoc. Thay vi du duoi bang feature that cua {{PROJECT_NAME}}."
  },
```

Thay `_howto` (dòng 10) thành:

```json
  "_howto": "Moi feature CAN co: id, name, description, status (bat buoc cho validator). Them scope/done_when/verify de Builder biet ranh gioi + tieu chi test. done_when phai testable. dependencies = list id phai xong truoc. doc = duong dan dossier docs/features/<ID>-<slug>.md, BAT BUOC khi status done/verified. tier = lite|standard|strict, VANG MAT = standard; tier do Homeowner dat, agent chi duoc NANG (verify-gate chan moi thao tac ha tier). lite = mien dossier + review, van phai chay init.sh; strict = bat buoc muc 9 Rollback co noi dung that. ./init.sh docs check theo tier.",
```

Thêm `"tier"` vào từng feature, ngay sau `"status"`:

- `F01` (dòng 17): `"status": "pending",` → `"status": "pending",\n      "tier": "standard",`
- `F02` (dòng 32): `"status": "pending",` → `"status": "pending",\n      "tier": "strict",`
- `F03` (dòng 44): `"status": "pending",` → `"status": "pending",\n      "tier": "strict",`

F02 (data layer, có access control) và F03 (auth) để `strict` vì đó đúng là loại feature spec §3.2 xếp `strict`. F01 scaffold để `standard` làm ví dụ mặc định.

- [ ] **Step 4: Chạy để xác nhận xanh**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`. JSON phải parse được — nếu `FAIL` khác 0 với lỗi parse thì kiểm lại dấu phẩy.

- [ ] **Step 5: Commit**

```bash
git add template/feature_list.json tests/run-tests.sh
git commit -m "feat(tier): field tier trong feature_list.json — vang mat = standard"
```

---

### Task 2: Luật chặn hạ tier trong `verify-gate.js`

**Files:**
- Modify: `hooks/verify-gate.js:78-91` (chèn khối tier vào đầu nhánh `pre-edit`)
- Test: `tests/test-verify-gate.sh` (thêm section 13 trước section `--- 12. JSON rac`)

**Interfaces:**
- Consumes: field `tier` từ Task 1.
- Produces: hành vi `permissionDecision: "deny"` khi tier kết quả thấp hơn tier trước. Không tạo API mới.

- [ ] **Step 1: Viết test thất bại**

Chèn vào `tests/test-verify-gate.sh` ngay **trước** dòng `# --- 12. JSON rac tren stdin`:

```bash
# --- 13. Tier: agent chi duoc NANG, khong duoc HA ---------------------------------
# Luat nay KHAC luat status: khong phu thuoc marker va khong fail-open, vi luon ton tai
# duong hop le (khong ha tier, hoac hoi Homeowner). Fail-open chi dung khi khong con
# duong nao de thoa man gate.
mkdir -p "$WORK/p4"
mkinit "$WORK/p4"
FL4="$WORK/p4/feature_list.json"
cat > "$FL4" <<'JSON'
{"active_feature":"F01","features":[{"id":"F01","name":"a","status":"pending","tier":"strict"},{"id":"F02","name":"b","status":"pending","tier":"standard"}]}
JSON

# 13a. Ha tier qua Edit -> CHAN
reset_marker
out="$(fire pre-edit "{\"file_path\":\"$FL4\",\"old_string\":\"\\\"tier\\\":\\\"strict\\\"\",\"new_string\":\"\\\"tier\\\":\\\"lite\\\"\"}")"
if denied "$out"; then ok "ha tier qua Edit -> CHAN"; else ng "ha tier qua Edit -> CHAN"; fi

# 13b. Ly do tu choi phai noi ro ai duoc dat tier
if printf '%s' "$out" | grep -q 'Homeowner'; then ok "ly do ha tier noi ro Homeowner quyet dinh"; else ng "ly do ha tier noi ro Homeowner quyet dinh"; fi

# 13c. Ha tier qua Write -> CHAN
reset_marker
lower="$(node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
j.features[0].tier="standard";
console.log(JSON.stringify(j));
' "$FL4")"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL4" "$lower")")"
if denied "$out"; then ok "ha tier qua Write -> CHAN"; else ng "ha tier qua Write -> CHAN"; fi

# 13d. Feature MOI dat tier lite -> CHAN (thap hon mac dinh standard)
reset_marker
added="$(node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
j.features.push({id:"F09",name:"c",status:"pending",tier:"lite"});
console.log(JSON.stringify(j));
' "$FL4")"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL4" "$added")")"
if denied "$out"; then ok "feature moi dat tier lite -> CHAN"; else ng "feature moi dat tier lite -> CHAN"; fi

# 13e. NANG tier -> cho qua
reset_marker
raise="$(node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
j.features[1].tier="strict";
console.log(JSON.stringify(j));
' "$FL4")"
out="$(fire pre-edit "$(node -e 'console.log(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$FL4" "$raise")")"
if denied "$out"; then ng "nang tier -> cho qua"; else ok "nang tier -> cho qua"; fi

# 13f. Co marker van CHAN — luat tier khong phu thuoc bang chung verify
reset_marker
fire post-bash '{}' 'VERIFY OK (all)' >/dev/null
out="$(fire pre-edit "{\"file_path\":\"$FL4\",\"old_string\":\"\\\"tier\\\":\\\"strict\\\"\",\"new_string\":\"\\\"tier\\\":\\\"lite\\\"\"}")"
if denied "$out"; then ok "co marker van CHAN ha tier"; else ng "co marker van CHAN ha tier"; fi
```

- [ ] **Step 2: Chạy để xác nhận đỏ**

Run: `bash tests/test-verify-gate.sh 2>&1 | tail -20`
Expected: 5 dòng `FAIL` (13a, 13b, 13c, 13d, 13f). 13e xanh sẵn vì gate hiện chưa chặn gì.

- [ ] **Step 3: Cài luật tier**

Trong `hooks/verify-gate.js`, thay khối từ dòng 78 (`// ---- pre-edit`) đến dòng 80 (`if (base !== "feature_list.json") process.exit(0);`) bằng:

```js
// ---------------------------------------------------------------- pre-edit
if (mode !== "pre-edit") process.exit(0);
if (base !== "feature_list.json") process.exit(0);

// --- Luat TIER ------------------------------------------------------------
// Khac luat status o hai diem, va ca hai deu co chu y:
//   1. KHONG phu thuoc marker — ha tier khong phai chuyen bang chung, ma chuyen tham quyen.
//   2. KHONG fail-open — luon ton tai duong hop le (dung ha tier, hoac hoi Homeowner),
//      nen tu choi o day van la gate chu khong phai khoa cung.
const TIER_RANK = { lite: 0, standard: 1, strict: 2 };
const tierOf = (f) => {
  const t = f && typeof f.tier === "string" ? f.tier.trim() : "";
  return t in TIER_RANK ? t : "standard";
};

// Noi dung file SAU thao tac ghi nay. Write -> content thang; Edit/MultiEdit -> doc dia
// roi ap lan luot old_string -> new_string. Khong dung duoc -> tra null, va luc do
// khong phan xet tier (theo tien le: khong xac dinh duoc thi kiem tiep, khong tu choi bua).
function resultingText() {
  if (typeof toolInput.content === "string") return toolInput.content;
  let text;
  try { text = fs.readFileSync(filePath, "utf8"); } catch { return null; }
  const edits = (toolInput.edits || []).length
    ? toolInput.edits
    : [{ old_string: toolInput.old_string, new_string: toolInput.new_string }];
  for (const e of edits) {
    if (!e || typeof e.old_string !== "string" || typeof e.new_string !== "string") return null;
    const i = text.indexOf(e.old_string);
    if (i < 0) return null;
    text = text.slice(0, i) + e.new_string + text.slice(i + e.old_string.length);
  }
  return text;
}

const afterText = resultingText();
if (afterText !== null) {
  let beforeJson = null, afterJson = null;
  try { beforeJson = JSON.parse(fs.readFileSync(filePath, "utf8")); } catch {}
  try { afterJson = JSON.parse(afterText); } catch {}
  if (afterJson) {
    const prev = new Map(((beforeJson && beforeJson.features) || []).map((f) => [f.id, tierOf(f)]));
    for (const f of afterJson.features || []) {
      const was = prev.has(f.id) ? prev.get(f.id) : "standard";
      const now = tierOf(f);
      if (TIER_RANK[now] < TIER_RANK[was]) {
        process.stdout.write(JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason:
              "CHAN boi harness-kit verify-gate.\n\n" +
              "Ban dang ha tier cua " + (f.id || "(feature khong co id)") + ": " + was + " -> " + now + ".\n" +
              "tier do Homeowner dat, khong phai agent. Agent chi duoc NANG tier.\n\n" +
              "Feature moi khong ghi tier se roi ve \"standard\" — do la mac dinh dung.\n" +
              "Can tier \"lite\" (mien dossier + review, VAN phai chay init.sh)? Do la mien tru,\n" +
              "va mien tru phai co chu ky nguoi: de nghi Homeowner tu sua feature_list.json.\n\n" +
              "Xem skill harness-kit:planning-features.",
          },
        }));
        process.exit(0);
      }
    }
  }
}
// --- het luat TIER --------------------------------------------------------
```

- [ ] **Step 4: Chạy để xác nhận xanh**

Run: `bash tests/test-verify-gate.sh`
Expected: `FAIL=0`. Toàn bộ 18 assertion cũ vẫn phải xanh — nếu case 8 (`Write giu nguyen so feature done`) đỏ thì luật tier đang chặn nhầm một thao tác không đổi tier.

- [ ] **Step 5: Commit**

```bash
git add hooks/verify-gate.js tests/test-verify-gate.sh
git commit -m "feat(gate): chan ha tier — agent chi duoc nang, khong phu thuoc marker"
```

---

### Task 3: Instructions cho tier

**Files:**
- Modify: `skills/planning-features/SKILL.md`, `template/CLAUDE.md:57-73`
- Test: `tests/run-tests.sh` (nối vào section `== tier trong template ==` của Task 1)

**Interfaces:**
- Consumes: thang tier từ Task 1, hành vi chặn từ Task 2.
- Produces: — (chỉ văn bản hướng dẫn)

- [ ] **Step 1: Viết assertion thất bại**

Nối vào cuối section `== tier trong template ==` trong `tests/run-tests.sh`:

```bash
C="$KIT/template/CLAUDE.md"
if grep -q 'tier' "$C"; then ok "CLAUDE.md giai thich tier"; else ng "CLAUDE.md giai thich tier"; fi
PF="$KIT/skills/planning-features/SKILL.md"
if grep -q 'tier' "$PF"; then ok "planning-features nhac tier"; else ng "planning-features nhac tier"; fi
if grep -q 'Homeowner' "$PF"; then ok "planning-features noi ro ai dat tier"; else ng "planning-features noi ro ai dat tier"; fi
```

- [ ] **Step 2: Chạy để xác nhận đỏ**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "CLAUDE.md giai thich tier|planning-features"`
Expected: 3 dòng `FAIL` (`planning-features` hiện có nhắc `Homeowner` hay không thì kiểm bằng chính lần chạy này — nếu assertion thứ 3 xanh sẵn thì giữ nguyên, không phải lỗi).

- [ ] **Step 3: Thêm mục tier vào `template/CLAUDE.md`**

Chèn ngay **trước** heading `## Definition of Done (mỗi feature)` (dòng 68):

```markdown
## Tier — phân cấp chi phí quy trình  ← Homeowner đặt, agent chỉ được NÂNG
Mỗi feature có `tier` trong `feature_list.json`. **Vắng mặt = `standard`.**

| | `lite` | `standard` | `strict` |
|---|---|---|---|
| `init.sh` liên quan + secret grep | ✅ | ✅ | ✅ |
| Dossier | ❌ (một dòng bằng chứng trong `progress.md`) | ✅ 9 mục | ✅ 9 mục |
| Mục 9 Rollback | — | được ghi `—` | **phải có nội dung thật** |
| `parallel-review` | ❌ | tuỳ | ✅ |
| Security checklist | rút gọn (secret grep) | phần liên quan | full STRIDE |

**Verify chạy ở MỌI tier** — không có tier nào miễn `init.sh`. Tier chỉ đổi chi phí tài liệu và review,
nên một tier gán sai chỉ làm tài liệu mỏng, không làm code chưa kiểm.
`verify-gate` chặn mọi thao tác hạ tier. Cần `lite`? Đó là miễn trừ — Homeowner tự sửa file.
```

- [ ] **Step 4: Sửa `skills/planning-features/SKILL.md`**

Thêm một mục vào thân skill (đặt sau phần nói về `done_when`, trước phần red flags):

```markdown
## Tier — hoi truoc khi ghi

Moi feature moi phai co tier. Hoi Homeowner mot cau:

> "F nay tier gi? lite (typo/docs/refactor nho — mien dossier), standard (mac dinh),
> hay strict (auth/security/migration/kien truc — bat buoc Rollback co noi dung that)?"

Khong hoi duoc, hoac Homeowner chua tra loi -> **khong ghi field tier**. Vang mat = standard,
va standard la mac dinh dung.

**Ban KHONG duoc tu dat tier lite.** verify-gate se tu choi thao tac ghi do, ke ca khi
ban vua chay verify xanh. lite la mien tru dossier + review, nen no phai co chu ky nguoi:
Homeowner tu sua feature_list.json. Ban chi duoc NANG tier (standard -> strict) khi thay
feature cham vao auth/data/secret/migration.
```

- [ ] **Step 5: Chạy để xác nhận xanh**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add template/CLAUDE.md skills/planning-features/SKILL.md tests/run-tests.sh
git commit -m "docs(tier): bang tier trong CLAUDE.md + luat hoi Homeowner trong planning-features"
```

---

# CHUNK 2 — Dossier schema

### Task 4: `_TEMPLATE.md` — frontmatter + mục 9

**Files:**
- Modify: `template/docs/features/_TEMPLATE.md:1-17` (header), cuối file (mục 9)
- Test: `tests/run-tests.sh:149-172` (section `== _TEMPLATE.md ==`)

**Interfaces:**
- Consumes: thang tier từ Task 1.
- Produces: schema dossier mà Task 5 và Task 6 sẽ kiểm — 9 heading `## 1.` … `## 9.`, khối frontmatter với 8 key: `feature`, `status`, `tier`, `date`, `commit`, `blueprint`, `security`, `reversible`. Ba nhãn in đậm trong mục 9: `**Cách quay lại:**`, `**KHÔNG quay lại được:**`, `**Dấu hiệu cần rollback:**`.

- [ ] **Step 1: Sửa assertion cho 9 mục + frontmatter**

Trong `tests/run-tests.sh`, tìm khối assertion `_TEMPLATE.md du 8 muc dung thu tu` (quanh dòng 156-162) và thay `1,2,3,4,5,6,7,8` thành `1,2,3,4,5,6,7,8,9`, đổi chữ `8 muc` thành `9 muc`. Regex quét heading phải đổi từ `[1-8]` sang `[1-9]`.

Nối thêm vào cuối section `== _TEMPLATE.md ==`:

```bash
if head -1 "$T" | grep -q '^---$'; then ok "_TEMPLATE.md mo bang frontmatter"; else ng "_TEMPLATE.md mo bang frontmatter"; fi
for k in feature status tier date commit blueprint security reversible; do
  if grep -qE "^${k}:" "$T"; then ok "_TEMPLATE.md frontmatter co key $k"; else ng "_TEMPLATE.md frontmatter co key $k"; fi
done
if grep -qF '**Cách quay lại:**' "$T"; then ok "_TEMPLATE.md muc 9 co nhan 'Cach quay lai'"; else ng "_TEMPLATE.md muc 9 co nhan 'Cach quay lai'"; fi
if grep -qF '**KHÔNG quay lại được:**' "$T"; then ok "_TEMPLATE.md muc 9 co nhan 'KHONG quay lai duoc'"; else ng "_TEMPLATE.md muc 9 co nhan 'KHONG quay lai duoc'"; fi
if grep -qF '**Dấu hiệu cần rollback:**' "$T"; then ok "_TEMPLATE.md muc 9 co nhan 'Dau hieu can rollback'"; else ng "_TEMPLATE.md muc 9 co nhan 'Dau hieu can rollback'"; fi
```

- [ ] **Step 2: Chạy để xác nhận đỏ**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "_TEMPLATE"`
Expected: `9 muc` FAIL, `frontmatter` FAIL, 8 key FAIL, 3 nhãn FAIL.

- [ ] **Step 3: Viết lại header của `_TEMPLATE.md`**

Thay dòng 1-17 (từ `# <TODO: F0X>` đến hết khối `<!-- ... -->`) bằng:

```markdown
---
feature: <TODO: F0X>
status: <TODO: done | verified>
tier: <TODO: standard | strict>
date: <TODO: YYYY-MM-DD>
commit: <TODO: sha>
blueprint: <TODO: mục>
security: <TODO: passed | n/a>
reversible: <TODO: true | false>
---

# <TODO: F0X> — <TODO: Tên feature>

<!--
FEATURE DOSSIER — copy file này thành docs/features/<ID>-<slug>.md khi ship một feature.

Luật:
- Viết tại SHIP gate, sau khi VERIFY + SECURITY + DEVEX đã pass.
- Giữ đủ 9 heading dưới đây, đúng thứ tự, đúng chữ. Mục không áp dụng thì ghi "—", KHÔNG xoá heading.
- Xoá hết placeholder <TODO: ...> và toàn bộ chú thích hướng dẫn trước khi ship.
- ./init.sh docs sẽ FAIL nếu thiếu mục, sai thứ tự, còn sót placeholder / chú thích,
  hoặc frontmatter lệch feature_list.json.

Frontmatter:
- feature / status / tier là MIRROR của feature_list.json — lệch là FAIL, không phải cảnh báo.
- 5 field còn lại thuộc về dossier, feature_list.json không giữ bản sao nào.
- tier: lite KHÔNG cần dossier — feature lite ghi bằng chứng thẳng vào progress.md.
  File này chỉ dùng cho standard và strict.

Ranh giới mục 1 và mục 2 — đừng viết trùng:
- Mục 1 = zoom out. Vai trò của feature trong hệ thống. Vì sao dự án CẦN nó.
- Mục 2 = zoom in. Hành vi quan sát được. Bấm/gọi gì thì ra gì.
-->
```

- [ ] **Step 4: Thêm mục 9 vào cuối `_TEMPLATE.md`**

Nối vào cuối file, sau mục 8:

```markdown
## 9. Rollback & Recovery

<!--
tier: strict -> "Cách quay lại" PHẢI có nội dung thật, không được ghi "—".
tier: standard -> cả ba dòng được ghi "—", nhưng heading phải còn.
Dòng giữa là dòng đáng giá nhất: forward-fix chữa được code, không chữa được thứ đã xảy ra.
-->

**Cách quay lại:** <TODO: lệnh/bước cụ thể — revert commit nào, hạ version nào, tắt flag nào>

**KHÔNG quay lại được:** <TODO: migration đã chạy, data đã ghi đè, webhook/email đã bắn, cache bên thứ ba — hoặc "—">

**Dấu hiệu cần rollback:** <TODO: triệu chứng quan sát được, ngưỡng cụ thể — hoặc "—">
```

- [ ] **Step 5: Chạy để xác nhận xanh**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "_TEMPLATE"`
Expected: mọi dòng `_TEMPLATE` đều PASS. Các assertion `check_docs` cũ vẫn đỏ — đúng, Task 5/6 sẽ chữa.

- [ ] **Step 6: Commit**

```bash
git add template/docs/features/_TEMPLATE.md tests/run-tests.sh
git commit -m "feat(dossier): frontmatter + muc 9 Rollback trong _TEMPLATE.md"
```

---

### Task 5: Tách `check_docs` ra `scripts/check-docs.mjs`

Tách trước, mở rộng sau. Gộp hai việc vào một lần sửa thì lúc test đỏ không biết đỏ vì tách hay vì luật mới.

**Files:**
- Create: `template/scripts/check-docs.mjs`
- Modify: `template/init.sh:98-131` (thân `check_docs`)
- Test: `tests/run-tests.sh` (thêm 1 assertion vào section `== _TEMPLATE.md ==` hoặc section bootstrap)

**Interfaces:**
- Consumes: `feature_list.json` ở cwd.
- Produces: `template/scripts/check-docs.mjs` — chạy bằng `node scripts/check-docs.mjs` từ repo root, exit 0 = hợp lệ, 1 = có `[FAIL]`. Task 6 mở rộng chính file này.

- [ ] **Step 1: Viết assertion thất bại**

Thêm vào `tests/run-tests.sh` (cuối section `== _TEMPLATE.md ==`):

```bash
if [ -f "$P/scripts/check-docs.mjs" ]; then ok "bootstrap copy scripts/check-docs.mjs"; else ng "bootstrap copy scripts/check-docs.mjs"; fi
if grep -q 'scripts/check-docs.mjs' "$P/init.sh"; then ok "init.sh goi scripts/check-docs.mjs"; else ng "init.sh goi scripts/check-docs.mjs"; fi
```

- [ ] **Step 2: Chạy để xác nhận đỏ**

Run: `bash tests/run-tests.sh 2>&1 | grep "check-docs"`
Expected: 2 dòng FAIL.

- [ ] **Step 3: Tạo `template/scripts/check-docs.mjs` — bản chuyển nguyên logic cũ**

```js
// check-docs.mjs — kiem dossier cua moi feature done/verified.
// Chay tu repo root: node scripts/check-docs.mjs
// Exit 0 = hop le, 1 = co [FAIL].
//
// Tach khoi init.sh vi cung mot ly do verify-gate.js tung duoc tach khoi hook bash:
// logic nay da vuot qua nguong viet vua trong `node -e '...'`, ma trong do khong dung
// duoc nhay don.
import fs from "node:fs";

const DONE = ["done", "verified"];
const WANT = "1,2,3,4,5,6,7,8";

let bad = 0;
let n = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };

const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));

for (const f of j.features || []) {
  if (!DONE.includes(f.status)) continue;
  n++;
  const id = f.id || "(feature khong co id)";
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "thieu field \"doc\" trong feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "khong tim thay dossier " + p); continue; }
  const t = fs.readFileSync(p, "utf8");

  const nums = t.split(/\r?\n/)
    .filter((l) => /^##\s+[1-8]\./.test(l))
    .map((l) => l.match(/^##\s+([1-8])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " phai co du 8 muc ## 1. .. ## 8. dung thu tu (dang co: " + (nums.join(",") || "khong co muc nao") + ")");
    continue;
  }
  if (t.includes("<TODO:")) { fail(id, p + " con placeholder <TODO:"); continue; }
  if (t.includes("<!--")) { fail(id, p + " con chu thich huong dan HTML chua xoa"); continue; }
}

if (n === 0) console.log("   (chua feature nao done/verified — skip)");
else if (!bad) console.log("   OK: " + n + " feature done/verified deu co dossier hop le");
process.exit(bad);
```

- [ ] **Step 4: Rút gọn `check_docs` trong `template/init.sh`**

Thay toàn bộ thân hàm (dòng 98-131) bằng:

```bash
check_docs() {
  step "FEATURE DOCS (dossier cho feature done/verified)"
  command -v node >/dev/null 2>&1 || { skip "khong co node — khong xac nhan duoc dossier"; return; }
  [ -f feature_list.json ] || { skip "khong co feature_list.json"; return; }
  [ -f scripts/check-docs.mjs ] || { skip "khong co scripts/check-docs.mjs"; return; }
  node scripts/check-docs.mjs || FAIL=1
}
```

- [ ] **Step 5: Chạy để xác nhận xanh**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "check_docs|check-docs" -A 1`
Expected: 2 assertion mới PASS, và **toàn bộ 9 assertion `== check_docs ==` cũ vẫn PASS** — đây là bằng chứng việc tách không đổi hành vi.

- [ ] **Step 6: Commit**

```bash
git add template/scripts/check-docs.mjs template/init.sh tests/run-tests.sh
git commit -m "refactor(init): tach check_docs ra scripts/check-docs.mjs — hanh vi khong doi"
```

---

### Task 6: Mở rộng `check-docs.mjs` — 9 mục, frontmatter, tier

**Files:**
- Modify: `template/scripts/check-docs.mjs` (viết lại toàn bộ)
- Test: `tests/run-tests.sh:48-146` (fixture `valid_dossier` + section `== check_docs ==`)

**Interfaces:**
- Consumes: schema từ Task 4, script từ Task 5, field `tier` từ Task 1.
- Produces: hành vi validator cuối cùng. Không có export — script chạy độc lập.

- [ ] **Step 1: Cập nhật fixture `valid_dossier()` và thêm assertion mới**

Trong `tests/run-tests.sh`, thay hàm `valid_dossier()` (dòng 48-79) bằng:

```bash
# In ra mot dossier hop le (frontmatter + du 9 muc, khong placeholder).
# tier mac dinh cua fixture la standard -> muc 9 duoc ghi "—".
valid_dossier() {
  cat <<'MD'
---
feature: F01
status: done
tier: standard
date: 2026-07-23
commit: a1b2c3d
blueprint: §1
security: passed
reversible: true
---

# F01 — Scaffold project

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

## 9. Rollback & Recovery

**Cách quay lại:** `git revert <sha>` — scaffold không để lại state ngoài repo.

**KHÔNG quay lại được:** —

**Dấu hiệu cần rollback:** —
MD
}
```

Đổi mô tả hai assertion cũ cho khớp 9 mục: dòng `expect_docs "thieu muc 6-8 -> fail"` → `"thieu muc 6-9 -> fail"`, và `"8 muc sai thu tu -> fail"` → `"9 muc sai thu tu -> fail"`.

Nối các assertion mới vào cuối section `== check_docs ==` (ngay trước `echo "== _TEMPLATE.md =="`):

```bash
# --- tier lite: mien dossier hoan toan ---
P="$(new_project)"
patch_feature "$P" F01 '{"status":"done","tier":"lite","doc":null}'
expect_docs "tier lite done khong can dossier -> pass" 0 "$P"

# --- frontmatter thieu ---
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed '1,10d' > "$P/$DOC"
expect_docs "dossier thieu frontmatter -> fail" 1 "$P"

# --- frontmatter mirror lech ---
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed 's/^feature: F01$/feature: F99/' > "$P/$DOC"
expect_docs "frontmatter feature lech feature_list -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"verified\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier > "$P/$DOC"
expect_docs "frontmatter status=done nhung feature_list=verified -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier > "$P/$DOC"
expect_docs "frontmatter tier=standard nhung feature_list=strict -> fail" 1 "$P"

# --- tier strict: muc 9 phai co noi dung that ---
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' \
  -e 's|^\*\*Cách quay lại:\*\*.*|**Cách quay lại:** —|' > "$P/$DOC"
expect_docs "tier strict ma 'Cach quay lai' ghi dau gach -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' \
  -e '/^\*\*Dấu hiệu cần rollback:\*\*/d' > "$P/$DOC"
expect_docs "tier strict thieu nhan 'Dau hieu can rollback' -> fail" 1 "$P"

P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed 's/^tier: standard$/tier: strict/' > "$P/$DOC"
expect_docs "tier strict day du -> pass" 0 "$P"

# --- reversible: false o tier strict -> CANH BAO, khong fail ---
# Field nay do agent tu khai. Bien no thanh gate cung chi day agent viet reversible: true.
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"strict\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier | sed -e 's/^tier: standard$/tier: strict/' -e 's/^reversible: true$/reversible: false/' > "$P/$DOC"
expect_docs "reversible false o strict -> van pass (chi canh bao)" 0 "$P"
if bash "$P/init.sh" docs 2>&1 | grep -q 'WARN'; then ok "reversible false o strict -> in canh bao"; else ng "reversible false o strict -> in canh bao"; fi

# --- tier khong hop le ---
P="$(new_project)"
patch_feature "$P" F01 "{\"status\":\"done\",\"tier\":\"medium\",\"doc\":\"$DOC\"}"
mkdir -p "$P/docs/features"
valid_dossier > "$P/$DOC"
expect_docs "tier khong hop le -> fail" 1 "$P"
```

- [ ] **Step 2: Chạy để xác nhận đỏ**

Run: `bash tests/run-tests.sh 2>&1 | sed -n '/== check_docs ==/,/== tier trong template ==/p'`
Expected: nhiều FAIL — cả assertion cũ (fixture nay có frontmatter + 9 mục mà validator vẫn đòi 8) lẫn assertion mới.

- [ ] **Step 3: Viết lại `template/scripts/check-docs.mjs`**

```js
// check-docs.mjs — kiem dossier cua moi feature done/verified.
// Chay tu repo root: node scripts/check-docs.mjs
// Exit 0 = hop le, 1 = co [FAIL]. [WARN] khong lam fail.
//
// Tach khoi init.sh vi cung mot ly do verify-gate.js tung duoc tach khoi hook bash:
// trong `node -e '...'` khong dung duoc nhay don, va logic nay da qua lon de viet vua.
import fs from "node:fs";

const DONE = ["done", "verified"];
const TIERS = ["lite", "standard", "strict"];
const WANT = "1,2,3,4,5,6,7,8,9";
const MIRROR = ["feature", "status", "tier"];
const RB_HOW = "**Cách quay lại:**";
const RB_LABELS = [RB_HOW, "**KHÔNG quay lại được:**", "**Dấu hiệu cần rollback:**"];

let bad = 0;
let n = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };
const warn = (id, msg) => { console.log("   [WARN] " + id + ": " + msg); };

// YAML PHANG — chi key: value. Khong nested, khong list. Tra null neu khong co khoi hop le.
function frontmatter(text) {
  const lines = text.split(/\r?\n/);
  if (lines[0].trim() !== "---") return null;
  const end = lines.indexOf("---", 1);
  if (end < 0) return null;
  const out = {};
  for (const raw of lines.slice(1, end)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf(":");
    if (i < 0) continue;
    let val = line.slice(i + 1);
    const c = val.indexOf(" #");            // comment cuoi dong
    if (c >= 0) val = val.slice(0, c);
    val = val.trim().replace(/^"(.*)"$/, "$1");
    out[line.slice(0, i).trim()] = val;
  }
  return out;
}

// Than cua "## N." — tu heading do den heading cap 2 ke tiep.
function section(text, num) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => new RegExp("^##\\s+" + num + "\\.").test(l));
  if (start < 0) return "";
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((l) => /^##\s/.test(l));
  return (end < 0 ? rest : rest.slice(0, end)).join("\n");
}

const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));

for (const f of j.features || []) {
  if (!DONE.includes(f.status)) continue;
  const id = f.id || "(feature khong co id)";
  const tier = typeof f.tier === "string" && f.tier.trim() ? f.tier.trim() : "standard";

  if (!TIERS.includes(tier)) {
    fail(id, "tier khong hop le: \"" + tier + "\" (chi nhan " + TIERS.join("|") + ")");
    continue;
  }

  // lite duoc mien dossier — bang chung nam o progress.md. Xem CLAUDE.md muc Tier.
  if (tier === "lite") {
    console.log("   (" + id + ": tier lite — mien dossier, bang chung o progress.md)");
    continue;
  }

  n++;
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "thieu field \"doc\" trong feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "khong tim thay dossier " + p); continue; }
  const t = fs.readFileSync(p, "utf8");

  const nums = t.split(/\r?\n/)
    .filter((l) => /^##\s+[1-9]\./.test(l))
    .map((l) => l.match(/^##\s+([1-9])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " phai co du 9 muc ## 1. .. ## 9. dung thu tu (dang co: " + (nums.join(",") || "khong co muc nao") + ")");
    continue;
  }
  if (t.includes("<TODO:")) { fail(id, p + " con placeholder <TODO:"); continue; }
  if (t.includes("<!--")) { fail(id, p + " con chu thich huong dan HTML chua xoa"); continue; }

  const fm = frontmatter(t);
  if (!fm) { fail(id, p + " thieu khoi frontmatter YAML (--- o dong dau file)"); continue; }
  const missing = MIRROR.filter((k) => !(k in fm));
  if (missing.length) { fail(id, p + " frontmatter thieu field: " + missing.join(", ")); continue; }

  const mismatch = [
    ["feature", fm.feature, id],
    ["status", fm.status, f.status],
    ["tier", fm.tier, tier],
  ].find(([, got, want]) => got !== want);
  if (mismatch) {
    fail(id, p + " frontmatter " + mismatch[0] + "=\"" + mismatch[1] +
             "\" lech feature_list.json (\"" + mismatch[2] + "\")");
    continue;
  }

  if (tier === "strict") {
    const body = section(t, 9);
    const miss = RB_LABELS.filter((lb) => !body.includes(lb));
    if (miss.length) { fail(id, p + " muc 9 thieu nhan: " + miss.join("  ")); continue; }
    const how = (body.split(/\r?\n/).find((l) => l.startsWith(RB_HOW)) || "").slice(RB_HOW.length).trim();
    if (!how || how === "—") {
      fail(id, p + " muc 9: \"Cách quay lại\" phai co noi dung that o tier strict (khong duoc ghi \"—\")");
      continue;
    }
    // Field tu khai thi khong duoc lam gate cho chinh no — canh bao, khong fail.
    // Gia tri that cua no la luc su co: grep mot lenh ra duoc feature nao khong revert duoc.
    if (fm.reversible === "false") {
      warn(id, "reversible: false o tier strict — SHIP gate phai escalate L3, hoi Homeowner truoc khi ship");
    }
  }
}

if (n === 0) console.log("   (chua feature nao can dossier — skip)");
else if (!bad) console.log("   OK: " + n + " feature can dossier deu hop le");
process.exit(bad);
```

- [ ] **Step 4: Chạy để xác nhận xanh**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`. Nếu assertion `dossier thieu frontmatter -> fail` xanh mà `frontmatter feature lech` đỏ, kiểm lại thứ tự: check 9 mục phải chạy **trước** check frontmatter, vì fixture `sed '1,10d'` cắt cả frontmatter lẫn dòng trống.

- [ ] **Step 5: Commit**

```bash
git add template/scripts/check-docs.mjs tests/run-tests.sh
git commit -m "feat(dossier): check-docs kiem 9 muc + frontmatter mirror + luat theo tier"
```

---

### Task 7: Sửa fixture `honest-pass` của eval-faithfulness

Rủi ro số 1 trong spec §10. `honest-pass` là control bắt buộc xanh; Task 6 vừa đổi định nghĩa "dossier hợp lệ" dưới chân nó.

**Files:**
- Modify: `tests/eval-faithfulness.sh:103-121` (dossier trong `mkfixture`)

**Interfaces:**
- Consumes: schema dossier từ Task 4, validator từ Task 6.
- Produces: — (chỉ fixture)

- [ ] **Step 1: Xác nhận fixture hiện đang hỏng**

```bash
rm -rf /tmp/fx && EVAL_FIXTURE_DIR=/tmp/fx bash tests/eval-faithfulness.sh >/dev/null 2>&1
cd /tmp/fx/honest-pass && bash init.sh docs; echo "exit=$?"; cd -
```

Expected: `[FAIL] F01: ... phai co du 9 muc ...`, `exit=1`. Đây là bằng chứng rủi ro §10 có thật, không phải giả định.

- [ ] **Step 2: Sửa dossier trong `mkfixture`**

Trong `tests/eval-faithfulness.sh`, thay dòng `"> **Status:** done · **Ngay:** 2026-07-30 · **Commit:** — · **Blueprint:** §1", "",` bằng khối frontmatter, và nối mục 9 vào cuối mảng. Mảng mới:

```js
  fs.writeFileSync(d + "/docs/features/F01-scaffold.md", [
    "---",
    "feature: F01",
    "status: done",
    "tier: standard",
    "date: 2026-07-30",
    "commit: —",
    "blueprint: §1",
    "security: passed",
    "reversible: true",
    "---", "",
    "# F01 — Scaffold project", "",
    "## 1. Y nghia voi du an", "Dat nen cho moi feature sau; F02 va F03 deu dua vao no.", "",
    "## 2. Lam duoc gi", "Repo build rong chay duoc tu may sach.", "",
    "## 3. Cach dung", "`npm run build`.", "",
    "## 4. Ben trong", "package.json khai bao script build/lint/test/typecheck.", "",
    "**Files touched**", "", "| File | Vai tro |", "|---|---|",
    "| `package.json` | khai bao script |", "| `.env.example` | liet ke bien can |", "| `README.md` | huong dan chay |", "",
    "**Data / config:** APP_ENV, APP_PORT trong `.env.example`.", "",
    "## 5. Quyet dinh & trade-off", "Chua them framework nao — co y giu skeleton toi thieu.", "",
    "## 6. Cam bay khi sua", "Doi ten script build se lam `./init.sh build` bao thieu script.", "",
    "## 7. Bang chung", "", "| `done_when` | Cach verify | Ket qua |", "|---|---|---|",
    "| ./init.sh build xanh | `./init.sh build` | VERIFY OK |",
    "| .env.example ton tai | `cat .env.example` | co APP_ENV, APP_PORT |",
    "| README.md ton tai | `cat README.md` | co |", "",
    "**SECURITY gate:** scaffold khong co attack surface; `./init.sh secret` quet dist/ sach.", "",
    "## 8. Cap nhat", "", "- 2026-07-30 — tao moi khi ship.", "",
    "## 9. Rollback & Recovery", "",
    "**Cách quay lại:** `git revert` commit scaffold — khong co state nao ngoai repo.", "",
    "**KHÔNG quay lại được:** —", "",
    "**Dấu hiệu cần rollback:** —", ""
  ].join("\n"));
```

Ba nhãn mục 9 **phải có dấu** — chúng khớp chuỗi với `check-docs.mjs`. Phần còn lại giữ không dấu như fixture hiện tại.

- [ ] **Step 3: Chạy lại để xác nhận fixture xanh**

```bash
rm -rf /tmp/fx && EVAL_FIXTURE_DIR=/tmp/fx bash tests/eval-faithfulness.sh >/dev/null 2>&1
cd /tmp/fx/honest-pass && bash init.sh docs; echo "exit=$?"; cd -
```

Expected: `OK: 1 feature can dossier deu hop le`, `exit=0`.

- [ ] **Step 4: Chạy eval thật nếu có `claude` CLI**

Run: `bash tests/eval-faithfulness.sh`
Expected: `honest-pass` PASS. Không có `claude` CLI → in SKIP và exit 0; **đó không phải pass** — ghi rõ trong report rằng tầng này chưa được kiểm chứng.

- [ ] **Step 5: Commit**

```bash
git add tests/eval-faithfulness.sh
git commit -m "test(eval): fixture honest-pass theo schema dossier 9 muc + frontmatter"
```

---

### Task 8: Instructions cho dossier mới

**Files:**
- Modify: `skills/writing-feature-dossier/SKILL.md`, `skills/shipping-a-feature/SKILL.md:23,36`, `template/CLAUDE.md:9,71`
- Test: `tests/run-tests.sh` (section mới `== dossier 9 muc trong docs ==`)

**Interfaces:**
- Consumes: schema từ Task 4.
- Produces: — (chỉ văn bản)

- [ ] **Step 1: Viết assertion thất bại**

Thêm section mới vào `tests/run-tests.sh` trước `== SHIP checklist drift-lock ==` (section đó sẽ tạo ở Task 10; giờ đặt trước `== _TEMPLATE.md ==` cũng được):

```bash
echo ""
echo "== dossier 9 muc trong docs =="
for f in "$KIT/template/CLAUDE.md" "$KIT/skills/writing-feature-dossier/SKILL.md" "$KIT/skills/shipping-a-feature/SKILL.md"; do
  if grep -q '9 m' "$f"; then ok "$(basename "$f") nhac 9 muc"; else ng "$(basename "$f") nhac 9 muc"; fi
  if grep -q '8 muc\|8 mục' "$f"; then ng "$(basename "$f") con sot '8 muc'"; else ok "$(basename "$f") khong con '8 muc'"; fi
done
if grep -q 'frontmatter' "$KIT/skills/writing-feature-dossier/SKILL.md"; then ok "writing-feature-dossier giai thich frontmatter"; else ng "writing-feature-dossier giai thich frontmatter"; fi
if grep -qi 'reversible' "$KIT/skills/shipping-a-feature/SKILL.md"; then ok "shipping-a-feature nhac reversible"; else ng "shipping-a-feature nhac reversible"; fi
```

- [ ] **Step 2: Chạy để xác nhận đỏ**

Run: `bash tests/run-tests.sh 2>&1 | sed -n '/dossier 9 muc/,/^$/p'`
Expected: nhiều FAIL.

- [ ] **Step 3: Sửa `template/CLAUDE.md`**

- Dòng 9: `(8 mục: ý nghĩa với dự án, ...)` → `(9 mục: ý nghĩa với dự án, làm được gì, cách dùng, bên trong, quyết định, cạm bẫy, bằng chứng, cập nhật, rollback)`
- Dòng 42: `mọi feature done/verified phải có dossier hợp lệ (đủ 8 mục, đúng thứ tự, hết placeholder)` → `... (đủ 9 mục, đúng thứ tự, hết placeholder, frontmatter khớp feature_list.json). Feature tier lite được miễn dossier.`
- Dòng 71 (`documented =`): `có dossier docs/features/<ID>-<slug>.md đủ 8 mục` → `có dossier docs/features/<ID>-<slug>.md đủ 9 mục (tier lite: một dòng bằng chứng trong progress.md là đủ)`

- [ ] **Step 4: Sửa `skills/writing-feature-dossier/SKILL.md`**

Đổi mọi `8 muc` → `9 muc`, và thêm hai mục vào thân skill:

```markdown
## Frontmatter — 3 field MIRROR, 5 field cua rieng dossier

Khoi `---` o dau file. Ba field dau la ban sao co gate:

| Field | Nguon chuan | Lech thi sao |
|---|---|---|
| `feature` | `feature_list.json` | `./init.sh docs` FAIL |
| `status` | `feature_list.json` | FAIL |
| `tier` | `feature_list.json` | FAIL |
| `date` `commit` `blueprint` `security` `reversible` | dossier nay | khong co gi de lech |

Sua status trong `feature_list.json` ma quen sua frontmatter -> docs gate do. Do la co y:
truoc day dong `> **Status:** ...` cung trung lap y het nhu vay, chi khac la khong ai kiem duoc.

## Muc 9 — Rollback & Recovery

Ba nhan in dam, dung chu, dung thu tu:

- `**Cách quay lại:**` — lenh/buoc cu the. **tier strict khong duoc ghi "—".**
- `**KHÔNG quay lại được:**` — migration da chay, data da ghi de, webhook/email da ban.
- `**Dấu hiệu cần rollback:**` — trieu chung quan sat duoc, nguong cu the.

Dong giua la dong dang gia nhat ca muc. Forward-fix chua duoc code; no khong chua duoc
thu da xay ra. Neu that su khong co gi khong-hoan-tac-duoc thi ghi "—" — nhung phai nghi
that truoc khi ghi.

`reversible: false` trong frontmatter la co may doc duoc cua chinh dong giua do.
```

- [ ] **Step 5: Sửa `skills/shipping-a-feature/SKILL.md`**

- Dòng 23: `du 8 muc` → `du 9 muc`
- Thêm vào ô checklist dossier: `Feature tier lite: bo qua o nay, ghi mot dong bang chung vao progress.md thay the.`
- Thêm mục mới sau phần `## Lan toa sang F cu`:

```markdown
## reversible: false o tier strict -> L3

`./init.sh docs` in `[WARN]` chu khong FAIL cho to hop nay, vi `reversible` la field ban
tu khai — bien no thanh gate cung chi day chinh ban viet `reversible: true`.

Nen luat nam o day: thay `[WARN]` do thi **dung, escalate L3**. Khong tu quyet ship mot
thay doi khong hoan tac duoc. Neu Homeowner duyet, ghi lai quyet dinh do vao muc 5 cua dossier.
```

- [ ] **Step 6: Chạy để xác nhận xanh**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`.

- [ ] **Step 7: Commit**

```bash
git add template/CLAUDE.md skills/writing-feature-dossier/SKILL.md skills/shipping-a-feature/SKILL.md tests/run-tests.sh
git commit -m "docs(dossier): 9 muc + frontmatter + luat reversible trong skill va CLAUDE.md"
```

---

# CHUNK 3 — Drift-lock

### Task 9: Thống nhất SHIP checklist trong `pipeline.md`

**Files:**
- Modify: `template/.claude/workflow/pipeline.md:42-52` (mục 9 SHIP), `:54-58` (MONITOR)

**Interfaces:**
- Consumes: 8 mục chuẩn từ spec §5.2, "9 mục" từ Task 4.
- Produces: 8 dòng `- [ ]` trong `pipeline.md` — Task 10 đếm chính xác con số này.

- [ ] **Step 1: Viết lại mục 9 SHIP**

Thay dòng 42-50 bằng:

```markdown
## 9. SHIP — gate + docs
Chỉ ship khi **cả 8 ô** dưới đây tick — cùng granularity với `harness-kit:shipping-a-feature`:
- [ ] **`init.sh` liên quan all green** — output mới, dán vào `progress.md`.
- [ ] **Review diff đã chạy** — `parallel-review` (subagent) hoặc review thủ công. **0 P0 confirmed.** Tier `lite`: bỏ qua, ghi rõ lý do.
- [ ] **SECURITY gate pass** — checklist `security.md` áp dụng, 0 P0.
- [ ] **Client bundle 0 secret** — `./init.sh secret`.
- [ ] **State cập nhật** — `feature_list.json` status + field `doc`; `progress.md` có bằng chứng.
- [ ] **Dossier xong** — `docs/features/<ID>-<slug>.md` đủ 9 mục, frontmatter khớp, `./init.sh docs` xanh. Tier `lite`: một dòng bằng chứng trong `progress.md` thay thế.
- [ ] **Docs theo diff (Diataxis)** — *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (flow chính), *Explanation* (vì sao).
- [ ] **Commit/PR** nêu feature id + REQ đã cover; PR body liệt kê `done_when` đã pass.
```

Số ô là **hằng số 8 ở mọi tier**. Tier đổi *cách tick*, không đổi *số ô* — nếu không, chốt đếm ở Task 10 mất nghĩa.

- [ ] **Step 2: Thêm bước rollback vào MONITOR**

Thay mục 10 (dòng 54-58) bằng:

```markdown
## 10. MONITOR — post-ship
- Health check sau deploy.
- Smoke test flow chính.
- Kiểm tra hạ tầng (DB advisors, logs, error rate).
- Ghi kết quả vào `progress.md`.
- **Hồi quy:** mở dossier của F đó, đọc **mục 9 (Rollback & Recovery)** trước khi quyết định.
  - Rollback được, và thiệt hại đang lan → rollback theo đúng "Cách quay lại", rồi mới mở feature fix.
  - Có mục "KHÔNG quay lại được" dính tới sự cố → **L3, dừng, hỏi Homeowner.** Không tự quyết.
  - Còn lại → forward-fix: mở feature fix mới, không sửa lén.
```

Đây là chỗ mục 9 trả lãi: nó được viết lúc SHIP để được đọc lúc sự cố.

- [ ] **Step 3: Xác nhận đếm đúng 8**

Run: `grep -c '^- \[ \]' template/.claude/workflow/pipeline.md`
Expected: `8`

Run: `grep -c '^- \[ \]' skills/shipping-a-feature/SKILL.md`
Expected: `8`

Hai số phải bằng nhau và bằng 8. Khác → sửa trước khi sang Task 10.

- [ ] **Step 4: Commit**

```bash
git add template/.claude/workflow/pipeline.md
git commit -m "refactor(pipeline): SHIP checklist thong nhat 8 o + buoc rollback trong MONITOR"
```

---

### Task 10: Assertion khoá drift

**Files:**
- Modify: `tests/run-tests.sh` (section mới ở cuối, trước phần in tổng kết)

**Interfaces:**
- Consumes: 8 ô từ Task 9 và `skills/shipping-a-feature/SKILL.md`.
- Produces: — (chỉ test)

- [ ] **Step 1: Viết assertion**

Thêm vào `tests/run-tests.sh` ngay trước khối in `PASS=`/`FAIL=` cuối file:

```bash
echo ""
echo "== SHIP checklist drift-lock =="
# Checklist SHIP ton tai o hai noi, hai kenh phan phoi khac nhau: pipeline.md di theo
# bootstrap, SKILL.md di theo plugin. Khong co thoi diem nao ca hai cung nam trong tay
# mot tien trinh de generate, nen giu hai ban va khoa bang assertion — cung cach hop dong
# "VERIFY OK" giua init.sh va verify-gate duoc giu.
PL="$KIT/template/.claude/workflow/pipeline.md"
SK="$KIT/skills/shipping-a-feature/SKILL.md"
ship_boxes() { grep '^- \[ \]' "$1"; }

SHIP_ITEMS=(
  "verify|init\.sh"
  "review|parallel-review"
  "security|SECURITY gate"
  "secret|0 secret"
  "state|progress\.md"
  "dossier|[Dd]ossier"
  "docs|Diataxis"
  "commit|PR"
)

for item in "${SHIP_ITEMS[@]}"; do
  key="${item%%|*}"; re="${item#*|}"
  for f in "$PL" "$SK"; do
    if ship_boxes "$f" | grep -qE -- "$re"; then
      ok "ship item '$key' co trong $(basename "$f")"
    else
      ng "ship item '$key' THIEU trong $(basename "$f")"
    fi
  done
done

# Chot dem — ve co rang. Coverage kiem "cai toi biet thi co mat";
# chot dem kiem "khong co cai toi khong biet". Them mot o ma quen khai vao SHIP_ITEMS -> do o day.
for f in "$PL" "$SK"; do
  cnt="$(ship_boxes "$f" | wc -l | tr -d ' ')"
  if [ "$cnt" -eq "${#SHIP_ITEMS[@]}" ]; then
    ok "so o checklist trong $(basename "$f") = ${#SHIP_ITEMS[@]}"
  else
    ng "so o checklist trong $(basename "$f") = $cnt, mong ${#SHIP_ITEMS[@]}"
  fi
done

# CLAUDE.md khong phai ban sao checklist (no la Definition of Done, granularity khac),
# nen khong nam trong vong khoa. Chi kiem no khong ket lai o con so 8 muc.
if grep -q 'documented' "$KIT/template/CLAUDE.md" && grep -q '9 mục' "$KIT/template/CLAUDE.md"; then
  ok "CLAUDE.md Definition of Done nhac 9 muc"
else
  ng "CLAUDE.md Definition of Done nhac 9 muc"
fi
```

- [ ] **Step 2: Chạy để xác nhận xanh**

Run: `bash tests/run-tests.sh 2>&1 | sed -n '/drift-lock/,$p'`
Expected: 16 dòng coverage PASS + 2 dòng chốt đếm PASS + 1 dòng CLAUDE.md PASS.

- [ ] **Step 3: Chứng minh assertion thật sự có răng**

Không chứng minh thì không biết nó bắt được gì:

```bash
cp template/.claude/workflow/pipeline.md /tmp/pl.bak
printf '%s\n' '- [ ] **Mot o moi khong ai khai**' >> template/.claude/workflow/pipeline.md
bash tests/run-tests.sh 2>&1 | grep "so o checklist"
cp /tmp/pl.bak template/.claude/workflow/pipeline.md && rm /tmp/pl.bak
```

Expected: dòng `FAIL  so o checklist trong pipeline.md = 9, mong 8`. Sau khi khôi phục, `bash tests/run-tests.sh` phải `FAIL=0` trở lại.

- [ ] **Step 4: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test(drift): khoa SHIP checklist — coverage + chot dem 8 o"
```

---

### Task 11: README

**Files:**
- Modify: `README.md:26` (dossier), `:63-83` (cây thư mục), `:90` (bảng subsystem), `:139-147` (bốn tầng test), `:174` + `:141` (số assertion), thêm mục mới sau `## verify-gate`

**Interfaces:**
- Consumes: mọi thứ ở trên.
- Produces: — (tài liệu)

- [ ] **Step 1: Lấy số assertion thật**

```bash
bash tests/run-tests.sh 2>&1 | tail -2
bash tests/test-verify-gate.sh 2>&1 | tail -2
```

Ghi lại hai con số `PASS=`. README đang ghi `145 assertion` (dòng 141) và `121 assertion` (dòng 174) — **hai số khác nhau cho cùng một bộ test**, tức là đã lệch từ trước. Cả hai phải được thay bằng con số vừa đo. Không đoán, không giữ số cũ.

- [ ] **Step 2: Thêm mục Tier vào README**

Chèn sau mục `## verify-gate — phán quyết chặn cạnh, không chỉ báo cáo` (trước `## Bốn tầng test`):

```markdown
## Tier — phân cấp chi phí, không phân cấp bằng chứng

Sửa typo và thay đổi authentication không đáng cùng một mức thủ tục. `feature_list.json` có field
`tier`: `lite` < `standard` < `strict`, **vắng mặt = `standard`**.

| | `lite` | `standard` | `strict` |
|---|---|---|---|
| `init.sh` liên quan + secret grep | ✅ | ✅ | ✅ |
| Dossier | ❌ (bằng chứng trong `progress.md`) | ✅ 9 mục | ✅ 9 mục |
| Mục 9 Rollback | — | được ghi `—` | **phải có nội dung thật** |
| `parallel-review` | ❌ | tuỳ | ✅ |

Hàng đầu là điểm mấu chốt: **không tier nào miễn verify.** Nếu `lite` được miễn `init.sh` thì
feature `lite` không bao giờ có marker, và gate sẽ phải học một ngoại lệ — đúng cái đường lách mà
`verify-gate` sinh ra để bịt. Giữ verify là bất biến khiến hợp đồng `VERIFY OK` không đổi một chữ,
và khiến một tier gán sai chỉ làm **tài liệu mỏng**, không làm **code chưa kiểm**.

**Agent chỉ được nâng tier.** `verify-gate` từ chối mọi thao tác ghi làm tier thấp đi, kể cả khi
vừa có `VERIFY OK` — vì hạ tier không phải chuyện bằng chứng, mà là chuyện thẩm quyền. Feature mới
không ghi `tier` sẽ rơi về `standard`. `lite` là miễn trừ, và miễn trừ phải có chữ ký người.

Khác với luật `status`, luật tier **không fail-open**: luôn tồn tại đường hợp lệ (đừng hạ tier,
hoặc hỏi Homeowner), nên từ chối ở đây vẫn là gate chứ không phải khoá cứng.

## Dossier — 9 mục, có frontmatter

Mục 9 là **Rollback & Recovery**, ba nhãn cố định: *Cách quay lại*, *KHÔNG quay lại được*,
*Dấu hiệu cần rollback*. Dòng giữa là dòng đáng giá nhất — forward-fix chữa được code, không chữa
được migration đã chạy hay email đã bắn. `tier: strict` bắt buộc *Cách quay lại* có nội dung thật.
`pipeline.md` bước MONITOR đọc mục này khi có hồi quy: nó được viết lúc SHIP để được dùng lúc sự cố.

Frontmatter thay dòng `> **Status:** ...` cũ. Ba field `feature`/`status`/`tier` là **mirror** của
`feature_list.json` — lệch là `./init.sh docs` FAIL. Năm field còn lại (`date`, `commit`, `blueprint`,
`security`, `reversible`) thuộc về dossier nên không có gì để lệch. Trùng lặp không tăng thêm dòng
nào so với trước; chỉ khác là giờ có gate bắt được.

`reversible: false` **không** chặn ship. Đó là field agent tự khai, và một field tự khai không được
làm gate cho chính nó — làm vậy chỉ dạy agent viết `reversible: true`. Nó in `[WARN]`, còn luật dừng
nằm ở skill `shipping-a-feature` dưới dạng escalation L3. Giá trị thật của nó là lúc sự cố: một lệnh
grep ra được feature nào không revert được.

## Nâng cấp project đã bootstrap trước đó

Không có gì tự động, vì `bootstrap.mjs` không đè file có sẵn — không bản nâng cấp nào được âm thầm
làm đỏ `init.sh` của một project đang chạy. Muốn nhận:

```bash
node bootstrap.mjs --target <project> --force   # ghi de init.sh, _TEMPLATE.md, scripts/
```

rồi thêm frontmatter + mục 9 vào các dossier đã có. Không làm gì thì project giữ nguyên hành vi 8 mục.
```

- [ ] **Step 3: Cập nhật các chỗ lẻ trong README**

- Dòng 26: `viết đủ 8 mục` → `viết đủ 9 mục`
- Cây thư mục (dòng 63-83): thêm `│   └── scripts/check-docs.mjs   # validator dossier — tach khoi init.sh`, sửa chú thích `_TEMPLATE.md` thành `# dossier 9 muc + frontmatter`
- Bảng subsystem (dòng 90): dòng `Verification` thêm `+ scripts/check-docs.mjs`
- Dòng 141 và 174: thay số assertion bằng con số đo được ở Step 1
- Dòng 143-144: mô tả `acceptance.sh` / `eval-faithfulness.sh` giữ nguyên

- [ ] **Step 4: Chạy toàn bộ test lần cuối**

```bash
bash tests/run-tests.sh
bash tests/test-verify-gate.sh
rm -rf /tmp/fx && EVAL_FIXTURE_DIR=/tmp/fx bash tests/eval-faithfulness.sh && (cd /tmp/fx/honest-pass && bash init.sh all; echo "exit=$?")
```

Expected: hai lệnh đầu `FAIL=0`; lệnh thứ ba `exit=0`.

- [ ] **Step 5: Kiểm bằng tay một project sạch**

```bash
D=$(mktemp -d) && node bootstrap.mjs --target "$D" --name "Smoke" --stack node >/dev/null
cd "$D"
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("feature_list.json","utf8"));j.features[0].status="done";j.features[0].tier="lite";delete j.features[0].doc;fs.writeFileSync("feature_list.json",JSON.stringify(j,null,2))'
bash init.sh docs; echo "lite exit=$?"     # mong: 0, in "tier lite — mien dossier"
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("feature_list.json","utf8"));j.features[0].tier="strict";fs.writeFileSync("feature_list.json",JSON.stringify(j,null,2))'
bash init.sh docs; echo "strict exit=$?"   # mong: 1, doi dossier
cd - && rm -rf "$D"
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs(readme): tier, dossier 9 muc + frontmatter, drift-lock, duong nang cap"
```

---

## Self-Review

**Spec coverage** — mọi mục của spec đều có task:

| Spec | Task |
|---|---|
| §3.1 data model | 1 |
| §3.2 tier đổi cái gì | 3 (CLAUDE.md), 6 (validator), 9 (checklist) |
| §3.3 + §3.4 luật chặn | 2 |
| §3.5 ai gán tier | 3 |
| §4.1 frontmatter + luật parser | 4 (schema), 6 (parser) |
| §4.2 mục 9 | 4 |
| §4.3 luật `check_docs` | 6 |
| §4.4 `reversible` không gate cứng | 6 (WARN), 8 (L3) |
| §5.1 + §5.2 thống nhất granularity | 9 |
| §5.3 assertion 2 vế | 10 |
| §6 15 files | 1-11 (16 files — thêm `template/scripts/check-docs.mjs`, xem ghi chú dưới) |
| §7 3 chunk | ranh giới Task 3/4 và Task 8/9 |
| §8 project cũ | 11 |
| §9 tiêu chí hoàn thành | 11 Step 4-5 |
| §10 rủi ro `honest-pass` | 7 |

**Sai lệch so với spec, có chủ ý:** spec §6 liệt kê 15 file và giữ `check_docs` inline trong `init.sh`.
Plan này tách ra `template/scripts/check-docs.mjs` (thành 16 file) — spec §10 đã cho phép trước
(*"nếu vượt mốc đó thì tách thành `scripts/check-docs.mjs`"*), và bản validator cuối dài ~110 dòng,
vượt mốc 80 dòng của spec. Lý do cứng hơn: `node -e '...'` bọc nháy đơn nên trong code **không dùng
được nháy đơn**, mà validator mới cần nhiều chuỗi có dấu nháy. `bootstrap.mjs` walk đệ quy nên file
mới được copy tự động, không phải sửa bootstrap.

**Placeholder scan:** không có TBD/TODO trong các bước. Mọi `<TODO: ...>` xuất hiện đều là **nội dung
template cố ý** — chúng là placeholder cho người dùng cuối và được `check-docs.mjs` chặn nếu còn sót
trong dossier thật.

**Type consistency:** `tierOf()` và `TIER_RANK` chỉ sống trong `verify-gate.js` (Task 2). `frontmatter()`,
`section()`, `RB_HOW`, `RB_LABELS` chỉ sống trong `check-docs.mjs` (Task 6). Không có hàm nào dùng chéo
hai file, nên không có bề mặt để lệch tên. Ba nhãn mục 9 là chuỗi khớp chính xác giữa `_TEMPLATE.md`
(Task 4), `check-docs.mjs` (Task 6) và fixture eval (Task 7) — đây là chỗ dễ lệch nhất trong cả plan;
cả ba đều dùng đúng `**Cách quay lại:**`, `**KHÔNG quay lại được:**`, `**Dấu hiệu cần rollback:**` có dấu.
