import json
import os
import random
import subprocess
import sys
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
IMAGE_TARBALL = os.environ["IMAGE_TARBALL"]
POLL_INTERVAL = int(os.environ["POLL_INTERVAL"])

CREDS_DIR = Path(os.environ["CREDENTIALS_DIRECTORY"])
RT_DIR = Path(os.environ["RUNTIME_DIRECTORY"])

GITEA_API_TOKEN = (CREDS_DIR / "gitea-api-token").read_text().strip()
GITEA_REG_TOKEN = (CREDS_DIR / "gitea-registration-token").read_text().strip()

# Image name tracks the content hash of the prebuilt tarball — the GCE
# custom image and the GCS object share that name.
IMAGE_NAME = (
    "gitea-actions-vm-" + os.path.basename(IMAGE_TARBALL).split("-")[0]
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


def write_cidata_files(stage, vm_name):
    (stage / "meta-data").write_text(
        f"instance-id: {vm_name}\nlocal-hostname: {vm_name}\n"
    )
    # DHCP-only network-config. GCE assigns DHCP on the primary NIC; we
    # match any predictable kernel name so the same config works
    # regardless of GCE's NIC naming.
    (stage / "network-config").write_text(
        "version: 2\nethernets:\n"
        "  primary:\n"
        "    match:\n"
        '      name: "e*"\n'
        "    dhcp4: true\n"
    )
    (stage / "user-data").write_text("")
    (stage / "config.yaml").write_text(
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


def launch_one(vm_name, zone):
    work = RT_DIR / vm_name
    stage = work / "stage"
    stage.mkdir(parents=True, exist_ok=True)

    gcs_uri = f"gs://{GCS_BUCKET}/{vm_name}.tar.gz"
    cidata_image = f"{vm_name}-cidata"
    gcs_created = False
    image_created = False
    vm_create_attempted = False

    try:
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

        write_cidata_files(stage, vm_name)

        # ISO9660 with volume identifier "cidata" -- recognised by cloud-init's
        # NoCloud datasource and surfaces as /dev/disk/by-label/cidata, which
        # is what the in-VM runner.service mounts.
        subprocess.check_call(
            [
                "xorriso",
                "-as",
                "mkisofs",
                "-output",
                str(work / "cidata.raw"),
                "-volid",
                "cidata",
                "-joliet",
                "-rock",
                str(stage),
            ]
        )

        # GCE image upload format: tar.gz containing a single `disk.raw`.
        subprocess.check_call(
            [
                "tar",
                "-Sczf",
                str(work / "cidata.tar.gz"),
                "-C",
                str(work),
                "--transform=s#cidata.raw#disk.raw#",
                "cidata.raw",
            ]
        )

        subprocess.check_call(
            [
                "gcloud",
                "storage",
                "cp",
                str(work / "cidata.tar.gz"),
                gcs_uri,
                "--quiet",
            ]
        )
        gcs_created = True

        subprocess.check_call(
            [
                "gcloud",
                "compute",
                "images",
                "create",
                cidata_image,
                "--source-uri",
                gcs_uri,
                "--quiet",
            ]
        )
        image_created = True

        vm_create_attempted = True
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
                # size=4: hyperdisk-balanced (N4 default) has a 4 GiB minimum,
                # GCE pads zeros after the ~1 MiB ISO. udev still tags
                # /dev/disk/by-label/cidata from the filesystem signature at
                # the start of the disk. mode=ro isn't valid for hyperdisk;
                # the in-VM unit mounts ISO with -o ro and the disk is
                # auto-deleted with the VM, so rw at the GCE layer is safe.
                f"--create-disk=name={vm_name}-cidata,image={cidata_image},"
                f"image-project={GCP_PROJECT},auto-delete=yes,size=4,"
                "device-name=cidata",
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
        # Best-effort reverse-order cleanup. Any straggler that survives
        # here is still picked up later by sweep_orphans().
        if vm_create_attempted:
            # `create` can fail after the VM resource exists (e.g. disk
            # creation succeeded, post-create polling timed out), so try
            # the delete regardless of where the exception fired.
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
        if image_created:
            subprocess.run(
                [
                    "gcloud",
                    "compute",
                    "images",
                    "delete",
                    cidata_image,
                    "--quiet",
                ],
                check=False,
            )
        if gcs_created:
            subprocess.run(
                [
                    "gcloud",
                    "storage",
                    "rm",
                    gcs_uri,
                    "--quiet",
                ],
                check=False,
            )
        raise


def cleanup_dead(dead):
    # Image and GCS first; VM last. Transient failures on the trailing
    # resources are recovered by sweep_orphans() on a subsequent pass
    # once the VM no longer shields them.
    for inst in dead:
        name = inst["name"]
        zone = inst.get("_zone_name") or inst["zone"].rsplit("/", 1)[-1]

        subprocess.run(
            [
                "gcloud",
                "compute",
                "images",
                "delete",
                f"{name}-cidata",
                "--quiet",
            ],
            check=False,
        )
        subprocess.run(
            [
                "gcloud",
                "storage",
                "rm",
                f"gs://{GCS_BUCKET}/{name}.tar.gz",
                "--quiet",
            ],
            check=False,
        )

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
    # Backstop for both launch_one partial-failure paths that escape
    # local cleanup and cleanup_dead's check=False image/GCS deletes.
    # Per-VM resources are name-prefixed (gitea-burst-<hex>...), so we
    # filter strictly to that prefix and leave the shared base image
    # (gitea-actions-vm-<hash>) alone. The age threshold guards against
    # listing eventual-consistency races against a just-launched VM
    # that hasn't yet surfaced in list_burst_instances().
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

    queued = count_queued_jobs()
    cap = min(last_launched + 1, MAX_INSTANCES - len(alive), queued)
    cap = max(0, cap)

    print(
        f"queued={queued} alive={len(alive)} dead={len(dead)} "
        f"last_launched={last_launched} cap={cap}",
        flush=True,
    )

    if cap:
        zones = list_zones_in_region()
        if not zones:
            print(f"no UP zones in region {GCP_REGION}", file=sys.stderr)
            return last_launched
        plan = [(random_vm_name(), random.choice(zones)) for _ in range(cap)]
        with ThreadPoolExecutor(max_workers=cap) as pool:
            futures = {pool.submit(launch_one, n, z): n for n, z in plan}
            for f in as_completed(futures):
                name = futures[f]
                try:
                    f.result()
                    print(f"launched: {name}", flush=True)
                except Exception as e:
                    print(
                        f"launch {name} failed: {e}",
                        file=sys.stderr,
                        flush=True,
                    )

    if dead:
        cleanup_dead(dead)

    # All currently-known burst VMs (alive + dead). Used by sweep_orphans
    # to decide which per-VM resources have no owner. Newly-launched VMs
    # in this sweep aren't in `instances`, but the sweep's age threshold
    # protects them.
    sweep_orphans({i["name"] for i in instances})

    return cap


def main():
    ensure_image()
    last_launched = 0
    while True:
        try:
            last_launched = reconcile(last_launched)
        except Exception as e:
            print(f"sweep failed: {e}", file=sys.stderr, flush=True)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
