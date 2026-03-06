import * as fs from "node:fs";
import * as path from "node:path";
import { nixHook } from "../src/hooks/nix.js";
import { jjRedirectHook } from "../src/hooks/jj-redirect.js";
import {
  extractRepoPath,
  redundantCwdCheck,
} from "../src/hooks/redundant-cwd.js";
import type { HookResult } from "../src/types.js";

function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.on("data", (chunk: Buffer) => (data += chunk.toString()));
    process.stdin.on("end", () => resolve(data));
  });
}

async function main() {
  const stdin = await readStdin();
  const input = JSON.parse(stdin);

  const command: string = input.tool_input.command;
  const cwd: string = input.cwd || process.cwd();

  let currentCommand = command;

  // --- nix hook ---
  let nixApprove = false;
  const nixResult = nixHook(currentCommand);
  if (nixResult.action === "block") {
    process.stderr.write(nixResult.reason);
    process.exit(2);
  }
  if (nixResult.action === "modify") {
    currentCommand = nixResult.command;
  }
  if (nixResult.action === "approve") {
    nixApprove = true;
  }
  if (nixResult.action === "approve_modify") {
    currentCommand = nixResult.command;
    nixApprove = true;
  }

  // --- jj-redirect hook ---
  const jjDirExists = fs.existsSync(path.join(cwd, ".jj"));
  const jjResult = jjRedirectHook(currentCommand, jjDirExists);
  if (jjResult.action === "block") {
    process.stderr.write(jjResult.reason);
    process.exit(2);
  }

  // --- redundant-cwd hook ---
  const rawPath = extractRepoPath(currentCommand);
  if (rawPath !== null) {
    try {
      const resolvedArgPath = fs.realpathSync(
        path.isAbsolute(rawPath) ? rawPath : path.join(cwd, rawPath),
      );
      const resolvedCwd = fs.realpathSync(cwd);
      const cwdResult = redundantCwdCheck(resolvedArgPath, resolvedCwd);
      if (cwdResult.action === "block") {
        process.stderr.write(cwdResult.reason);
        process.exit(2);
      }
    } catch {
      // If realpath fails (path doesn't exist), skip the check
    }
  }

  // Output the Claude protocol response if command was modified or needs approval
  if (currentCommand !== command || nixApprove) {
    const output: Record<string, unknown> = {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: nixApprove ? "allow" : "ask",
        ...(currentCommand !== command && {
          updatedInput: { command: currentCommand },
        }),
      },
    };
    process.stdout.write(JSON.stringify(output));
  }

  process.exit(0);
}

main().catch((err: Error) => {
  process.stderr.write(`Hook error: ${err.message}`);
  process.exit(1);
});
