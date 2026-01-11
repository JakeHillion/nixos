# Generates snapshot JSON files from test files
{ pkgs, lib, inputs, system }:

let
  testLib = import ./lib.nix { inherit pkgs lib inputs system; };

  # Discover all test-*.nix files
  dirContents = builtins.readDir ./.;
  testFileNames = lib.filterAttrs
    (name: type:
      type == "regular" &&
      lib.hasPrefix "test-" name &&
      lib.hasSuffix ".nix" name)
    dirContents;

  stripNix = name: lib.removeSuffix ".nix" name;

  # Build attrset of testName -> output (normalized to remove store path hashes)
  testOutputs = lib.mapAttrs'
    (fileName: _: {
      name = stripNix fileName;
      value = testLib.normalizeStorePaths (import ./${fileName} { inherit testLib pkgs lib inputs system; });
    })
    testFileNames;

  # Generate shell commands to write each snapshot
  snapshotCommands = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (testName: value: ''
      echo "  ${testName}.json"
      echo ${lib.escapeShellArg (builtins.toJSON value)} | ${pkgs.jq}/bin/jq . > "$SNAPSHOT_DIR/${testName}.json"
    '')
    testOutputs);

in
pkgs.writeShellScriptBin "generate-snapshots" ''
  set -e
  SNAPSHOT_DIR="''${1:-./tests/snapshots}"
  mkdir -p "$SNAPSHOT_DIR"

  echo "Generating ${toString (lib.length (lib.attrNames testOutputs))} snapshots to $SNAPSHOT_DIR:"
  ${snapshotCommands}
  echo "Done."
''
