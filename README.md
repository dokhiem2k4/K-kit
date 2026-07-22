# harness-kit — bộ harness tái sử dụng cho coding-agent

Đóng gói workflow đã dùng ở **Deutsch Lernen** thành template dùng lại cho **mọi project sau**:
vibecode-kit (8 bước) + các phần bổ sung (SHIP/MONITOR, adversarial VERIFY, SECURITY STRIDE/OWASP,
DevEx, Diataxis docs, guardrails, multi-agent subagents). Chấm **100/100** trên `harness-creator` validator.

## Dùng nhanh (1 lệnh)
```bash
node "C:/Users/ADMIN/.claude/harness-kit/bootstrap.mjs" \
  --target "D:/dev/<PROJECT_DIR>" \
  --name "<Tên đề tài>" \
  --tagline "<mô tả 1 dòng>" \
  --stack "<tech stack>"
```
→ copy nguyên bộ harness vào project, thay hết token `{{...}}`. Không đè file có sẵn (trừ `--force`).
Thử trước: thêm `--dry-run`.

## Sau khi bootstrap — chỉnh cho khớp đề tài
Thứ tự đề xuất (đa số chỉ đổi tên/nội dung, cấu trúc giữ nguyên):
1. **Blueprint** — viết/trỏ tới `docs/specs/blueprint.md` (design đã duyệt). Nếu đã có spec, chạy lại bootstrap với `--blueprint <path>`.
2. **`feature_list.json`** — thay F01..F0x bằng feature thật (id/name/description/status bắt buộc; thêm scope/done_when/verify). `done_when` phải testable.
3. **`CLAUDE.md` → Invariants** — giữ cái áp dụng, thêm invariant đặc thù project.
4. **`.claude/workflow/security.md`** — điền attack surface thật vào bảng STRIDE + per-feature.
5. **`init.sh` → CONFIG** — sửa `CLIENT_DIRS` + lệnh build/test theo stack.
6. **`.claude/workflows/parallel-review.mjs` → LENSES** — chỉnh focus theo rủi ro thật (tùy chọn).
7. **Audit:** `node <harness-creator>/scripts/validate-harness.mjs --target <PROJECT_DIR>` → kỳ vọng 100/100.

## Cấu trúc bộ kit
```
harness-kit/
├── README.md                 # file này
├── bootstrap.mjs             # copy template + fill token
├── harness.config.example    # ví dụ giá trị token
└── template/                 # nội dung đổ vào project
    ├── CLAUDE.md             # instructions: startup, invariants, DoD, subagents
    ├── feature_list.json     # state: feature + deps + done_when
    ├── progress.md           # state: current + evidence
    ├── session-handoff.md    # lifecycle: resume xuyên phiên
    ├── init.sh               # verification: build/test + secret-leak grep
    └── .claude/
        ├── workflow/         # docs: pipeline, security, subagents
        └── workflows/        # runnable: adversarial-verify, parallel-review, parallel-build
```

## 5 subsystem (harness-creator model)
| Subsystem | File | Vai trò |
|---|---|---|
| Instructions | `CLAUDE.md` | startup path, invariants, definition of done |
| State | `feature_list.json`, `progress.md` | feature nào, done chưa, bằng chứng |
| Verification | `init.sh` | lệnh phải chạy trước khi done + secret grep |
| Scope | `feature_list.json` deps + done_when | chống overreach / nửa vời |
| Lifecycle | `session-handoff.md` + End-of-Session | phiên sau restart sạch |

## Multi-agent (opt-in)
3 workflow chạy được qua `Workflow` tool của Claude Code:
- `adversarial-verify` — refute từng `done_when` bằng subagent + judge (VERIFY).
- `parallel-review` — review diff nhiều lens, verify đối kháng (SHIP gate; thay second-opinion).
- `parallel-build` — build leaf độc lập trong worktree song song.
Chi tiết: `.claude/workflow/subagents.md`. Tốn token → chỉ fan-out khi đáng.

## Ghi chú
- Yêu cầu `node` (bootstrap) + `bash` (chạy `init.sh`; Windows dùng Git Bash).
- Template có anchor tiếng Anh (Startup Workflow / Definition of Done / ...) để qua validator; nội dung tiếng Việt.
- Đây là *harness*, không phải app scaffold — nó điều phối cách agent làm, không sinh code sản phẩm.
