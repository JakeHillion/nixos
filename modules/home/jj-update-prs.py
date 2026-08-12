"""Push a jj stack, then sync each pull request to its commit message.

Bookmarks are re-derived from the same revset and bookmark template that
`jj submit-stack` pushes with, so the two can never disagree about which
branches are in play. A branch with no open pull request is reported and
skipped rather than treated as an error.

Gitea and GitHub are both supported; the forge is picked from the host in
the remote URL. Gitea reads its token from the tea config, GitHub from the
gh CLI.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

import yaml

TEA_CONFIG = "~/.config/tea/config.yml"
GITHUB_HOST = "github.com"
GITHUB_API = "https://api.github.com"
USER_AGENT = "jj-update-prs"
STACK_REVSET = "trunk()..@-"
DEFAULT_BOOKMARK_TEMPLATE = '"push-" ++ change_id.short()'
FIELD_SEP = "\x1f"
RECORD_SEP = "\x1e"
PAGE_SIZE = 50
MAX_PAGES = 20

SCP_URL = re.compile(r"^(?:[^@/]+@)?(?P<host>[^:/]+):(?P<path>.+)$")


class Error(Exception):
    """A failure worth reporting to the user without a traceback."""


def capture(*args):
    try:
        proc = subprocess.run(args, capture_output=True, text=True)
    except FileNotFoundError:
        raise Error(f"`{args[0]}` is not installed")
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise Error(f"`{' '.join(args)}` failed:\n{detail}")
    return proc.stdout


def jj_config(key, default):
    try:
        return capture("jj", "config", "get", key).strip()
    except Error:
        return default


def stack():
    """Return [(bookmark, description)] for the commits submit-stack pushes."""
    bookmark = jj_config(
        "templates.git_push_bookmark", DEFAULT_BOOKMARK_TEMPLATE
    )
    template = f'{bookmark} ++ "{FIELD_SEP}" ++ description ++ "{RECORD_SEP}"'
    out = capture(
        "jj", "log", "-r", STACK_REVSET, "--no-graph", "-T", template
    )
    commits = []
    for record in out.split(RECORD_SEP):
        if not record.strip(FIELD_SEP + "\n"):
            continue
        name, _, description = record.partition(FIELD_SEP)
        commits.append((name.strip(), description))
    return commits


def split_message(description):
    """Split a commit message the way git's %s and %b do."""
    title, _, body = description.partition("\n")
    return title.strip(), body.strip("\n")


def normalise_body(body):
    """Gitea stores web-authored bodies with CRLF; compare like for like."""
    return (body or "").replace("\r\n", "\n").strip("\n")


def parse_remote(url):
    if "://" in url:
        parsed = urllib.parse.urlparse(url)
        host, path = parsed.hostname, parsed.path
    else:
        match = SCP_URL.match(url)
        if not match:
            raise Error(f"cannot parse remote URL: {url}")
        host, path = match.group("host"), match.group("path")
    path = path.strip("/")
    if path.endswith(".git"):
        path = path[: -len(".git")]
    parts = path.split("/")
    if len(parts) < 2 or not all(parts[-2:]):
        raise Error(f"cannot find owner/repo in remote URL: {url}")
    return host, parts[-2], parts[-1]


def remote_url(remote):
    for line in capture("jj", "git", "remote", "list").splitlines():
        name, _, url = line.partition(" ")
        if name == remote:
            return url.strip()
    raise Error(f"no such git remote: {remote}")


def host_key(host):
    """Fold the ssh alias of a forge onto its web host."""
    return re.sub(r"^(ssh|git)\.", "", (host or "").lower())


def find_login(host):
    path = os.path.expanduser(TEA_CONFIG)
    try:
        with open(path) as handle:
            config = yaml.safe_load(handle) or {}
    except FileNotFoundError:
        raise Error(
            f"no tea config at {path}; run `tea login add` to authenticate"
        )
    for login in config.get("logins") or []:
        url = login.get("url") or ""
        candidates = {
            host_key(urllib.parse.urlparse(url).hostname),
            host_key(login.get("ssh_host")),
        }
        if host_key(host) in candidates - {""}:
            return login
    raise Error(
        f"no tea login for {host}; run `tea login add` to authenticate"
    )


class Forge:
    """The slice of the pull request API that Gitea and GitHub share."""

    accept = "application/json"
    page_size_param = "limit"

    def __init__(self, base, token, owner, repo):
        self.base = base
        self.token = token
        self.owner = owner
        self.repo = repo

    def _request(self, method, path, payload=None):
        url = f"{self.base}/repos/{self.owner}/{self.repo}{path}"
        data = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"token {self.token}")
        request.add_header("Accept", self.accept)
        # Cloudflare's bot rules 403 urllib's default User-Agent.
        request.add_header("User-Agent", USER_AGENT)
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace").strip()
            raise Error(f"{method} {url} returned {exc.code}: {detail}")
        except urllib.error.URLError as exc:
            raise Error(f"{method} {url} failed: {exc.reason}")

    def pulls_by_head(self):
        """Map branch name to pull request, ignoring pulls from forks."""
        origin = f"{self.owner}/{self.repo}".lower()
        found = {}
        for page in range(1, MAX_PAGES + 1):
            query = f"?state=open&{self.page_size_param}={PAGE_SIZE}"
            batch = self._request("GET", f"/pulls{query}&page={page}")
            for pull in batch:
                head = pull.get("head") or {}
                source = (head.get("repo") or {}).get("full_name") or ""
                if head.get("ref") and source.lower() == origin:
                    found.setdefault(head["ref"], pull)
            if len(batch) < PAGE_SIZE:
                break
        return found

    def update(self, index, title, body):
        self._request(
            "PATCH",
            f"/pulls/{index}",
            {
                "title": title,
                "body": body,
            },
        )


class Gitea(Forge):
    def __init__(self, host, owner, repo):
        login = find_login(host)
        base = f"{login['url'].rstrip('/')}/api/v1"
        super().__init__(base, login["token"], owner, repo)


class GitHub(Forge):
    accept = "application/vnd.github+json"
    page_size_param = "per_page"

    def __init__(self, host, owner, repo):
        token = capture("gh", "auth", "token", "--hostname", host).strip()
        super().__init__(GITHUB_API, token, owner, repo)


def forge_for(host, owner, repo):
    if host_key(host) == GITHUB_HOST:
        return GitHub(GITHUB_HOST, owner, repo)
    return Gitea(host, owner, repo)


def main():
    parser = argparse.ArgumentParser(
        description="Push a jj stack and sync its pull requests."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would change without editing anything",
    )
    parser.add_argument(
        "--no-push",
        action="store_true",
        help="skip `jj submit-stack` and only sync pull requests",
    )
    parser.add_argument(
        "--remote",
        default="origin",
        help="git remote to resolve the forge from (default: origin)",
    )
    args = parser.parse_args()

    if not args.no_push:
        push = subprocess.run(["jj", "submit-stack"])
        if push.returncode != 0:
            return push.returncode

    commits = stack()
    if not commits:
        print(f"no commits in {STACK_REVSET}")
        return 0

    host, owner, repo = parse_remote(remote_url(args.remote))
    forge = forge_for(host, owner, repo)
    pulls = forge.pulls_by_head()

    for bookmark, description in commits:
        pull = pulls.get(bookmark)
        if pull is None:
            print(f"{bookmark}: no open pull request")
            continue

        title, body = split_message(description)
        if not title:
            print(f"{bookmark}: no description, left alone")
            continue

        stale = []
        if pull.get("title") != title:
            stale.append("title")
        if normalise_body(pull.get("body")) != normalise_body(body):
            stale.append("body")

        index = pull["number"]
        if not stale:
            print(f"{bookmark}: #{index} up to date")
        elif args.dry_run:
            print(f"{bookmark}: #{index} would update {', '.join(stale)}")
        else:
            forge.update(index, title, body)
            print(f"{bookmark}: #{index} updated {', '.join(stale)}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Error as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
