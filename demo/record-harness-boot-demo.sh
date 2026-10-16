#!/usr/bin/env bash
# record-harness-boot-demo.sh — records demo/harness-boot-demo.gif.
# Runs INSIDE a fresh turbo-flow Codespace (the point: nothing preinstalled).
# Prereqs (user-space, no privileges):
#   pip3 install --user --break-system-packages asciinema pexpect
#   curl -fsSL -o ~/bin/agg https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-musl
# Then:  bash demo/record-harness-boot-demo.sh
#
# Records the v3 boot: the shell opens, the boot hook fires (no menu),
# setup-harness.sh --claude --codex runs visibly, then tmux opens with all
# 5 windows. The driver cycles through every window. Fails closed on any error.
set -euo pipefail
cd "$(dirname "$0")/.."

bash demo/auth-guard.sh

exec python3 - <<'PYEOF'
import os, sys, time, pexpect, json

def die(msg):
    print(f"recorder: TAKE FAILED — {msg}", file=sys.stderr)
    sys.exit(1)

def drain(sec):
    child.expect(pexpect.TIMEOUT, timeout=sec)

env = dict(os.environ)
env["TF_HOME"] = env.get("TF_HOME", os.getcwd())
env.setdefault("LANG", "C.UTF-8")
env.setdefault("LC_CTYPE", "C.UTF-8")
env["TERM"] = "xterm-256color"

child = pexpect.spawn(
    "asciinema", ["rec", "-q", "--overwrite", "-c", "bash", "/tmp/harness-boot.cast"],
    encoding="utf-8", dimensions=(35, 110), timeout=900, env=env)

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

drain(0.5)
child.send("source ~/.bashrc\r")

tmux_up = False
for i in range(60):
    drain(5)
    r = os.popen("tmux has-session -t turboflow 2>/dev/null && echo YES || echo NO").read().strip()
    if r == "YES":
        tmux_up = True
        break
    try:
        idx = child.expect(["install FAILED", "done WITH GAPS", "✗ npm"], timeout=1)
        die(f"boot failure marker at {(i+1)*5}s (idx {idx})")
    except pexpect.TIMEOUT:
        pass
if not tmux_up:
    die("tmux session 'turboflow' never appeared within 300s")

drain(15)

win_indexes = os.popen("tmux list-windows -t turboflow -F '#I'").read().split()
if len(win_indexes) < 5:
    die(f"expected 5 windows, found {len(win_indexes)}: {win_indexes}")

for wnum in win_indexes:
    child.send("\x02")
    drain(0.5)
    child.send(str(wnum))
    drain(4)

child.send("\x02")
drain(0.5)
child.send(str(win_indexes[0]))
drain(3)

child.send("\x02")
drain(0.5)
child.send("d")
drain(2)

try:
    child.send("exit\r")
except OSError:
    pass

try:
    child.expect(pexpect.EOF, timeout=10)
except (pexpect.TIMEOUT, pexpect.EOF):
    child.terminate(force=True)

cast_path = "/tmp/harness-boot.cast"
size = os.path.getsize(cast_path) if os.path.exists(cast_path) else 0
if size < 25000:
    die(f"cast too small ({size} bytes)")

try:
    with open(cast_path) as f:
        lines = f.readlines()
    json.loads(lines[-1].strip())
except (json.JSONDecodeError, IndexError):
    die("cast file truncated (last line not valid JSON)")

print(f"cast written: {cast_path} ({size} bytes, {len(lines)} lines)")
print(f"render: ~/bin/agg {cast_path} demo/harness-boot-demo.gif --speed 1.8 --font-size 12")
PYEOF
