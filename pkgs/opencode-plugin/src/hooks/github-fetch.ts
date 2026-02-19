import { spawnSync } from "node:child_process";
import type { HookResult } from "../types.js";

export interface GitHubUrl {
  owner: string;
  repo: string;
  ref: string | null;
  filePath: string | null;
}

export function parseGitHubUrl(url: string): GitHubUrl | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }

  const segments = parsed.pathname.split("/").filter(Boolean);

  if (parsed.hostname === "raw.githubusercontent.com") {
    if (segments.length < 3) return null;
    const [owner, repo, ref, ...rest] = segments;
    return {
      owner,
      repo,
      ref,
      filePath: rest.length > 0 ? rest.join("/") : null,
    };
  }

  if (parsed.hostname !== "github.com" && parsed.hostname !== "www.github.com")
    return null;

  if (segments.length < 2) return null;
  const [owner, repo, action, ref, ...rest] = segments;

  if (!action) {
    return { owner, repo, ref: null, filePath: null };
  }

  if (action === "tree" || action === "blob") {
    if (!ref) return null;
    return {
      owner,
      repo,
      ref,
      filePath:
        action === "blob" && rest.length > 0 ? rest.join("/") : null,
    };
  }

  return null;
}

export function parseStorePath(output: string): string | null {
  const match = output.match(
    /Downloaded '.*?' to '(\/nix\/store\/[^']+)'/,
  );
  return match ? match[1] : null;
}

export function githubFetchHook(url: string): HookResult {
  const gh = parseGitHubUrl(url);
  if (!gh) return { action: "allow" };

  const flakeRef = gh.ref
    ? `github:${gh.owner}/${gh.repo}/${gh.ref}`
    : `github:${gh.owner}/${gh.repo}`;

  const result = spawnSync("nix", ["flake", "prefetch", flakeRef], {
    encoding: "utf-8",
    timeout: 120_000,
  });

  const combined = (result.stdout || "") + (result.stderr || "");
  const storePath = parseStorePath(combined);

  if (!storePath) {
    const detail = combined.trim() || result.error?.message || "unknown error";
    return {
      action: "block",
      reason: `Failed to prefetch ${flakeRef}: ${detail}\nUse the github-fetch skill (/github-fetch) in the main conversation for GitHub URLs.`,
    };
  }

  const readInstructions = gh.filePath
    ? `Use the Read tool to read: ${storePath}/${gh.filePath}`
    : `Use the Read tool or Glob tool to explore: ${storePath}/`;

  return {
    action: "block",
    reason: `GitHub repository prefetched to Nix store. Do NOT use WebFetch for GitHub URLs.\n\nStore path: ${storePath}\n${readInstructions}`,
  };
}
