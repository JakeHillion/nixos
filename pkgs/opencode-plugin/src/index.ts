import type { Plugin } from "@opencode-ai/plugin";
import * as fs from "node:fs";
import * as path from "node:path";
import { nixHook } from "./hooks/nix.js";
import { jjRedirectHook } from "./hooks/jj-redirect.js";
import { extractRepoPath, redundantCwdCheck } from "./hooks/redundant-cwd.js";

export type { HookResult } from "./types.js";

const plugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return;

      const command = output.args.command;
      if (typeof command !== "string") return;
      const cwd = process.cwd();

      // --- nix hook ---
      const nixResult = nixHook(command);
      if (nixResult.action === "block") {
        throw new Error(nixResult.reason);
      }
      if (nixResult.action === "modify") {
        output.args.command = nixResult.command;
      }
      if (nixResult.action === "approve_modify") {
        output.args.command = nixResult.command;
      }

      // --- redundant-cwd hook ---
      const rawPath = extractRepoPath(output.args.command);
      if (rawPath !== null) {
        try {
          const resolvedArgPath = fs.realpathSync(
            path.isAbsolute(rawPath) ? rawPath : path.join(cwd, rawPath),
          );
          const resolvedCwd = fs.realpathSync(cwd);
          const cwdResult = redundantCwdCheck(resolvedArgPath, resolvedCwd);
          if (cwdResult.action === "block") {
            throw new Error(cwdResult.reason);
          }
        } catch (e: unknown) {
          if (
            e instanceof Error &&
            "code" in e &&
            (e as NodeJS.ErrnoException).code === "ENOENT"
          ) {
            // path doesn't exist, skip the check
          } else {
            throw e;
          }
        }
      }

      // --- jj-redirect hook ---
      const jjDirExists = fs.existsSync(path.join(cwd, ".jj"));
      const jjResult = jjRedirectHook(output.args.command, jjDirExists);
      if (jjResult.action === "block") {
        throw new Error(jjResult.reason);
      }
    },
  };
};

export default plugin;
