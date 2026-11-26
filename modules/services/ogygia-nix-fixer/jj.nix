{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.ogygia-nix-fixer;
  repo = "/var/lib/ogygia-nix-fixer/repo";
  wrapper = pkgs.writeShellApplication {
    name = "ogygia-nix-fixer-jj";
    runtimeInputs = [ pkgs.unstable.jujutsu pkgs.git pkgs.openssh ];
    text = ''
      # The fixer's repository is read-only to us. JJ_CONFIG is cleared so jj
      # doesn't try to write a config ID into it.
      fixer_jj() {
        JJ_CONFIG=''' jj -R ${repo} --ignore-working-copy "$@"
      }

      if [ "''${1-}" != git ] || [ "''${2-}" != push ]; then
        fixer_jj "$@"
        exit
      fi
      shift 2

      # Pushing would write a bookmark into the fixer's repository, so push
      # each change's commit straight from its Git objects instead.
      force=
      changes=()
      while [ $# -gt 0 ]; do
        case $1 in
          -c | --change)
            changes+=("''${2:?$1 needs a revision}")
            shift 2
            ;;
          --change=*)
            changes+=("''${1#--change=}")
            shift
            ;;
          -c*)
            changes+=("''${1#-c}")
            shift
            ;;
          --force)
            force=+
            shift
            ;;
          *)
            echo "ogygia-nix-fixer-jj: only git push [--force] -c <revision> is supported" >&2
            exit 1
            ;;
        esac
      done
      if [ ''${#changes[@]} -eq 0 ]; then
        echo "ogygia-nix-fixer-jj: git push needs -c <revision>" >&2
        exit 1
      fi

      template=$(jj config get templates.git_push_bookmark)
      refspecs=()
      for change in "''${changes[@]}"; do
        mapfile -t found < <(fixer_jj log --no-graph -r "$change" -T "$template"' ++ " " ++ commit_id ++ "\n"')
        if [ ''${#found[@]} -ne 1 ]; then
          echo "ogygia-nix-fixer-jj: $change is not exactly one revision" >&2
          exit 1
        fi
        read -r bookmark commit <<<"''${found[0]}"
        refspecs+=("$force$commit:refs/heads/$bookmark")
      done

      git -c safe.directory=${repo} -C ${repo} push git@github.com:ogygia-nix/ogygia-nix.git "''${refspecs[@]}"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    users.groups.ogygia-nix-fixer.members = [ config.custom.user ];
    environment.systemPackages = [ wrapper ];
  };
}
