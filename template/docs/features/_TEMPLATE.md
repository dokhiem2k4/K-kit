---
feature: <TODO: F0X>
status: <TODO: done | verified>
tier: <TODO: standard | strict>
date: <TODO: YYYY-MM-DD>
commit: <TODO: sha>
blueprint: <TODO: section>
security: <TODO: passed | n/a>
reversible: <TODO: true | false>
---

# <TODO: F0X> — <TODO: Feature name>

<!--
FEATURE DOSSIER — copy this file to docs/features/<ID>-<slug>.md when you ship a feature.

Rules:
- Write it at the SHIP gate, after VERIFY + SECURITY + DEVEX have passed.
- Keep all 9 headings below, in order, worded exactly. A section that does not apply gets "—", NEVER delete the heading.
- Remove every <TODO: ...> placeholder and every guidance comment before shipping.
- ./init.sh docs will FAIL on a missing section, a wrong order, a leftover placeholder / comment,
  or frontmatter that disagrees with feature_list.json.

Frontmatter:
- feature / status / tier MIRROR feature_list.json — a mismatch is a FAIL, not a warning. The old
  "Status: done" line duplicated exactly the same thing; the only difference is that this one is checked.
- The other 5 fields belong to the dossier; feature_list.json holds no copy of them.
- tier: lite needs NO dossier at all — a lite feature records its evidence directly in progress.md.
  This file is only for standard and strict.

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

## 9. Rollback & Recovery

<!--
tier: strict  -> "How to revert" MUST have real content; it may not be "—".
tier: standard -> all three lines may be "—", but the heading stays.
The middle line is the one that earns this section: forward-fix cures code, it does not cure a
migration that already ran or an email that already went out. If nothing here is irreversible, say
so — but think before you do, because this is read during an incident, not during review.
-->

**How to revert:** <TODO: concrete commands/steps — which commit to revert, which version to roll back, which flag to turn off>

**CANNOT be reverted:** <TODO: migrations already run, data already overwritten, webhooks/emails already sent, third-party caches — or "—">

**Signs a rollback is needed:** <TODO: observable symptoms, concrete thresholds — or "—">
