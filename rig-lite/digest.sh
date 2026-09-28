#!/usr/bin/env bash
# digest.sh — gather mechanical inputs for a morning digest into one file.
# A scheduled agent (see automations/README.md task 1) or you runs this,
# then writes the narrative summary on top.
#
# Usage: digest.sh [output-file]   default: <kit>/memory/inbox/YYYY-MM-DD.md
#        digest.sh --selftest      exercise every parser fixture
#
# Config files, all optional, read from the kit directory (this script's dir):
#   repos.txt — one GitHub slug (owner/repo) or local repo PATH per line
#   sites.txt — one URL per line, liveness-checked
# Verdict annotations in the merge queue come from the gate log
# (gate.sh appends one JSON line per verdict):
#   ${GATE_LOG:-~/.local/state/rig-lite/gate-log.jsonl}
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_LOG="${GATE_LOG:-$HOME/.local/state/rig-lite/gate-log.jsonl}"

# Repo-hygiene parser: concatenated gh JSON objects in (compact `gh repo list --jq '.[]'`
# lines + pretty `gh api` objects), gap-only lines out. Fixture-tested via --selftest.
SLUG_RE='^[A-Za-z0-9]([A-Za-z0-9_.-]*[A-Za-z0-9])?/[A-Za-z0-9]([A-Za-z0-9_.-]*[A-Za-z0-9])?$'

# one redaction pipeline for every echoed external-tool stderr — the same
# shapes gate.sh redacts: a token-bearing URL in a gh error must never land
# in a digest file a scheduled agent reads and summarizes
redact() {
  sed -E -e $'s/\x1b\[[0-9;]*[a-zA-Z]//g' \
    -e 's/VERDICT:/VERDICT·/g' \
    -e 's/([Tt]oken|[Kk]ey|[Ss]ecret|[Pp]assword|[Aa]uthorization|Bearer)([=: ]+)[^ ]+/\1\2REDACTED/g' \
    -e 's/sk-[A-Za-z0-9_-]{8,}/REDACTED/g' \
    -e 's/(ghp|gho|ghu|ghs)_[A-Za-z0-9]{20,}/REDACTED/g' \
    -e 's/AKIA[0-9A-Z]{12,}/REDACTED/g'
}
hygiene_parse() { # $1 = file of concatenated gh JSON objects
  python3 - "$1" <<'PY'
import json, sys
gaps = []
junk = 0
dec = json.JSONDecoder()
buf = open(sys.argv[1], encoding="utf-8", errors="replace").read()
i, n = 0, len(buf)
while i < n:
    while i < n and buf[i] in " \t\r\n":
        i += 1
    if i >= n:
        break
    try:
        r, i = dec.raw_decode(buf, i)
    except json.JSONDecodeError:
        nl = buf.find("\n", i)
        i = len(buf) if nl == -1 else nl + 1  # always advance: skip the junk line
        junk += 1
        continue
    if not isinstance(r, dict):
        junk += 1  # resync landed on a bare value mid-object — not a repo record
        continue
    if r.get("archived") or r.get("isArchived"):
        continue
    topics = r.get("topics") or r.get("repositoryTopics") or []
    names = [t["name"] if isinstance(t, dict) else str(t) for t in topics]
    issues = []
    if not (r.get("license") or r.get("licenseInfo")): issues.append("no LICENSE")
    if not r.get("description"): issues.append("no description")
    if not (r.get("homepage") or r.get("homepageUrl")): issues.append("no homepage")
    if not names: issues.append("no topics")
    if issues:
        fork = " (fork)" if r.get("fork") or r.get("isFork") else ""
        gaps.append(f"- {r.get('nameWithOwner') or r.get('full_name')}{fork}: {' · '.join(issues)}")
if junk:
    print(f"- ({junk} unparseable chunks skipped — completeness unknown)")
print("\n".join(gaps) if gaps else "- all repos licensed, described, linked, and tagged")
PY
}

# Merge-queue renderer: open-PR JSON (concatenated gh objects, caller adds .repo) +
# gate-log path in, one status line per PR out. Fixture-tested via --selftest.
mq_render() { # $1 = open-PR JSON file, $2 = gate-log path ("" = no log, all UNGATED)
  python3 - "$1" "$2" <<'PY'
import json, sys, os
from collections import defaultdict

def norm(repo):  # gate-log keys are clone-dir basenames; PR repos are slugs
    r = (repo or "").strip().rstrip("/")
    return r.split("/")[-1] if r else r

prs = []
dec = json.JSONDecoder()
buf = open(sys.argv[1], encoding="utf-8", errors="replace").read()
i, n = 0, len(buf)
while i < n:
    while i < n and buf[i] in " \t\r\n":
        i += 1
    if i >= n:
        break
    try:
        r, i = dec.raw_decode(buf, i)
    except json.JSONDecodeError:
        nl = buf.find("\n", i)
        i = len(buf) if nl == -1 else nl + 1  # always advance past junk
        continue
    if isinstance(r, dict):
        prs.append(r)

gate = defaultdict(lambda: {"runs": 0, "revise": 0, "last": "", "last_res": ""})
log = sys.argv[2] if len(sys.argv) > 2 else ""
if log and os.path.isfile(log):
    for line in open(log, encoding="utf-8", errors="replace"):
        try:
            e = json.loads(line)
        except Exception:
            continue
        t = e.get("target", "")
        if not t.startswith("pr#"):
            continue
        g = gate[(norm(e.get("repo")), t[3:])]
        g["runs"] += 1
        res = e.get("result") or ""
        if "REVISE" in res:
            g["revise"] += 1
        if (e.get("ts") or "") > g["last"]:
            g["last"] = e["ts"]
            g["last_res"] = "APPROVED" if "APPROVED" in res else ("REVISE" if "REVISE" in res else (res or "?")[:20])

if not prs:
    print("- (queue empty)")
else:
    for p in prs:
        repo = norm(p.get("repo") or "")
        num = str(p.get("number") or "")
        title = (p.get("title") or "").strip()
        t = f" · {title[:48]}" if title else ""
        rounds = lambda g: f"{g['runs']} round{'s' if g['runs'] != 1 else ''}"
        g = gate.get((repo, num))
        if not g:
            print(f"- {repo} #{num}{t} · UNGATED ← gate.sh --pr {num}")
        elif g["last_res"] == "APPROVED":
            print(f"- {repo} #{num}{t} · GATED: APPROVED {g['last'][:10]} ({rounds(g)})")
        else:
            print(f"- {repo} #{num}{t} · REVISE outstanding ({g['last'][:10]}, {rounds(g)}, {g['revise']} REVISE)")
PY
}

# Tag `gh pr list --jq '.[]'` output (one JSON object per line) with its repo slug.
# The slug travels as argv DATA — never built into code, so there is no injection
# surface regardless of the repos.txt line's shape. Fixture-tested via --selftest.
mq_tag() { # $1 = owner/repo slug; stdin = PR JSON objects
  python3 -c 'import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
    except Exception:
        continue
    o["repo"] = sys.argv[1]
    print(json.dumps(o))' "$1"
}

# Merged-PR renderer: TSV rows "<owner/repo>/<num>|<title>|<mergedAtIso>" + gate-log
# path in, annotated PR lines out. repo normalization is in lockstep with norm()
# in mq_render — BOTH copies are fixture-tested via --selftest; change them together.
merged_render() { # $1 = merged-PR TSV file, $2 = gate-log path
  python3 - "$1" "$2" <<'PY'
import json, sys, os, datetime
from collections import defaultdict

def norm(x):  # identical to mq_render.norm()
    r = (x or "").strip().rstrip("/")
    return r.split("/")[-1] if r else r

now = datetime.datetime.now(datetime.timezone.utc)
rows = []
# explicit utf-8: cron often runs under LC_ALL=C, and PR titles are arbitrary
# user text — a locale-encoded open() would raise mid-loop and kill the section
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    if not l.strip(): continue
    parts = l.rstrip("\n").split("|", 2)
    if len(parts) != 3 or not parts[2]: continue
    if "/" not in parts[0]: continue  # no slash → not a slug row; skip rather than crash
    repo, num = parts[0].rsplit("/", 1)
    try:
        mt = datetime.datetime.fromisoformat(parts[2].replace("Z", "+00:00"))
    except Exception:
        continue
    if now - mt <= datetime.timedelta(days=7):
        rows.append((repo, num, parts[1], mt))
if not rows:
    print("- (no merged PRs in the last 7 days)"); sys.exit(0)
gate = defaultdict(lambda: {"runs": 0, "revise": 0, "last": ""})
log = sys.argv[2] if len(sys.argv) > 2 else ""
if log and os.path.isfile(log):
    for line in open(log, encoding="utf-8", errors="replace"):
        try: e = json.loads(line)
        except Exception: continue
        t = e.get("target", "")
        if t.startswith("pr#"):
            g = gate[(norm(e.get("repo")), t[3:])]
            g["runs"] += 1
            if "REVISE" in (e.get("result") or ""): g["revise"] += 1
            if (e.get("ts") or "") > g["last"]: g["last"] = e["ts"]
for repo, num, title, mt in rows:
    g = gate.get((norm(repo), num))
    m = mt.strftime("%b %d")
    t = f" — {title[:48]}" if title else ""
    if g:
        print(f"- {repo} #{num}{t} · merged {m} · {g['runs']} gate round{'s' if g['runs'] != 1 else ''} ({g['revise']} REVISE)")
    else:
        print(f"- {repo} #{num}{t} · merged {m} · (no gate runs logged)")
PY
}

# Codespace-hygiene renderer: gh codespace list JSON in, stale lines out.
# Rows with missing/unparseable timestamps count as unknown and are reported,
# never silently skipped (a skip would read as "all clean"). Fixture-tested.
cs_render() { # $1 = gh codespace list JSON file
  python3 - "$1" <<'PY'
import json, sys, datetime
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
if not raw.strip():
    print("- (empty codespace list; hygiene unknown)"); sys.exit(0)
try:
    rows = json.loads(raw)
except Exception:
    print("- (codespace list unparseable; hygiene unknown)"); sys.exit(0)
if not isinstance(rows, list):
    print("- (codespace list unexpected shape; hygiene unknown)"); sys.exit(0)
if not rows:
    print("- (no codespaces)"); sys.exit(0)
now = datetime.datetime.now(datetime.timezone.utc)
stale, unknown = [], 0
for r in rows:
    ts = r.get("lastUsedAt") or r.get("createdAt")
    d = None
    if ts:
        try:
            d = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except Exception:
            d = None
    if d is None:
        unknown += 1
        continue
    days = (now - d).days
    name = r.get("name") or r.get("displayName") or "?"
    repo = r.get("repository") or "?"
    if days >= 7:
        stale.append(f"- STALE {name} ({repo}, {days}d) ← gh codespace delete -c {name}")
if stale:
    print("\n".join(stale))
elif len(rows) - unknown > 0:
    print(f"- {len(rows) - unknown} checked, all used within 7d")
if unknown:
    print(f"- ({unknown} codespace(s) with unknown last-used — NOT checked)")
PY
}

# --selftest: fixture-driven checks for every parser in this script.
if [[ "${1:-}" == "--selftest" ]]; then
  FIX=$(mktemp)
  trap 'rm -f "$FIX" "${MQF:-}" "${GLF:-}" "${MPF:-}" "${CSF:-}"' EXIT  # installed before the other mktemps so partial failure can't leak
  cat > "$FIX" <<'FX'
{"nameWithOwner":"ok/already-clean","description":"d","homepage":"https://x.dev","license":{"key":"mit"},"repositoryTopics":[{"name":"a"}],"isArchived":false}
{"full_name":"gap/rest-fields","description":null,"homepage":"","license":null,"topics":null,"archived":false}
<html> rate limit exceeded {"looks":"almost-json"}
{"nameWithOwner":"trunc/ated","description":"partial
"topics": []
{"full_name":"newline/in-desc","description":"line1\nline2","homepage":"","license":{"key":"mit"},"topics":[]}
{"full_name":"es/ñandú-🚀","description":"emoji 🚀 desc","homepage":"","license":{"key":"mit"},"topics":["a"]}
FX
  want=$'- (4 unparseable chunks skipped — completeness unknown)\n- gap/rest-fields: no LICENSE · no description · no homepage · no topics\n- newline/in-desc: no homepage · no topics\n- es/ñandú-🚀: no homepage'
  got=$(hygiene_parse "$FIX")
  if [[ "$got" == "$want" ]]; then
    echo "parser fixture OK — survives junk, truncation, bare-value resync, escaped newlines"
  else
    echo "selftest FAILED — want:"; echo "$want"; echo "got:"; echo "$got"
    exit 1
  fi
  # slug filter: accept true GitHub slugs, reject local paths and typos
  for s in a/b some-org/repo.name org-name/repo_name x9/y.z; do
    if [[ ! "$s" =~ $SLUG_RE ]]; then echo "selftest FAILED — slug '$s' should match"; exit 1; fi
  done
  # shellcheck disable=SC2088  # '~/x' is a literal rejection fixture, not an expansion
  for s in '../x' 'a/.' '/abs/path' '~/x' 'x/...' 'a//b'; do
    if [[ "$s" =~ $SLUG_RE ]]; then echo "selftest FAILED — slug '$s' should NOT match"; exit 1; fi
  done
  echo "slug filter OK"
  # merge-queue join: basename normalization (incl. path form), verdict states, last-by-ts
  MQF=$(mktemp); GLF=$(mktemp)
  cat > "$MQF" <<'FX'
{"repo":"some-org/alpha","number":11,"title":"support tickets"}
{"repo":"some-org/beta","number":5,"title":"automation tier"}
{"repo":"some-org/other","number":9,"title":"ungated one"}
FX
  cat > "$GLF" <<'FX'
{"ts":"2026-09-14T10:00:00","repo":"/Users/x/alpha/","target":"pr#11","result":"GATE: REVISE"}
{"ts":"2026-09-16T23:00:00","repo":"alpha","target":"pr#11","result":"GATE: APPROVED"}
{"ts":"2026-09-16T22:00:00","repo":"beta","target":"pr#5","result":"GATE: REVISE"}
FX
  want=$'- alpha #11 · support tickets · GATED: APPROVED 2026-09-16 (2 rounds)\n- beta #5 · automation tier · REVISE outstanding (2026-09-16, 1 round, 1 REVISE)\n- other #9 · ungated one · UNGATED ← gate.sh --pr 9'
  got=$(mq_render "$MQF" "$GLF")
  if [[ "$got" == "$want" ]]; then
    echo "merge-queue join OK — basename join (incl. path form), verdict states, last-by-ts"
  else
    echo "selftest FAILED — want:"; echo "$want"; echo "got:"; echo "$got"
    exit 1
  fi
  if [[ "$(mq_render /dev/null "$GLF")" != "- (queue empty)" ]]; then
    echo "selftest FAILED — empty PR set should print '(queue empty)'"; exit 1
  fi
  if ! mq_render "$MQF" "" | grep -q "UNGATED ← gate.sh --pr 11"; then
    echo "selftest FAILED — no gate log should render all PRs UNGATED"; exit 1
  fi
  echo "no-log join OK — absent gate log degrades to UNGATED, never crashes"
  # merged-PR join: the second repo-normalization copy must join the same way.
  # LC_ALL=C on purpose: cron runs there, PR titles are arbitrary user text —
  # the renderer must survive non-ASCII and slash-less junk rows regardless
  MPF=$(mktemp)
  Y=$(python3 -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
  printf 'some-org/alpha/11|support tickets|%s\nsome-org/beta/5|automation tier|%s\nsome-org/u/3|soporte ñandú 🚀|%s\nnotaslug|junk row|%s\n' "$Y" "$Y" "$Y" "$Y" > "$MPF"
  mout=$(LC_ALL=C merged_render "$MPF" "$GLF")
  if echo "$mout" | grep -q "alpha #11" && echo "$mout" | grep -q "2 gate rounds" \
     && echo "$mout" | grep -q "beta #5" && echo "$mout" | grep -q "1 gate round" \
     && echo "$mout" | grep -q "ñandú" && ! echo "$mout" | grep -q "notaslug"; then
    echo "merged-PR join OK — joins intact, unicode title survives LC_ALL=C, junk row skipped"
  else
    echo "selftest FAILED — merged_render output:"; echo "$mout"; exit 1
  fi
  # codespace hygiene: staleness math + unknown-timestamp reporting (never silent)
  CSF=$(mktemp)
  D10=$(python3 -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=10)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
  D1=$(python3 -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
  printf '[{"name":"old-cs","repository":"r/o","lastUsedAt":"%s"},{"name":"new-cs","repository":"r/n","lastUsedAt":"%s"},{"name":"weird","repository":"r/w","lastUsedAt":null,"createdAt":"not-a-date"}]' \
    "$D10" "$D1" > "$CSF"
  want=$'- STALE old-cs (r/o, 10d) ← gh codespace delete -c old-cs\n- (1 codespace(s) with unknown last-used — NOT checked)'
  got=$(cs_render "$CSF")
  if [[ "$got" == "$want" ]]; then
    echo "codespace hygiene OK — staleness math + unknown timestamps reported"
  else
    echo "selftest FAILED — want:"; echo "$want"; echo "got:"; echo "$got"
    exit 1
  fi
  printf '{"error":"not a list"}' > "$CSF"
  if [[ "$(cs_render "$CSF")" != "- (codespace list unexpected shape; hygiene unknown)" ]]; then
    echo "selftest FAILED — non-list JSON must report unknown, not crash"; exit 1
  fi
  echo "shape guard OK"
  # the live tagging pipeline that feeds mq_render — broken here = dead feature
  tagout=$(printf '%s\n%s\n' '{"number":11,"title":"a"}' 'garbage' | mq_tag "x/y")
  if [[ "$(printf '%s\n' "$tagout" | wc -l | tr -d ' ')" == "1" ]] \
     && printf '%s' "$tagout" | grep -q '"repo": "x/y"'; then
    echo "mq tagging pipeline OK — objects tagged, junk skipped"
  else
    echo "selftest FAILED — mq_tag output:"; echo "$tagout"; exit 1
  fi
  # failure detection: a failing gh inside the exact pipeline shape must make the
  # `if !` fire — and a healthy one must NOT (the pair isolates gh-status
  # propagation through `set -o pipefail`, not mq_tag's own exit)
  fakegh() { return 7; }
  if fakegh | mq_tag "x/y" >/dev/null 2>&1; then
    echo "selftest FAILED — gh failure would NOT fire the MQFAILED branch (pipefail off?)"
    exit 1
  fi
  fakeok() { printf '{"number":1,"title":"t"}\n'; return 0; }
  if ! fakeok | mq_tag "x/y" >/dev/null 2>&1; then
    echo "selftest FAILED — healthy pipeline wrongly treated as failed"
    exit 1
  fi
  echo "failure detection OK — failed gh fires the branch, healthy gh does not"
  exit 0
fi

OUT=${1:-$KIT/memory/inbox/$(date +%F).md}
mkdir -p "$(dirname "$OUT")"
# Per-run temp dir + one trap: the dir path is set before any section runs,
# so an abort can never leak temps.
RUNTMP=$(mktemp -d)
trap 'rm -rf "$RUNTMP"' EXIT

{
  echo "# Digest inputs — $(date '+%F %R')"
  echo
  echo "## Gate runs (7 days)"
  python3 - "$GATE_LOG" <<'PY'
import json, os, sys
from datetime import datetime, timedelta, timezone
log = sys.argv[1]
runs = []
if log and os.path.isfile(log):
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    for line in open(log, encoding="utf-8", errors="replace"):
        try:
            r = json.loads(line)
            ts = r.get("ts", "")
            d = datetime.fromisoformat(ts.replace("Z", "+00:00")) if ts else None
            if d and d >= cutoff:
                runs.append(r)
        except Exception:
            continue
if not runs:
    print(f"- no gate runs in the last 7 days (log: {log})")
else:
    ok = sum(1 for r in runs if "APPROVED" in (r.get("result") or ""))
    reviewers = ", ".join(sorted({r.get("reviewer", "?") for r in runs}))
    print(f"- **{len(runs)} gate runs** ({reviewers}) — {ok} APPROVED / {len(runs)-ok} REVISE")
PY
  echo
  if [[ -f "$KIT/repos.txt" ]]; then
    while IFS= read -r r; do
      [[ -z "$r" || "$r" == \#* ]] && continue
      echo "## $r"
      if [[ -d "$r" ]]; then
        (cd "$r" 2>/dev/null && \
          echo "- branch: $(git branch --show-current 2>/dev/null)" && \
          echo "- dirty files: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')" && \
          echo "- last commit: $(git log -1 --format='%h %ad %s' --date=short 2>/dev/null)")
      elif command -v gh >/dev/null 2>&1; then
        echo "### PRs";  gh pr list -R "$r" --limit 10 --json number,title,author,reviewDecision \
          --template '{{range .}}- #{{.number}} {{.title}} ({{.author.login}}, review: {{.reviewDecision}}){{"\n"}}{{end}}' 2>/dev/null
        echo "### Issues"; gh issue list -R "$r" --limit 10 \
          --template '{{range .}}- #{{.number}} {{.title}}{{"\n"}}{{end}}' 2>/dev/null
      else
        echo "- (gh not found; add local path or install gh)"
      fi
      echo
    done < "$KIT/repos.txt"
  else
    echo "No repos.txt — add 'owner/repo' or local paths, one per line."
  fi
  echo
  echo "## Merge queue"
  # Open PRs across repos.txt joined with gate-log verdicts — answers "ready to merge?"
  MQTMP="$RUNTMP/mq"
  : > "$MQTMP"  # create eagerly — a run where every gh query fails must still render the queue section
  MQFAILED=""
  MQSCANNED=0
  if [[ -f "$KIT/repos.txt" ]] && command -v gh >/dev/null 2>&1; then
    while IFS= read -r r; do
      if [[ -z "$r" || "$r" == \#* ]]; then continue; fi  # blank/comment lines
      if [[ ! "$r" =~ $SLUG_RE ]]; then continue; fi  # local-path repos: not queue-able
      MQSCANNED=$((MQSCANNED + 1))
      # failure detection: gh's non-zero exit must fire the ! branch — this relies
      # on `set -o pipefail` (top of file), proven by --selftest's fake-gh fixture
      if ! gh pr list -R "$r" --state open --limit 30 --json number,title --jq '.[]' 2>/dev/null \
        | mq_tag "$r" >> "$MQTMP"; then
        MQFAILED+=" $r"  # a failed query must shorten the queue LOUDLY, not silently
      fi
    done < "$KIT/repos.txt"
    if [[ $MQSCANNED -eq 0 ]]; then
      echo "- (no GitHub slug repos in repos.txt — merge queue covers slug repos only)"
    else
      mq_render "$MQTMP" "$GATE_LOG"
      if [[ -n "$MQFAILED" ]]; then
        echo "- (query failed for:$MQFAILED — their PRs are missing from this queue)"
      fi
    fi
  else
    echo "- (gh not found or no repos.txt; cannot build merge queue)"
  fi
  rm -f "$MQTMP"
  echo
  echo "## Tasks completed — merged PRs (7 days)"
  TMPPRS="$RUNTMP/prs"; : > "$TMPPRS"
  if [[ -f "$KIT/repos.txt" ]] && command -v gh >/dev/null 2>&1; then
    while IFS= read -r r; do
      # slug repos only, same filter as the merge queue — local paths and
      # typos are not merge-history sources
      [[ -z "$r" || "$r" == \#* || "$r" != */* ]] && continue
      [[ "$r" =~ $SLUG_RE ]] || continue
      gh pr list -R "$r" --state merged --limit 20 --json number,title,mergedAt \
        --template '{{range .}}{{.number}}|{{.title}}|{{.mergedAt}}{{"\n"}}{{end}}' 2>/dev/null | sed "s|^|$r/|" >> "$TMPPRS"
    done < "$KIT/repos.txt"
  fi
  merged_render "$TMPPRS" "$GATE_LOG"
  rm -f "$TMPPRS"
  echo
  echo "## Kit repo activity"
  (cd "$KIT" && git log --oneline -5 2>/dev/null | sed 's/^/- /') || echo "- (kit not inside a git repo)"
  echo
  echo "## Site liveness"
  if [[ -f "$KIT/sites.txt" ]]; then
    while IFS= read -r url; do
      [[ -z "$url" || "$url" == \#* ]] && continue
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url" 2>/dev/null || echo 000)
      if [[ "$code" == 2* || "$code" == 3* ]]; then
        echo "- UP   $url ($code)"
      else
        echo "- DOWN $url ($code)  ← check this"
      fi
    done < "$KIT/sites.txt"
  else
    echo "(no sites.txt)"
  fi
  echo
  echo "## Codespace hygiene"
  # Stale codespaces burn free-tier hours — flag anything unused >7 days.
  CSTMP="$RUNTMP/cs"
  if ! command -v gh >/dev/null 2>&1; then
    echo "- (gh not found; cannot check codespaces)"
  elif ! gh codespace list --json name,displayName,repository,lastUsedAt,createdAt --limit 300 > "$CSTMP" 2>/dev/null; then
    echo "- (gh codespace list failed; hygiene unknown)"
  else
    cs_render "$CSTMP"
  fi
  rm -f "$CSTMP"
  echo
  echo "## Repo hygiene"
  # Gap-only: repos missing LICENSE / About description / homepage / topic tags.
  # Archived repos skipped; one "all clean" line = nothing to fix. Weekly fix pass
  # (automations/README.md task 5) clears what lands here.
  # Repo metadata is untrusted: JSON end-to-end, one parser — never flatten to TSV
  # (a tab/newline in a description would split or shift records).
  if command -v gh >/dev/null 2>&1; then
    OWNER="${DIGEST_HYGIENE_OWNER:-$(gh api user --jq .login 2>/dev/null)}"
    if [[ -z "$OWNER" ]]; then
      echo "- (cannot resolve the authenticated gh user — set DIGEST_HYGIENE_OWNER or re-auth gh)"
    else
      HYG="$RUNTMP/hyg"
      HYGFAIL=0
      if ! HYGERR=$(gh repo list "$OWNER" --json nameWithOwner,isArchived,isFork,licenseInfo,description,homepageUrl,repositoryTopics \
        --limit 200 --jq '.[]' 2>&1 >"$HYG"); then HYGFAIL=1; fi
      # repos.txt entries under other owners (org repos) that `gh repo list $OWNER` misses.
      # GitHub slug entries only — local paths and typos are skipped.
      if [[ -f "$KIT/repos.txt" ]]; then
        while IFS= read -r r; do
          if [[ ! "$r" =~ $SLUG_RE ]]; then continue; fi
          if [[ "$r" == "$OWNER"/* ]]; then continue; fi
          gh api "repos/$r" >> "$HYG" 2>/dev/null || HYGFAIL=1
        done < "$KIT/repos.txt"
      fi
      if [[ -s "$HYG" ]]; then
        hygiene_parse "$HYG"
        if [[ $HYGFAIL == 1 ]]; then
          echo "- (a gh query failed; listed repos may be incomplete — hygiene of missing repos unknown)"
        fi
      else
        ERRNOTE=""
        if [[ -n "${HYGERR:-}" ]]; then ERRNOTE=" — first error: $(printf '%s' "${HYGERR%%$'\n'*}" | redact)"; fi
        echo "- (gh queries failed or returned nothing; hygiene unknown${ERRNOTE:0:120})"
      fi
      rm -f "$HYG"
    fi
  else
    echo "- (gh not found; cannot check repo hygiene)"
  fi
  echo
  echo "## Inbox backlog"
  ls -1 "$KIT/memory/inbox/" 2>/dev/null | tail -5 | sed 's/^/- /'
} > "$OUT"
echo "$OUT"
