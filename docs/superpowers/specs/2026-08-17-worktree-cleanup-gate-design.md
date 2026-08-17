# Design — mechanical worktree-cleanliness check (inspired by Pi's AgentHarness "zero dead state")

**Date:** 2026-08-17
**Status:** approved (awaiting an implementation plan)
**Scope:** `template/init.sh`, `tests/run-tests.sh`, `README.md`

---

## 1. The problem

Pi's `AgentHarness` deletes every register belonging to an operation the moment it finishes — "zero
dead state," a property of the mechanism, not of agent discipline.

harness-kit's closest equivalent (the `2026-08-17-state-compaction-drift-lock` change) added a
**checklist line** to the SHIP gate: `git worktree remove .worktrees/<slug>` after a merge. That line
is agent-run, not machine-checked — and it is demonstrably not enough on its own: at the moment this
spec is being written, `.worktrees/feat-tier-rollback` sits in this very repository, its branch already
merged into `main`, uncleaned, from *before* the checklist line existed. The checklist line prevents
nothing from happening again automatically; it only asks nicely.

## 2. Decisions already settled

| Question | Settled | Reason |
|---|---|---|
| Block or warn | **Warn only, never `FAIL`** | A stale worktree can belong to *other* parallel work unrelated to the feature currently being shipped. Hard-failing `init.sh` — and by extension `verify-gate`'s `VERIFY OK` contract — over something the current feature did not cause would be overreach: it would block shipping feature A because feature B's worktree was never cleaned up. |
| Where it runs | **Its own `check_worktree` function, folded into `all`** — not a new top-level `init.sh` target | It has no independent "just check this" use case the way `docs`/`lang`/`state` do; it is a repo-hygiene side note surfaced alongside everything else. |
| What counts as "stale" | **A worktree whose branch is fully merged into the current branch, and is not the worktree the check is currently running from** | Merged = safe to remove; an unmerged worktree is active work in progress and must never be flagged. |

**Deliberately NOT doing (YAGNI):**

- Auto-removing the worktree — already rejected in the state-compaction spec (§2 of
  `2026-08-17-state-compaction-drift-lock-design.md`): "a checklist + evidence, not an autorun git
  command taken on the agent's behalf." This spec does not revisit that decision, only adds the
  missing evidence half.
- Failing the gate — rejected above; would punish shipping one feature for another feature's leftover
  worktree.
- Detecting *unmerged, abandoned* worktrees (branches nobody is working on but not yet merged either)
  — a different, harder problem (requires a staleness heuristic, e.g. "no commits in N days"), and not
  what caused the concrete instance found in this repo. Out of scope; revisit only if it recurs in that
  shape.

## 3. The check

```bash
# Repo hygiene: a worktree whose branch is already merged should have been removed at SHIP
# (see shipping-a-feature's checklist). This only WARNS — a stale worktree may belong to
# other work in progress, unrelated to the feature currently being verified.
check_worktree() {
  step "WORKTREE (merged worktrees not yet cleaned up)"
  command -v git >/dev/null 2>&1 || { skip "no git — cannot check worktree cleanliness"; return; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { skip "not a git repository"; return; }

  local current here stale=""
  current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  here="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"

  # Plain `git worktree list` — one line per worktree: "<path> <sha> [<branch>]", or
  # "(detached HEAD)"/"(bare)" in place of the bracketed branch. Deliberately NOT --porcelain:
  # its multi-line blocks were the first draft of this check and were verified WRONG against a
  # real multi-worktree repo during this spec's own review (the line after "worktree <path>" is
  # "HEAD <sha>", not "branch ..." — an off-by-one that would have silently matched nothing).
  # The single-line plain format has no such trap.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    wpath="$(printf '%s\n' "$line" | awk '{print $1}')"
    [ "$wpath" = "$here" ] && continue                        # never flag the worktree we are running from
    wbranch="$(printf '%s\n' "$line" | sed -n 's/.*\[\(.*\)\]$/\1/p')"
    [ -z "$wbranch" ] && continue                             # detached/bare — not ours to judge
    # git branch --merged prefixes the CURRENT worktree's branch with "* " but a branch checked
    # out in ANOTHER linked worktree with "+ " (verified against this repo's own two worktrees
    # during this spec's review — an easy trap: a sed pattern stripping only "* " leaves the
    # "+ " row never matching, silently hiding every merged worktree from detection).
    if git branch --merged "$current" 2>/dev/null | sed 's/^[*+ ] //' | grep -qxF "$wbranch"; then
      stale="${stale}  $wpath (branch: $wbranch)\n"
    fi
  done < <(git worktree list 2>/dev/null)

  if [ -n "$stale" ]; then
    printf '   [WARN] merged worktree(s) not yet cleaned up:\n%b' "$stale"
    echo "   Run: git worktree remove <path>   (see shipping-a-feature's SHIP checklist)"
  else
    echo "   OK: no merged worktree left uncleaned"
  fi
}
```

Both traps noted in the comments above were caught empirically, not theoretically: this exact script
was run against this repository's own two real worktrees (`main` and the pre-existing, still-uncleaned
`.worktrees/feat-tier-rollback`) during this spec's review, confirming it correctly flags the latter as
`[WARN]` and never flags the former.

Wired into the `all)` case alongside the other checks (`template/init.sh:159` today) — **never** into
`state)`/`docs)`/etc. individually, since it is not feature-scoped.

## 4. Files to change — 3

| File | Work |
|---|---|
| `template/init.sh` | add `check_worktree` (§3), call it from `all)` |
| `tests/run-tests.sh` | fixtures: a project with a merged-but-present worktree → `[WARN]` printed, exit still 0; a project with only an unmerged worktree → no warning; a project with no worktrees at all → `OK`/skip cleanly; the warning never sets `FAIL` (assert `./init.sh all` still exits 0 with the warning present) |
| `README.md` | one line added to the `init.sh` target description noting the worktree hygiene check runs under `all` |

**Untouched:** `hooks/verify-gate.js` — this check has no gating role, so it does not touch the
`VERIFY OK` contract at all; `skills/shipping-a-feature/SKILL.md` — its existing checklist line already
covers the instruction, this spec only adds the machine-checked evidence behind it.

## 5. Completion criteria

- [ ] A repo with a merged, present worktree → `./init.sh all` prints `[WARN]` naming the path and
      branch, and still exits 0 (never blocks).
- [ ] A repo with only unmerged worktrees (active work) → no warning.
- [ ] A repo with no worktrees beyond the current one → prints `OK`, no warning.
- [ ] Not a git repository → `SKIP`, not a false `OK`.
- [ ] `bash tests/run-tests.sh` green, with the new assertions counted.

## 6. Risks

**Porcelain output parsing is the fragile part.** `git worktree list --porcelain` format has evolved
across git versions before; the implementer must verify the exact block shape against the git version
in CI/dev machines before trusting the parsing sketch in §3, not merely port it verbatim.

**A WARN that nobody reads is only marginally better than a checklist nobody ticks.** This is a
conscious, bounded improvement: it does not close the gap Pi closes (a *structural* guarantee of no
dead state), it only makes the dead state *visible* every time `init.sh all` runs, which is far more
often than a human re-reads a SHIP checklist by memory. Closing it further would mean reopening the
"warn vs fail" decision in §2 — not done here.
