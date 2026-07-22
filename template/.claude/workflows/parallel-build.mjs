export const meta = {
  name: 'parallel-build',
  description: 'Build INDEPENDENT leaf sub-tasks of a feature in parallel, each in an isolated git worktree; returns per-task completion summaries for the coordinator to review and merge.',
  phases: [
    { title: 'Build', detail: 'one builder per sub-task, worktree-isolated' },
  ],
}

// Only for genuinely independent leaves (no shared lib/schema). Coordinator reviews + merges after.
//   Workflow({ name:'parallel-build', args:{ featureId, tasks:[{ id, spec, files:[...] }] } })
const PROJECT = '{{PROJECT_NAME}}'
const featureId = (args && args.featureId) || 'UNKNOWN'
const tasks = (args && args.tasks) || []
if (!tasks.length) { log('No tasks in args.tasks.'); return { featureId, results: [] } }

const SUMMARY = {
  type: 'object', additionalProperties: false,
  properties: {
    taskId: { type: 'string' },
    status: { type: 'string', enum: ['DONE', 'PARTIAL', 'BLOCKED'] },
    filesChanged: { type: 'array', items: { type: 'string' } },
    tests: { type: 'string' },
    deviations: { type: 'string' },
    notes: { type: 'string' },
  },
  required: ['taskId', 'status', 'filesChanged'],
}

const results = await parallel(tasks.map((t) => () =>
  agent(
    `You are a Builder for feature ${featureId}, sub-task ${t.id} of "${PROJECT}". ` +
    `Implement EXACTLY this spec — do NOT expand scope:\n\n${t.spec}\n\n` +
    `Obey CLAUDE.md invariants and .claude/workflow/security.md. Touch only: ${(t.files || []).join(', ') || 'files this sub-task needs'}.\n` +
    `Self-test (build/typecheck + relevant tests). Return a completion summary (taskId="${t.id}").`,
    { label: `build:${featureId}:${t.id}`, phase: 'Build', schema: SUMMARY, isolation: 'worktree', agentType: 'general-purpose' }
  )
))

const done = results.filter(Boolean)
log(`${featureId}: ${done.filter((r) => r.status === 'DONE').length}/${tasks.length} DONE (in worktrees — coordinator must review + merge).`)
return { featureId, results: done }
