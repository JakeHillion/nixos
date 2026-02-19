import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  parseGitHubUrl,
  parseStorePath,
} from "../src/hooks/github-fetch.js";

describe("parseGitHubUrl", () => {
  it("returns null for non-GitHub URLs", () => {
    assert.strictEqual(parseGitHubUrl("https://example.com/foo"), null);
  });

  it("returns null for invalid URLs", () => {
    assert.strictEqual(parseGitHubUrl("not a url"), null);
  });

  it("parses github.com/OWNER/REPO", () => {
    assert.deepStrictEqual(
      parseGitHubUrl("https://github.com/NixOS/nixpkgs"),
      { owner: "NixOS", repo: "nixpkgs", ref: null, filePath: null },
    );
  });

  it("parses github.com/OWNER/REPO/tree/REF", () => {
    assert.deepStrictEqual(
      parseGitHubUrl("https://github.com/NixOS/nixpkgs/tree/master"),
      { owner: "NixOS", repo: "nixpkgs", ref: "master", filePath: null },
    );
  });

  it("parses github.com/OWNER/REPO/tree/REF/subdir (no filePath)", () => {
    assert.deepStrictEqual(
      parseGitHubUrl(
        "https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name",
      ),
      { owner: "NixOS", repo: "nixpkgs", ref: "master", filePath: null },
    );
  });

  it("parses github.com/OWNER/REPO/blob/REF/path/to/file", () => {
    assert.deepStrictEqual(
      parseGitHubUrl(
        "https://github.com/NixOS/nixpkgs/blob/master/flake.nix",
      ),
      {
        owner: "NixOS",
        repo: "nixpkgs",
        ref: "master",
        filePath: "flake.nix",
      },
    );
  });

  it("parses blob URLs with deep paths", () => {
    assert.deepStrictEqual(
      parseGitHubUrl(
        "https://github.com/NixOS/nixpkgs/blob/nixos-24.11/pkgs/by-name/he/hello/package.nix",
      ),
      {
        owner: "NixOS",
        repo: "nixpkgs",
        ref: "nixos-24.11",
        filePath: "pkgs/by-name/he/hello/package.nix",
      },
    );
  });

  it("parses raw.githubusercontent.com URLs", () => {
    assert.deepStrictEqual(
      parseGitHubUrl(
        "https://raw.githubusercontent.com/NixOS/nixpkgs/master/flake.nix",
      ),
      {
        owner: "NixOS",
        repo: "nixpkgs",
        ref: "master",
        filePath: "flake.nix",
      },
    );
  });

  it("parses raw.githubusercontent.com with deep paths", () => {
    assert.deepStrictEqual(
      parseGitHubUrl(
        "https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/he/hello/package.nix",
      ),
      {
        owner: "NixOS",
        repo: "nixpkgs",
        ref: "master",
        filePath: "pkgs/by-name/he/hello/package.nix",
      },
    );
  });

  it("returns null for raw.githubusercontent.com with too few segments", () => {
    assert.strictEqual(
      parseGitHubUrl("https://raw.githubusercontent.com/NixOS/nixpkgs"),
      null,
    );
  });

  it("returns null for github.com with only owner", () => {
    assert.strictEqual(
      parseGitHubUrl("https://github.com/NixOS"),
      null,
    );
  });

  it("returns null for github.com actions/issues/pulls URLs", () => {
    assert.strictEqual(
      parseGitHubUrl("https://github.com/NixOS/nixpkgs/issues/123"),
      null,
    );
    assert.strictEqual(
      parseGitHubUrl("https://github.com/NixOS/nixpkgs/pull/456"),
      null,
    );
  });

  it("handles www.github.com", () => {
    assert.deepStrictEqual(
      parseGitHubUrl("https://www.github.com/NixOS/nixpkgs"),
      { owner: "NixOS", repo: "nixpkgs", ref: null, filePath: null },
    );
  });
});

describe("parseStorePath", () => {
  it("extracts store path from nix flake prefetch output", () => {
    const output =
      "Downloaded 'github:NixOS/nixpkgs' to '/nix/store/abc123-source' (hash 'sha256-xxx')";
    assert.strictEqual(
      parseStorePath(output),
      "/nix/store/abc123-source",
    );
  });

  it("returns null when no store path found", () => {
    assert.strictEqual(parseStorePath("some random output"), null);
  });

  it("extracts path from multi-line output", () => {
    const output = `warning: some warning
Downloaded 'github:NixOS/nixpkgs/master' to '/nix/store/xyz789-source' (hash 'sha256-yyy')
`;
    assert.strictEqual(
      parseStorePath(output),
      "/nix/store/xyz789-source",
    );
  });
});
