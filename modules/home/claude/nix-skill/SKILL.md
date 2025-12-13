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
