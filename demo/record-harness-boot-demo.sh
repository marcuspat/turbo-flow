#!/usr/bin/env bash
# record-harness-boot-demo.sh — records demo/harness-boot-demo.gif.
# Runs INSIDE a fresh turbo-flow Codespace (the point: nothing preinstalled).
# Prereqs (user-space, no privileges):
#   pip3 install --user --break-system-packages asciinema pexpect
#   curl -fsSL -o ~/bin/agg https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-musl
#     (pinned; verify: sha256 == ddcbf6ca044c8ac3a434dcb9ee89fb9e3be87209982b7c2adb55f782e8f0f390 —
#      agg publishes no checksums on the release page, so it is inlined here)
# Then:  bash demo/record-harness-boot-demo.sh   (it execs the driver below)
#
# Records the v3 boot: no menu — the first shell auto-installs claude+codex+ruflo,
# then tmux opens with all 5 windows. The driver cycles through every window
# so the GIF shows each harness running inside its tmux pane.
set -euo pipefail
cd "$(dirname "$0")/.."

# refuse to record an authenticated session — same rule as the rig-lite demo
bash demo/auth-guard.sh

exec python3 - <<'PYEOF'
import os, sys, time, pexpect

# Take: bash --login -> source ~/.bashrc -> boot hook fires (no menu!) ->
# setup-harness.sh --claude --codex runs visibly -> tmux with 5 windows.
# Then cycle through all 5 windows to show each harness running.
child = pexpect.spawn(
    "asciinema", ["rec", "-q", "--overwrite", "-c", "bash --login", "/tmp/harness-boot.cast"],
    encoding="utf-8", dimensions=(35, 110), timeout=900,
    env={"TERM": "xterm-256color", "HOME": os.environ.get("HOME", "/home/vscode"),
         "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
         "USER": "vscode", "SHELL": "/bin/bash",
         "TF_HOME": os.environ.get("TF_HOME", os.getcwd())})

# wait for the prompt
for i in range(15):
    time.sleep(1)
    try:
        child.expect(r"\$ |➜ ", timeout=2)
        break
    except pexpect.TIMEOUT:
        continue

time.sleep(0.5)
child.send("source ~/.bashrc\r")           # triggers the boot hook (no menu)

# wait for tmux (the status bar contains window names)
for i in range(60):
    time.sleep(5)
    try:
        child.expect(["claude", "install FAILED", "done WITH GAPS"], timeout=2)
        if i > 0 or True:
            pass  # matched — check if it's tmux or a failure
        break
    except pexpect.TIMEOUT:
        continue

# wait for CLIs to load in their windows
time.sleep(15)

# cycle through all 5 windows (Ctrl+B then number)
for window_num in [0, 1, 2, 3, 4]:
    child.send("\x02")
    time.sleep(0.5)
    child.send(str(window_num))
    time.sleep(4)

# back to window 0
child.send("\x02")
time.sleep(0.5)
child.send("0")
time.sleep(3)

# detach and exit
child.send("\x02")
time.sleep(0.5)
child.send("d")
time.sleep(2)
child.send("exit\r")
time.sleep(2)

try:
    child.expect(pexpect.EOF, timeout=10)
except:
    child.terminate(force=True)

size = os.path.getsize("/tmp/harness-boot.cast") if os.path.exists("/tmp/harness-boot.cast") else 0
if size < 1000:
    print("recorder: take FAILED (cast too small: %d bytes)" % size, file=sys.stderr)
    sys.exit(1)
print("cast written: /tmp/harness-boot.cast (%d bytes)" % size)
print("render with: ~/bin/agg /tmp/harness-boot.cast demo/harness-boot-demo.gif --speed 1.8 --font-size 12")
PYEOF
