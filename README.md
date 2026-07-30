# harness-kit — bộ harness tái sử dụng cho coding-agent

Đóng gói workflow đã dùng ở **Deutsch Lernen** thành template dùng lại cho **mọi project sau**:
vibecode-kit (8 bước) + các phần bổ sung (SHIP/MONITOR, adversarial VERIFY, SECURITY STRIDE/OWASP,
DevEx, Diataxis docs, guardrails, multi-agent subagents) — đóng gói thành plugin có skill auto-trigger.

## Dùng nhanh (1 lệnh)
```bash
node "<đường-dẫn>/harness-kit/bootstrap.mjs" \
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
7. **Dossier** — không phải điền trước. Mỗi lần ship xong một F, copy `docs/features/_TEMPLATE.md` thành `docs/features/<ID>-<slug>.md`, viết đủ 8 mục, trỏ field `doc` trong `feature_list.json`. `./init.sh docs` chặn ship nếu thiếu.
8. **Audit:** `bash tests/run-tests.sh` (cấu trúc) + `bash tests/acceptance.sh` (hành vi). Validator ngoài `harness-creator/scripts/validate-harness.mjs` **không nằm trong repo này** — chỉ chạy được nếu bạn có sẵn bộ đó.

## Auto-trigger — cài kit làm plugin (khuyến nghị)
Không có bước này thì harness chỉ là file nằm chờ: agent không đọc thì không có gì xảy ra.

**Cách 1 — plugin (đủ tính năng).** Thêm `harness-kit/` làm plugin của Claude Code. Khi đó:
- 9 skill trong `skills/` auto-trigger theo `description`, gọi bằng `harness-kit:<tên>`.
- `hooks/session-start` chạy đầu mỗi phiên. Nó **chỉ kích hoạt trong project thật sự có harness**
  (phải có cả `feature_list.json` lẫn `.claude/workflow/pipeline.md`) — repo khác thì im lặng thoát.
- Hook bơm vào đầu phiên: skill `using-harness` + **state thật** (active feature, status, `done_when`,
  dependency chưa xong, feature `done` mà thiếu field `doc`). Agent bắt đầu phiên đã biết mình ở đâu.

**Cách 2 — project-local (zero-install).** `node bootstrap.mjs ... --with-skills` copy `skills/` vào
`.claude/skills/`. Skill vẫn auto-trigger qua `description`, gọi bằng tên trần. **Yếu hơn:** không có
hook → không có bơm state đầu phiên.

Hook viết bằng bash; Windows chạy qua Git Bash.

## Cấu trúc bộ kit
```
harness-kit/
├── README.md                 # file này
├── bootstrap.mjs             # copy template + fill token (+ --with-skills)
├── harness.config.example    # ví dụ giá trị token
├── .claude-plugin/
│   └── plugin.json           # manifest — cài kit làm plugin
├── hooks/
│   ├── hooks.json            # đăng ký SessionStart
│   └── session-start         # bơm using-harness + state thật (chỉ trong project có harness)
├── skills/                   # 9 gate skill, mỗi cái có frontmatter description để auto-trigger
│   ├── using-harness/        #   meta: chọn gate skill nào + red flags chung
│   ├── harness-startup/      #   đầu phiên: đọc state theo thứ tự
│   ├── planning-features/    #   Blueprint -> feature_list.json, done_when testable
│   ├── building-a-feature/   #   scope, live testing, escalation L1/L2/L3
│   ├── debugging-a-feature/  #   test đỏ: scope, test tái hiện, dossier mục 8
│   ├── verifying-a-feature/  #   bằng chứng, refute pass, vòng fix có breaker
│   ├── security-gate/        #   STRIDE + OWASP, P0 chặn ship
│   ├── writing-feature-dossier/
│   └── shipping-a-feature/   #   SHIP checklist + MONITOR + End of Session
└── template/                 # nội dung đổ vào project
    ├── CLAUDE.md             # instructions: startup, invariants, DoD, subagents
    ├── feature_list.json     # state: feature + deps + done_when
    ├── progress.md           # state: current + evidence
    ├── session-handoff.md    # lifecycle: resume xuyên phiên
    ├── init.sh               # verification: build/test + secret-leak grep + check dossier
    ├── docs/features/
    │   └── _TEMPLATE.md      # dossier 8 mục — copy khi ship xong 1 feature
    └── .claude/
        ├── workflow/         # docs: pipeline, security, subagents
        └── workflows/        # runnable: adversarial-verify, parallel-review, parallel-build
```

## 5 subsystem (harness-creator model)
| Subsystem | File | Vai trò |
|---|---|---|
| Instructions | `CLAUDE.md` | startup path, invariants, definition of done |
| State | `feature_list.json`, `progress.md`, `docs/features/<ID>-<slug>.md` | feature nào, done chưa, bằng chứng, và **dossier** mô tả từng feature đã ship |
| Verification | `init.sh` | lệnh phải chạy trước khi done + secret grep + `docs` |
| Scope | `feature_list.json` deps + done_when | chống overreach / nửa vời |
| Lifecycle | `session-handoff.md` + End-of-Session | phiên sau restart sạch |

## Multi-agent (opt-in)
3 workflow chạy được qua `Workflow` tool của Claude Code:
- `adversarial-verify` — refute từng `done_when` bằng subagent + judge (VERIFY).
- `parallel-review` — review diff nhiều lens, verify đối kháng (SHIP gate; thay second-opinion).
- `parallel-build` — build leaf độc lập trong worktree song song.
Chi tiết: `.claude/workflow/subagents.md`. Tốn token → chỉ fan-out khi đáng.

## Hai tầng test
```bash
bash tests/run-tests.sh                          # cấu trúc — 121 assertion, không tốn token
bash tests/acceptance.sh                         # hành vi   — 5 phiên Claude Code thật, tốn token
ACCEPTANCE_MODEL=haiku bash tests/acceptance.sh  # cùng bộ probe trên model yếu hơn
```

`run-tests.sh` kiểm **cấu trúc**: file có tồn tại, frontmatter có đúng, `init.sh` có trả đúng exit code.
Nó không trả lời được câu hỏi quan trọng nhất — *agent có thật sự invoke skill không*.

`acceptance.sh` kiểm **hành vi**: bootstrap project tạm, mở phiên Claude Code thật qua
`--plugin-dir`, rồi đọc transcript xem skill nào được gọi.

| Probe | Prompt | Kỳ vọng |
|---|---|---|
| `resume` | "tiếp tục đi" | `harness-startup`, hook bơm state |
| `claim-done` | "F01 xong rồi, đánh done" | `verifying-a-feature` — không đánh done thẳng |
| `add-feature` | "thêm feature đổi avatar" | `planning-features` — không viết bừa vào JSON |
| `test-fails` | "npm test đang đỏ, sửa giúp tôi" | `debugging-a-feature` — không nhảy thẳng vào sửa |
| `no-harness` | "chào, đây là repo gì" | hook im, **không** invoke skill nào |

Sonnet 5/5, Haiku 5/5.

Bốn lỗi chỉ tầng test này bắt được — không lỗi nào lọt qua được 121 assertion cấu trúc:

1. `description` quá rộng kéo `harness-startup` vào repo không có harness. Vá bằng 2 hàng rào:
   điều kiện tiên quyết đặt ở **đầu** `description`, và `<PRECONDITION>` bail-out trong thân skill.
2. Fixture âm nằm **trong chính repo kit** — xung quanh đầy `skills/`, `template/feature_list.json`,
   nên agent gọi skill là hợp lý. Đo tay: trong repo kit 3/3 false-positive trên haiku, ngoài repo 0/5.
3. Probe `test-fails` chạy trên project **không có test nào** — "test đang đỏ" là tiền đề giả.
4. Probe `test-fails` dùng chung project với probe 2 và 3, mà cả hai đều **ghi** vào
   `feature_list.json` → kết quả phụ thuộc thứ tự chạy.

Ba cái sau là lỗi của **test**, không phải của skill. Fixture dùng chung không phải fixture.

Không có `claude` CLI → `acceptance.sh` in SKIP và exit 0; đó **không** phải pass.

## Ghi chú
- Yêu cầu `node` (bootstrap + `./init.sh docs`) + `bash` (chạy `init.sh`; Windows dùng Git Bash). Không có `node` thì `check_docs` in SKIP chứ không giả vờ pass.
- **`init.sh` phân biệt "script thiếu" với "script chạy rồi fail".** Trước đây `npm run lint || echo "(no lint script)"` gộp hai thứ đó làm một nên lint đỏ vẫn qua được gate. Giờ script thiếu → SKIP có đếm; script fail → `FAIL=1`. Dòng cuối in số check bị SKIP để một lần chạy toàn SKIP không đọc thành "all green".
- Template có anchor tiếng Anh (Startup Workflow / Definition of Done / ...) để qua validator; nội dung tiếng Việt.
- Đây là *harness*, không phải app scaffold — nó điều phối cách agent làm, không sinh code sản phẩm.
