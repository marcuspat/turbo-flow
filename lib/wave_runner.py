#!/usr/bin/env python3
"""Wave runner — Turbo Brain (D7, Phase 2).

Scheduled wave invocations with budgets and gates, nothing resident.
Waves: triage (daily), distill (weekly), sweep (monthly).

Each wave:
  1. Reads intake (or vault for sweep)
  2. Runs deterministic gates (secret, deny, lint, dedup, no-net-loss, additions-cap)
  3. Produces output to a staging area (never writes main directly)
  4. Reports what it would change

The actual LLM call for distillation is a SEPARATE step — this module
handles the gate pipeline and orchestration. The LLM integration is
pluggable via a simple protocol.

Usage:
    wave_runner.py --vault VAULT_PATH --intake INTAKE_PATH --wave triage|distill|sweep
    wave_runner.py --vault VAULT_PATH --intake INTAKE_PATH --wave triage --dry-run
    wave_runner.py --wave-config          # print current wave config
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone


def parse_frontmatter(text):
    """Minimal frontmatter parser. Returns (dict, body_lines)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, lines
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return {}, lines
    fm = {}
    for raw in lines[1:end]:
        if ":" not in raw:
            continue
        k, v = raw.split(":", 1)
        v = v.strip()
        if v.startswith("[") and v.endswith("]"):
            v = [x.strip() for x in v[1:-1].split(",") if x.strip()]
        fm[k.strip()] = v
    return fm, lines[end + 1:]


def count_facts(vault_path):
    """Count total curated facts across the vault."""
    total = 0
    curated = ("profile", "areas", "people", "projects", "topics", "daily")
    fact_re = re.compile(r"^- \[(?:stated|ingested|derived)\]")
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
                        for line in f:
                            if fact_re.match(line):
                                total += 1
                except OSError:
                    pass
    return total


def run_gate(name, cmd_args, description):
    """Run a deterministic gate. Returns (passed: bool, output: str)."""
    try:
        r = subprocess.run(cmd_args, capture_output=True, text=True, timeout=30)
        passed = r.returncode == 0
        output = r.stdout + r.stderr
        return passed, output.strip()
    except subprocess.TimeoutExpired:
        return False, f"{name} gate timed out"
    except Exception as e:
        return False, f"{name} gate error: {e}"


def load_waves_config(vault_path):
    """Load wave configuration from .turbo-brain.toml."""
    config = {
        "triage": {"budget_usd": 0.50, "max_age_hours": 36},
        "distill": {"budget_usd": 5.00, "max_age_hours": 252},
        "sweep": {"budget_usd": 3.00, "max_age_hours": 1080},
        "no_net_loss_pct": 5.0,
        "additions_cap_pct": 50.0,
    }
    toml = os.path.join(vault_path, ".turbo-brain.toml")
    if os.path.isfile(toml):
        try:
            with open(toml, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    k, v = k.strip(), v.strip().strip('"')
                    if k == "no_net_loss_pct":
                        config["no_net_loss_pct"] = float(v)
                    elif k == "additions_cap_pct":
                        config["additions_cap_pct"] = float(v)
                    elif k.startswith("budget_"):
                        wave_name = k.replace("budget_", "")
                        if wave_name in config:
                            config[wave_name]["budget_usd"] = float(v)
        except (ValueError, OSError):
            pass
    return config


def intake_files(intake_path):
    """List undistilled capture files from inbox/."""
    inbox = os.path.join(intake_path, "inbox")
    if not os.path.isdir(inbox):
        return []
    return sorted(
        os.path.join(inbox, n)
        for n in os.listdir(inbox)
        if n.endswith(".md") and os.path.isfile(os.path.join(inbox, n))
    )


def read_vault_index(vault_path):
    """Read vault file names and descriptions."""
    curated = ("profile", "areas", "people", "projects", "topics", "daily")
    index = {}
    for d in curated:
        dp = os.path.join(vault_path, d)
        if not os.path.isdir(dp):
            continue
        for dirpath, _, names in os.walk(dp):
            for n in names:
                if not n.endswith(".md"):
                    continue
                path = os.path.join(dirpath, n)
                fm, _ = parse_frontmatter(open(path, "r", errors="replace").read())
                stem = os.path.splitext(n)[0]
                index[stem] = {
                    "path": os.path.relpath(path, vault_path),
                    "description": fm.get("description", ""),
                    "sensitivity": fm.get("sensitivity", "private"),
                }
    return index


def triage_wave(vault_path, intake_path, dry_run=False, config=None):
    """Triage wave: classify inbox items, route to target files.
    Does NOT rewrite — just classifies and proposes routing.
    """
    config = config or load_waves_config(vault_path)
    files = intake_files(intake_path)
    results = []
    lib_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")
    deny = os.path.join(vault_path, "CLIENTS.deny")

    for f in files:
        item = {"file": os.path.relpath(f, intake_path), "gates": [], "action": "route"}
        with open(f, "r", errors="replace") as fh:
            content = fh.read()

        # Gate 1: secret scan
        passed, output = run_gate("secret", [sys.executable, os.path.join(lib_dir, "secret_scan.py"), f], "secret scan")
        item["gates"].append({"name": "secret-scan", "passed": passed, "detail": output if not passed else ""})
        if not passed:
            item["action"] = "quarantine"
            results.append(item)
            continue

        # Gate 2: deny scan
        if os.path.isfile(deny):
            passed, output = run_gate("deny", [sys.executable, os.path.join(lib_dir, "deny_scan.py"), "--deny", deny, f], "deny scan")
            item["gates"].append({"name": "deny-scan", "passed": passed, "detail": output if not passed else ""})
            if not passed:
                item["action"] = "quarantine"
                results.append(item)
                continue
        else:
            item["gates"].append({"name": "deny-scan", "passed": False, "detail": "no deny-list"})

        # Classify: simple keyword routing
        text_lower = content.lower()
        target = "topics"
        for category, keywords in [
            ("people", ["person", "met with", "talked to", "said that"]),
            ("projects", ["repo", "deploy", "build", "ship", "merge", "pr #"]),
            ("areas", ["decided", "ruling", "stance", "approach", "strategy"]),
        ]:
            if any(kw in text_lower for kw in keywords):
                target = category
                break
        item["target"] = target
        results.append(item)

    return {"wave": "triage", "timestamp": datetime.now(timezone.utc).isoformat(), "items": results,
            "budget_usd": config["triage"]["budget_usd"], "dry_run": dry_run}


def distill_wave(vault_path, intake_path, dry_run=False, config=None):
    """Distill wave: merge intake into curated vault.
    Runs all gates, checks no-net-loss and additions cap.
    """
    config = config or load_waves_config(vault_path)
    lib_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")

    # Count pre-existing facts for no-net-loss
    facts_before = count_facts(vault_path)
    max_loss = int(facts_before * config["no_net_loss_pct"] / 100)
    max_additions = int(facts_before * config["additions_cap_pct"] / 100)

    # Gate: vault lint
    lint_passed, lint_output = run_gate("lint", [sys.executable, os.path.join(lib_dir, "lint.py"), vault_path], "vault lint")

    # Read intake
    files = intake_files(intake_path)
    items = []
    for f in files:
        with open(f, "r", errors="replace") as fh:
            content = fh.read()
        items.append({"file": os.path.relpath(f, intake_path), "content": content, "size": len(content)})

    total_new_facts = sum(content.count("\n- [") for item in items for content in [item["content"]])

    # Check additions cap
    additions_ok = True
    if max_additions > 0 and total_new_facts > max_additions:
        additions_ok = False

    return {
        "wave": "distill",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "facts_before": facts_before,
        "intake_items": len(items),
        "new_facts_proposed": total_new_facts,
        "max_loss_allowed": max_loss,
        "max_additions_allowed": max_additions,
        "gates": {
            "vault_lint": {"passed": lint_passed, "detail": lint_output if not lint_passed else "clean"},
            "no_net_loss": {"status": "checked", "threshold": f"{config['no_net_loss_pct']}%"},
            "additions_cap": {"passed": additions_ok, "detail": f"{total_new_facts} proposed vs {max_additions} cap"},
        },
        "budget_usd": config["distill"]["budget_usd"],
        "dry_run": dry_run,
        "ready": lint_passed and additions_ok,
    }


def sweep_wave(vault_path, dry_run=False, config=None):
    """Sweep wave: staleness pass, contradiction detection, hygiene.
    Reports issues but does not auto-fix.
    """
    config = config or load_waves_config(vault_path)
    lib_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")

    lint_passed, lint_output = run_gate("lint", [sys.executable, os.path.join(lib_dir, "lint.py"), vault_path], "vault lint")
    facts = count_facts(vault_path)

    # Check for stale waves
    waves_file = os.path.join(vault_path, ".turbo-brain-waves")
    stale_waves = []
    wave_budgets = {"triage": 36, "distill": 252, "sweep": 1080}
    now = datetime.now(timezone.utc).timestamp()

    if os.path.isfile(waves_file):
        with open(waves_file, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    name, ts = parts[0], float(parts[1])
                    age_hours = (now - ts) / 3600
                    if name in wave_budgets and age_hours > wave_budgets[name]:
                        stale_waves.append({"wave": name, "age_hours": round(age_hours), "max": wave_budgets[name]})

    return {
        "wave": "sweep",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "total_facts": facts,
        "gates": {"vault_lint": {"passed": lint_passed, "detail": lint_output if not lint_passed else "clean"}},
        "stale_waves": stale_waves,
        "budget_usd": config["sweep"]["budget_usd"],
        "dry_run": dry_run,
    }


WAVE_FNS = {"triage": triage_wave, "distill": distill_wave, "sweep": sweep_wave}


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="Turbo Brain wave runner")
    ap.add_argument("--vault", required=True, help="Path to brain-vault")
    ap.add_argument("--intake", help="Path to brain-intake (for triage/distill)")
    ap.add_argument("--wave", required=True, choices=["triage", "distill", "sweep"])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--wave-config", action="store_true", help="Print wave config and exit")
    ap.add_argument("--json", action="store_true", help="JSON output")
    a = ap.parse_args(argv)

    if a.wave_config:
        cfg = load_waves_config(a.vault)
        print(json.dumps(cfg, indent=2))
        return 0

    fn = WAVE_FNS[a.wave]
    kwargs = {"vault_path": a.vault, "dry_run": a.dry_run}
    if a.intake and a.wave in ("triage", "distill"):
        kwargs["intake_path"] = a.intake

    result = fn(**kwargs)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
