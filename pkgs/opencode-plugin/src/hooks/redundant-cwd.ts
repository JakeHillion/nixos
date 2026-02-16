import type { HookResult } from "../types.js";

/**
 * Extract the path argument from git -C or jj -R/--repository flags.
 * Returns null if no such flag is present.
 */
export function extractRepoPath(command: string): string | null {
  const match = command.match(
    /(?:git\s+-C|jj\s+(?:-R|--repository))\s+(\S+)/,
  );
  if (!match) return null;

  // Strip surrounding quotes if present
  return match[1].replace(/^['"]|['"]$/g, "");
}

export function redundantCwdCheck(
  resolvedArgPath: string,
  resolvedCwd: string,
): HookResult {
  if (resolvedArgPath === resolvedCwd) {
    return {
      action: "block",
      reason:
        "Redundant -C/-R flag: the path is already the working directory. Run the command without it.",
    };
  }
  return { action: "allow" };
}
