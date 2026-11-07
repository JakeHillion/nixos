# nixos

### Secret management

Two secret mechanisms coexist in this repo. They store, register, and rekey differently, so before working with any `.age` file identify which one it uses.

**Classic agenix** — one encrypted file per recipient set, registered explicitly. The secret is referenced by a literal path (e.g. `tokenSecret = ../../modules/services/gitea/actions/boron.age`) and must be listed in `secrets.nix` with its `.publicKeys` (typically `jake_users ++ [ neb.<loc>.<host> ]`). Adding a host that needs the secret means extending that `publicKeys` list and re-encrypting.

**agenix-rekey** ([oddlama/agenix-rekey](https://github.com/oddlama/agenix-rekey), configured in `modules/rekey.nix`) — a single master-encrypted source that is automatically rekeyed to each host. The secret is referenced by `rekeyFile = ./token.age` inside its module and is **not** listed in `secrets.nix`; recipients are derived from the host public keys in `modules/ssh/host-keys.nix`. Rekeyed outputs live under `secrets/rekeyed/<hostname>/`, keyed by the short hostname rather than the FQDN. Adding a host that needs the secret is just enabling the consuming module on it, then running the rekey command (which needs the master key) and committing the generated `secrets/rekeyed/<hostname>/` files.

New secrets should prefer agenix-rekey where possible.

#### Editing agenix-rekey secrets

agenix-rekey sources come in two tiers, distinguished by file name:

- `*.age` — encrypted to the master identity (`secrets/master.recipients`) only. Reading one needs the master passphrase.
- `*.agent.age` — encrypted to both the master identity and an agent identity (`secrets/agent.recipients`). Use this tier for material that must stay out of this public repo but is fine for agents to read, such as private config.

The agent identity is itself an agent-tier secret (`modules/home/claude/agent-identity.agent.age`), deployed to every devbox at `/run/agenix/claude/agent-identity`.

Edit every agenix-rekey source, in either tier, with the devshell's `agent-secret` script rather than `agenix edit`. It encrypts each file to the recipients for its tier, and decrypts agent-tier files with the agent identity where present, falling back to the master identity:

    agent-secret cat FILE     # decrypt to stdout
    agent-secret write FILE   # encrypt stdin
    agent-secret edit FILE    # edit with $EDITOR
    agent-secret rekey        # produce missing agent-tier outputs, remove orphans

`agenix edit` encrypts to the master identity alone, so using it on a `*.agent.age` file drops agent access.

`agent-secret rekey` writes the same `secrets/rekeyed/<hostname>/` files that `agenix rekey` would, which `agenix rekey -a` then skips as already rekeyed. `agenix rekey -a` still rekeys everything else. It also `git rm`s committed rekeyed outputs that no host tracks any more, which the `rekeyed-secrets` flake check rejects.

### Building Raspberry Pi images

Raspberry Pi images that support headless SSH can be built as follows:

    nix build '.#nixosConfigurations."li.pop.neb.jakehillion.me".config.formats.sd-aarch64'

Although this will have some support for Nebula it will not be authenticated without further setup. This is because each device generates its own signing key that still needs to be signed by the CA.

This command should be run on a Linux machine with an aarch64 processor or binfmt misc support (`rooster.cx` and `merlin.rig` at the time of writing). When creating Pi images you might need to comment out or update the existing file system UUID.

### Building on another system

Some systems are very slow at rebuilding themselves, with one example being Boron struggling to build Mongo. Currently I have no centralised build process so we don't have signed images. This process works:

    STORE_PATH=`nix build --no-link --print-out-paths '.#nixosConfigurations."boron.cx.neb.jakehillion.me".config.system.build.toplevel'`
    nix-store --export $(nix-store --query --requisites $STORE_PATH) | zstd > closure.nar.zst
    cat closure.nar.zst | ssh boron.cx.neb.jakehillion.me sh -c 'unzstd | sudo nix-store --import'

Then use `update` or `nixos-rebuild` as normal on the host (provided it can evaluate the Nix).
