import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  extractRepoPath,
  redundantCwdCheck,
} from "../src/hooks/redundant-cwd.js";

describe("extractRepoPath", () => {
  it("returns null for commands without -C/-R", () => {
    assert.equal(extractRepoPath("git status"), null);
  });

  it("returns null for jj log without -R", () => {
    assert.equal(extractRepoPath("jj log"), null);
  });

  it("extracts path from git -C", () => {
    assert.equal(extractRepoPath("git -C /foo/bar status"), "/foo/bar");
  });

  it("extracts path from jj -R", () => {
    assert.equal(extractRepoPath("jj -R /foo/bar log"), "/foo/bar");
  });

  it("extracts path from jj --repository", () => {
    assert.equal(
      extractRepoPath("jj --repository /foo/bar log"),
      "/foo/bar",
    );
  });

  it("strips surrounding double quotes", () => {
    assert.equal(extractRepoPath('git -C "/foo/bar" status'), "/foo/bar");
  });

  it("strips surrounding single quotes", () => {
    assert.equal(extractRepoPath("git -C '/foo/bar' status"), "/foo/bar");
  });

  it("handles relative paths", () => {
    assert.equal(extractRepoPath("git -C ../other status"), "../other");
  });

  it("handles dot path", () => {
    assert.equal(extractRepoPath("git -C . status"), ".");
  });
});

describe("redundantCwdCheck", () => {
  it("allows when paths differ", () => {
    assert.deepStrictEqual(redundantCwdCheck("/foo/bar", "/baz/qux"), {
      action: "allow",
    });
  });

  it("blocks when paths match", () => {
    const result = redundantCwdCheck("/foo/bar", "/foo/bar");
    assert.equal(result.action, "block");
    if (result.action === "block") {
      assert.ok(result.reason.includes("Redundant"));
    }
  });

  it("allows when paths are similar but different", () => {
    assert.deepStrictEqual(redundantCwdCheck("/foo/bar", "/foo/baz"), {
      action: "allow",
    });
  });
});
