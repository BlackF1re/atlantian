#!/usr/bin/env python3
"""Validate the small set of workflow-level AtlANTian automation contracts."""
from pathlib import Path
import sys
import yaml

ROOT = Path(__file__).resolve().parents[2]
WF = ROOT / ".github" / "workflows"


def fail(message: str) -> None:
    raise SystemExit(f"automation contract: {message}")


def load(name: str):
    path = WF / name
    if not path.is_file():
        fail(f"missing workflow: {name}")
    data = yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    if not isinstance(data, dict) or not isinstance(data.get("jobs"), dict):
        fail(f"invalid workflow structure: {name}")
    return data


def job_needs(job: dict) -> set[str]:
    value = job.get("needs", [])
    if isinstance(value, str):
        return {value}
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return set(value)
    fail(f"invalid job needs declaration: {value!r}")


def checkout_is_credentialless(job: dict) -> bool:
    for step in job.get("steps", []):
        if not isinstance(step, dict) or not str(step.get("uses", "")).startswith("actions/checkout@"):
            continue
        options = step.get("with", {})
        return isinstance(options, dict) and options.get("persist-credentials") == "false"
    return False


files = {p.name for p in WF.glob("*.yml")} | {p.name for p in WF.glob("*.yaml")}
if "debian-watch.yml" in files:
    fail("legacy debian-watch.yml survived")

ci = load("ci.yml")
build = load("build-release.yml")
upstream = load("upstream-watch.yml")
load("image-download-metrics.yml")
load("dependabot-actions-automerge.yml")

ci_on = ci.get("on", {})
if not {"pull_request", "workflow_dispatch"}.issubset(ci_on):
    fail("CI must support pull_request and protected-branch workflow_dispatch validation")

build_on = build.get("on", {})
dispatch = build_on.get("workflow_dispatch", {})
inputs = dispatch.get("inputs", {}) if isinstance(dispatch, dict) else {}
if set(inputs) != {"publish"}:
    fail("Build & Release must expose only the public publish input")
if "push" not in build_on:
    fail("Build & Release must retain automatic main push planning")

build_jobs = build["jobs"]
required_build_jobs = {
    "plan",
    "preflight",
    "rootfs",
    "kernel",
    "assemble",
    "validate_artifacts",
    "validate_sd",
    "validate_nand",
    "sd_upgrade",
    "nand_rebase",
    "seal",
    "publish",
}
if set(build_jobs) != required_build_jobs:
    fail(f"Build & Release job graph changed unexpectedly: {sorted(build_jobs)}")

expected_needs = {
    "preflight": {"plan"},
    "rootfs": {"plan", "preflight"},
    "kernel": {"plan", "preflight"},
    "assemble": {"plan", "rootfs", "kernel"},
    "validate_artifacts": {"plan", "assemble"},
    "validate_sd": {"plan", "assemble"},
    "validate_nand": {"plan", "assemble"},
    "sd_upgrade": {"plan", "assemble"},
    "nand_rebase": {"plan", "assemble"},
    "seal": {"plan", "assemble", "validate_artifacts", "validate_sd", "validate_nand", "sd_upgrade", "nand_rebase"},
    "publish": {"plan", "seal"},
}
for name, expected in expected_needs.items():
    actual = job_needs(build_jobs[name])
    if actual != expected:
        fail(f"Build & Release job {name} needs {sorted(actual)}, expected {sorted(expected)}")

for name in ("rootfs", "kernel"):
    if build_jobs[name].get("runs-on") != "ubuntu-24.04":
        fail(f"{name} must remain an independent ubuntu-24.04 runner job")

for name, job in build_jobs.items():
    condition = job.get("if", "")
    if "github.ref == 'refs/heads/main'" not in condition:
        fail(f"Build & Release job {name} is not explicitly restricted to main")

build_text = (WF / "build-release.yml").read_text(encoding="utf-8")
if "run: sudo -E ./scripts/build-incremental.sh rootfs" not in build_text:
    fail("rootfs is not a direct streaming build job")
if "run: sudo -E ./scripts/build-incremental.sh kernel" not in build_text:
    fail("kernel is not a direct streaming build job")
if "out/build-logs/rootfs.log" in build_text or "out/build-logs/kernel.log" in build_text:
    fail("release workflow buffers core build stdout instead of streaming it")
if "actions/download-artifact@" in build_text:
    fail("release handoff unexpectedly added a second artifact Action dependency")
if "actions/cache@" in build_text:
    fail("release workflow must not expose shared Actions caches to manually dispatched build code")
for token in ("ROOTFS_SHA256", "KERNEL_SHA256", "CANDIDATE_SHA256", "REBASE_SHA256"):
    if token not in build_text:
        fail(f"release handoff is missing trusted digest boundary: {token}")
if 'tar -I zstd -xf handoff/release-candidate.tar.zst' in build_text:
    fail("release candidate is extracted directly into the checkout workspace")
if '-C "$candidate_root" -xf handoff/release-candidate.tar.zst' not in build_text:
    fail("release candidate is not isolated under runner temporary storage")
if 'ATLANTIAN_CANDIDATE_DIR=$candidate_root/artifacts/current' not in build_text:
    fail("validation jobs do not expose the isolated candidate data root")

upstream_on = upstream.get("on", {})
if not {"schedule", "workflow_dispatch", "push"}.issubset(upstream_on):
    fail("Upstream Base Watch triggers are incomplete")

upstream_jobs = upstream["jobs"]
if set(upstream_jobs) != {"candidate", "apply"}:
    fail(f"Upstream Base Watch must separate candidate execution from privileged apply: {sorted(upstream_jobs)}")
candidate = upstream_jobs["candidate"]
apply = upstream_jobs["apply"]
if candidate.get("permissions") != {"contents": "read"}:
    fail("upstream candidate job must have contents:read as its only permission")
if job_needs(apply) != {"candidate"}:
    fail("privileged upstream apply job must depend on the candidate job")
apply_permissions = apply.get("permissions", {})
for permission in ("actions", "contents", "pull-requests", "statuses"):
    if apply_permissions.get(permission) != "write":
        fail(f"upstream apply job is missing required {permission}:write permission")
if not checkout_is_credentialless(candidate) or not checkout_is_credentialless(apply):
    fail("both upstream trust zones must checkout with persist-credentials: false")

candidate_text = "\n".join(str(step.get("run", "")) for step in candidate.get("steps", []) if isinstance(step, dict))
apply_text = "\n".join(str(step.get("run", "")) for step in apply.get("steps", []) if isinstance(step, dict))
for token in ("scripts/build-kernel.sh", "scripts/build-uboot.sh", "scripts/build-uboot-nand.sh"):
    if token not in candidate_text:
        fail(f"read-only upstream candidate job no longer compiles {token}")
    if token in apply_text:
        fail(f"privileged upstream apply job must never execute upstream build path {token}")
if "candidate_digest" not in candidate.get("outputs", {}):
    fail("upstream candidate job does not expose its sealed diff digest")
for token in ("EXPECTED_DIGEST", "git diff --binary --no-ext-diff", "sha256sum"):
    if token not in apply_text:
        fail(f"upstream privileged apply lost candidate digest verification: {token}")
if "gh auth setup-git" not in apply_text:
    fail("upstream apply must authenticate git only inside the trusted privileged zone")

all_text = "\n".join(p.read_text(encoding="utf-8") for p in WF.glob("*.y*ml"))
if "origin=debian-watch" in all_text or "inputs.origin" in all_text or "debian-watch.yml" in all_text:
    fail("legacy watcher dispatch contract survived")
if "gh workflow run build-release.yml --ref main -f publish=true" not in (WF / "upstream-watch.yml").read_text(encoding="utf-8"):
    fail("upstream watcher does not request the ordinary verified publication path")

print(f"validated {len(files)} workflow files and current CI/release/upstream contracts")
