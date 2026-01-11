# Test runner - auto-discovers test-*.nix files and compares against snapshots
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

  # Load the snapshot for a test file
  loadSnapshot = testName:
    let path = ./snapshots/${testName}.json;
    in if builtins.pathExists path
    then builtins.fromJSON (builtins.readFile path)
    else builtins.throw "Snapshot not found: ${testName}.json - run `nix run .#generate-snapshots`";

  # Run a test file: compare its output against the snapshot
  runTestFile = fileName:
    let
      testName = stripNix fileName;
      actual = testLib.normalizeStorePaths (import ./${fileName} {
        inherit testLib pkgs lib inputs system;
      });
      expected = loadSnapshot testName;
    in
    if actual == expected
    then
      pkgs.runCommand "test-${testName}" { } ''
        echo "PASS: ${testName}"
        mkdir -p $out
        echo "pass" > $out/result
      ''
    else
      builtins.throw ''
        Test failed: ${testName}
          Expected: ${builtins.toJSON expected}
          Actual:   ${builtins.toJSON actual}'';

in
lib.mapAttrs'
  (fileName: _: {
    name = stripNix fileName;
    value = runTestFile fileName;
  })
  testFileNames
