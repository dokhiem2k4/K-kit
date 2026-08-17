---
name: writing-feature-dossier
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use at the ship gate after a feature passes verify and security, when creating docs/features/<ID>-<slug>.md, or when a new feature changes the behaviour of an already-shipped one - enforces the 8 fixed sections that ./init.sh docs checks mechanically
---

# Writing a feature dossier

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

**Principle:** `feature_list.json` answers "is it finished". `progress.md` answers "where do things stand".
The dossier answers **"what is that F really, how does it run, why was it built this way"** — the thing a later
session would otherwise have to re-read the code to learn.

One feature = **exactly one** file `docs/features/<ID>-<slug>.md`. Never merged, never split.

## When to write it

At the **SHIP gate**, after VERIFY + SECURITY + DEVEX have passed. Not earlier (there is no evidence yet),
not later (later never happens).

Start by copying `docs/features/_TEMPLATE.md`. Then point the `doc` field in `feature_list.json`
at the path you just created.

## The 8 sections — exact order, exact wording

`./init.sh docs` anchors on the headings. A section that does not apply gets `—`, **never delete the heading**.

| # | Heading | Answers | For whom |
|---|---|---|---|
| 1 | `## 1. Why it matters` | Its role in the bigger picture; which F it unlocks; what the project lacks without it; which REQ it covers | both |
| 2 | `## 2. What it does` | Observable behaviour: press/call what, get what | humans |
| 3 | `## 3. How to use it` | Concrete steps / endpoint / screen / command + a real example | humans |
| 4 | `## 4. Under the hood` | The A→B→C flow; a **files touched** table; schema; env vars | **agents** |
| 5 | `## 5. Decisions & trade-offs` | What was chosen, what was dropped, why; what was **deliberately not done** | both |
| 6 | `## 6. Pitfalls when editing` | What breaks easily, invariants to preserve, hidden dependencies | **agents** |
| 7 | `## 7. Evidence` | Each `done_when` → how it was verified → the result; the SECURITY result | both |
| 8 | `## 8. Updates` | A dated line, added whenever a later F changes this F's behaviour | both |

## The boundary between sections 1 and 2 — do not write it twice

- **Section 1 = zoom out.** The feature's role in the system. Why the project NEEDS it.
- **Section 2 = zoom in.** Observable behaviour. Press/call what, get what.

If section 1 is full of "the user clicks X and sees Y", you have written section 2 twice.

## Sections 4 and 6 are the most valuable parts

These are the two a later session reads to save half a day:

- **Section 4** must include a `| File | Role |` table — every file touched, one line each. Do not list every file in the repo, only the ones belonging to this feature.
- **Section 6** must be specific: "swapping the order of these two middlewares loses the session", not "be careful when editing".

A generic section 6 is a useless section 6.

## Before shipping: clean it up

- [ ] Every `<TODO: ...>` placeholder removed
- [ ] Every `<!-- ... -->` guidance comment removed
- [ ] The header carries Status / Date / Commit / Blueprint
- [ ] `feature_list.json` has a `doc` field pointing at the right path
- [ ] `./init.sh docs` is **green**

`./init.sh docs` FAILs on a missing section, a wrong order, a leftover `<TODO:` or a leftover `<!--`. This gate cannot be talked around.

## Ripple — the rule most often broken

Is the feature you are shipping **changing the behaviour of an older F**? You must add **a dated line to section 8**
of that older F's dossier. Do it inside this SHIP, do not defer it.

A dossier that drifts from the code is worse than no dossier — because the next session will believe it.

## Red flags

| You think | Reality |
|---|---|
| "Write the dossier after shipping, it is faster" | After shipping = never. Write it inside the gate. |
| "This section does not apply, delete the heading" | Write `—`. Deleting the heading makes `init.sh docs` FAIL. |
| "Copy the description over from feature_list.json" | The dossier exists to answer what feature_list cannot. |
| "'Be careful when editing' is enough for section 6" | Useless. Name exactly what breaks and why. |
| "The old F is probably unaffected" | You just changed its behaviour. Add the line to section 8. |
| "Leave the `<TODO:` and fix it later" | `./init.sh docs` FAILs. And you will not fix it. |
| "Summarize all the verify output into section 7" | Section 7 summarizes and points at `progress.md`. The full output lives there. |
