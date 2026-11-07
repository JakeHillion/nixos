# agent-secret: read, write, edit and rekey agenix-rekey sources.
#
# Sources come in two tiers, chosen by file name. *.agent.age sources are
# encrypted to both the master identity (secrets/master.recipients) and the
# agent identity (secrets/agent.recipients); every other *.age source is
# encrypted to the master identity alone. See the "Secret management" section
# of README.md.

root="$(git rev-parse --show-toplevel)"
master_identity="$root/secrets/master-key.age"
agent_identity="${AGENT_SECRET_IDENTITY:-/run/agenix/claude/agent-identity}"

die() {
  echo "agent-secret: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: agent-secret cat FILE     decrypt FILE to stdout
       agent-secret write FILE   encrypt stdin to FILE
       agent-secret edit FILE    edit FILE with $EDITOR
       agent-secret rekey        rekey missing agent-tier secrets and remove orphans
USAGE
  exit 1
}

is_agent_tier() {
  [[ "$1" == *.agent.age ]]
}

# Sets identity_args to decrypt FILE, preferring the agent identity for
# agent-tier sources and otherwise using the passphrase-protected master.
set_identity_args() {
  if is_agent_tier "$1" && [[ -r "$agent_identity" ]]; then
    identity_args=(-i "$agent_identity")
  else
    identity_args=(-i "$master_identity")
  fi
}

# Classic agenix secrets are encrypted to the keys in secrets.nix, which this
# script would replace with the master identity.
require_rekey_source() {
  local rel
  rel="$(realpath -m --relative-to="$root" "$1")"
  [[ "$rel" == *.age ]] || die "$1 is not an .age file"
  if grep -qF "\"$rel\"" "$root/secrets.nix"; then
    die "$1 is a classic agenix secret; edit it with agenix -e"
  fi
}

tmpdir="$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}" agent-secret.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cmd_cat() {
  require_rekey_source "$1"
  set_identity_args "$1"
  age -d "${identity_args[@]}" "$1"
}

# Encrypts the plaintext in NEW to FILE, unless it matches the plaintext in OLD,
# the current contents of FILE. Re-encrypting unchanged plaintext would change
# the source's hash and force every host to be rekeyed.
encrypt_if_changed() {
  local file="$1" new="$2" old="$3"
  if [[ -e "$file" ]] && cmp -s "$old" "$new"; then
    return
  fi

  local recipient_args=(-R "$root/secrets/master.recipients")
  if is_agent_tier "$file"; then
    recipient_args+=(-R "$root/secrets/agent.recipients")
  fi
  age -e "${recipient_args[@]}" -o "$file.tmp" "$new"
  mv "$file.tmp" "$file"
  git add "$file"
}

# Decrypts FILE, if it exists, to $tmpdir/old.
decrypt_old() {
  local file="$1"
  : >"$tmpdir/old"
  if [[ -e "$file" ]]; then
    set_identity_args "$file"
    age -d "${identity_args[@]}" -o "$tmpdir/old" "$file"
  fi
}

cmd_write() {
  local file="$1"
  require_rekey_source "$file"
  cat >"$tmpdir/new"
  decrypt_old "$file"
  encrypt_if_changed "$file" "$tmpdir/new" "$tmpdir/old"
}

cmd_edit() {
  local file="$1" editor
  require_rekey_source "$file"
  decrypt_old "$file"
  cp "$tmpdir/old" "$tmpdir/edit"
  read -ra editor <<<"${EDITOR:-vi}"
  "${editor[@]}" "$tmpdir/edit"
  encrypt_if_changed "$file" "$tmpdir/edit" "$tmpdir/old"
}

# Produce the rekeyed outputs agenix-rekey expects for agent-tier secrets, and
# remove committed outputs that no host tracks any more. `agenix rekey` skips
# outputs that already exist, so the new ones are left alone by it. Output
# names mirror agenix-rekey's local storage mode:
# <localStorageDir>/<identHash>-<name>.age.
cmd_rekey() {
  local entries src pubkey out agent file rel
  # The --apply argument is a Nix expression, not shell.
  # shellcheck disable=SC2016
  entries="$(nix eval --json "$root#nixosConfigurations" --apply '
    configs:
    let
      dummyPubkey = "age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs3290gq";
      isAgentTier = s: builtins.match ".*\\.agent\\.age" (toString s.rekeyFile) != null;
      relative = p: builtins.head (builtins.match "/nix/store/[^/]+/(.*)" (toString p));
      forHost = host:
        let
          rekey = host.config.age.rekey;
          pubkeyHash = builtins.hashString "sha256" rekey.hostPubkey;
          entry = s: {
            src = toString s.rekeyFile;
            pubkey = builtins.replaceStrings [ "\n" ] [ "" ] rekey.hostPubkey;
            out = "${relative rekey.localStorageDir}/${builtins.substring 0 32 (builtins.hashString "sha256" (pubkeyHash + builtins.hashFile "sha256" s.rekeyFile))}-${s.name}.age";
            agent = isAgentTier s;
          };
        in
        if rekey.hostPubkey == dummyPubkey then [ ]
        else map entry (builtins.filter (s: s.rekeyFile != null && !s.intermediary) (builtins.attrValues host.config.age.secrets));
    in
    builtins.concatMap forHost (builtins.attrValues configs)
  ')"

  # Each source is decrypted once, however many hosts it's rekeyed for.
  local -A plaintexts=()
  local missing=()
  while IFS=$'\t' read -r src pubkey out agent; do
    [[ -e "$root/$out" ]] && continue
    if [[ "$agent" != true ]]; then
      missing+=("$out")
      continue
    fi
    if [[ -z "${plaintexts[$src]-}" ]]; then
      plaintexts[$src]="$tmpdir/plaintext.${#plaintexts[@]}"
      set_identity_args "$src"
      age -d "${identity_args[@]}" -o "${plaintexts[$src]}" "$src" || die "failed to decrypt $src"
    fi
    mkdir -p "$(dirname "$root/$out")"
    if ! age -e -r "$pubkey" -o "$root/$out.tmp" "${plaintexts[$src]}"; then
      rm -f "$root/$out.tmp"
      die "failed to rekey $out"
    fi
    mv "$root/$out.tmp" "$root/$out"
    git -C "$root" add "$out"
    echo "rekeyed $out" >&2
  done < <(jq -r '.[] | [.src, .pubkey, .out, .agent] | @tsv' <<<"$entries")

  # Orphans fail the rekeyed-secrets flake check. Only committed files are
  # removed, with git rm, so anything removed can be restored from history;
  # anything else is reported.
  jq -r '.[].out' <<<"$entries" | sort -u >"$tmpdir/tracked"
  while IFS= read -r -d '' file; do
    rel="${file#"$root/"}"
    grep -qxF "$rel" "$tmpdir/tracked" && continue
    if git -C "$root" cat-file -e "HEAD:$rel" 2>/dev/null; then
      git -C "$root" rm -q -- "$rel"
      echo "removed orphan $rel" >&2
    else
      echo "orphan not removed because it isn't committed: $rel" >&2
    fi
  done < <(find "$root/secrets/rekeyed" -type f -print0)

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "master-tier outputs missing; these need agenix rekey -a:" >&2
    printf '  %s\n' "${missing[@]}" >&2
  fi
}

case "${1:-}" in
  cat | write | edit)
    [[ $# -eq 2 ]] || usage
    "cmd_$1" "$2"
    ;;
  rekey)
    [[ $# -eq 1 ]] || usage
    cmd_rekey
    ;;
  *) usage ;;
esac
