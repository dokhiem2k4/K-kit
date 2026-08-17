# Subagents — multi-agent playbook — {{PROJECT_NAME}}

Claude Code has `Agent` (a subagent with fresh context) + `Workflow` (a deterministic orchestration script,
with `isolation:'worktree'` for parallel builders).

## Opt-in & cost
- `Workflow` **only runs when the Homeowner opts in**.
- Every fan-out costs tokens → use it only when it is worth it (verifying a heavy feature, reviewing a large diff, building several independent leaves). Small jobs → inline.

## 3 patterns
| Pattern | Context | Use for | Constraint |
|---|---|---|---|
| **Coordinator** | Workers start fresh (inherit nothing) | multi-phase verify/review/research | Safest; prompts must be self-contained |
| **Fork/worktree** | Its own worktree | building independent leaves in parallel | **1 level** — workers do not fork again; the coordinator merges |
| **Swarm** | A shared task list | long, independent workstreams | Flat roster |

**The golden rule:** the coordinator **synthesizes before delegating**, never "based on your findings". Workers get a self-contained prompt + minimal tools (`Explore` to verify/read, `general-purpose` to build).

## Saved workflows (invoked by name)

### 1. `adversarial-verify` — VERIFY (replacing one-directional self-review)
Read `feature_list.json`, take the feature's `done_when` + the applicable security checks, pass them via `args`:
```
Workflow({ name:'adversarial-verify', args:{
  featureId:'F0X',
  criteria:[ "...", "..." ],            // from done_when
  securityChecks:[ "..." ],             // from security.md
  context:'extra notes (optional)'
}})
```
- Each criterion → a skeptic *trying to refute it* (reading the real repo) → a judge reproducing independently.
- Returns `confirmedFailures[]`. **≥1 → not done**, go back to BUILD.

### 2. `parallel-review` — the SHIP gate (replacing a cross-model second opinion)
```
Workflow({ name:'parallel-review' })   // no args needed; the subagents run git diff themselves
```
- Parallel lenses: correctness / authz / secret-leak / injection / config / devex.
- A finding only survives an adversarial verification. Returns `confirmed[]` sorted P0→P2. **A confirmed P0 → do not SHIP.**

### 3. `parallel-build` — building independent leaves (fork/worktree)
Only for sub-tasks that are **genuinely independent** (no shared lib/schema).
```
Workflow({ name:'parallel-build', args:{ featureId:'F0X', tasks:[
  { id:'a', spec:'...', files:['path/a'] },
  { id:'b', spec:'...', files:['path/b'] }
]}})
```
- Each builder runs in **its own worktree** → they never touch each other's files.
- The **coordinator reviews + merges**, then runs `parallel-review` + `init.sh`.

## Gotchas
- Workflow scripts **cannot read the filesystem** → pass data through `args`; only the subagents inside read the repo.
- Coordinator-pattern workers **cannot see your context** → make the prompt self-contained.
- Fork/worktree is **1 level**: a builder never spawns a builder.
- Subagent results are *input for you to synthesize*, not the final decision — the main Builder still updates `progress.md`.
