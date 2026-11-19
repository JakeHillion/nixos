---
name: megamerge
description: Use when working in a jj repository with a megamerge, an empty merge commit tying together many in-flight commits so the working copy sees all of them at once. Covers what the megamerge is, how to find it, who may move it, and how an agent adds a commit to it.
user-invocable: false
---

# The jj megamerge

Every commit is one PR. Commits waiting for review sit in substacks on
`trunk()`, tied together by the megamerge `M`: an empty merge whose
parents are the tips of every substack. The working copy is an empty
commit on `M`, so builds and agents see all the in-flight work at once,
while each commit depends only on what it needs and can merge on its
own.

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

A commit that needs work from two substacks sits on an empty merge of
exactly those commits, until one of them lands. Other people's branches
can be substacks too; they're immutable, so leave them as they are.

`M` is found, never stored. Use the change ID the user gives, or `@-` if
it's an empty merge, or your own empty merge described `megamerge`. If
there's more than one candidate, ask; if there's none, offer to make one
on `trunk()` and whatever tips the user wants in it. It never carries a
bookmark.

`megamerge-sync` brings `M` up to date with the remote. `megamerge-place`
moves a new commit down to the fewest parents it needs.

## Who moves what

Only the main session rewrites `M`, and it does one such change at a
time. Anything else working on top of `M` owns exactly one change, which
is the only commit it touches.

Rewriting `M` also rewrites everything on top of it, so a change can
diverge if `M` moves while its owner is changing it. The owner keeps the
version with its own latest work and abandons the other. `change_id()`
names every version of a divergent change.

## Adding a commit

Changes are made on `M`, each as exactly one commit whose only parent is
`M`. `megamerge-place` then moves the commit down to its base, and the
main session makes it a parent of `M`, dropping any parent it makes
redundant with `jj simplify-parents`.
