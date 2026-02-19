import type { HookResult } from "../types.js";

export function nixHook(command: string): HookResult {
  const isNixBuild = /(?:^|[;&|])\s*nix\s+build\b/.test(command);
  const isNixRun = /(?:^|[;&|])\s*nix\s+run\b/.test(command);

  // Only act on commands containing nix build or nix run
  if (!isNixBuild && !isNixRun) {
    return { action: "allow" };
  }

  let modified = command;

  // For nix build only: add --no-link and --print-out-paths if missing
  if (isNixBuild) {
    if (!modified.includes("--no-link")) {
      modified = modified.replace(/(nix\s+build)/, "$1 --no-link");
    }
    if (!modified.includes("--print-out-paths")) {
      modified = modified.replace(/(nix\s+build)/, "$1 --print-out-paths");
    }
  }

  // Quote unquoted .# arguments for both nix build and nix run
  modified = modified.replace(
    /([ \t])([^ \t'"]*\.#[^ \t'"]*)/g,
    '$1"$2"',
  );

  // Always approve nix build commands
  if (isNixBuild) {
    if (modified === command) {
      return { action: "approve" };
    }
    return { action: "approve_modify", command: modified };
  }

  if (modified === command) {
    return { action: "allow" };
  }

  return { action: "modify", command: modified };
}
