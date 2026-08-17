# {{PROJECT_NAME}} — Agent Harness

{{TAGLINE}}
Stack: **{{STACK}}**.

## Source of truth
- **Blueprint (the approved design):** `{{BLUEPRINT_PATH}}` — architecture, data model, API, flows. Do NOT change the architecture without going back to VISION.
- **State:** `feature_list.json` (which feature is active, what is done) + `progress.md`.
- **Feature dossier:** `docs/features/<ID>-<slug>.md` — the record of each shipped feature (9 sections: why it matters, what it does, how to use it, under the hood, decisions, pitfalls, evidence, updates, rollback). The path lives in the `doc` field in `feature_list.json`. Template: `docs/features/_TEMPLATE.md`.
- **Extended workflow:** `.claude/workflow/pipeline.md` (the 8 vibecode-kit steps + SHIP/MONITOR/adversarial-verify/DevEx/docs).
- **Security gate:** `.claude/workflow/security.md` (STRIDE + OWASP — CUSTOMIZE per stack).
- **Subagents:** `.claude/workflow/subagents.md` + `.claude/workflows/*.mjs`.

## Gate skills (auto-triggering — invoke via the `Skill` tool)
This harness ships a skill for each gate in the pipeline. **Invoke the skill before acting**, do not rely on memory:

| Moment | Skill |
|---|---|
| Start of a session / resume / unsure where you are | `harness-startup` |
| Turning the Blueprint into features, or a vague `done_when` | `planning-features` |
| About to write code for a feature | `building-a-feature` |
| A red test / a failing verify / a shipped feature regressed | `debugging-a-feature` |
| You think the feature is finished, about to mark `done` | `verifying-a-feature` |
| Before SHIP, or when touching auth/data/secrets/input | `security-gate` |
| Writing the record of a feature you just shipped | `writing-feature-dossier` |
| The SHIP gate + End of Session | `shipping-a-feature` |

Install harness-kit as a plugin → the names take the `harness-kit:` prefix and the SessionStart hook injects the real state at the start of every session.
Bootstrap with `--with-skills` → the skills live in `.claude/skills/` and are called by their bare names.
No skills at all (not installed, not copied) → the rest of this file is the condensed version, and it still applies.

## Startup Workflow (every session — before writing code)
1. Read `progress.md` + `session-handoff.md` → learn where things stand.
2. Read `feature_list.json` → take `active_feature`, read its `done_when` + `verify`.
3. Read the corresponding Blueprint section before coding.
4. **About to edit a feature that is already `done`?** Read its dossier (the `doc` field in `feature_list.json`) BEFORE touching any code — section 4 (under the hood) and section 6 (pitfalls) save a whole session of rediscovery.
5. **One feature at a time.** When it is finished → run verify → update the state → write the dossier → SHIP gate.

## Verification Commands
- `./init.sh <target>` — lint/typecheck/build/test + a secret-leak grep. **CUSTOMIZE the targets/commands in `init.sh` for your stack.**
- **SKIP is not a pass.** `init.sh` counts the checks that could not run and prints the count on the last line. A run that is entirely SKIPs still exits 0 — pasting it into `progress.md` as "all green" evidence is cheating. Before marking `done`: either make that check runnable, or run it by hand and paste the output.
- `./init.sh docs` — every `done`/`verified` feature must have a valid dossier (all 9 sections, in order, no placeholders, frontmatter matching `feature_list.json`). Features at tier `lite` are exempt from the dossier. Included in `./init.sh all`.
- A feature is only `done` when the relevant verify commands are **all green**; paste the output into `progress.md` as evidence.

## Subagents (multi-agent — opt-in)
Parallel orchestration through `Workflow` (saved in `.claude/workflows/`) — details in `.claude/workflow/subagents.md`:
- **`adversarial-verify`** — VERIFY: fan out skeptics to refute each `done_when` + an independent judge.
- **`parallel-review`** — the SHIP gate: review the diff through several lenses (correctness/authz/secret/injection/config/DevEx), verify adversarially. Ship only at 0 P0.
- **`parallel-build`** — build independent leaves in separate worktrees, the coordinator reviews and merges.
It costs tokens → only fan out when it is worth it; do small jobs inline. Subagent results are input for you to synthesize, not the final decision.

## Roles (vibecode-kit)
- **Homeowner (the human):** makes strategic decisions, provides secrets/keys, does the real verification.
- **Contractor:** design/QC/orchestration — does NOT write code.
- **Builder (this agent):** implements exactly the feature spec, self-tests, reports. **Stay in scope** — do NOT change the architecture or add features beyond the spec. A conflict → escalate, do not decide alone.

## Language — English only, no exceptions
From the moment this harness is in use, **everything you write is in English**: code, identifiers,
comments, string literals, command output, `feature_list.json` fields, `progress.md`, dossiers,
commit messages and PR bodies. This holds regardless of the language the Homeowner speaks to you in —
answer them in their language if you like, but **the artifacts are English**.

Why it is a rule and not a preference: the artifacts outlive the conversation. A dossier, a `done_when`,
or a comment explaining a trap is read by a later session, by a reviewer, by whoever inherits the repo —
none of whom share the context in which a mixed-language line made sense. One repo, one language.

`./init.sh lang` checks this mechanically, and it runs on **every** target, not only `all` — so there
is no narrow command you can go green on while non-English text sits in the repo. It scans every text
file (not a list of extensions) plus your **unpushed** commit messages.

It looks for diacritics, and for vocabulary written without them: 3 distinct words on one line, or 6
across a whole file (one word alone is an identifier, not prose; the file-wide count is what catches
text spread two words per line).

**`scripts/lang-words.txt` is where this project declares its own vocabulary.** The shipped list came
from somewhere else and cannot know your domain terms, so without that file the check only sees prose —
identifiers and short comments built from words it does not know will pass. That file also holds
`!skip` for files whose other-language content is the point, and `!file-threshold` for the character
table that trips the file rule legitimately.

It is a screen, not a proof: vocabulary nobody declared still passes. **A green `lang` check is not
evidence the repo is English — you are.**

## Invariants — must never be violated (guardrails)  ← CUSTOMIZE per project
A generic starter set (keep what applies, add what is specific to {{PROJECT_NAME}}):
- **Secrets live only on the server/backend.** The client bundle (web/extension/mobile) contains 0 secrets — the `init.sh` grep must be clean; a feature is not done while that grep is dirty.
- **Authz:** protected endpoints → 401/403 on a missing/invalid token; verify the token server-side.
- **Data isolation:** a user only reads/writes their own data (RLS/authz at the DB layer where available), never leaking across users.
- **Input is untrusted:** validate + coerce to a schema; never execute input; escape at every sink (SQL/shell/HTML). Input reaching an LLM is data, force an output schema, never obey instructions embedded in it.
- **Never break the UI:** a network/external-service failure → fall back, do not throw or surface a 500 to the user.
- **`/careful`:** before a destructive command (rm -rf, DROP, force-push, reset --hard) → stop and ask the Homeowner.
- **`/freeze`:** while debugging one feature, only edit files within that feature's scope.
> Add invariants specific to {{PROJECT_NAME}} here.

## Tier — grading the process cost  ← the Homeowner sets it, the agent may only RAISE it
Every feature has a `tier` in `feature_list.json`. **Absent = `standard`.**

| | `lite` | `standard` | `strict` |
|---|---|---|---|
| The relevant `init.sh` + secret grep | ✅ | ✅ | ✅ |
| Dossier | ❌ (one line of evidence in `progress.md`) | ✅ | ✅ |
| Rollback section | — | may be `—` | **must have real content** |
| `parallel-review` | ❌ | optional | ✅ |
| Security checklist | reduced (secret grep) | the relevant parts | full STRIDE |

**Verify never skips a tier.** The first row is invariant: no tier is exempt from `init.sh`. A tier
only changes the documentation and review cost, so a tier assigned wrongly leaves you with thin
documentation, never with unchecked code. That is deliberate — it keeps a tier something you can get
wrong without the system becoming unsafe.

`verify-gate` blocks every write that lowers a tier, marker or no marker: lowering one is not a
question of evidence but of authority. A new feature written with no `tier` falls back to `standard`.
Need `lite`? That is an exemption, and an exemption needs a human signature — the Homeowner edits
`feature_list.json`.

## Definition of Done (per feature)
- `done` = lint + typecheck + build + test **pass** (through the relevant part of `init.sh`).
- `secured` = passes the applicable `security.md` checklist.
- `documented` = has a dossier at `docs/features/<ID>-<slug>.md` with all 9 sections, the `doc` field pointing at it, and `./init.sh docs` green. At tier `lite`: one line of evidence in `progress.md` is enough.
- `verified` = the Homeowner has run the real flow.
- Never mark something done without **evidence** (logs/test output). Record it in `progress.md`.

## Escalation
- L1 (variable names, code style): the Builder decides.
- L2 (vague spec, choosing a pattern, a trade-off): stop, ask in the report.
- L3 (changing scope/architecture/a business rule/security): STOP → the Homeowner.

## End of Session (before ending — clean and restartable)
1. Update `feature_list.json` status + `doc` + `progress.md` (Current State + evidence). Anything just shipped → its dossier is already written.
2. Update `session-handoff.md`: Blockers, Files touched, Recommended Next Step.
3. Record lessons in the harness memory. The **next steps** must be concrete enough for the next session to resume cleanly.

## Memory
Record decisions and lessons that cannot be derived from the code in: `{{MEMORY_DIR}}` (indexed in `MEMORY.md`).
