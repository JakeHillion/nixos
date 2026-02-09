---
name: github-fetch
description: Use when fetching files from GitHub, browsing GitHub repositories, or accessing raw.githubusercontent.com URLs.
---

# Accessing GitHub Repositories

**Never use `WebFetch` or `curl` to access GitHub repository contents.** Instead, use `nix flake prefetch` to download the repository to the local Nix store, then read files directly.

## Procedure

**Each step below MUST be a separate Bash invocation. Never combine these steps using `&&`, `;`, `$()`, subshells, or pipes. The store path must be copied from the output of step 1 and pasted literally into step 2.**

1. **Prefetch the repository** (single command, no pipes or subshells):

   ```bash
   nix flake prefetch github:OWNER/REPO       # latest default branch
   nix flake prefetch github:OWNER/REPO/REF   # specific branch, tag, or commit
   ```

   This prints the store path. Read it from the output:
   ```
   Downloaded '...' to '/nix/store/abc123-source' (hash '...')
   ```

2. **List the store path** in a separate Bash call to gain read access for the session. Copy the literal path from the output above:

   ```bash
   ls /nix/store/abc123-source/
   ```

3. **Read files** directly from the store path using the `Read` tool.

## URL mapping

When you encounter a GitHub URL, extract the owner, repo, and optional ref:

| URL pattern | Prefetch command |
|---|---|
| `github.com/OWNER/REPO` | `nix flake prefetch github:OWNER/REPO` |
| `github.com/OWNER/REPO/tree/REF` | `nix flake prefetch github:OWNER/REPO/REF` |
| `github.com/OWNER/REPO/blob/REF/path/to/file` | `nix flake prefetch github:OWNER/REPO/REF` then read `path/to/file` |
| `raw.githubusercontent.com/OWNER/REPO/REF/path` | `nix flake prefetch github:OWNER/REPO/REF` then read `path` |

## Example

To read `README.md` from `BurntSushi/ripgrep` at tag `14.1.1`:

**Bash call 1:**
```bash
nix flake prefetch github:BurntSushi/ripgrep/14.1.1
```
Output: `Downloaded '...' to '/nix/store/sp0czi5mp89y5akbaaz2nhs8cd9nx6z3-source' (hash '...')`

**Bash call 2** (copy the store path from above):
```bash
ls /nix/store/sp0czi5mp89y5akbaaz2nhs8cd9nx6z3-source/
```

**Step 3:** Use the `Read` tool on `/nix/store/sp0czi5mp89y5akbaaz2nhs8cd9nx6z3-source/README.md`.
