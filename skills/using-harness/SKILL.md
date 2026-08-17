---
name: using-harness
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use when starting any session in a project that has a harness (feature_list.json + .claude/workflow/) - routes every pipeline moment to its gate skill and forbids marking work done without machine evidence
---

# Using the harness

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

<SUBAGENT-STOP>
If you were dispatched as a subagent for one specific task, ignore this skill.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
In a harness project, **the state files are the truth, not your memory**.
If there is even a 1% chance one of the gate skills below applies, you MUST invoke it before acting.
</EXTREMELY-IMPORTANT>

## The core rule

```
NEVER CLAIM DONE WITHOUT AN EXIT CODE
```

A feature is `done` only when the commands in its `verify` field ran **in this turn** and returned exit 0.
"It should pass", "the logic is right", "the build was green earlier" — none of those count.

## Choosing a gate skill

| Moment | Skill |
|---|---|
| Start of a session / "continue" / unsure where you are | `harness-kit:harness-startup` |
| Turning the Blueprint into features, or a vague `done_when` | `harness-kit:planning-features` |
| About to write code for a feature | `harness-kit:building-a-feature` |
| A red test / a failing verify / a shipped feature regressed | `harness-kit:debugging-a-feature` |
| You think the feature is finished, about to mark `done` | `harness-kit:verifying-a-feature` |
| Before SHIP, or when touching auth / data / secrets / user input | `harness-kit:security-gate` |
| A feature passed VERIFY + SECURITY and is about to ship | `harness-kit:shipping-a-feature` |
| Writing the dossier for a feature you just shipped | `harness-kit:writing-feature-dossier` |
| End of session | `harness-kit:shipping-a-feature` (the End of Session section) |

Announce `Using [skill] to [purpose]`, then follow that skill exactly. If the skill has a checklist → create one todo per item.

> The names above are the plugin form. If the harness was installed project-locally (`.claude/skills/`),
> drop the prefix: `harness-startup`, `building-a-feature`, ...

## Four guardrails, always on

- **English only** — every artifact you write is English: code, identifiers, comments, strings, output, state files, dossiers, commit messages. Reply to the Homeowner in whatever language they used; **write the artifacts in English**. `./init.sh lang` checks it.
- **`/freeze`** — while fixing a bug in some F, touch only files inside that F's scope.
- **`/careful`** — before a destructive command (`rm -rf`, `DROP`, `force-push`, `reset --hard`): stop and ask the Homeowner.
- **One feature at a time** — `active_feature` in `feature_list.json` is the only feature you may touch.

## Red flags — these thoughts mean you are rationalizing

| You think | Reality |
|---|---|
| "This is small, it does not need the gate" | The gate is cheaper than a debugging session. Invoke the skill. |
| "Let me read the code first" | `harness-startup` tells you WHAT to read first. Read that first. |
| "I remember what the harness says" | This project's harness may have changed. Read the real file. |
| "There is nothing to test in this feature" | Then its `done_when` is wrong. Fix `done_when`, do not skip verify. |
| "Just do it quickly, gate it later" | Gate it later = never gate it. |
| "I only changed one line" | One line is still a diff. Every diff goes through the SHIP gate. |
| "The Homeowner is in a hurry" | Shipping something broken costs more time than the gate does. |
| "The Homeowner wrote to me in another language, so I will answer in the code too" | Answer them in their language; the artifacts stay English. The code outlives the conversation. |
| "Just this one comment in my own language" | One comment becomes a file becomes a repo. English only. |

## Priority order

Gate skills come before technical skills. `verifying-a-feature` decides *when* something counts as finished;
a language/framework skill decides *how*. Never let the second override the first.

## Human override

A direct instruction from the Homeowner > a skill > default behaviour. Only skip the workflow when the
Homeowner says so explicitly — never infer it from the fact that they are in a hurry.
