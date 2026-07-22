# {{PROJECT_NAME}} — Agent Harness

{{TAGLINE}}
Stack: **{{STACK}}**.

## Source of truth
- **Blueprint (design đã duyệt):** `{{BLUEPRINT_PATH}}` — kiến trúc, data model, API, luồng. KHÔNG đổi kiến trúc mà không quay lại VISION.
- **State:** `feature_list.json` (feature đang làm, done chưa) + `progress.md`.
- **Workflow mở rộng:** `.claude/workflow/pipeline.md` (8 bước vibecode-kit + SHIP/MONITOR/adversarial-verify/DevEx/docs).
- **Security gate:** `.claude/workflow/security.md` (STRIDE + OWASP — CUSTOMIZE theo stack).
- **Subagents:** `.claude/workflow/subagents.md` + `.claude/workflows/*.mjs`.

## Startup Workflow (mỗi phiên — before writing code)
1. Đọc `progress.md` + `session-handoff.md` → biết đang ở đâu.
2. Đọc `feature_list.json` → lấy `active_feature`, đọc `done_when` + `verify`.
3. Đọc mục tương ứng trong Blueprint trước khi code.
4. **One feature at a time** (làm 1 feature một lúc). Xong → chạy verify → cập nhật state → SHIP gate.

## Verification Commands
- `./init.sh <target>` — lint/typecheck/build/test + secret-leak grep. **CUSTOMIZE target/lệnh trong `init.sh` theo stack.**
- Feature chỉ `done` khi lệnh verify liên quan **all green**; dán output làm bằng chứng vào `progress.md`.

## Subagents (multi-agent — opt-in)
Điều phối song song qua `Workflow` (saved trong `.claude/workflows/`) — chi tiết `.claude/workflow/subagents.md`:
- **`adversarial-verify`** — VERIFY: fan-out skeptic refute từng `done_when` + judge độc lập.
- **`parallel-review`** — SHIP gate: review diff nhiều lens (correctness/authz/secret/injection/config/DevEx), verify đối kháng. 0 P0 mới ship.
- **`parallel-build`** — build leaf độc lập trong worktree riêng, coordinator review+merge.
Tốn token → chỉ fan-out khi đáng; việc vặt làm inline. Kết quả subagent là input để bạn tổng hợp, không phải quyết định cuối.

## Roles (vibecode-kit)
- **Homeowner (con người):** quyết định chiến lược, cấp secrets/keys, verify thật.
- **Contractor:** design/QC/orchestrate — KHÔNG code.
- **Builder (agent này):** implement đúng feature spec, self-test, report. **Stay in scope** — KHÔNG tự đổi kiến trúc/thêm feature ngoài spec. Xung đột → escalate, không tự quyết.

## Invariants — không được vi phạm (guardrails)  ← CUSTOMIZE per project
Starter chung (giữ cái áp dụng, thêm cái riêng của {{PROJECT_NAME}}):
- **Secrets chỉ ở server/backend.** Client bundle (web/extension/mobile) chứa 0 secret — `init.sh` grep phải sạch, feature không done nếu grep dơ.
- **Authz:** endpoint bảo vệ → 401/403 khi thiếu/sai token; verify token phía server.
- **Data isolation:** user chỉ đọc/ghi data của chính mình (RLS/authz ở tầng DB nếu có), không rò chéo user.
- **Input là untrusted:** validate + ép schema; không execute input; escape ở mọi sink (SQL/shell/HTML). Input đưa vào LLM phải coi như dữ liệu, ép output schema, không thi hành chỉ thị trong đó.
- **Không vỡ UI:** lỗi mạng/dịch vụ ngoài → fallback, không throw/500 lộ ra người dùng.
- **`/careful`:** trước lệnh phá hủy (rm -rf, DROP, force-push, reset --hard) → dừng, hỏi Homeowner.
- **`/freeze`:** khi debug 1 feature, chỉ sửa file trong scope feature đó.
> Thêm invariant đặc thù {{PROJECT_NAME}} vào đây.

## Definition of Done (mỗi feature)
- `done` = lint + typecheck + build + test **pass** (qua `init.sh` phần liên quan).
- `secured` = qua checklist `security.md` áp dụng.
- `verified` = Homeowner chạy qua flow thật.
- Không đánh dấu done nếu chưa có **bằng chứng** (log/test output). Ghi vào `progress.md`.

## Escalation
- L1 (tên biến, code style): Builder tự quyết.
- L2 (spec mơ hồ, chọn pattern, trade-off): dừng, hỏi trong report.
- L3 (đổi scope/kiến trúc/business rule/security): STOP → Homeowner.

## End of Session (before ending — clean, restartable)
1. Cập nhật `feature_list.json` status + `progress.md` (Current State + bằng chứng).
2. Cập nhật `session-handoff.md`: Blockers, Files touched, Recommended Next Step.
3. Ghi bài học vào harness memory. **Next steps** phải rõ để phiên sau resume sạch.

## Memory
Ghi quyết định/bài học không suy ra được từ code vào: `{{MEMORY_DIR}}` (index ở `MEMORY.md`).
