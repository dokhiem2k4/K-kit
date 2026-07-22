# Pipeline mở rộng — {{PROJECT_NAME}} (vibecode-kit + gaps)

Nền là 8 bước vibecode-kit. Bổ sung phần vibecode-kit thiếu (đối chiếu gstack):
**adversarial VERIFY, SECURITY gate, DevEx review, SHIP, MONITOR, Diataxis docs, guardrails, memory**.

```
SCAN → RRI → VISION → BLUEPRINT ─┐  (design đã duyệt)
                                  ▼
   BUILD(6) → VERIFY(7) → SECURITY(7.5) → DEVEX(7.6) → REFINE(8) → SHIP(9) → MONITOR(10)
     │guardrails   │adversarial   │STRIDE/OWASP   │TTHW      │        │gate   │post-deploy
```

Với mỗi feature trong `feature_list.json`, đi qua BUILD→...→SHIP rồi mới sang feature kế.

---

## 6. BUILD — với guardrails
- Implement đúng `scope` + `done_when`. KHÔNG thêm ngoài scope. Xung đột spec → escalate L2/L3.
- **Live testing:** phần chạy được phải được *chạy thật* (curl endpoint, mở app, build ra artifact) — không chỉ đọc code.
- **`/freeze`:** khi sửa bug, chỉ sửa file thuộc feature đang làm.
- **`/careful`:** lệnh phá hủy → dừng, xác nhận Homeowner.
- **Atomic commit:** mỗi feature/bugfix = 1 commit gọn, message nêu lý do + feature id. Bugfix → kèm test tái hiện.

## 7. VERIFY — adversarial (thay self-review một chiều)
1. Chạy `init.sh` phần liên quan → all green, dán output vào `progress.md`.
2. **Refute pass (subagent):** saved workflow **`adversarial-verify`** — xem `subagents.md`. Truyền `done_when` qua `args.criteria`.
   Mỗi criterion → skeptic *cố refute* + judge reproduce. **≥1 `confirmedFailures` → chưa done**, quay lại BUILD.
   - Không opt-in Workflow → spawn `Agent` (Explore) thủ công cùng tinh thần.
3. **Requirement traceability:** mỗi REQ trong Blueprint phải map tới feature. Thiếu → Open Question.

## 7.5 SECURITY gate (CSO)
Chạy checklist `security.md` áp dụng cho feature. **Không SHIP nếu còn P0.**

## 7.6 DEVEX review
- **TTHW (time-to-hello-world):** clone → chạy được mất bao lâu? README + `.env.example` đủ chưa?
- **Friction map:** lỗi mơ hồ, thiếu script, bước thủ công ẩn → ghi + vá nếu rẻ.

## 8. REFINE
Được: sửa text/nội dung trong section có sẵn, fix issue VERIFY/SECURITY.
Không được (quay lại VISION): thêm feature, đổi layout lớn, đổi stack, thêm module. → L3.

## 9. SHIP — gate + docs
Chỉ ship khi:
- [ ] `init.sh` liên quan **all green**.
- [ ] `parallel-review` (subagent) — **0 P0 confirmed** trên diff.
- [ ] SECURITY gate pass; client bundle 0 secret.
- [ ] `feature_list.json` + `progress.md` cập nhật (có bằng chứng).
- [ ] **Feature dossier** `docs/features/<ID>-<slug>.md` viết xong, đủ 8 mục, `feature_list.json` có field `doc`, `./init.sh docs` **xanh**. Bắt đầu từ `docs/features/_TEMPLATE.md`.
- [ ] **Docs (Diataxis)** theo diff: *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (flow chính), *Explanation* (vì sao).
- Commit/PR nêu feature id + REQ đã cover; PR body liệt kê `done_when` đã pass.

**Lan tỏa:** nếu feature đang ship **đổi hành vi của một F cũ**, phải thêm một dòng có ngày vào **mục 8 (Cập nhật)** trong dossier của F cũ đó — làm ngay trong SHIP này, không để nợ. Dossier lệch với code còn tệ hơn không có dossier.

## 10. MONITOR — post-ship
- Health check sau deploy.
- Smoke test flow chính.
- Kiểm tra hạ tầng (DB advisors, logs, error rate).
- Ghi kết quả vào `progress.md`; hồi quy → mở feature fix mới, không sửa lén.

---

## Checkpoint gates (không bỏ qua)
- **BUILD→VERIFY:** status DONE/DEFERRED có lý do; không BLOCKED chưa resolve.
- **VERIFY→SECURITY:** adversarial refute pass; traceability đủ.
- **SECURITY→SHIP:** 0 P0 security; 0 secret trong bundle.
- **SHIP→next:** state cập nhật + bằng chứng + docs sync + **dossier feature đã ghi** (`./init.sh docs` xanh).

## Memory routine (mỗi cuối phiên)
Ghi vào harness memory những gì không suy ra được từ code: quyết định kiến trúc phát sinh, cạm bẫy đã gặp, trade-off. Cập nhật `session-handoff.md` trước khi dừng.
