# Design — Feature Dossier cho harness-kit

**Ngày:** 2026-07-23
**Trạng thái:** đã duyệt (chờ implementation plan)
**Phạm vi:** `harness-kit/template/*` + `README.md`

---

## 1. Vấn đề

Harness hiện ghi state ở `feature_list.json` (feature nào, done chưa) và `progress.md` (nhật ký + bằng chứng lệnh).
Cả hai đều **ngắn theo thiết kế**: chúng trả lời "đang ở đâu", không trả lời "F đó rốt cuộc là cái gì, làm sao nó chạy,
vì sao làm như vậy". Sau vài phiên, muốn hiểu lại một feature thì phải đọc lại code.

**Mục tiêu:** mỗi feature khi hoàn thành để lại đúng một file Markdown đọc-lại-được, phục vụ cả người lẫn agent phiên sau.

## 2. Quyết định đã chốt

| Câu hỏi | Chốt |
|---|---|
| Đối tượng đọc | **Một file gộp** — vừa mô tả cho người, vừa chi tiết nội tại cho agent |
| Thời điểm viết | **Tại SHIP gate** (bước 9 pipeline), sau khi VERIFY + SECURITY + DEVEX pass |
| Mức ép buộc | **Instruction + check cơ học trong `init.sh`** (không dựa vào trí nhớ agent) |
| Cách tra cứu | **Quy ước tên + field `doc` trong `feature_list.json`** — không có file index riêng |

**Cố ý KHÔNG làm (YAGNI):** không `docs/features/INDEX.md`; không script sinh skeleton;
không tách docs-người / docs-agent thành 2 file; không check độ mới (staleness) của dossier.

## 3. Quy ước file

- Đường dẫn: `docs/features/<ID>-<slug>.md` — ví dụ `docs/features/F01-scaffold.md`.
  `<ID>` khớp `id` trong `feature_list.json`; `<slug>` là kebab-case của `name`.
- Mỗi feature đúng **một** file. Không gộp nhiều F, không tách một F ra nhiều file.
- Template gốc: `docs/features/_TEMPLATE.md` (bootstrap copy sẵn vào project; không bị check quét vì tên bắt đầu bằng `_`).

## 4. Cấu trúc dossier — 8 mục cố định

Heading cấp 2, đúng thứ tự, **đúng chữ**. Mục không áp dụng thì ghi `—` chứ **không xoá heading**
(check cơ học bám vào heading).

Header đầu file:

```markdown
# F01 — Scaffold project

> **Status:** done · **Ngày:** 2026-07-23 · **Commit:** a1b2c3d · **Blueprint:** §2.1
```

(Trong `_TEMPLATE.md` các giá trị này là `<TODO: ...>`.)

| # | Heading | Trả lời | Cho ai |
|---|---|---|---|
| 1 | `## 1. Ý nghĩa với dự án` | Vai trò của F trong bức tranh chung; nó **unlock** gì (F nào dựa vào nó); không có nó thì dự án **thiếu** gì; cover REQ nào của Blueprint | cả hai |
| 2 | `## 2. Làm được gì` | Hành vi quan sát được: bấm/gọi gì thì ra gì | người |
| 3 | `## 3. Cách dùng` | Bước cụ thể / endpoint / màn hình / lệnh + ví dụ thật (request→response nếu là API) | người |
| 4 | `## 4. Bên trong` | Luồng chính A→B→C; **files touched** (path + vai trò 1 dòng); schema/bảng đụng tới; biến env/config cần | agent |
| 5 | `## 5. Quyết định & trade-off` | Chọn gì, bỏ gì, vì sao; cái gì **cố ý không làm** (out of scope) | cả hai |
| 6 | `## 6. Cạm bẫy khi sửa` | Chỗ dễ vỡ, invariant phải giữ, phụ thuộc ngầm | agent |
| 7 | `## 7. Bằng chứng` | Từng `done_when` → cách verify → kết quả; kết quả SECURITY gate. Output dài để ở `progress.md`, đây chỉ tóm tắt + trỏ | cả hai |
| 8 | `## 8. Cập nhật` | Dòng có ngày, ghi khi F sau đổi hành vi F này | cả hai |

**Ranh giới mục 1 vs mục 2** (ghi thẳng vào `_TEMPLATE.md` dạng chú thích để agent không viết trùng):
mục 1 **zoom out** — vai trò trong hệ thống; mục 2 **zoom in** — hành vi cụ thể.

Mục 1 tận dụng dữ liệu có sẵn trong `feature_list.json`: `dependencies` (F này cần gì) và chiều ngược lại
(F nào khai báo phụ thuộc nó) — agent điền được ngay, không phải suy đoán.

## 5. Ràng buộc — 6 chỗ sửa trong template

### 5.1 File mới: `template/docs/features/_TEMPLATE.md`
Skeleton 8 mục + header, kèm chú thích hướng dẫn ngắn dưới mỗi heading dưới dạng `<!-- ... -->`, và chỗ cần điền
đánh dấu `<TODO: ...>`. Bootstrap tự copy (`walk()` đã quét toàn bộ `template/`), không cần sửa `bootstrap.mjs`.

### 5.2 `template/init.sh` — target `docs`
- Thêm hàm `check_docs()`; thêm `docs` vào `case` và vào nhánh `all`.
- Parse `feature_list.json` bằng `node -e` (node vốn đã là yêu cầu của harness: bootstrap + `.claude/workflows/*.mjs`).
  Không có `node` → in `(khong co node — skip)`, **không** set FAIL và **không** in "OK" (không giả vờ pass).
- Luật: với mọi feature có `status ∈ {done, verified}`:
  1. có field `doc` (string, không rỗng);
  2. file `doc` tồn tại;
  3. chứa đủ 8 heading `## 1.` … `## 8.` đúng thứ tự;
  4. không còn placeholder chưa điền. Marker placeholder là **`<TODO:` … `>`** (do `_TEMPLATE.md` quy định) —
     check grep đúng chuỗi `<TODO:`, không grep `<...>` chung chung để tránh báo nhầm code snippet / thẻ HTML.
     Chú thích hướng dẫn trong template dùng `<!-- ... -->` và cũng bị tính là chưa điền nếu còn sót.
- Vi phạm bất kỳ → in `[FAIL]` kèm feature id + lý do, `FAIL=1`.
- Feature `pending / in_progress / blocked / deferred` → bỏ qua (chưa cần dossier).

### 5.3 `template/CLAUDE.md`
- **Source of truth:** thêm dòng trỏ `docs/features/<ID>-<slug>.md` — "hồ sơ từng feature đã xong; đọc trước khi sửa F cũ".
- **Definition of Done:** thêm bậc `documented` = có dossier đủ 8 mục, `./init.sh docs` xanh.
- **Startup Workflow:** bước đọc state → nếu sắp sửa một F đã done, đọc dossier của nó trước.
- **End of Session:** nhắc dossier nằm trong state phải cập nhật.

### 5.4 `template/.claude/workflow/pipeline.md`
- Mục **9. SHIP** — thêm checkbox bắt buộc:
  `[ ] Feature dossier docs/features/<ID>-<slug>.md đầy đủ 8 mục; ./init.sh docs xanh; feature_list.json có field doc.`
- Thêm luật lan tỏa: **F mới đổi hành vi F cũ → phải thêm dòng vào mục 8 (Cập nhật) của dossier F cũ**, ngay trong SHIP của F mới.
- Mục **Checkpoint gates** — `SHIP→next` bổ sung "dossier đã ghi".

### 5.5 `template/feature_list.json`
- Ba feature mẫu F01/F02/F03 thêm field `"doc"` với đường dẫn theo quy ước.
- `_howto` bổ sung: `doc` = đường dẫn dossier, bắt buộc khi status done/verified; `init.sh docs` sẽ check.

### 5.6 `README.md` (harness-kit)
- Cây "Cấu trúc bộ kit": thêm `docs/features/_TEMPLATE.md`.
- Bảng "5 subsystem": dossier thuộc **State** (cùng `feature_list.json`, `progress.md`).
- Mục "Sau khi bootstrap": nhắc dossier sinh dần khi ship từng F, không phải điền trước.

## 6. Tiêu chí hoàn thành

- [ ] `_TEMPLATE.md` tồn tại, đủ 8 mục, có chú thích ranh giới mục 1 vs mục 2.
- [ ] `./init.sh docs` **FAIL** khi một feature `done` thiếu `doc` / thiếu file / thiếu heading / còn placeholder.
- [ ] `./init.sh docs` **PASS** khi mọi feature `done` có dossier hợp lệ, và khi chưa feature nào `done`.
- [ ] `./init.sh all` chạy được `check_docs` và không vỡ các check cũ.
- [ ] `node bootstrap.mjs --dry-run` liệt kê `docs/features/_TEMPLATE.md`.
- [ ] Bootstrap vào thư mục trống → `docs/features/_TEMPLATE.md` có mặt, token `{{...}}` đã thay hết.
- [ ] `validate-harness.mjs` vẫn **100/100**.
- [ ] `README.md` + `CLAUDE.md` + `pipeline.md` + `feature_list.json` mô tả nhất quán cùng một quy ước.

## 7. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| Target project không có `node` → check im lặng bỏ qua | In rõ dòng skip, không in "OK"; ghi trong `README.md` rằng node là yêu cầu của harness |
| Agent viết dossier hình thức, đủ heading nhưng rỗng nghĩa | Check bắt marker `<TODO:` và `<!-- -->` còn sót; chất lượng nội dung do SHIP gate người duyệt |
| Dossier lệch với code sau vài F | Luật mục 8 (Cập nhật) trong pipeline; cố ý không làm staleness check (YAGNI) |
| Mục 1 và mục 2 viết trùng nhau | Chú thích ranh giới zoom-out/zoom-in ngay trong `_TEMPLATE.md` |
