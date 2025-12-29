---
name: jj
description: Use when performing VCS operations in a directory with a .jj directory.
---

# Jujutsu Version Control

**This repository uses Jujutsu (jj), not Git. Do not use git commands.**

Use `jj` for all version control operations. Run `jj --help` for full documentation.

Common commands:
- `jj status` / `jj st` - show working copy status
- `jj log` - show commit history
- `jj diff --git` - show changes (use --git for readable diffs)
- `jj new` - create a new empty change on top
- `jj describe -m "message"` - set/update commit description
- `jj squash` - squash working copy into parent
- `jj git push` - push to remote
- `jj git fetch` - fetch from remote

File tracking (use when `jj status` shows untracked files):
- `jj file track <path>` - start tracking a file
- `jj file untrack <path>` - stop tracking a file

## Workflow

Always keep an empty working copy commit on top. The typical flow:

1. Make changes (they go into the working copy `@`)
2. When done, run `jj squash` to fold changes into parent
3. Run `jj new` to create a fresh empty commit on top

To amend a commit: just make changes and `jj squash` - this folds the working copy into the parent. Then `jj new` to restore the empty working copy on top.

Key differences from Git:
- Working copy is automatically a commit (no staging area)
- No `git commit --amend` - use `jj squash` instead
- Branches are called "bookmarks" (`jj bookmark`)
