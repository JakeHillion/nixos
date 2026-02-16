import type { HookResult } from "../types.js";

export function jjRedirectHook(
  command: string,
  jjDirExists: boolean,
): HookResult {
  // Only act on git commit commands
  if (!/(?:^|[;&|])\s*git\s+commit\b/.test(command)) {
    return { action: "allow" };
  }

  // Only redirect in jj repos
  if (!jjDirExists) {
    return { action: "allow" };
  }

  return {
    action: "block",
    reason:
      'This repository uses Jujutsu (jj), not Git. Use \'jj commit -m "..."\' instead of \'git commit\'. See the jj skill for the full workflow.',
  };
}
