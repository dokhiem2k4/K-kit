# Design — the Feature Dossier for harness-kit

**Date:** 2026-07-23
**Status:** approved (awaiting an implementation plan)
**Scope:** `harness-kit/template/*` + `README.md`

---

## 1. The problem

The harness currently records state in `feature_list.json` (which feature, whether it is done) and `progress.md` (a log + command evidence).
Both are **short by design**: they answer "where are we", not "what is that F really, how does it run,
why was it built that way". After a few sessions, understanding a feature again means re-reading the code.

**Goal:** every completed feature leaves behind exactly one re-readable Markdown file, serving both humans and the agent in a later session.

## 2. Decisions already settled

| Question | Settled |
|---|---|
| Audience | **One combined file** — a description for humans plus the internal detail for agents |
| When it is written | **At the SHIP gate** (pipeline step 9), after VERIFY + SECURITY + DEVEX pass |
| How it is enforced | **Instructions + a mechanical check in `init.sh`** (never relying on the agent's memory) |
| How it is looked up | **A naming convention + the `doc` field in `feature_list.json`** — no separate index file |

**Deliberately NOT doing (YAGNI):** no `docs/features/INDEX.md`; no skeleton-generating script;
no splitting human-docs from agent-docs into 2 files; no staleness check on the dossier.

## 3. File convention

- Path: `docs/features/<ID>-<slug>.md` — for example `docs/features/F01-scaffold.md`.
  `<ID>` matches `id` in `feature_list.json`; `<slug>` is the kebab-case of `name`.
- Exactly **one** file per feature. Never merge several Fs, never split one F across files.
- The source template: `docs/features/_TEMPLATE.md` (bootstrap copies it in; it is exempt from the scan because its name starts with `_`).

## 4. Dossier structure — 8 fixed sections

Level-2 headings, in order, **worded exactly**. A section that does not apply gets `—`, the heading is **never deleted**
(the mechanical check anchors on the headings).

The header at the top of the file:

```markdown
# F01 — Scaffold project

> **Status:** done · **Date:** 2026-07-23 · **Commit:** a1b2c3d · **Blueprint:** §2.1
```

(In `_TEMPLATE.md` these values are `<TODO: ...>`.)

| # | Heading | Answers | For whom |
|---|---|---|---|
| 1 | `## 1. Why it matters` | The F's role in the bigger picture; what it **unlocks** (which Fs build on it); what the project would **lack** without it; which Blueprint REQ it covers | both |
| 2 | `## 2. What it does` | Observable behaviour: press/call what, get what | humans |
| 3 | `## 3. How to use it` | Concrete steps / endpoint / screen / command + a real example (request→response if it is an API) | humans |
| 4 | `## 4. Under the hood` | The main flow A→B→C; **files touched** (path + a one-line role); schema/tables involved; env/config variables needed | agents |
| 5 | `## 5. Decisions & trade-offs` | What was chosen, what was dropped, why; what was **deliberately not done** (out of scope) | both |
| 6 | `## 6. Pitfalls when editing` | What breaks easily, invariants to preserve, hidden dependencies | agents |
| 7 | `## 7. Evidence` | Each `done_when` → how it was verified → the result; the SECURITY gate result. Long output stays in `progress.md`; this is a summary + a pointer | both |
| 8 | `## 8. Updates` | A dated line, written whenever a later F changes this F's behaviour | both |

**The boundary between section 1 and section 2** (written directly into `_TEMPLATE.md` as a comment so the agent does not duplicate):
section 1 **zooms out** — the role in the system; section 2 **zooms in** — the concrete behaviour.

Section 1 makes use of data already in `feature_list.json`: `dependencies` (what this F needs) and the reverse direction
(which Fs declare a dependency on it) — the agent can fill it in immediately, with no guesswork.

## 5. Constraints — 6 edits in the template

### 5.1 New file: `template/docs/features/_TEMPLATE.md`
An 8-section skeleton + the header, with short guidance comments under each heading as `<!-- ... -->`, and every blank
marked `<TODO: ...>`. Bootstrap copies it automatically (`walk()` already scans all of `template/`), so `bootstrap.mjs` needs no changes.

### 5.2 `template/init.sh` — the `docs` target
- Add a `check_docs()` function; add `docs` to the `case` and to the `all` branch.
- Parse `feature_list.json` with `node -e` (node is already a harness requirement: bootstrap + `.claude/workflows/*.mjs`).
  No `node` → print `(no node — skip)`, do **not** set FAIL and do **not** print "OK" (never fake a pass).
- The rule: for every feature with `status ∈ {done, verified}`:
  1. it has a `doc` field (a non-empty string);
  2. the `doc` file exists;
  3. it contains all 8 headings `## 1.` … `## 8.` in order;
  4. no placeholder is left unfilled. The placeholder marker is **`<TODO:` … `>`** (defined by `_TEMPLATE.md`) —
     grep for the exact string `<TODO:`, never a generic `<...>`, to avoid false positives on code snippets / HTML tags.
     The guidance comments in the template use `<!-- ... -->` and also count as unfilled if left behind.
- Any violation → print `[FAIL]` with the feature id + the reason, and set `FAIL=1`.
- Features in `pending / in_progress / blocked / deferred` → skipped (no dossier needed yet).

### 5.3 `template/CLAUDE.md`
- **Source of truth:** add a line pointing at `docs/features/<ID>-<slug>.md` — "the record of each finished feature; read it before editing an old F".
- **Definition of Done:** add the `documented` tier = a dossier with all 8 sections, `./init.sh docs` green.
- **Startup Workflow:** in the read-the-state step → if you are about to edit an already-done F, read its dossier first.
- **End of Session:** remind that the dossier is part of the state that must be updated.

### 5.4 `template/.claude/workflow/pipeline.md`
- Section **9. SHIP** — add a required checkbox:
  `[ ] The feature dossier docs/features/<ID>-<slug>.md has all 8 sections; ./init.sh docs is green; feature_list.json has the doc field.`
- Add the ripple rule: **a new F that changes an old F's behaviour → must add a line to section 8 (Updates) of the old F's dossier**, inside the new F's SHIP.
- The **Checkpoint gates** section — `SHIP→next` gains "the dossier is written".

### 5.5 `template/feature_list.json`
- The three sample features F01/F02/F03 gain a `"doc"` field with the conventional path.
- `_howto` gains: `doc` = the dossier path, required once status is done/verified; `init.sh docs` will check it.

### 5.6 `README.md` (harness-kit)
- The "Layout of the kit" tree: add `docs/features/_TEMPLATE.md`.
- The "5 subsystems" table: the dossier belongs to **State** (alongside `feature_list.json`, `progress.md`).
- The "After bootstrapping" section: note that dossiers accumulate as each F ships, they are not filled in up front.

## 6. Completion criteria

- [ ] `_TEMPLATE.md` exists, has all 8 sections, and carries the section 1 vs section 2 boundary comment.
- [ ] `./init.sh docs` **FAILs** when a `done` feature is missing `doc` / the file / a heading / still has a placeholder.
- [ ] `./init.sh docs` **PASSes** when every `done` feature has a valid dossier, and when no feature is `done` yet.
- [ ] `./init.sh all` runs `check_docs` without breaking the existing checks.
- [ ] `node bootstrap.mjs --dry-run` lists `docs/features/_TEMPLATE.md`.
- [ ] Bootstrapping into an empty directory → `docs/features/_TEMPLATE.md` is present with every `{{...}}` token replaced.
- [ ] `validate-harness.mjs` still scores **100/100**.
- [ ] `README.md` + `CLAUDE.md` + `pipeline.md` + `feature_list.json` describe one consistent convention.

## 7. Risks

| Risk | Mitigation |
|---|---|
| The target project has no `node` → the check silently skips | Print an explicit skip line, never print "OK"; document in `README.md` that node is a harness requirement |
| The agent writes a hollow dossier — all headings present, no meaning | The check catches leftover `<TODO:` and `<!-- -->` markers; content quality is the human's call at the SHIP gate |
| The dossier drifts from the code after a few Fs | The section 8 (Updates) rule in the pipeline; deliberately no staleness check (YAGNI) |
| Sections 1 and 2 end up saying the same thing | The zoom-out/zoom-in boundary comment sits right inside `_TEMPLATE.md` |
