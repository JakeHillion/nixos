import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { nixHook } from "../src/hooks/nix.js";

describe("nixHook", () => {
  it("allows non-nix commands unchanged", () => {
    assert.deepStrictEqual(nixHook("echo hello"), { action: "allow" });
  });

  it("allows nix commands that are not build or run", () => {
    assert.deepStrictEqual(nixHook("nix flake check"), { action: "allow" });
  });

  it("allows nix fmt", () => {
    assert.deepStrictEqual(nixHook("nix fmt"), { action: "allow" });
  });

  it("adds --no-link and --print-out-paths to nix build", () => {
    const result = nixHook("nix build .#foo");
    assert.equal(result.action, "modify");
    if (result.action === "modify") {
      assert.ok(result.command.includes("--no-link"));
      assert.ok(result.command.includes("--print-out-paths"));
    }
  });

  it("does not add --no-link if already present", () => {
    const result = nixHook("nix build --no-link .#foo");
    assert.equal(result.action, "modify");
    if (result.action === "modify") {
      assert.ok(!result.command.includes("--no-link --no-link"));
      assert.ok(result.command.includes("--print-out-paths"));
    }
  });

  it("does not add --print-out-paths if already present", () => {
    const result = nixHook("nix build --print-out-paths .#foo");
    assert.equal(result.action, "modify");
    if (result.action === "modify") {
      assert.ok(result.command.includes("--no-link"));
      assert.ok(!result.command.includes("--print-out-paths --print-out-paths"));
    }
  });

  it("quotes unquoted .# arguments", () => {
    const result = nixHook("nix build --no-link --print-out-paths .#foo");
    assert.equal(result.action, "modify");
    if (result.action === "modify") {
      assert.ok(result.command.includes('".#foo"'));
    }
  });

  it("does not double-quote already quoted .# arguments", () => {
    const result = nixHook(
      'nix build --no-link --print-out-paths ".#foo"',
    );
    assert.deepStrictEqual(result, { action: "allow" });
  });

  it("handles nix run with .# quoting but no flags", () => {
    const result = nixHook("nix run .#generate-snapshots");
    assert.equal(result.action, "modify");
    if (result.action === "modify") {
      assert.ok(result.command.includes('".#generate-snapshots"'));
      assert.ok(!result.command.includes("--no-link"));
      assert.ok(!result.command.includes("--print-out-paths"));
    }
  });

  it("allows nix run with already quoted .# argument", () => {
    const result = nixHook('nix run ".#generate-snapshots"');
    assert.deepStrictEqual(result, { action: "allow" });
  });

  it("handles compound commands with nix build after &&", () => {
    const result = nixHook("echo foo && nix build .#bar");
    assert.equal(result.action, "modify");
    if (result.action === "modify") {
      assert.ok(result.command.includes("--no-link"));
      assert.ok(result.command.includes('".#bar"'));
    }
  });

  it("handles complex flake references", () => {
    const result = nixHook(
      "nix build --no-link --print-out-paths .#nixosConfigurations.host.config.system.build.toplevel",
    );
    assert.equal(result.action, "modify");
    if (result.action === "modify") {
      assert.ok(
        result.command.includes(
          '".#nixosConfigurations.host.config.system.build.toplevel"',
        ),
      );
    }
  });

  it("handles nix build without .# argument", () => {
    const result = nixHook("nix build");
    assert.equal(result.action, "modify");
    if (result.action === "modify") {
      assert.ok(result.command.includes("--no-link"));
      assert.ok(result.command.includes("--print-out-paths"));
      assert.ok(!result.command.includes(".#"));
    }
  });
});
