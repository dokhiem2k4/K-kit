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
