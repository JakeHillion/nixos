import base64
import json
import os
import random
import re
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import requests

GITEA_URL = os.environ["GITEA_URL"]
GITEA_REPOS = json.loads(os.environ["GITEA_REPOS"])
JOB_AGE_THRESHOLD = int(os.environ["JOB_AGE_THRESHOLD"])
MAX_INSTANCES = int(os.environ["MAX_INSTANCES"])
GCP_PROJECT = os.environ["GCP_PROJECT"]
GCP_REGION = os.environ["GCP_REGION"]
GCS_BUCKET = os.environ["GCS_BUCKET"]
MACHINE_TYPE = os.environ["MACHINE_TYPE"]
BOOT_DISK_SIZE_GB = os.environ["BOOT_DISK_SIZE_GB"]
RUNNER_LABELS = os.environ["RUNNER_LABELS"]
MAX_RUN_DURATION = os.environ["MAX_RUN_DURATION"]
IMAGE_NAME = os.environ["IMAGE_NAME"]
IMAGE_TARBALL = os.environ["IMAGE_TARBALL"]
POLL_INTERVAL = int(os.environ["POLL_INTERVAL"])

HETZNER_ENABLED = os.environ.get("HETZNER_ENABLED") == "1"
HETZNER_SERVER_TYPE = os.environ.get("HETZNER_SERVER_TYPE", "")
HETZNER_IMAGE = os.environ.get("HETZNER_IMAGE", "")

CREDS_DIR = Path(os.environ["CREDENTIALS_DIRECTORY"])
RT_DIR = Path(os.environ["RUNTIME_DIRECTORY"])

GITEA_API_TOKEN = (CREDS_DIR / "gitea-api-token").read_text().strip()
GITEA_REG_TOKEN = (CREDS_DIR / "gitea-registration-token").read_text().strip()
HCLOUD_TOKEN = (
    (CREDS_DIR / "hcloud-token").read_text().strip() if HETZNER_ENABLED else ""
)

HCLOUD_API = "https://api.hetzner.cloud/v1"

CONFIG_YAML = (
    "log:\n"
    "  level: debug\n"
    "runner:\n"
    "  file: .runner\n"
    "  capacity: 1\n"
    "  fetch_timeout: 5s\n"
    "  fetch_interval: 2s\n"
    # Drain an in-flight job on SIGTERM (the in-VM cycle timer fires
    # hourly to recover from the "unregistered runner" wedge); needs
    # to exceed the job timeout so a cycle never kills a long job.
    "  shutdown_timeout: 6h\n"
    "host:\n"
    "  workdir_parent: /var/lib/gitea-runner-jobs\n"
)

ALIVE_STATES = {
    "PROVISIONING",
    "STAGING",
    "RUNNING",
    "REPAIRING",
    "SUSPENDING",
    "SUSPENDED",
}
DEAD_STATES = {"TERMINATED", "STOPPING", "STOPPED"}

HETZNER_ALIVE_STATES = {"initializing", "starting", "running"}


def parse_duration(s):
    # gcloud duration syntax: 30m, 1h, 2h30m, ...
    m = re.fullmatch(r"(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?", s)
    if not m or not any(m.groups()):
        raise ValueError(f"invalid duration: {s}")
    h, mi, sec = (int(x) if x else 0 for x in m.groups())
    return h * 3600 + mi * 60 + sec


MAX_RUN_SECONDS = parse_duration(MAX_RUN_DURATION)


def gitea_session():
    s = requests.Session()
    s.headers["Authorization"] = f"token {GITEA_API_TOKEN}"
    s.headers["Accept"] = "application/json"
    return s


def iso_to_epoch(s):
    # Gitea emits RFC3339 with a trailing Z; fromisoformat() in <3.11
    # doesn't accept Z, so normalise.
    return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())


def count_queued_jobs():
    s = gitea_session()
    cutoff = int(time.time()) - JOB_AGE_THRESHOLD
    total = 0
    for repo in GITEA_REPOS:
        owner, name = repo.split("/", 1)
        r = s.get(
            f"{GITEA_URL}/api/v1/repos/{owner}/{name}/actions/runs",
            params={"status": "queued", "limit": 50},
            timeout=15,
        )
        r.raise_for_status()
        runs = r.json().get("workflow_runs", [])
        for run in runs:
            rid = run["id"]
            jobs_url = (
                f"{GITEA_URL}/api/v1/repos/{owner}/{name}"
                f"/actions/runs/{rid}/jobs"
            )
            jr = s.get(jobs_url, timeout=15)
            if not jr.ok:
                continue
            for job in jr.json().get("jobs", []):
                st = (job.get("status") or "").lower()
                if st not in ("queued", "waiting"):
                    continue
                if job.get("runner_id") not in (None, 0, ""):
                    continue
                created = job.get("created_at") or run.get("created_at")
                if not created:
                    continue
                try:
                    if iso_to_epoch(created) > cutoff:
                        continue
                except ValueError:
                    continue
                total += 1
    return total


def list_zones_in_region():
    out = subprocess.check_output(
        [
            "gcloud",
            "compute",
            "zones",
            "list",
            f"--filter=region:{GCP_REGION} AND status:UP",
            "--format=value(name)",
        ]
    )
    return [z for z in out.decode().split() if z]


def list_burst_instances():
    # No --zones filter: returns instances from all zones in the project.
    # We filter to the configured region in Python below so a stale label
    # in another region doesn't surface here.
    out = subprocess.check_output(
        [
            "gcloud",
            "compute",
            "instances",
            "list",
            "--filter=labels.role=gitea-actions-burst",
            "--format=json",
        ]
    )
    instances = json.loads(out)
    out_list = []
    for inst in instances:
        zone_url = inst.get("zone", "")
        # zone field is a self-link like .../zones/europe-north1-a;
        # strip everything before the zone name then drop the trailing
        # -<a|b|c> to compare against the configured region.
        zone_name = zone_url.rsplit("/", 1)[-1]
        if zone_name.rsplit("-", 1)[0] == GCP_REGION:
            inst["_zone_name"] = zone_name
            out_list.append(inst)
    return out_list


def random_vm_name():
    return f"gitea-burst-{random.randint(0, 2 ** 32 - 1):08x}"


def write_user_data(stage):
    # #cloud-config user-data carrying the per-VM runner credentials;
    # cloud-init's write_files places them before the in-VM runner unit
    # starts (it orders after cloud-final). Identical content to what the
    # local actions-vm module puts on its NoCloud ISO — only the transport
    # differs (instance metadata here). JSON is a YAML subset, so emit the
    # cloud-config without needing a YAML library.
    runner_b64 = base64.b64encode((stage / ".runner").read_bytes()).decode()
    config_b64 = base64.b64encode(CONFIG_YAML.encode()).decode()
    files = [
        {
            "path": "/var/lib/gitea-runner/.runner",
            "encoding": "b64",
            "content": runner_b64,
            "owner": "runner:runner",
            "permissions": "0600",
        },
        {
            "path": "/var/lib/gitea-runner/config.yaml",
            "encoding": "b64",
            "content": config_b64,
            "owner": "runner:runner",
            "permissions": "0644",
        },
    ]
    path = stage / "user-data"
    path.write_text("#cloud-config\n" + json.dumps({"write_files": files}))
    return path


def register_runner(stage, vm_name):
    # `gitea-runner register --ephemeral` writes .runner into cwd.
    subprocess.check_call(
        [
            "gitea-runner",
            "register",
            "--no-interactive",
            "--ephemeral",
            "--instance",
            GITEA_URL,
            "--token",
            GITEA_REG_TOKEN,
            "--name",
            vm_name,
            "--labels",
            RUNNER_LABELS,
        ],
        cwd=stage,
    )


def launch_gcp(vm_name, zone, user_data):
    if zone is None:
        raise RuntimeError(f"no UP zones in region {GCP_REGION}")
    try:
        subprocess.check_call(
            [
                "gcloud",
                "compute",
                "instances",
                "create",
                vm_name,
                f"--zone={zone}",
                f"--machine-type={MACHINE_TYPE}",
                f"--image={IMAGE_NAME}",
                f"--image-project={GCP_PROJECT}",
                f"--boot-disk-size={BOOT_DISK_SIZE_GB}GB",
                "--labels=role=gitea-actions-burst",
                # cloud-init's GCE datasource reads
                # instance/attributes/user-data from the metadata server
                # and applies the write_files above.
                f"--metadata-from-file=user-data={user_data}",
                "--no-restart-on-failure",
                "--maintenance-policy=TERMINATE",
                f"--max-run-duration={MAX_RUN_DURATION}",
                "--instance-termination-action=STOP",
                # Burst VMs don't call any GCP APIs from inside; skip the
                # default Compute SA attachment so we don't need
                # iam.serviceAccountUser on it.
                "--no-service-account",
                "--no-scopes",
                "--quiet",
            ]
        )
    except Exception:
        # `create` can fail after the VM resource exists (e.g. disk
        # creation succeeded, post-create polling timed out), so try a
        # best-effort delete before re-raising. A straggler that survives
        # this is force-stopped by --max-run-duration and reaped by
        # cleanup_dead.
        subprocess.run(
            [
                "gcloud",
                "compute",
                "instances",
                "delete",
                vm_name,
                f"--zone={zone}",
                "--quiet",
            ],
            check=False,
        )
        raise


def hcloud_request(method, path, **kwargs):
    r = requests.request(
        method,
        f"{HCLOUD_API}{path}",
        headers={"Authorization": f"Bearer {HCLOUD_TOKEN}"},
        timeout=30,
        **kwargs,
    )
    r.raise_for_status()
    return r.json() if r.text else {}


def launch_hetzner(vm_name, user_data):
    image = hetzner_image_id()
    # Capacity for the configured server type comes and goes per location,
    # so try every location (in random order, to spread load) before
    # giving up on this launch.
    locations = [
        loc["name"] for loc in hcloud_request("GET", "/locations")["locations"]
    ]
    random.shuffle(locations)
    errors = []
    for location in locations:
        try:
            hcloud_request(
                "POST",
                "/servers",
                json={
                    "name": vm_name,
                    "server_type": HETZNER_SERVER_TYPE,
                    "image": image,
                    "location": location,
                    "user_data": user_data,
                    "labels": {"role": "gitea-actions-burst"},
                },
            )
            return
        except requests.HTTPError as e:
            body = e.response.text[:200] if e.response is not None else ""
            errors.append(f"{location}: {e} {body}")
    raise RuntimeError(
        "hetzner launch failed in all locations: " + "; ".join(errors)
    )


def launch_one(vm_name, zone):
    stage = RT_DIR / vm_name / "stage"
    stage.mkdir(parents=True, exist_ok=True)

    register_runner(stage, vm_name)
    user_data = write_user_data(stage)

    try:
        launch_gcp(vm_name, zone, user_data)
        return "gcp"
    except Exception as e:
        if not HETZNER_ENABLED:
            raise
        print(
            f"gcp launch of {vm_name} failed ({e}); trying hetzner",
            file=sys.stderr,
            flush=True,
        )

    launch_hetzner(vm_name, user_data.read_text())
    return "hetzner"


def list_hetzner_servers():
    servers = []
    page = 1
    while True:
        resp = hcloud_request(
            "GET",
            "/servers",
            params={
                "label_selector": "role=gitea-actions-burst",
                "page": page,
                "per_page": 50,
            },
        )
        servers.extend(resp["servers"])
        page = resp["meta"]["pagination"]["next_page"]
        if not page:
            return servers


def split_hetzner_servers(servers):
    # A runner VM powers itself off after its single job, which on Hetzner
    # leaves the server in "off" (still billed) rather than anything
    # self-cleaning — so off servers are dead and get deleted. Hetzner also
    # has no equivalent of GCE's --max-run-duration; enforce the same
    # backstop here by treating anything older as dead even if running.
    now = time.time()
    alive, dead = [], []
    for srv in servers:
        if srv["status"] == "deleting":
            continue
        age = now - iso_to_epoch(srv["created"])
        if srv["status"] in HETZNER_ALIVE_STATES and age <= MAX_RUN_SECONDS:
            alive.append(srv)
        else:
            dead.append(srv)
    return alive, dead


def cleanup_dead_hetzner(dead):
    for srv in dead:
        try:
            hcloud_request("DELETE", f"/servers/{srv['id']}")
        except requests.HTTPError as e:
            print(
                f"cleanup: delete hetzner server {srv['name']} failed: {e}",
                file=sys.stderr,
            )


def cleanup_dead(dead):
    for inst in dead:
        name = inst["name"]
        zone = inst.get("_zone_name") or inst["zone"].rsplit("/", 1)[-1]
        try:
            subprocess.run(
                [
                    "gcloud",
                    "compute",
                    "instances",
                    "delete",
                    name,
                    f"--zone={zone}",
                    "--quiet",
                ],
                check=True,
            )
        except subprocess.CalledProcessError as e:
            print(
                f"cleanup: delete instance {name} failed: {e}", file=sys.stderr
            )


ORPHAN_AGE_SECONDS = 5 * 60


def sweep_orphans(live_vm_names):
    # Reaps the per-VM cidata images and GCS tarballs created by the
    # previous launch scheme — user-data now rides instance metadata, so
    # new VMs create neither, but resources leaked before the switch
    # still need deleting. Per-VM resources are name-prefixed
    # (gitea-burst-<hex>...), so we filter strictly to that prefix and
    # leave the shared base image (gitea-actions-vm-<hash>) alone. The
    # age threshold guards against eventual-consistency races against a
    # just-launched VM that hasn't yet surfaced in
    # list_burst_instances().
    now = int(time.time())

    try:
        out = subprocess.check_output(
            [
                "gcloud",
                "compute",
                "images",
                "list",
                "--filter=name~^gitea-burst-.*-cidata$",
                "--format=value(name,creationTimestamp)",
            ]
        )
    except subprocess.CalledProcessError as e:
        print(f"sweep: images list failed: {e}", file=sys.stderr)
        out = b""
    for line in out.decode().splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        img_name, ts = parts
        vm_name = img_name[: -len("-cidata")]
        if vm_name in live_vm_names:
            continue
        try:
            age = now - iso_to_epoch(ts)
        except ValueError:
            continue
        if age < ORPHAN_AGE_SECONDS:
            continue
        print(
            f"sweep: deleting orphan image {img_name} (age={age}s)", flush=True
        )
        subprocess.run(
            ["gcloud", "compute", "images", "delete", img_name, "--quiet"],
            check=False,
        )

    try:
        out = subprocess.check_output(
            [
                "gcloud",
                "storage",
                "objects",
                "list",
                f"gs://{GCS_BUCKET}/gitea-burst-*.tar.gz",
                "--format=value(name,timeCreated)",
            ]
        )
    except subprocess.CalledProcessError as e:
        print(f"sweep: storage objects list failed: {e}", file=sys.stderr)
        return
    for line in out.decode().splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        obj_name, ts = parts
        if not obj_name.endswith(".tar.gz"):
            continue
        vm_name = obj_name[: -len(".tar.gz")]
        if vm_name in live_vm_names:
            continue
        try:
            age = now - iso_to_epoch(ts)
        except ValueError:
            continue
        if age < ORPHAN_AGE_SECONDS:
            continue
        print(
            f"sweep: deleting orphan GCS object {obj_name} (age={age}s)",
            flush=True,
        )
        subprocess.run(
            [
                "gcloud",
                "storage",
                "rm",
                f"gs://{GCS_BUCKET}/{obj_name}",
                "--quiet",
            ],
            check=False,
        )


_hetzner_image_id = None
_hetzner_image_lock = threading.Lock()


def hetzner_image_id():
    # Lazy + cached: normally resolved once at startup, but a failure
    # there (e.g. transient API error) only degrades Hetzner launches —
    # each later launch retries the lookup/upload instead of taking the
    # whole reconciler (and with it GCP bursting) down.
    global _hetzner_image_id
    with _hetzner_image_lock:
        if _hetzner_image_id is None:
            _hetzner_image_id = ensure_image_hetzner()
        return _hetzner_image_id


def ensure_image_hetzner():
    # The snapshot is found via a label carrying the image name (itself
    # keyed on the qcow2 content hash). hcloud-upload-image boots a
    # temporary server into the rescue system, streams the raw image onto
    # its disk, and snapshots it.
    params = {
        "type": "snapshot",
        "label_selector": f"gitea-actions-vm-image={IMAGE_NAME}",
    }
    found = hcloud_request("GET", "/images", params=params)["images"]
    if not found:
        print(f"uploading hetzner snapshot {IMAGE_NAME}", flush=True)
        subprocess.check_call(
            [
                "hcloud-upload-image",
                "upload",
                f"--image-path={HETZNER_IMAGE}",
                "--architecture=x86",
                "--compression=zstd",
                f"--description={IMAGE_NAME}",
                f"--labels=gitea-actions-vm-image={IMAGE_NAME}",
            ],
            env={**os.environ, "HCLOUD_TOKEN": HCLOUD_TOKEN},
        )
        found = hcloud_request("GET", "/images", params=params)["images"]
        if not found:
            raise RuntimeError("hetzner snapshot missing after upload")
    return found[0]["id"]


def ensure_image():
    # One-shot at startup. Idempotent on the GCE side: describe → if
    # found we're done; otherwise upload the prebuilt tarball + create
    # the custom image.
    r = subprocess.run(
        ["gcloud", "compute", "images", "describe", IMAGE_NAME, "--quiet"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if r.returncode == 0:
        return
    print(f"uploading runner image {IMAGE_NAME}", flush=True)
    gcs_uri = f"gs://{GCS_BUCKET}/{IMAGE_NAME}.tar.gz"
    subprocess.check_call(
        ["gcloud", "storage", "cp", IMAGE_TARBALL, gcs_uri, "--quiet"]
    )
    subprocess.check_call(
        [
            "gcloud",
            "compute",
            "images",
            "create",
            IMAGE_NAME,
            "--source-uri",
            gcs_uri,
            "--family=gitea-actions-vm",
            # N4 requires GVNIC; UEFI_COMPATIBLE + VIRTIO_SCSI_MULTIQUEUE
            # are no-ops on this base image but pre-emptive for other
            # series users might switch to. Ubuntu 26.04 supports all of
            # these in-kernel.
            "--guest-os-features=GVNIC,UEFI_COMPATIBLE,VIRTIO_SCSI_MULTIQUEUE",
            "--quiet",
        ]
    )


def reconcile(last_launched):
    instances = list_burst_instances()
    alive = [i for i in instances if i.get("status") in ALIVE_STATES]
    dead = [i for i in instances if i.get("status") in DEAD_STATES]
    h_servers = list_hetzner_servers() if HETZNER_ENABLED else []
    h_alive, h_dead = split_hetzner_servers(h_servers)

    queued = count_queued_jobs()
    # MAX_INSTANCES caps burst VMs across both providers combined.
    cap = min(
        last_launched + 1,
        MAX_INSTANCES - len(alive) - len(h_alive),
        queued,
    )
    cap = max(0, cap)

    print(
        f"queued={queued} alive={len(alive)} dead={len(dead)} "
        f"hetzner_alive={len(h_alive)} hetzner_dead={len(h_dead)} "
        f"last_launched={last_launched} cap={cap}",
        flush=True,
    )

    if cap:
        zones = list_zones_in_region()
        if not zones and not HETZNER_ENABLED:
            print(f"no UP zones in region {GCP_REGION}", file=sys.stderr)
            return last_launched
        plan = [
            (random_vm_name(), random.choice(zones) if zones else None)
            for _ in range(cap)
        ]
        with ThreadPoolExecutor(max_workers=cap) as pool:
            futures = {pool.submit(launch_one, n, z): n for n, z in plan}
            for f in as_completed(futures):
                name = futures[f]
                try:
                    provider = f.result()
                    print(f"launched on {provider}: {name}", flush=True)
                except Exception as e:
                    print(
                        f"launch {name} failed: {e}",
                        file=sys.stderr,
                        flush=True,
                    )

    if dead:
        cleanup_dead(dead)
    if h_dead:
        cleanup_dead_hetzner(h_dead)

    # All currently-known burst VMs (alive + dead). Used by sweep_orphans
    # to decide which per-VM resources have no owner. Newly-launched VMs
    # in this sweep aren't in `instances`, but the sweep's age threshold
    # protects them.
    sweep_orphans({i["name"] for i in instances})

    return cap


def main():
    ensure_image()
    if HETZNER_ENABLED:
        try:
            hetzner_image_id()
        except Exception as e:
            print(
                f"hetzner snapshot ensure failed ({e}); "
                "will retry on first hetzner launch",
                file=sys.stderr,
                flush=True,
            )
    last_launched = 0
    while True:
        try:
            last_launched = reconcile(last_launched)
        except Exception as e:
            print(f"sweep failed: {e}", file=sys.stderr, flush=True)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
