#!/usr/bin/env bash
# demo.sh — the rig-lite demo recorded via asciinema in a fresh Codespace.
# Warm-run this once BEFORE recording so the recorded pass hits warm caches.
set -uo pipefail
cd /workspaces/turbo-flow

t() { # type a command char-by-char, then run it
  local cmd="$1"; local i=0
  while (( i < ${#cmd} )); do printf '%s' "${cmd:i:1}"; i=$((i+1)); sleep 0.012; done
  sleep 0.35; printf '\n'; bash -c "$cmd"
  sleep 0.55
}

clear
t 'echo "TURBO FLOW v5.0-PREVIEW — the rig era  ·  fresh Codespace, nothing preinstalled"'
t 'grep -a "━━━" /tmp/e2e.log | tail -12'        # the 11 install steps that ran in THIS container
t 'bash rig-lite/self-test.sh'                    # 26 fail-closed checks
t 'echo "gate.sh — cross-model review, fail-closed"'
# live gate run: reviewer CLIs stubbed (no API keys on the recording box)
D=$(mktemp -d) || exit 1; cd "$D" || exit 1
git init -q -b main && git config user.email demo@demo && git config user.name demo
git commit -q --allow-empty -m base && git checkout -qb feat
echo 'def approve(everything): return True' > gate_me.py
git add . && git commit -qm "add gate_me"
mkdir -p bin && printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "security: returns True for everything — no checks, no tests.\\nVERDICT: REVISE\\n"\n' > bin/claude && chmod +x bin/claude
t "env PATH=\"$PWD/bin:$PATH\" /workspaces/turbo-flow/rig-lite/gate.sh --builder codex"
# fix + approve take
printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "checks pass, tests cover the branch.\\nVERDICT: APPROVED\\n"\n' > bin/claude
echo 'def approve(x): return bool(x)' > gate_me.py && git commit -qam "fix"
t "env PATH=\"$PWD/bin:$PATH\" /workspaces/turbo-flow/rig-lite/gate.sh --builder codex"
cd /workspaces/turbo-flow
t 'echo "✓ deterministic-first · cross-family reviewer · fail-closed · humans merge"'
t 'echo "private beta open → turbo-rig-beta.vercel.app"'
sleep 1.2
