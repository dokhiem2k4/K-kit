# {{PROJECT_NAME}} — Agent Harness

{{TAGLINE}}
Stack: **{{STACK}}**.

## Source of truth
- **Blueprint (design đã duyệt):** `{{BLUEPRINT_PATH}}` — kiến trúc, data model, API, luồng. KHÔNG đổi kiến trúc mà không quay lại VISION.
- **State:** `feature_list.json` (feature đang làm, done chưa) + `progress.md`.
- **Feature dossier:** `docs/features/<ID>-<slug>.md` — hồ sơ từng feature đã ship (8 mục: ý nghĩa với dự án, làm được gì, cách dùng, bên trong, quyết định, cạm bẫy, bằng chứng, cập nhật). Đường dẫn nằm ở field `doc` trong `feature_list.json`. Template: `docs/features/_TEMPLATE.md`.
- **Workflow mở rộng:** `.claude/workflow/pipeline.md` (8 bước vibecode-kit + SHIP/MONITOR/adversarial-verify/DevEx/docs).
- **Security gate:** `.claude/workflow/security.md` (STRIDE + OWASP — CUSTOMIZE theo stack).
- **Subagents:** `.claude/workflow/subagents.md` + `.claude/workflows/*.mjs`.

## Gate skills (auto-trigger — dùng qua tool `Skill`)
Harness này đi kèm skill cho từng gate của pipeline. **Invoke skill trước khi hành động**, đừng dựa trí nhớ:

| Thời điểm | Skill |
|---|---|
| Bắt đầu phiên / resume / không rõ đang ở đâu | `harness-startup` |
| Sắp viết code cho một feature | `building-a-feature` |
| Nghĩ là feature xong, sắp đánh `done` | `verifying-a-feature` |
| Trước SHIP, hoặc chạm auth/data/secret/input | `security-gate` |
| Viết hồ sơ feature vừa ship | `writing-feature-dossier` |
| SHIP gate + End of Session | `shipping-a-feature` |

Cài harness-kit làm plugin → tên có tiền tố `harness-kit:` và SessionStart hook tự bơm state thật vào đầu phiên.
Bootstrap bằng `--with-skills` → skill nằm ở `.claude/skills/`, gọi bằng tên trần.
Không có skill (chưa cài, chưa copy) → phần dưới của file này là bản rút gọn, vẫn phải theo.

## Startup Workflow (mỗi phiên — before writing code)
1. Đọc `progress.md` + `session-handoff.md` → biết đang ở đâu.
2. Đọc `feature_list.json` → lấy `active_feature`, đọc `done_when` + `verify`.
3. Đọc mục tương ứng trong Blueprint trước khi code.
4. **Sắp sửa một feature đã `done`?** Đọc dossier của nó (`doc` trong `feature_list.json`) TRƯỚC khi đụng code — mục 4 (bên trong) và mục 6 (cạm bẫy) tiết kiệm cả phiên dò lại.
5. **One feature at a time** (làm 1 feature một lúc). Xong → chạy verify → cập nhật state → viết dossier → SHIP gate.

## Verification Commands
- `./init.sh <target>` — lint/typecheck/build/test + secret-leak grep. **CUSTOMIZE target/lệnh trong `init.sh` theo stack.**
- **SKIP không phải pass.** `init.sh` đếm số check không chạy được và in ra ở dòng cuối. Một lần chạy toàn SKIP vẫn exit 0 — dán nó vào `progress.md` như bằng chứng "all green" là gian lận. Trước khi đánh `done`: làm cho check đó chạy được, hoặc chạy tay và dán output.
- `./init.sh docs` — mọi feature `done`/`verified` phải có dossier hợp lệ (đủ 8 mục, đúng thứ tự, hết placeholder). Nằm trong `./init.sh all`.
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
- `documented` = có dossier `docs/features/<ID>-<slug>.md` đủ 8 mục, field `doc` đã trỏ đúng, `./init.sh docs` xanh.
- `verified` = Homeowner chạy qua flow thật.
- Không đánh dấu done nếu chưa có **bằng chứng** (log/test output). Ghi vào `progress.md`.

## Escalation
- L1 (tên biến, code style): Builder tự quyết.
- L2 (spec mơ hồ, chọn pattern, trade-off): dừng, hỏi trong report.
- L3 (đổi scope/kiến trúc/business rule/security): STOP → Homeowner.

## End of Session (before ending — clean, restartable)
1. Cập nhật `feature_list.json` status + `doc` + `progress.md` (Current State + bằng chứng). Feature nào vừa ship → dossier đã viết xong.
2. Cập nhật `session-handoff.md`: Blockers, Files touched, Recommended Next Step.
3. Ghi bài học vào harness memory. **Next steps** phải rõ để phiên sau resume sạch.

## Memory
Ghi quyết định/bài học không suy ra được từ code vào: `{{MEMORY_DIR}}` (index ở `MEMORY.md`).
