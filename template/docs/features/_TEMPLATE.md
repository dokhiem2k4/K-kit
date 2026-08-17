# <TODO: F0X> — <TODO: Feature name>

> **Status:** <TODO: done | verified> · **Date:** <TODO: YYYY-MM-DD> · **Commit:** <TODO: sha> · **Blueprint:** <TODO: section>

<!--
FEATURE DOSSIER — copy this file to docs/features/<ID>-<slug>.md when you ship a feature.

Rules:
- Write it at the SHIP gate, after VERIFY + SECURITY + DEVEX have passed.
- Keep all 8 headings below, in order, worded exactly. A section that does not apply gets "—", NEVER delete the heading.
- Remove every <TODO: ...> placeholder and every guidance comment before shipping.
- ./init.sh docs will FAIL on a missing section, a wrong order, or a leftover placeholder / comment.

The boundary between sections 1 and 2 — do not write it twice:
- Section 1 = zoom out. The feature's role in the system. Why the project NEEDS it.
- Section 2 = zoom in. Observable behaviour. Press/call what, get what.
-->

## 1. Why it matters

<TODO: What role does this F play in the bigger picture? What does it unlock (which features build on it —
check `dependencies` in feature_list.json, in both directions)? What would the project lack without it?
Which REQ / Blueprint section does it cover?>

## 2. What it does

<TODO: Observable behaviour, concretely. What the user presses or calls, and what comes back.>

## 3. How to use it

<TODO: Concrete steps, endpoint, screen, or command. With a real example — request → response if it is an API.>

## 4. Under the hood

<TODO: The main flow A → B → C.>

**Files touched**

| File | Role |
|---|---|
| `<TODO: path>` | <TODO: one line> |

**Data / config:** <TODO: tables, schema, env vars needed — or "—">

## 5. Decisions & trade-offs

<TODO: What was chosen, what was dropped, why. What was DELIBERATELY not done (out of scope), so nobody later mistakes it for an oversight.>

## 6. Pitfalls when editing

<TODO: What breaks easily, invariants to preserve, hidden dependencies. What anyone editing this file needs to know first.>

## 7. Evidence

| `done_when` | How verified | Result |
|---|---|---|
| <TODO: criterion> | <TODO: command / action> | <TODO: pass + summary> |

**SECURITY gate:** <TODO: the result of the applicable security.md checklist>
The full output lives in `progress.md`; this is only a summary.

## 8. Updates

- <TODO: YYYY-MM-DD> — created at ship time.
