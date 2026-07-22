# Session Handoff — {{PROJECT_NAME}}

> Đọc file này đầu phiên. Cập nhật cuối phiên trước khi dừng.

## Bối cảnh nhanh
- Blueprint: `{{BLUEPRINT_PATH}}`.
- Harness: `CLAUDE.md` (invariants), `feature_list.json` (state), `.claude/workflow/` (pipeline + security + subagents).
- Verify: `./init.sh <target>`.

## Đang ở đâu (restart markers)
- **Last Updated:** {{DATE}}.
- **Current Objective / Feature active:** F01 (chưa bắt đầu).
- **Recommended Next Step:** scaffold theo Blueprint → `./init.sh scaffold`.
- **Blockers:** _(keys/quyết định đợi Homeowner)_
- **Files:** harness files ở root + `.claude/`; chưa có file sản phẩm.

## Quyết định treo (cần Homeowner)
- _(liệt kê)_

## Next Session — cách tiếp tục (clean restart)
1. Đọc `progress.md` + file này.
2. Lấy `active_feature` từ `feature_list.json`, đọc `done_when`+`verify`.
3. Theo `.claude/workflow/pipeline.md`: BUILD → VERIFY(adversarial) → SECURITY → DevEx → SHIP.
4. Cập nhật state + bằng chứng vào `progress.md`; ghi bài học vào harness memory.
