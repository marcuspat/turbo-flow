#!/usr/bin/env python3
"""setup-harness-glm.py — merge GLM Coding Plan env into ~/.claude/settings.json.

Called by setup-harness.sh (--glm). The key is passed on stdin (never argv).
Creates the file 0600 from the start (no world-readable window); a malformed
existing settings.json is backed up, never silently wiped.
"""
import json
import os
import sys
import time

def main():
    key = sys.stdin.read().strip()
    if not key:
        print("glm-merge: empty key", file=sys.stderr)
        return 1
    p = os.path.expanduser("~/.claude/settings.json")
    cfg = {}
    if os.path.exists(p):
        try:
            cfg = json.load(open(p))
            if not isinstance(cfg, dict):
                raise ValueError("settings.json is not a JSON object")
        except Exception as e:
            bak = p + ".bak-" + str(int(time.time()))
            os.replace(p, bak)
            print(f"glm-merge: settings.json unreadable ({e}) — backed up to {bak}, starting fresh", file=sys.stderr)
            cfg = {}
    cfg.setdefault("env", {})["ANTHROPIC_AUTH_TOKEN"] = key
    cfg["env"]["ANTHROPIC_BASE_URL"] = "https://api.z.ai/api/anthropic"
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, p)
    os.chmod(p, 0o600)
    print("glm-merge: GLM wired into ~/.claude/settings.json (0600)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
