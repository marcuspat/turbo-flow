#!/usr/bin/env bash
# record-harness-boot-demo.sh — records demo/harness-boot-demo.gif.
# Runs INSIDE a fresh turbo-flow Codespace (the point: nothing preinstalled).
# Prereqs (user-space, no privileges):
#   pip3 install --user --break-system-packages asciinema pexpect
#   curl -fsSL -o ~/bin/agg https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-musl
#     (pin + verify the sha256 against the release page before running it)
# Then:  bash demo/record-harness-boot-demo.sh   (it execs the driver below)
set -euo pipefail
cd "$(dirname "$0")/.."

# refuse to record an authenticated session — same rule as the rig-lite demo
bash demo/auth-guard.sh

exec python3 - <<'PYEOF'
import os, sys, time, pexpect

# Take: fresh bash -> ./setup-harness.sh -> the menu -> pick 1 (Claude path).
# Node + Claude Code install for real on camera; plugins wire via the CLI path.
child = pexpect.spawn("asciinema", ["rec", "-q", "--overwrite", "-c", "bash", "/tmp/harness-boot.cast"],
                      encoding="utf-8", dimensions=(32, 100), timeout=900)
child.expect(r"\$ ")
child.send("./setup-harness.sh\r")                # cwd is already the repo root
child.expect(r"choice \[1-4/q\]", timeout=60)      # the harness menu lands
time.sleep(0.8)
for ch in "1":                                     # typed like a human
    child.send(ch); time.sleep(0.25)
child.send("\r")
i = child.expect(["done. next: open the repo README", pexpect.EOF, pexpect.TIMEOUT], timeout=780)
if i != 0:
    print("recorder: take FAILED (session ended or timed out before the script completed)", file=sys.stderr)
    sys.exit(1)
time.sleep(1.0)
try:
    child.send("exit\r")
except OSError:
    pass
child.expect(pexpect.EOF, timeout=30)
print("cast written: /tmp/harness-boot.cast (%d bytes)" % os.path.getsize("/tmp/harness-boot.cast"))
print("render with: ~/bin/agg /tmp/harness-boot.cast demo/harness-boot-demo.gif --speed 1.3 --font-size 13")
PYEOF
