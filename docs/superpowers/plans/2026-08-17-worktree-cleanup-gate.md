# Worktree Cleanup Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `./init.sh all` a mechanical, WARN-only check that surfaces any git worktree whose branch is already merged but still sitting on disk — closing the gap between the SHIP checklist's "Worktree cleaned up" line (agent-run, easily skipped) and actual evidence.

**Architecture:** One new function, `check_worktree`, added to `template/init.sh` and wired only into the `all)` case (never a standalone target — it is repo hygiene, not feature-scoped verification). It parses the plain (non-porcelain) output of `git worktree list`, cross-references `git branch --merged`, and prints `[WARN]` for any match. It never sets `FAIL=1`.

**Tech Stack:** Bash only — no new dependency, matches every other `check_*` function already in `template/init.sh`.

## Global Constraints

- **Warn only — this check must never set `FAIL=1`.** A stale worktree can belong to unrelated
  parallel work; hard-failing `init.sh` over it would block shipping an unrelated feature. (Spec §2)
- **Folded into `all)` only** — not a new top-level `init.sh` target, unlike `docs`/`state`/`lang`. (Spec §2)
- **Never flag the worktree the check is currently running from**, and **never flag an unmerged
  worktree** (active work in progress). (Spec §2, §3)
- Use plain `git worktree list`, **not** `--porcelain` — the porcelain multi-line block format was
  tried and found to parse incorrectly during this spec's own review; the plain single-line format
  has no such trap. (Spec §3, verified empirically against this repo's own two real worktrees)
- When reading `git branch --merged` output, strip **both** `"* "` (current branch) and `"+ "`
  (a branch checked out in another linked worktree) prefixes — stripping only `"* "` silently hides
  every worktree-checked-out branch from the merged list, which is precisely the case this check
  exists to catch. (Spec §3, verified empirically)

---

### Task 1: `check_worktree` in `template/init.sh`, wired into `all`, with tests

**Files:**
- Modify: `template/init.sh:132` (insert the new function after `check_state()`, which currently ends
  at line 132) and `template/init.sh:178` (the `all)` case line)
- Modify: `tests/run-tests.sh` (new section, appended at the end, before the final
  `PASS=$PASSED  FAIL=$FAILED` block)
- Modify: `README.md:79` (one word added to the `init.sh` layout-tree comment)

**Interfaces:**
- Consumes: nothing new — reads `git worktree list` / `git branch --merged` directly, and the existing
  `step()`/`skip()`/`FAIL` globals already defined at the top of `template/init.sh`.
- Produces: the bash function `check_worktree` (no arguments, no return value — same shape as every
  other `check_*` function in this file), callable from the `all)` case. Prints `[WARN]` lines to
  stdout; never touches `FAIL`.

- [ ] **Step 1: Write the failing tests in `tests/run-tests.sh`**

Insert this new section immediately before the final `echo ""` / `echo "PASS=$PASSED  FAIL=$FAILED"`
block at the very end of the file:

```bash
echo ""
echo "== check_worktree: merged worktrees are surfaced as a WARN, never a FAIL =="

# Give the fixture its OWN git repo. .tmp-tests/ sits inside harness-kit's own working tree (it is
# gitignored, but gitignored is not the same as "outside the repo"), so without this,
# `git rev-parse --show-toplevel` from inside the fixture would resolve to harness-kit's OWN root,
# and check_worktree would report harness-kit's real (still uncleaned) .worktrees/feat-tier-rollback
# instead of the fixture's own state. Same reason the 0-SKIP fixture earlier in this file needed its
# own `git init -q`.
init_git_project() {
  local p="$1"
  ( cd "$p" && git init -q \
      && git -c user.email=t@t -c user.name=t add -A \
      && git -c user.email=t@t -c user.name=t commit -qm "init" >/dev/null )
}

P="$(new_project)"
init_git_project "$P"
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "no merged worktree left uncleaned"; then
  ok "no worktrees beyond the current one -> OK, no warning"
else
  ng "no worktrees beyond the current one -> OK, no warning"
fi
rc=0; bash "$P/init.sh" all >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "no worktrees -> exit 0"; else ng "no worktrees -> exit 0 (rc=$rc)"; fi

P="$(new_project)"
init_git_project "$P"
( cd "$P" && git branch -q feat-done && git worktree add -q .worktrees/feat-done feat-done >/dev/null 2>&1 )
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "[WARN] merged worktree(s) not yet cleaned up"; then
  ok "a merged, present worktree -> WARN"
else
  ng "a merged, present worktree -> WARN"
fi
if printf '%s' "$out" | grep -qF "feat-done"; then
  ok "the warning names the branch"
else
  ng "the warning names the branch"
fi
rc=0; bash "$P/init.sh" all >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "a merged worktree -> still exit 0 (never blocks)"; else ng "a merged worktree -> still exit 0 (rc=$rc)"; fi
if printf '%s' "$out" | grep -qF "VERIFY OK"; then ok "a merged worktree -> VERIFY OK still prints"; else ng "a merged worktree -> VERIFY OK still prints"; fi

P="$(new_project)"
init_git_project "$P"
( cd "$P" && git worktree add -q -b feat-wip .worktrees/feat-wip >/dev/null 2>&1 \
    && cd .worktrees/feat-wip \
    && echo "x" > newfile.txt \
    && git -c user.email=t@t -c user.name=t add -A \
    && git -c user.email=t@t -c user.name=t commit -qm "wip" >/dev/null )
out="$(bash "$P/init.sh" all 2>&1)"
if printf '%s' "$out" | grep -qF "[WARN] merged worktree(s)"; then
  ng "an unmerged (active) worktree -> no warning"
else
  ok "an unmerged (active) worktree -> no warning"
fi

if grep -qF "check_worktree" "$KIT/template/init.sh"; then
  ok "init.sh defines check_worktree"
else
  ng "init.sh defines check_worktree"
fi
if grep -qF "check_state; check_worktree" "$KIT/template/init.sh"; then
  ok "the all target runs check_worktree"
else
  ng "the all target runs check_worktree"
fi
```

- [ ] **Step 2: Run the suite to confirm the new section fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "check_worktree\|worktree beyond\|merged, present\|unmerged (active)"`
Expected: every new assertion prints `FAIL` — `check_worktree` does not exist yet, so `./init.sh all`
does not error (unknown functions are simply never called), it just never prints anything about
worktrees at all, and the two `grep -qF "init.sh defines check_worktree"` /
`"the all target runs check_worktree"` checks fail outright since the string is not in the file yet.

- [ ] **Step 3: Add `check_worktree` to `template/init.sh`**

Insert immediately after the existing `check_state()` function (which currently ends at
`template/init.sh:132`, right before the `check_lang` comment block):

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
  # real multi-worktree repo during this check's own design (the line after "worktree <path>" is
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
    # during this check's design — a sed pattern stripping only "* " leaves the "+ " row never
    # matching, silently hiding every merged worktree from detection).
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

- [ ] **Step 4: Wire it into the `all)` case**

Find (`template/init.sh:171-180`):

```bash
case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  docs)     check_docs ;;
  state)    check_state ;;
  lang)     : ;;                 # nothing extra — the unconditional run below is the whole target
  all)      check_scaffold; check_build; check_secret; check_docs; check_state ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac
```

Replace the `all)` line only:

```bash
case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  docs)     check_docs ;;
  state)    check_state ;;
  lang)     : ;;                 # nothing extra — the unconditional run below is the whole target
  all)      check_scaffold; check_build; check_secret; check_docs; check_state; check_worktree ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac
```

(`check_worktree` is deliberately absent from the `case` dispatch itself — there is no standalone
`worktree)` target, per the spec's decision that this is repo hygiene surfaced under `all`, not a
feature-scoped verification a Homeowner would ever want to run in isolation.)

- [ ] **Step 5: Update the README layout-tree comment**

Find (`README.md:79`):

```
    ├── init.sh               # verification: build/test + secret grep + dossier + state + language
```

Replace with:

```
    ├── init.sh               # verification: build/test + secret grep + dossier + state + worktree hygiene + language
```

- [ ] **Step 6: Run the suite to confirm the new section passes**

Run: `bash tests/run-tests.sh 2>&1 | grep -A1 "check_worktree\|worktree beyond\|merged, present\|unmerged (active)"`
Expected: every new assertion prints `PASS`.

- [ ] **Step 7: Run the full suite**

Run: `bash tests/run-tests.sh`
Expected: `FAIL=0`, and the final `PASS=<N>` line shows a number 8 higher than before this task
(8 new assertions: no-worktree OK, no-worktree exit 0, merged→WARN, warning names the branch,
merged→still exit 0, merged→VERIFY OK still prints, unmerged→no warning, `check_worktree` defined,
`all` wires it in — count them against the actual new lines added in Step 1 if this number drifts;
what matters is `FAIL=0`, not hitting this exact figure).

- [ ] **Step 8: Commit**

```bash
git add template/init.sh tests/run-tests.sh README.md
git commit -m "feat(init): add check_worktree — WARN on merged-but-uncleaned worktrees under ./init.sh all"
```

---

## Completion checklist (matches spec §5)

- [ ] A repo with a merged, present worktree → `./init.sh all` prints `[WARN]` naming the path and
      branch, and still exits 0.
- [ ] A repo with only unmerged worktrees (active work) → no warning.
- [ ] A repo with no worktrees beyond the current one → prints `OK`, no warning.
- [ ] `bash tests/run-tests.sh` green, with the new assertions counted.

Note: the spec's "not a git repository → SKIP, not a false OK" criterion is implemented defensively
in `check_worktree` (the `git rev-parse --is-inside-work-tree` guard) but is **not** given a dedicated
test in this plan — every fixture directory under `.tmp-tests/` is, by construction, already inside
harness-kit's own git working tree (merely gitignored, not excluded), so there is no way to construct
a "truly not a git repository" fixture without changing how `tests/run-tests.sh` itself is invoked.
This matches existing precedent: `check_lang`'s own "not a git repository" branch
(`template/init.sh:158-159`) has no dedicated test either, for the identical reason.
