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

upstream_on = upstream.get("on", {})
if not {"schedule", "workflow_dispatch", "push"}.issubset(upstream_on):
    fail("Upstream Base Watch triggers are incomplete")

all_text = "\n".join(p.read_text(encoding="utf-8") for p in WF.glob("*.y*ml"))
if "origin=debian-watch" in all_text or "inputs.origin" in all_text or "debian-watch.yml" in all_text:
    fail("legacy watcher dispatch contract survived")
if "gh workflow run build-release.yml --ref main -f publish=true" not in (WF / "upstream-watch.yml").read_text(encoding="utf-8"):
    fail("upstream watcher does not request the ordinary verified publication path")

print(f"validated {len(files)} workflow files and current CI/release/upstream contracts")
