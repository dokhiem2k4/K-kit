# Session Handoff — {{PROJECT_NAME}}

> Read this file at the start of a session. Update it at the end, before stopping.

## Quick context
- Blueprint: `{{BLUEPRINT_PATH}}`.
- Harness: `CLAUDE.md` (invariants), `feature_list.json` (state), `.claude/workflow/` (pipeline + security + subagents).
- Verify: `./init.sh <target>`.

## Where things stand (restart markers)
- **Last Updated:** {{DATE}}.
- **Active feature:** see `feature_list.json.active_feature` — also surfaced automatically by the SessionStart hook.
- **Recommended Next Step:** scaffold per the Blueprint → `./init.sh scaffold`.
- **Blockers:** _(keys/decisions waiting on the Homeowner)_
- **Files:** harness files at the root + `.claude/`; no product files yet.

## Pending decisions (need the Homeowner)
- _(list them)_

## Next Session — how to continue (clean restart)
1. Read `progress.md` and this file.
2. Take `active_feature` from `feature_list.json`, read its `done_when` + `verify`.
3. Follow `.claude/workflow/pipeline.md`: BUILD → VERIFY (adversarial) → SECURITY → DevEx → SHIP.
4. Update the state + evidence in `progress.md`; record lessons in the harness memory.
