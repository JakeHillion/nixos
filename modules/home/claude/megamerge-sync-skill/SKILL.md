---
name: megamerge-sync
description: Use when bringing a jj megamerge up to date with the remote, or pulling remote branches into it. Rebases everything under the megamerge onto the latest trunk, drops what has landed, and optionally adds the heads of a revset as new substacks.
argument-hint: "[revset…]"
---

# Syncing the megamerge

Read the `megamerge` skill first and find `M`. Arguments: $ARGUMENTS

Sync rewrites `M`. Don't run it while another operation that rewrites
`M` is running, such as a placement agent.

## Steps

1. **Fetch.** `jj git fetch`. Commits on remote branches that were
   force-pushed are followed automatically, including ones under `M`.
2. **Adopt.** For each revset argument, add its heads as parents of `M`:

   ```
   jj rebase -s <M> -o 'parents(<M>) | heads(<revset>)'
   ```

   An argument is usually a remote bookmark (`feature/x@origin`) or a
   local stack. Skip heads already in `::<M>`.
3. **Rebase onto trunk.** Move every root of your own work under `M`
   whose parents have all landed:

   ```
   jj rebase -s 'roots((trunk()..<M>) & mutable()) ~ children(~::trunk())' -o 'trunk()' --skip-emptied
   ```

   Don't use `rebase -b`: it fails on immutable commits under `M`, such as
   an adopted remote branch, and those stay where they are. A commit of
   yours stacked on someone else's branch stays on it until that branch
   lands. A landed commit keeps its change ID, so its local copy is
   dropped, either as divergent or emptied.
4. **Simplify.** Drop the parents and merges that landing made
   redundant:

   ```
   jj simplify-parents -s '(trunk()..<M>) & mutable()'
   jj abandon '(trunk()..<M> & mutable() & empty() & ~merges()) ~ <M>'
   ```

   A merge loses each parent that lands. Once it has one left, the
   first command leaves it as a plain empty commit and the second
   abandons it.
5. **Check.** Confirm `M` is empty, the working copy is an empty commit
   on `M`, and nothing is divergent. List conflicted commits with
   `jj log -r 'trunk()..<M> & conflicts()'`.

## Conflicts

Hand conflicts to a fresh general-purpose subagent, one at a time,
starting with the commit closest to `trunk()`, since resolving that
often clears its descendants. Its prompt gives the commit, `M`, and
these rules:

- resolve in its own workspace on the conflicted commit, then
  `jj squash` the resolution into it;
- keep the commit's intent and message, and touch no other commit;
- run the repository's checks on the result;
- don't push;
- report what conflicted and how it resolved it.

A conflict in someone else's branch can't be resolved here. Tell the
user, and offer to drop that branch from `M`.

## Report

Tell the user, briefly:

- what landed and dropped out;
- what was adopted;
- what conflicts remain, if any;
- which commits now sit directly on `trunk()`, so are ready to merge on
  their own, and which still wait on others.
