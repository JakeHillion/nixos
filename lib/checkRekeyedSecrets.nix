# Fails if secrets/rekeyed contains files that agenix rekey doesn't track for
# any host, such as outputs left behind by a changed source or a removed
# secret. agenix rekey -a deletes them as orphans.
{ lib, pkgs, nixosConfigurations, root }:

let
  dummyPubkey = "age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs3290gq";

  relative = p: lib.removePrefix "${toString root}/" (toString p);

  # The outputs agenix rekey tracks for a host in local storage mode.
  trackedFor = host:
    let
      rekey = host.config.age.rekey;
      pubkeyHash = builtins.hashString "sha256" rekey.hostPubkey;
      identHash = s: builtins.substring 0 32 (builtins.hashString "sha256" (pubkeyHash + builtins.hashFile "sha256" s.rekeyFile));
      secrets = builtins.filter (s: s.rekeyFile != null && !s.intermediary) (builtins.attrValues host.config.age.secrets);
    in
    lib.optionals (rekey.hostPubkey != dummyPubkey)
      (map (s: "${relative rekey.localStorageDir}/${identHash s}-${s.name}.age") secrets);

  tracked = lib.genAttrs (lib.concatMap trackedFor (builtins.attrValues nixosConfigurations)) (_: true);

  orphans = builtins.filter (f: !(tracked ? ${f}))
    (map relative (lib.filesystem.listFilesRecursive (root + "/secrets/rekeyed")));
in
pkgs.runCommand "rekeyed-secrets" { } (
  if orphans == [ ] then "touch $out" else ''
    echo "Rekeyed secrets not tracked by agenix rekey; run agenix rekey -a to remove them:" >&2
    ${lib.concatMapStrings (f: "echo ${lib.escapeShellArg "  ${f}"} >&2\n") orphans}
    exit 1
  ''
)
