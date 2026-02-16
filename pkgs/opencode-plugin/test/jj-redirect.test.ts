import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { jjRedirectHook } from "../src/hooks/jj-redirect.js";

describe("jjRedirectHook", () => {
  it("allows non-git-commit commands", () => {
    assert.deepStrictEqual(jjRedirectHook("git status", true), {
      action: "allow",
    });
  });

  it("allows git push in jj repos", () => {
    assert.deepStrictEqual(jjRedirectHook("git push", true), {
      action: "allow",
    });
  });

  it("allows git commit in non-jj repos", () => {
    assert.deepStrictEqual(jjRedirectHook('git commit -m "test"', false), {
      action: "allow",
    });
  });

  it("blocks git commit in jj repos", () => {
    const result = jjRedirectHook('git commit -m "test"', true);
    assert.equal(result.action, "block");
    if (result.action === "block") {
      assert.ok(result.reason.includes("Jujutsu"));
      assert.ok(result.reason.includes("jj commit"));
    }
  });

  it("blocks git commit after && in jj repos", () => {
    const result = jjRedirectHook(
      'git add . && git commit -m "test"',
      true,
    );
    assert.equal(result.action, "block");
  });

  it("blocks git commit after ; in jj repos", () => {
    const result = jjRedirectHook(
      'git add .; git commit -m "test"',
      true,
    );
    assert.equal(result.action, "block");
  });

  it("allows non-commit git commands in jj repos", () => {
    assert.deepStrictEqual(jjRedirectHook("git log --oneline", true), {
      action: "allow",
    });
  });
});
