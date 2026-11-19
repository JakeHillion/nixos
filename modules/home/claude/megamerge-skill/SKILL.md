---
name: megamerge
description: Use when working in a jj repository with a megamerge, an empty merge commit tying together many in-flight commits so the working copy sees all of them at once. Covers finding the megamerge, its invariants, creating one, adding and removing commits, and the contract an agent follows to add a commit to it.
user-invocable: false
---

# The jj megamerge

Every commit is one PR. Commits waiting for review are kept as a set of
substacks on `trunk()`, tied together by the megamerge `M`: an empty
merge commit whose parents are the tip of every substack. The working
copy is an empty commit on `M`, so builds and agents see every commit
at once, while each commit only depends on what it needs and can merge
on its own.

```
@        (empty)
○        M
├─┬─┬─╮
│ │ │ ○  F5
│ │ ○ │  F4
│ │ ○ │  F2
│ ○ │ │  F3
○ │ │ │  F1
├─┴─┴─╯
◆  trunk()
```

`megamerge-sync` brings `M` up to date with the remote. `megamerge-place`
moves a commit down to the fewest parents it needs.

## Finding M

`M` is known by its change ID, never by a bookmark. Find it in this
order:

1. A change ID the user gave.
2. `@-`, if it's an empty merge:
   `jj log -r '@- & merges() & empty()'`.
3. `jj log -r 'description(exact:"megamerge\n") & merges() & empty() & mine()'`.

If that finds several, ask which. If it finds none, offer to create one
(below). Once found, use the change ID for the rest of the task: it
survives every rewrite.

## Invariants

- `M` is empty, has no conflicts, and has no bookmark.
- `M`'s commits are `trunk()..M ~ merges()`. Each is one PR.
- A commit only sits on another when it needs it. A commit that needs
  commits from two substacks sits on an empty merge of exactly those
  commits, which stays until sync simplifies it away. Every merge under
  `M` other than `M` itself is one of these.
- `M` has no redundant parents. Run `jj simplify-parents -r <M>` after
  anything that changes them.
- Other people's commits, such as a remote branch under review, can be
  parents of `M` or sit under one. They're immutable: never rewrite
  them.
- Only one operation that rewrites `M` runs at a time: sync, placement,
  and adding or removing a commit. Two at once each rewrite `M` and
  leave it divergent. If `jj log -r 'divergent()'` shows `M`, stop and
  tell the user.
- Nothing is pushed unless the user asks.

## Creating M

Make `M` on `trunk()` and the tips of any work the user wants in it,
then put the working copy on it:

```
jj new 'trunk()' <tips…> --no-edit -m megamerge
jj simplify-parents -r <M>
jj new <M>
```

`simplify-parents` drops `trunk()` once a tip already sits on it.

## Adding and removing commits

Add a commit `X`, and anything under it, as a new substack:
`jj rebase -s <M> -o 'parents(<M>) | <X>'`. That rewrites only `M` and
its descendants. To move a commit of your own to sit directly on
`trunk()` as it joins, use `jj rebase -r <X> -A 'trunk()' -B <M>`.
`megamerge-sync` with a revset argument adds remote branches the same
way.

Drop a substack tip from `M`, leaving the commits where they are:
`jj rebase -s <M> -o 'parents(<M>) ~ <X>'`.

## The worker contract

An agent that makes a commit for the megamerge works like this. Prompts
can say "follow the megamerge worker contract" with `M`'s change ID:

- Work in its own workspace under `/tmp`, with the working copy on `M`:
  `jj workspace add --name <name> -r <M> /tmp/<name>`. Several workers
  can run at once, since making a child of `M` doesn't rewrite `M`.
- Make exactly one commit whose only parent is `M`, mergeable on its own
  as one PR, following the repository's commit rules. Commit with
  `jj commit`, so the workspace's working copy ends up empty on it.
- Don't move the commit, don't touch any other commit, and don't push.
- When done, run `jj workspace forget <name>` and `rm -rf /tmp/<name>`.
  Forgetting abandons the empty working copy and leaves the commit.
- Report the commit's change ID.

The new commit then goes through `megamerge-place`.
