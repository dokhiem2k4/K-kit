export const meta = {
  name: 'parallel-review',
  description: 'Multi-lens review of the current git diff (correctness, authz, secret-leak, injection, config, DevEx); every finding adversarially verified before it survives.',
  phases: [
    { title: 'Review', detail: 'one reviewer per lens over the diff' },
    { title: 'Verify', detail: 'refute each finding in the repo' },
  ],
}

// Reviews the CURRENT diff. No args needed; subagents run `git diff` themselves.
// CUSTOMIZE the LENSES focus text to your stack's real risks.
const PROJECT = '{{PROJECT_NAME}}'
const LENSES = [
  { key: 'correctness', focus: 'Logic bugs, wrong states, unhandled errors, non-idempotent writes, error paths that throw/500 instead of degrading gracefully.' },
  { key: 'authz', focus: 'Protected endpoints require a valid token (401/403 otherwise); access control enforced server-side; no cross-user data leakage; no client-side privilege escalation.' },
  { key: 'secret-leak', focus: 'No secrets (private keys, service tokens, API keys) in client bundle or committed files; secrets only read server-side from env.' },
  { key: 'injection', focus: 'Untrusted input parameterized/escaped at every sink (SQL/shell/HTML); if an LLM is used, prompt is schema-locked and output validated, never executed/rendered raw.' },
  { key: 'config', focus: 'CORS not *, security headers/CSP set, .env not committed, no debug/verbose leaks, sane defaults.' },
  { key: 'devex', focus: 'Time-to-hello-world: README and .env.example complete, error messages clear, no hidden manual steps.' },
]

const FINDINGS = {
  type: 'object', additionalProperties: false,
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        properties: {
          title: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['P0', 'P1', 'P2'] },
          detail: { type: 'string' },
        },
        required: ['title', 'file', 'severity', 'detail'],
      },
    },
  },
  required: ['findings'],
}
const VERDICT = {
  type: 'object', additionalProperties: false,
  properties: { isReal: { type: 'boolean' }, reason: { type: 'string' } },
  required: ['isReal', 'reason'],
}

const results = await pipeline(
  LENSES,
  (l) => agent(
    `Review the CURRENT git diff (run \`git diff\` and \`git diff --staged\`) of "${PROJECT}" ` +
    `through the ${l.key} lens.\nFocus: ${l.focus}\n` +
    `Return only real findings with file + severity (P0 blocks ship). If clean, return empty findings.`,
    { label: `review:${l.key}`, phase: 'Review', schema: FINDINGS, agentType: 'general-purpose' }
  ),
  (review) => parallel(((review && review.findings) || []).map((f) => () =>
    agent(
      `Adversarially verify this finding in the actual repo. Is it REAL and reproducible?\n` +
      `Title: ${f.title}\nFile: ${f.file}:${f.line || '?'}\nSeverity: ${f.severity}\nDetail: ${f.detail}\n` +
      `Inspect the code yourself. Default isReal=false unless you can concretely confirm it.`,
      { label: `verify:${f.file}`, phase: 'Verify', schema: VERDICT, agentType: 'Explore' }
    ).then((v) => ({ ...f, verdict: v }))
  ))
)

const order = { P0: 0, P1: 1, P2: 2 }
const confirmed = results.flat().filter(Boolean)
  .filter((f) => f.verdict && f.verdict.isReal)
  .sort((a, b) => order[a.severity] - order[b.severity])
log(`Confirmed ${confirmed.length} finding(s); ${confirmed.filter((f) => f.severity === 'P0').length} P0.`)
return { confirmed }
