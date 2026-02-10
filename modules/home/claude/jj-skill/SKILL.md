---
name: jj
description: Use when running git commands, committing, pushing, pulling, or checking status in a jj repository.
---

# Jujutsu Version Control

**This repository uses Jujutsu (jj), not Git. Do not use git commands.**

Use `jj` for all version control operations. Run `jj --help` for full documentation.

Common commands:
- `jj status` / `jj st` - show working copy status
- `jj log` - show commit history
- `jj diff --git` - show changes (use --git for readable diffs)
- `jj new` - create a new empty change on top
- `jj describe -m "message"` - set/update commit description. use `jj commit -m "message"` if attempting to describe the unnamed commit at the top to ensure there is still a new empty change on top after.
- `jj squash` - squash working copy into parent
- `jj git push` - push to remote
- `jj git fetch` - fetch from remote
- `jj file show -r REV FILE` - read a file's content at a specific revision

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
- We always expect a staging commit at the top of the stack. Do not attempt to remove it/describe it. Use `jj commit` to turn the working commit into a named commit _and_ name a new commit on top of it.
- No `git commit --amend` - use `jj squash` instead
- Branches are called "bookmarks" (`jj bookmark`)

This skill does not require you to take any action unless specifically asked for. Feel free to inspect the state of the repository, but don't take this as an instruction to create a commit/squash etc.
