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
# Fails closed: any timeout or error marker aborts the take (exit 1).
set -euo pipefail
cd "$(dirname "$0")/.."

# refuse to record an authenticated session — same rule as the rig-lite demo
bash demo/auth-guard.sh

exec python3 - <<'PYEOF'
import os, sys, time, pexpect

def die(msg):
    print(f"recorder: TAKE FAILED — {msg}", file=sys.stderr)
    sys.exit(1)

child = pexpect.spawn(
    "asciinema", ["rec", "-q", "--overwrite", "-c", "bash --login", "/tmp/harness-boot.cast"],
    encoding="utf-8", dimensions=(35, 110), timeout=900,
    env={"TERM": "xterm-256color", "HOME": os.environ.get("HOME", "/home/vscode"),
         "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
         "USER": "vscode", "SHELL": "/bin/bash",
         "TF_HOME": os.environ.get("TF_HOME", os.getcwd())})

# wait for the prompt — die if it never appears
prompt_found = False
for i in range(15):
    time.sleep(1)
    try:
        child.expect(r"\$ |➜ ", timeout=2)
        prompt_found = True
        break
    except pexpect.TIMEOUT:
        continue
if not prompt_found:
    die("no shell prompt appeared within 15s")

time.sleep(0.5)
child.send("source ~/.bashrc\r")

# wait for tmux — match the SESSION NAME in the tmux status bar (not "claude"
# which appears in npm install output long before tmux starts).
# die on failure markers; die on timeout.
tmux_up = False
for i in range(60):
    time.sleep(5)
    try:
        idx = child.expect(["turboflow", "install FAILED", "done WITH GAPS", "✗ npm"], timeout=2)
        if idx == 0:
            tmux_up = True
            break
        else:
            die(f"boot failure marker detected at {(i+1)*5}s (expect index {idx})")
    except pexpect.TIMEOUT:
        continue
if not tmux_up:
    die("tmux never appeared within 300s — the boot may have failed silently")

# wait for CLIs to load in their windows
# drain: let asciinema read the pty buffer while waiting
child.expect(pexpect.TIMEOUT, timeout=15)

# cycle through all 5 windows (Ctrl+B then number)
for window_num in [0, 1, 2, 3, 4]:
    child.send("\x02")
    child.expect(pexpect.TIMEOUT, timeout=0.5)  # drain
    child.send(str(window_num))
    child.expect(pexpect.TIMEOUT, timeout=4)  # drain while the window is visible

# back to window 0
child.send("\x02")
time.sleep(0.5)
child.send("0")
child.expect(pexpect.TIMEOUT, timeout=3)  # drain

# detach and exit
child.send("\x02")
time.sleep(0.5)
child.send("d")
child.expect(pexpect.TIMEOUT, timeout=2)  # drain
child.send("exit\r")
time.sleep(2)

RGFORCED = False
try:
    child.expect(pexpect.EOF, timeout=10)
except (pexpect.TIMEOUT, pexpect.EOF):
    child.terminate(force=True)
    RGFORCED = True  # the cast may be truncated — check size more strictly

size = os.path.getsize("/tmp/harness-boot.cast") if os.path.exists("/tmp/harness-boot.cast") else 0
RGMIN = 10000 if not RGFORCED else 30000  # force-terminated casts need a higher floor
if size < RGMIN:
    die(f"cast too small ({size} bytes, minimum {RGMIN}{' — force-terminated' if RGFORCED else ''}) — the recording likely captured an incomplete session")
print(f"cast written: /tmp/harness-boot.cast ({size} bytes)")
print("render with: ~/bin/agg /tmp/harness-boot.cast demo/harness-boot-demo.gif --speed 1.8 --font-size 12")
PYEOF
