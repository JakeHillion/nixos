---
name: megamerge-place
description: Use when a new commit has been made on a jj megamerge and should be moved down to the fewest parents it needs, so it can be reviewed and merged as independently as possible. Takes the commit's change ID and optionally the megamerge's.
argument-hint: "<commit> [megamerge]"
context: fork
agent: general-purpose
---

# Placing a commit under the megamerge

Read the `megamerge` skill first. The commit `X` is `$0`. `M` is `$1`;
if that isn't a change ID, find `M` as the `megamerge` skill says.

The goal is to give `X` the fewest parents it needs, so that as much as
possible it is a PR that can be reviewed and merged on its own. `X`
usually starts as a child of `M`, where it was made and tested.

## Rules

- Never change `X`'s content or message, and touch no other commit,
  except to create an empty merge for `X` to sit on.
- Don't push.
- Only the final rebase rewrites `M`. Every trial runs on a duplicate of
  `X`, so the user and other agents can keep working on `M` while you
  build.

## The check

A placement stands if `X` has no conflicts on it and the repository's
checks pass with the working copy on `X`. Use the checks the
repository documents for a commit (CLAUDE.md, AGENTS.md,
CONTRIBUTING.md). Scope them to what `X` affects if the repository says
how. If the repository documents no checks, stop and ask.

## Steps

1. Record `X`'s commit ID now: `jj log --no-graph -r <X> -T commit_id`.
   This is `BEFORE`, used at the end.
2. Try `trunk()` first, then a wider base if needed. To try a base `B`:

   ```
   jj duplicate -r <X> -o <B>
   jj workspace add --name place-<X> -r <duplicate> /tmp/place-<X>
   ```

   `duplicate` prints the new commit's change ID. If the duplicate has a
   conflict, `B` fails without building. Otherwise run the check in the
   workspace. Afterwards, clean up:
   `jj workspace forget place-<X>`, `rm -rf /tmp/place-<X>`,
   `jj abandon <duplicate>`.
3. If `trunk()` fails, work out which of `trunk()..<M> ~ merges()` `X`
   needs: commits it conflicts without, and commits whose code or tests
   its diff relies on. Its base is the heads of that set. One head can
   be in the middle of a substack, so `X` branches off there. Several
   heads need an empty merge of exactly those commits. Reuse one if it
   exists, otherwise try the base with `jj duplicate -r <X> -o <h1> -o <h2>`
   and create the merge only once the base passes. If the check fails,
   widen the set and try again. `M`'s parents always work, since that is
   where `X` was made.
4. Place `X` on the base that passed. For several heads, first create
   the merge with `jj new <heads…> --no-edit`.

   ```
   jj rebase -r <X> -A <base> -B <M>
   jj simplify-parents -r <M>
   ```

5. Check the result:
   - `jj diff --from <BEFORE> --to <M>` is empty. `M` now holds exactly
     what `X` held on `M`, so placing `X` changed nothing in the combined
     tree. If it isn't empty, something is wrong: stop and report.
   - `M` is empty, has no conflicts, and is not divergent.
   - The working copy is still an empty commit on `M`. If you moved it,
     run `jj new <M>`.

## Report

Give:

- `X`'s parents, and why it needs each one;
- the bases tried and why each failed;
- the check's result on the placement that passed;
- the result of the tree comparison.
