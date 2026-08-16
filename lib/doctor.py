#!/usr/bin/env python3
"""Doctor — Turbo Brain vault health check.

Checks environment, repo health, gates, wave staleness, and vault size.
Returns structured JSON for API consumption.

Usage:
    doctor.py --vault VAULT_PATH [--intake INTAKE_PATH]
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone


def have(cmd):
    return subprocess.run(["which", cmd], capture_output=True).returncode == 0


def count_facts(vault_path):
    """Count total curated facts."""
    total = 0
    curated = ("profile", "areas", "people", "projects", "topics", "daily")
    for d in curated:
        dp = os.path.join(vault_path, d)
        if not os.path.isdir(dp):
            continue
        for dirpath, _, names in os.walk(dp):
            for n in names:
                if not n.endswith(".md"):
                    continue
                try:
                    with open(os.path.join(dirpath, n), "r", errors="replace") as f:
                        total += sum(1 for line in f if line.startswith("- ["))
                except OSError:
                    pass
    return total


def vault_files_by_category(vault_path):
    """Count files per category."""
    cats = {}
    for d in ("profile", "areas", "people", "projects", "topics", "daily"):
        dp = os.path.join(vault_path, d)
        if not os.path.isdir(dp):
            cats[d] = 0
            continue
        count = 0
        for dirpath, _, names in os.walk(dp):
            count += sum(1 for n in names if n.endswith(".md"))
        cats[d] = count
    return cats


def vault_size_bytes(vault_path):
    """Total bytes of curated markdown."""
    total = 0
    curated = ("profile", "areas", "people", "projects", "topics", "daily")
    for d in curated:
        dp = os.path.join(vault_path, d)
        if not os.path.isdir(dp):
            continue
        for dirpath, _, names in os.walk(dp):
            for n in names:
                if n.endswith(".md"):
                    try:
                        total += os.path.getsize(os.path.join(dirpath, n))
                    except OSError:
                        pass
    return total


def wave_status(vault_path):
    """Check last-success per wave with staleness."""
    waves_file = os.path.join(vault_path, ".turbo-brain-waves")
    wave_budgets = {"triage": 36, "distill": 252, "sweep": 1080}
    now = datetime.now(timezone.utc).timestamp()
    results = []

    for name, max_hours in wave_budgets.items():
        ts = None
        if os.path.isfile(waves_file):
            with open(waves_file, "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 2 and parts[0] == name:
                        ts = float(parts[1])

        entry = {"wave": name, "max_age_hours": max_hours}
        if ts is None:
            entry["status"] = "NOT YET RUN"
            entry["age_hours"] = None
            entry["last_success"] = None
        else:
            age = (now - ts) / 3600
            entry["age_hours"] = round(age, 1)
            entry["last_success"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
            entry["status"] = "ok" if age <= max_hours else "STALE"
        results.append(entry)

    return results


def deny_list_status(vault_path):
    """Check deny-list status."""
    deny_path = os.path.join(vault_path, "CLIENTS.deny")
    if not os.path.isfile(deny_path):
        return {"present": False, "terms": 0, "status": "MISSING"}
    with open(deny_path, "r") as f:
        terms = [l.split("#")[0].strip() for l in f if l.split("#")[0].strip()]
    return {"present": True, "terms": len(terms),
            "status": "ok" if terms else "UNARMED (0 terms)"}


def intake_count(intake_path):
    """Count undistilled captures."""
    inbox = os.path.join(intake_path, "inbox")
    if not os.path.isdir(inbox):
        return 0
    return sum(1 for n in os.listdir(inbox) if n.endswith(".md") and os.path.isfile(os.path.join(inbox, n)))


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--vault", required=True)
    ap.add_argument("--intake", default="")
    a = ap.parse_args(argv)

    lib_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")
    result = {
        "toolchain": {"git": have("git"), "python3": have("python3"), "rg": have("rg")},
        "vault": {
            "path": a.vault,
            "is_git_repo": os.path.isdir(os.path.join(a.vault, ".git")),
            "files_by_category": vault_files_by_category(a.vault),
            "total_files": sum(vault_files_by_category(a.vault).values()),
            "total_facts": count_facts(a.vault),
            "size_bytes": vault_size_bytes(a.vault),
            "d4_trigger": vault_size_bytes(a.vault) > 3 * 1024 * 1024,
        },
        "deny_list": deny_list_status(a.vault),
        "waves": wave_status(a.vault),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    if a.intake:
        result["intake"] = {
            "path": a.intake,
            "is_git_repo": os.path.isdir(os.path.join(a.intake, ".git")),
            "undistilled": intake_count(a.intake),
        }

    # Run lint
    try:
        r = subprocess.run([sys.executable, os.path.join(lib_dir, "lint.py"), "--json", a.vault],
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            result["lint"] = {"passed": True, "errors": 0}
        else:
            lint_data = json.loads(r.stdout)
            result["lint"] = {"passed": False, "errors": len(lint_data.get("errors", []))}
    except Exception:
        result["lint"] = {"passed": None, "errors": None, "error": "lint failed to run"}

    # Hooks check
    for repo_name, repo_path in [("vault", a.vault), ("intake", a.intake) if a.intake else ()]:
        hook = os.path.join(repo_path, ".git", "hooks", "pre-commit")
        result.setdefault("hooks", {})[repo_name] = os.path.isfile(hook) and os.access(hook, os.X_OK)

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
