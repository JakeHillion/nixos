---
name: megamerge-sync
description: Use when bringing a jj megamerge up to date with the remote, or pulling remote branches into it. Rebases the work under the megamerge onto the latest trunk, drops what has landed, and optionally adds the heads of a revset as new substacks.
argument-hint: "[revset…]"
---

# Syncing the megamerge

Read the `megamerge` skill first. Sync rewrites `M`, so it runs in the
main session.

The goal is that every commit under `M` that sat on the old `trunk()`
now sits on the new one. Everything above those commits comes along
with them: the rest of each substack, `M`, and any work in progress on
`M`. If nothing is left under `M`, `M` itself is what sits on the old
`trunk()`, so it moves too.

```
jj git fetch
jj rebase -s 'roots(trunk()..<M>) & mutable()' -o 'trunk()' --simplify-parents --skip-emptied
jj abandon '(trunk()..<M>) & empty() & ~merges() ~ <M>'
```

A commit that landed keeps its change ID, so the rebase drops its local
copy. `--simplify-parents` then removes every parent that is now part of
`trunk()`, which turns a merge whose other side landed into a plain
empty commit. `--skip-emptied` won't drop that commit, because it was
already empty, so the `abandon` does. Here F1 lands, and the merge X sat
on goes away:

```
before                           after
○  M                             ○  M
├─╮                              ├─╮
│ ○  X                           │ ○  X
│ ○  merge(F1, F2)               │ ○  F2
│ ├─╮                            ○ │  F3
│ │ ○  F2                        ├─╯
│ ○ │  F1                        ◆  F1   ← trunk()
○ │ │  F3                        ◆  upstream
├─┴─╯                            ◆  old trunk()
◆  old trunk()
```

`& mutable()` leaves alone any branch you didn't write that has been
pulled in. jj treats other people's remote branches as immutable, so
they stay on the base their author gave them, and your commits on top
of them stay there too, until those branches land.

Each revset in the arguments ($ARGUMENTS) is pulled in: its heads become
parents of `M`, with
`jj rebase -s <M> -o 'parents(<M>) | heads(<revset>)' --simplify-parents`. This is usually someone's branch under review, or a
stack of yours. A branch already pulled in follows force-pushes on its
own when you fetch.

Hand any conflicts to an agent, starting nearest `trunk()`.

Finish by telling the user what landed, what came in, what conflicts,
and which commits now sit directly on `trunk()`, ready to merge.
