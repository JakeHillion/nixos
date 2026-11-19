---
name: megamerge-place
description: Use when a new commit has been made on a jj megamerge and should be moved down to the fewest parents it needs, so it can be reviewed and merged as independently as possible. Takes the commit's change ID and optionally the megamerge's.
argument-hint: "<commit> [megamerge]"
context: fork
agent: general-purpose
---

# Placing a commit under the megamerge

Read the `megamerge` skill first. You own commit $0 (`X`), which was made
on the megamerge `M`. If a megamerge is given, it is $1.

Give `X` the fewest parents it needs, so it's as close as possible to a
PR that merges on its own. Try `trunk()` first. If `X` conflicts there
or fails the repository's own checks, work out which commits under `M`
it relies on and put it on those. Where that's the middle of a substack,
`X` branches off there. `M`'s parents always work, since that's where
`X` was made.

```
before:  trunk() ── F1 ── F2 ── M ── X
after:   trunk() ── F1 ── F2 ── M
                     └─ X
```

When `X` needs commits from more than one substack, it sits on an empty
merge of exactly those commits. Look for an existing merge under `M`
whose parents are exactly that set, with nothing extra, and put `X` on
it. If there isn't one, create it.

```
  ○  X
  ○  merge(F1, F3)
╭─┤
│ ○  F3
○ │  F1
├─╯
◆  trunk()
```

Move only `X`, and never change its content or message. Don't rewrite
`M`: the main session adds `X` back under it from your report. Build
in a workspace of your own in an appropriate temporary directory. Use
the checks the repository documents, and ask if it documents none.

Report `X`'s parents and why it needs each, and how the check went.
