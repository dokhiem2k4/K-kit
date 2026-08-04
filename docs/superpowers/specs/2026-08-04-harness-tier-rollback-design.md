# Design — Tier, Rollback, Frontmatter, Drift-lock cho harness-kit

**Ngày:** 2026-08-04
**Trạng thái:** đã duyệt (chờ implementation plan)
**Phạm vi:** `hooks/verify-gate.js`, `template/*`, `skills/*`, `tests/*`, `README.md`

---

## 1. Vấn đề

Bốn hạn chế còn lại sau khi đối chiếu bản phân tích với implementation thật:

1. **Không có rollback strategy.** Grep toàn repo cho `rollback|recovery|revert strategy`: 0 kết quả.
   Đường xử lý duy nhất là forward-fix (`pipeline.md:58` — "hồi quy → mở feature fix mới").
   Forward-fix chữa được code, không chữa được migration đã chạy, data đã ghi đè, webhook đã bắn.
2. **Không phân cấp workflow.** Sửa typo và thay đổi authentication đi qua cùng 7 gate, cùng dossier 8 mục.
3. **Dossier không có metadata cấu trúc.** Dòng `_TEMPLATE.md:3` (`> **Status:** … · **Ngày:** …`)
   đã trùng lặp `status` với `feature_list.json` từ trước, nhưng phi cấu trúc nên không ai kiểm được.
4. **SHIP checklist trùng lặp, không có gì khoá.** Và nó **đã lệch sẵn** — xem §5.

**Ba nhận xét ban đầu đã bị bác sau khi đối chiếu code, ghi lại để không quay lại bàn:**

| Nhận xét | Vì sao không đúng |
|---|---|
| "Tài liệu quá lớn" | Runtime chỉ nạp `CLAUDE.md` (86 dòng) + đúng 1 skill (57–120 dòng). README không vào context agent. |
| "Thiếu dependency management" | `feature_list.json` đã có `dependencies`; `hooks/session-start:51-55` chặn feature có dep chưa xong. |
| "Agent phải tự nhớ quy trình" | `hooks/session-start` bơm state; `hooks/verify-gate` chặn ghi `done` không bằng chứng. Còn hở: `progress.md`, `session-handoff.md`. |

## 2. Quyết định đã chốt

| Câu hỏi | Chốt | Lý do |
|---|---|---|
| Ai gán `tier` | **Homeowner gán, agent chỉ được nâng** | Tái dùng cơ chế sẵn có (`verify-gate` chặn ghi vào `feature_list.json`) thay vì phát minh cơ chế mới |
| Tier bỏ qua gate nào | **Không bao giờ bỏ verify.** Chỉ đổi chi phí dossier + review | Giữ tier là thứ **có thể gán sai mà hệ thống vẫn an toàn**; hợp đồng `VERIFY OK` không đổi một chữ |
| Rollback sống ở đâu | **Mục 9 của dossier, nối cuối.** `Cập nhật` giữ nguyên mục 8 | Trong harness-kit, thứ gì không có validator thì không tồn tại |
| Frontmatter chứa gì | **Thay dòng metadata cũ.** 3 field mirror có gate + 5 field dossier-owned | Không tăng trùng lặp so với hiện tại, mà lần đầu kiểm được |
| Chống drift bằng gì | **Assertion 2 vế (coverage + chốt đếm)**, không generate | Repo đã có tiền lệ đúng dạng: hợp đồng `VERIFY OK` giữ bằng assertion |

**Cố ý KHÔNG làm (YAGNI):**

- `required_by` — suy ngược được từ `dependencies`; thêm field là tạo state lệch.
- Mục "Impact Analysis" riêng — mục 1, 4, 6 đã phủ phần lớn.
- Suy `tier` từ diff — đẩy phần khó nhất vào `init.sh`, file người dùng buộc phải customize.
- Sinh frontmatter tự động — `init.sh` phải thuần đọc-và-phán, không được sửa thứ nó đang chấm.
- Rollback tự động hoá (script revert, health-check gate) — harness điều phối agent, không chạy hạ tầng.

## 3. Tier

### 3.1 Data model

Field mới trong mỗi feature của `feature_list.json`:

```json
{ "id": "F03", "name": "Auth", "tier": "strict", "status": "pending" }
```

Thang: `lite` < `standard` < `strict`. **Vắng mặt = `standard`** — project đã bootstrap không cần đụng gì.

### 3.2 Tier đổi cái gì

| | `lite` | `standard` | `strict` |
|---|---|---|---|
| `init.sh` liên quan + secret grep | ✅ | ✅ | ✅ |
| Dossier | ❌ (một dòng bằng chứng trong `progress.md`) | ✅ 9 mục | ✅ 9 mục |
| Mục 9 Rollback | — | được ghi `—` | **phải có nội dung thật** |
| `parallel-review` | ❌ | tuỳ | ✅ |
| Security checklist | rút gọn (secret grep) | phần liên quan | full STRIDE |

Hàng đầu là bất biến: verify chạy ở mọi tier. Hệ quả cơ học — `verify-gate` **không cần biết `tier` tồn tại**
cho luật `status`, và không có nhánh "lite thì cho qua không cần marker". Nếu `lite` được miễn verify thì
feature `lite` sẽ không bao giờ có marker, buộc phải dạy gate một ngoại lệ, và ngoại lệ đó chính là
đường lách mà cả kiến trúc này sinh ra để bịt.

### 3.3 Luật chặn — khác loại với luật `status`

Luật `status` là *có điều kiện* (chặn khi thiếu marker) và **fail-open** khi hợp đồng vỡ
(`verify-gate.js:108-122`), vì lúc đó không tồn tại đường nào để agent thoả mãn gate.

Luật `tier` không có tính chất đó — luôn tồn tại đường hợp lệ (không hạ tier, hoặc hỏi Homeowner):

> **Chặn nếu tier kết quả của bất kỳ feature nào thấp hơn tier trước đó**, với "trước đó" = tier trên đĩa,
> hoặc `standard` nếu feature chưa tồn tại. **Không phụ thuộc marker. Không fail-open.**

Hệ quả có chủ ý:

- Agent tạo feature mới thì **không viết `tier`** → rơi về `standard`.
- Viết `"tier": "lite"` cho feature mới **bị chặn** (thấp hơn default).
- Nâng lên `strict` **luôn được phép** — agent có đúng một chiều tự do, chiều làm quy trình chặt hơn.
- Đặt `lite` là miễn trừ, và miễn trừ phải có chữ ký người: Homeowner tự sửa file.

### 3.4 Cách tính "tier kết quả" trong hook

Trong nhánh `pre-edit` của `hooks/verify-gate.js`, sau khối kiểm `status` hiện có:

- `Write` → lấy `tool_input.content`.
- `Edit` → đọc file trên đĩa, thay `old_string` bằng `new_string`.
- `MultiEdit` → áp lần lượt các `edits` theo thứ tự.

Parse JSON cả hai bên, so từng `id`. Parse hỏng → **không cho qua** (theo tiền lệ `verify-gate.js:101`).

### 3.5 Ai gán tier

`skills/planning-features` được sửa để hỏi Homeowner tier khi tạo feature và ghi kết quả.
Vì gate chặn mọi giá trị dưới `standard`, câu trả lời `lite` phải do người tự tay sửa file.

## 4. Dossier — frontmatter + mục 9

### 4.1 Frontmatter

Thay dòng blockquote `_TEMPLATE.md:3` bằng:

```yaml
---
feature: F03          # mirror — phải khớp feature_list.json
status: done          # mirror
tier: strict          # mirror
date: 2026-08-04      # dossier-owned
commit: a1b2c3d       # dossier-owned
blueprint: "§4.2"     # dossier-owned
security: passed      # dossier-owned
reversible: false     # dossier-owned — nối với mục 9
---
```

Parser: YAML **phẳng** tự viết trong `check_docs` — chỉ `key: value`, không nested, không list.
Khoảng 10 dòng node. Không thêm dependency; harness-kit vẫn chỉ cần `node` + `bash`.

Luật parser, chốt rõ để implementation không phải đoán:

- Frontmatter phải là khối đầu tiên của file, mở và đóng bằng đúng một dòng `---`.
- Mỗi dòng dạng `key: value`. Bỏ qua dòng trống và dòng bắt đầu bằng `#`.
- Cắt bỏ phần sau ` #` (dấu thăng có khoảng trắng đứng trước) — comment cuối dòng.
  Các comment `# mirror` trong ví dụ trên là chú giải của spec này; `_TEMPLATE.md` ship **không** có chúng.
- Giá trị được trim, bỏ cặp nháy bao ngoài nếu có. Không parse kiểu — `reversible: false` so sánh
  bằng chuỗi `"false"`.
- Thiếu khối frontmatter, hoặc thiếu một trong ba field mirror → FAIL.

Frontmatter dùng `---` nên không đụng hai luật quét sẵn có: quét `## N.` theo dòng, và luật cấm `<!--`.

### 4.2 Mục 9

```markdown
## 9. Rollback & Recovery

**Cách quay lại:** <lệnh/bước cụ thể — revert commit nào, hạ version nào, tắt flag nào>

**KHÔNG quay lại được:** <migration đã chạy, data đã ghi đè, webhook/email đã bắn, cache bên thứ ba — hoặc "—">

**Dấu hiệu cần rollback:** <triệu chứng quan sát được, ngưỡng cụ thể — hoặc "—">
```

Dòng giữa là lý do mục này tồn tại. Nó là thứ duy nhất forward-fix không thay thế được,
và là thứ người ta chỉ nghĩ ra khi bị bắt viết.

### 4.3 Luật mới trong `check_docs`

| Điều kiện | Hành vi |
|---|---|
| `tier: lite` + status `done`/`verified` | **bỏ qua hoàn toàn** — không đòi field `doc`, không quét dossier |
| còn lại | dossier đủ **9 mục** đúng thứ tự, hết placeholder `<TODO:`, hết `<!--` (giữ luật cũ) |
| mọi dossier bị quét | frontmatter parse được; `feature`/`status`/`tier` khớp `feature_list.json` |
| `tier: strict` | mục 9 có nội dung thật — xem luật dưới |
| `tier: strict` + `reversible: false` | **in cảnh báo, KHÔNG fail** — xem §4.4 |

**Luật "nội dung thật" cho mục 9 (chỉ áp dụng `tier: strict`).** Validator bám vào ba nhãn in đậm
cố định — cùng cách nó đang bám vào heading `## N.`:

- Thân mục 9 phải có đủ ba dòng bắt đầu bằng `**Cách quay lại:**`, `**KHÔNG quay lại được:**`,
  `**Dấu hiệu cần rollback:**`. Thiếu nhãn nào → FAIL.
- Riêng `**Cách quay lại:**` phải có nội dung sau dấu hai chấm và nội dung đó **không được là `—`**.
- Hai nhãn còn lại được phép ghi `—` (không phải feature nào cũng có phần không-hoàn-tác-được).

Với `tier: standard`, chỉ cần heading `## 9.` tồn tại — thân mục được phép ghi `—`.

### 4.4 Vì sao `reversible` không phải gate cứng

`reversible` là field **do agent tự khai**. Biến nó thành thứ chặn ship chỉ dạy agent viết `reversible: true`.
Một field tự khai không được phép làm gate cho chính nó — đó đúng là nguyên tắc `verify-gate` đang áp dụng
khi nó đọc output `init.sh` chứ không đọc lời agent nói.

Nên tách làm hai tầng:

- `init.sh` **in cảnh báo** khi gặp `strict` + `reversible: false`, không fail.
- `skills/shipping-a-feature` coi tổ hợp đó là **escalation L3** — dừng, hỏi Homeowner.

Giá trị thật của field là lúc sự cố: trả lời "feature nào không revert được" bằng một lệnh grep.

## 5. Drift-lock cho SHIP checklist

### 5.1 Hiện trạng — đã lệch sẵn

SHIP checklist chỉ có **hai** bản, không phải ba:

- `pipeline.md:42-50` — 6 ô `- [ ]`
- `skills/shipping-a-feature/SKILL.md:18-25` — 8 ô `- [ ]`
- `CLAUDE.md:68-73` — **không phải** checklist SHIP mà là *Definition of Done* ở granularity khác

Hai bản kia đã lệch: skill tách "SECURITY gate" với "client bundle 0 secret" thành hai ô, pipeline gộp làm một.
Drift đã xảy ra rồi, chỉ chưa ai thấy. **Phải thống nhất granularity trước, khoá sau** — không thống nhất
thì không có gì để đếm.

### 5.2 Danh sách chuẩn — 8 mục

Lấy granularity của skill (mịn hơn) làm chuẩn, sửa `pipeline.md` §9 cho khớp:

| key | khái niệm |
|---|---|
| `verify` | `./init.sh` phần liên quan all green |
| `review` | review diff đã chạy, 0 P0 confirmed |
| `security` | SECURITY gate pass |
| `secret` | client bundle 0 secret |
| `state` | `feature_list.json` + `progress.md` cập nhật |
| `dossier` | dossier đủ 9 mục, `./init.sh docs` xanh |
| `docs` | Docs theo diff (Diataxis) |
| `commit` | commit/PR nêu feature id + REQ |

Checklist giữ nguyên **8 ô ở mọi tier** — số ô là hằng số để chốt đếm ở §5.3 có nghĩa.
Tier đổi *cách tick*, không đổi *số ô*: với `lite`, ô `dossier` được tick bằng dòng bằng chứng trong
`progress.md` thay vì file dossier, và ô `review` được tick bằng "không áp dụng ở tier này".
Cả hai đều phải ghi rõ lý do khi tick — `lite` không phải giấy phép bỏ trống.

### 5.3 Assertion — hai vế

Trong `tests/run-tests.sh`, một mảng 8 dòng `key|regex`, rồi:

1. **Coverage** — mỗi regex khớp trong **cả hai** file. Bắt "thêm mục vào một nơi, quên nơi kia".
2. **Chốt đếm** — số dòng `- [ ]` trong mỗi file đúng bằng 8. Bắt "thêm mục mà không khai vào mảng chuẩn".

Vế 2 là vế có răng. Coverage kiểm *"cái tôi biết thì có mặt"*; chốt đếm kiểm *"không có cái tôi không biết"*.

`CLAUDE.md` nằm ngoài vòng khoá (artifact khác). Chỉ thêm một assertion lẻ: dòng `documented` trong
Definition of Done phải nhắc **9 mục**.

## 6. Files phải sửa — 15

**Cơ chế (4)**

| File | Việc |
|---|---|
| `hooks/verify-gate.js` | luật hạ-tier trong nhánh `pre-edit` (§3.3, §3.4) |
| `template/init.sh` | viết lại `check_docs`: tier-aware, frontmatter, 9 mục, cảnh báo `reversible` |
| `template/feature_list.json` | field `tier` ở 3 feature mẫu + `legend` + `_howto` |
| `template/docs/features/_TEMPLATE.md` | frontmatter thay dòng 3 + mục 9 |

**Instructions (6)**

| File | Việc |
|---|---|
| `template/CLAUDE.md` | bảng tier; DoD `documented` → 9 mục; nhắc mục 9 |
| `template/.claude/workflow/pipeline.md` | §9 thống nhất lên 8 ô; ghi chú tier; bước rollback trong MONITOR |
| `skills/planning-features` | hỏi Homeowner tier khi tạo feature |
| `skills/shipping-a-feature` | 9 mục; checklist theo tier; `reversible: false` → L3 |
| `skills/writing-feature-dossier` | frontmatter + mục 9 |
| `README.md` | tier, rollback, frontmatter, drift-lock; "8 mục" → "9 mục"; số assertion mới; mục nâng cấp project cũ |

**Tests (3)**

| File | Việc |
|---|---|
| `tests/run-tests.sh` | fixture `valid_dossier()` thêm frontmatter + mục 9; "8 muc" → 9; assertion tier (lite bỏ qua, mirror lệch → fail, strict + mục 9 rỗng → fail); assertion drift 2 vế; `_TEMPLATE.md` có frontmatter + 9 mục |
| `tests/test-verify-gate.sh` | tier hạ qua `Write` → deny; hạ qua `Edit` → deny; feature mới đặt `lite` → deny; nâng `strict` → allow; không phụ thuộc marker |
| `tests/eval-faithfulness.sh` | fixture `honest-pass` cập nhật theo định nghĩa dossier mới |

**Không đụng:** `tests/acceptance.sh` (feature fixture không có `tier` → rơi về `standard`, hành vi như cũ),
`bootstrap.mjs` (giữ thuần copy + thay token).

## 7. Thứ tự implementation — 3 chunk

Bốn điểm không tách được thành bốn phần độc lập: **rollback và frontmatter dính nhau** qua `reversible`,
và cả hai được kiểm bởi cùng một lần viết lại `check_docs`. Tách ra thì phải sửa `check_docs` hai lần.

| Chunk | Nội dung | Phụ thuộc |
|---|---|---|
| **1. Tier** | field + default `standard` + luật hạ-tier + `planning-features` | — |
| **2. Dossier schema** | frontmatter + mục 9 + `check_docs` tier-aware + `_TEMPLATE.md` | `tier` từ chunk 1 |
| **3. Drift lock** | thống nhất `pipeline.md` §9 + assertion 2 vế | "9 mục" chốt từ chunk 2 |

Mỗi chunk kết thúc ở trạng thái xanh và ship được độc lập.

## 8. Project đã bootstrap trước đó

Không tự động nhận gì — `bootstrap.mjs` không đè file có sẵn. Đó là hành vi đúng: không bản nâng cấp nào
được âm thầm làm đỏ `init.sh` của một project đang chạy.

README thêm mục ngắn về đường nâng cấp thủ công: chạy lại bootstrap với `--force` cho riêng `init.sh` và
`_TEMPLATE.md`, rồi thêm frontmatter + mục 9 vào các dossier đã có. Ai không làm gì thì giữ nguyên hành vi 8 mục.

## 9. Tiêu chí hoàn thành

- [ ] `bash tests/run-tests.sh` xanh, số assertion tăng đúng bằng số assertion mới thêm.
- [ ] `bash tests/test-verify-gate.sh` xanh, có đủ 4 case tier.
- [ ] `bash tests/eval-faithfulness.sh` — `honest-pass` vẫn xanh trên cả Sonnet lẫn Haiku.
- [ ] `bash tests/acceptance.sh` — 5/5 không đổi.
- [ ] Bootstrap một project sạch → feature `lite` `done` không đòi dossier; feature `strict` `done` thiếu mục 9 → `./init.sh docs` đỏ.
- [ ] Agent thử hạ tier `strict` → `lite` bị `verify-gate` từ chối, kể cả khi đang có marker.

## 10. Rủi ro

**`eval-faithfulness.sh` probe `honest-pass`.** Đây là control **bắt buộc phải xanh** — không có nó,
một skill chỉ biết từ chối mọi thứ vẫn đạt 100%. Nó xanh nhờ fixture khớp định nghĩa "dossier hợp lệ" hiện tại,
và chunk 2 đổi định nghĩa đó. Fixture phải sửa **trong cùng chunk 2**, không để sang chunk sau — nếu không,
con số "Sonnet 5/5, Haiku 5/5" ở README thành sai mà không ai chạy lại để biết.

**Tier trở thành từ khoá mới cho agent lách.** Giảm thiểu bằng thiết kế: agent chỉ nâng được, không hạ được,
và dù gán sai tier thì `init.sh` vẫn chạy đủ. Thiệt hại tối đa của một tier sai là tài liệu mỏng,
không phải code chưa kiểm.

**`check_docs` phình to.** Nó đang là ~30 dòng node inline trong `init.sh`; thêm parser frontmatter,
nhánh tier và kiểm mục 9 sẽ đẩy lên ~80 dòng. Chấp nhận được, nhưng nếu vượt mốc đó thì tách thành
`scripts/check-docs.mjs` — cùng lý do `verify-gate.js` từng được tách khỏi hook bash.
