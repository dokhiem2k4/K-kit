# Subagents — multi-agent playbook — {{PROJECT_NAME}}

Claude Code có `Agent` (subagent, fresh context) + `Workflow` (script điều phối deterministic, có
`isolation:'worktree'` cho builders song song).

## Opt-in & cost
- `Workflow` **chỉ chạy khi Homeowner opt-in**.
- Mỗi fan-out tốn token → chỉ dùng khi đáng (verify feature nặng, review diff lớn, build nhiều leaf độc lập). Việc vặt → inline.

## 3 pattern
| Pattern | Context | Dùng cho | Ràng buộc |
|---|---|---|---|
| **Coordinator** | Worker fresh (zero inherit) | verify/review/research nhiều pha | An toàn nhất; prompt self-contained |
| **Fork/worktree** | Worktree riêng | build leaf độc lập song song | **1 cấp** — worker không fork tiếp; coordinator merge |
| **Swarm** | Task list chung | workstream dài, độc lập | Flat roster |

**Luật vàng:** coordinator **tổng hợp rồi mới giao**, không "based on your findings". Worker: prompt tự chứa + tool tối thiểu (`Explore` verify/read, `general-purpose` build).

## Saved workflows (gọi bằng tên)

### 1. `adversarial-verify` — VERIFY (thay self-review một chiều)
Đọc `feature_list.json`, lấy `done_when` của feature + security check áp dụng, truyền qua `args`:
```
Workflow({ name:'adversarial-verify', args:{
  featureId:'F0X',
  criteria:[ "...", "..." ],            // tu done_when
  securityChecks:[ "..." ],             // tu security.md
  context:'note them (optional)'
}})
```
- Mỗi criterion → skeptic *cố refute* (đọc repo thật) → judge reproduce độc lập.
- Trả `confirmedFailures[]`. **≥1 → chưa done**, quay lại BUILD.

### 2. `parallel-review` — SHIP gate (thay cross-model second-opinion)
```
Workflow({ name:'parallel-review' })   // khong can args; subagent tu chay git diff
```
- Lens song song: correctness / authz / secret-leak / injection / config / devex.
- Mỗi finding → verify đối kháng mới sống. Trả `confirmed[]` sort P0→P2. **P0 confirmed → không SHIP.**

### 3. `parallel-build` — BUILD leaf độc lập (fork/worktree)
Chỉ cho sub-task **thực sự độc lập** (không chung lib/schema).
```
Workflow({ name:'parallel-build', args:{ featureId:'F0X', tasks:[
  { id:'a', spec:'...', files:['path/a'] },
  { id:'b', spec:'...', files:['path/b'] }
]}})
```
- Mỗi builder chạy **worktree riêng** → không đụng file nhau.
- **Coordinator review + merge** rồi chạy `parallel-review` + `init.sh`.

## Gotchas
- Workflow script **không đọc filesystem** → truyền dữ liệu qua `args`; subagent bên trong mới đọc repo.
- Worker coordinator-pattern **không thấy context của bạn** → prompt tự chứa.
- Fork/worktree **1 cấp**: builder không spawn builder.
- Kết quả subagent là *đầu vào để bạn tổng hợp*, không phải quyết định cuối — Builder chính vẫn cập nhật `progress.md`.
