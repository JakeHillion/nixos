---
name: nix
description: Use when running Nix commands with flakes.
---

# Nix Flake Syntax

**Always quote flake targets containing `.#`**

Examples:
- ✓ `nix build ".#foo"`
- ✗ `nix build .#foo`

Common commands:
- `nix flake check` - validate flake
- `nix fmt` - format code (if repo uses it)

# Command details

When running `nix build`, always append `--no-link`. If you care about the output
append `--print-out-path`. Forgetting `--no-link` leads to clutter with various
`result` symlinks appearing in the directory.
