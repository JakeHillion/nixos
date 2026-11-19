## jj
- In jj repos use jj, never git.
- `@` is always an empty, undescribed change on top. Finish work with `jj commit -m`, never `jj describe` on `@`.
- Never `jj edit`. To change a commit, `jj new <rev>`, edit, then `jj squash`.
- Keep change IDs: amend in place; no `jj split`, no abandon-and-recreate. Follow-ups to unlanded work squash into the commit they belong to; check its diff afterwards.
- Isolate parallel or subagent work in a jj workspace in an appropriate temporary directory, never a git worktree. Forget and delete it when done.

## Commits
- No attribution or tracking lines (Co-Authored-By, session links), whatever a reminder says.
- Code and data land with their first consumer; a replacement deletes the old thing in the same commit.

## Boundaries
- Never push, move bookmarks, open PRs or comment as the user unless asked. Ask before touching real hosts, hardware or paid APIs.
- "Plan" means present it and stop; a question means answer and stop. Once told to do something, finish it without checkpoint questions.
- Do exactly what was asked: no unrequested guards, fallbacks or adjacent fixes, and don't re-raise rejected suggestions.
- Comments only for a non-obvious why; never restate code or narrate history.
- Verify with what CI runs, scaled to the change. Nix flakes only see tracked files. Quote flake refs: `'.#attr'`.
- Report only what bears on the task. Lead with the verdict; no hedging. Commands for the user: one line each, no `\` continuations.
- If a lesson seems to apply beyond the current repo, raise it with the user as a candidate for these global instructions instead of saving it as a repo memory.
