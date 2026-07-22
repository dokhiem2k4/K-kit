export const meta = {
  name: 'adversarial-verify',
  description: 'Fan out skeptic subagents to REFUTE each done_when criterion of a feature; confirmed failures returned.',
  phases: [
    { title: 'Refute', detail: 'one skeptic per criterion tries to make it fail' },
    { title: 'Judge', detail: 'independent judge reproduces each alleged failure' },
  ],
}

// Workflow scripts have NO filesystem access. Coordinator passes criteria via args
// (read feature_list.json first):
//   Workflow({ name:'adversarial-verify', args:{ featureId, criteria:[...], context, securityChecks:[...] } })
const PROJECT = '{{PROJECT_NAME}}'
const featureId = (args && args.featureId) || 'UNKNOWN'
const criteria = (args && args.criteria) || []
const context = (args && args.context) ||
  'See CLAUDE.md (invariants), feature_list.json (done_when), .claude/workflow/security.md, and the Blueprint.'
const securityChecks = (args && args.securityChecks) || []

if (!criteria.length && !securityChecks.length) {
  log('No criteria/securityChecks in args — nothing to verify.')
  return { featureId, confirmedFailures: [], note: 'empty input' }
}

const VERDICT = {
  type: 'object', additionalProperties: false,
  properties: {
    criterion: { type: 'string' },
    refuted: { type: 'boolean' },
    failureScenario: { type: 'string' },
    evidence: { type: 'string' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
  },
  required: ['criterion', 'refuted', 'failureScenario', 'confidence'],
}

const items = criteria.map((c, i) => ({ c, i, kind: 'done_when' }))
  .concat(securityChecks.map((c, i) => ({ c, i: 1000 + i, kind: 'security' })))

const results = await pipeline(
  items,
  (it) => agent(
    `You are an ADVERSARIAL verifier for feature ${featureId} of "${PROJECT}".\n\n` +
    `Context: ${context}\n\n` +
    `Claim to REFUTE (${it.kind}): "${it.c}"\n\n` +
    `Inspect the ACTUAL repository (read code, migrations, configs, tests). Try hard to find one concrete ` +
    `input/state/path where this claim FAILS: empty/malformed input, another user's data, missing/invalid auth ` +
    `token, stale or missing cache, permissive CORS, a secret leaked into the client bundle, untrusted input ` +
    `reaching a sink (SQL/shell/LLM prompt), a race, or simply code that is not built yet. ` +
    `Default refuted=true if you cannot POSITIVELY confirm it holds. Return the concrete failure scenario + file evidence.`,
    { label: `refute:${featureId}:${it.i}`, phase: 'Refute', schema: VERDICT, agentType: 'Explore' }
  ),
  (verdict, it) => {
    if (!verdict || !verdict.refuted) return { ...(verdict || { criterion: it.c }), confirmed: false }
    return agent(
      `Independent JUDGE for feature ${featureId} of "${PROJECT}". Another agent claims this criterion FAILS:\n` +
      `Criterion: "${verdict.criterion}"\nAlleged failure: "${verdict.failureScenario}"\nEvidence: "${verdict.evidence || ''}"\n\n` +
      `Verify yourself by inspecting the repo. Return the same schema with refuted=true ONLY if you independently ` +
      `reproduce/confirm the failure. If it's a false alarm, refuted=false.`,
      { label: `judge:${featureId}:${it.i}`, phase: 'Judge', schema: VERDICT, agentType: 'Explore' }
    ).then((j) => ({ ...(j || verdict), confirmed: !!(j && j.refuted) }))
  }
)

const confirmedFailures = results.filter(Boolean).filter((r) => r.confirmed)
log(`${featureId}: ${confirmedFailures.length} confirmed failure(s) / ${items.length} checks.`)
return { featureId, checks: items.length, confirmedFailures }
