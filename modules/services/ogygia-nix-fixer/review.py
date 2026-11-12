import json
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory


def run(*args, input=None, env=None):
    return subprocess.check_output(
        args, input=input, env=env, text=True
    ).strip()


def main(source, destination, upstream):
    source = Path(source)
    destination = Path(destination)
    megamerge_file = source.parent / "state/megamerge"
    if not megamerge_file.exists() or not (source / ".jj").is_dir():
        print("Fixer has not created its checkout and megamerge yet.")
        return
    megamerge = megamerge_file.read_text().strip()
    if not re.fullmatch(r"[k-z]{8,32}", megamerge):
        raise ValueError("Expected a JJ change ID in state/megamerge")

    # Pin one immutable operation. Resolving '@' with concurrent heads could
    # make JJ merge operations, which must never happen in the source repo.
    heads = list((source / ".jj/repo/op_heads/heads").iterdir())
    if len(heads) != 1:
        print("Fixer has concurrent operations; wait for them to settle.")
        return

    def log(revisions):
        output = run(
            "jj",
            "--repository",
            str(source),
            "--ignore-working-copy",
            "--at-operation",
            heads[0].name,
            "log",
            "--no-graph",
            "--revisions",
            revisions,
            "--template",
            'json(self) ++ "\\n"',
            # JJ 0.46 otherwise tries to initialize Jake's secure per-repo
            # config by rewriting config-id in the read-only source.
            env={**os.environ, "JJ_CONFIG": ""},
        )
        return [json.loads(line) for line in output.splitlines()]

    if len(log(f"{megamerge} & empty() ~ conflicts()")) != 1:
        print("Megamerge is not uniquely empty and conflict-free; skipping.")
        return
    pending = f"(trunk()..{megamerge})"
    blocked = f"({pending} & (merges() | empty() | conflicts())) ~ {megamerge}"
    commits = log(f"({pending} ~ {megamerge}) ~ ({blocked})::")
    wanted = {}
    for commit in commits:
        ref = "refs/heads/fuzz/" + commit["change_id"]
        if ref in wanted:
            raise ValueError(
                "Divergent change IDs in the source; skipping import"
            )
        wanted[ref] = commit["commit_id"]

    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        # Publish only a fully configured clone, so an interrupted first fetch
        # is retried without touching an existing review repository.
        with TemporaryDirectory(
            dir=destination.parent, prefix=".fuzz-review-"
        ) as tmp:
            staged = Path(tmp) / "repo"
            run("jj", "git", "clone", "--colocate", upstream, str(staged))
            run(
                "jj",
                "--repository",
                str(staged),
                "config",
                "set",
                "--repo",
                "git.abandon-unreachable-commits",
                "false",
            )
            run(
                "git",
                "-C",
                str(staged),
                "remote",
                "set-url",
                "--push",
                "origin",
                "git@github.com:ogygia-nix/ogygia-nix.git",
            )
            staged.rename(destination)
    if not (destination / ".jj").is_dir():
        raise ValueError("Review destination is not a colocated JJ repository")
    if (
        run(
            "jj",
            "--repository",
            str(destination),
            "config",
            "get",
            "git.abandon-unreachable-commits",
        )
        != "false"
    ):
        raise ValueError(
            "Review repo must set git.abandon-unreachable-commits=false"
        )

    def git(*args, input=None):
        return run("git", "-C", str(destination), *args, input=input)

    current = dict(
        line.split(" ", 1)
        for line in git(
            "for-each-ref",
            "--format=%(refname) %(objectname)",
            "refs/heads/fuzz/",
        ).splitlines()
    )
    checked_out = {
        line.removeprefix("branch ")
        for line in git("worktree", "list", "--porcelain").splitlines()
        if line.startswith("branch ")
    }
    if wanted:
        # Fetch only objects: no source bookmarks, FETCH_HEAD or destination
        # checkout changes. Full Git commit objects retain their JJ change IDs.
        git(
            "-c",
            f"safe.directory={source}",
            "fetch",
            "--no-tags",
            "--no-write-fetch-head",
            "--stdin",
            str(source / ".git"),
            input="\n".join(wanted.values()) + "\n",
        )
    updates = []
    for ref in sorted(current.keys() | wanted.keys()):
        if ref in checked_out:
            print(f"Leaving checked-out bookmark {ref} alone.")
            continue
        old = current.get(ref, "0" * 40)
        new = wanted.get(ref)
        if new == old:
            continue
        updates.append(
            f"update {ref} {new} {old}" if new else f"delete {ref} {old}"
        )
    if updates:
        # Compare-and-swap every ref in one transaction. Leave all other refs,
        # the index, HEAD, JJ operations and the working tree untouched.
        git(
            "update-ref",
            "--stdin",
            input="start\n" + "\n".join(updates) + "\nprepare\ncommit\n",
        )
    print(
        f"{len(wanted)} eligible commits; updated {len(updates)} review refs."
    )


if __name__ == "__main__":
    main(*sys.argv[1:])
