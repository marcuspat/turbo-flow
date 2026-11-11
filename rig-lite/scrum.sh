#!/usr/bin/env bash
# scrum.sh — scrum ceremonies for an agent fleet: the sprint container, the
# async standup, and Law-11 escalation detection. Everything is computed from
# state that already exists — the gate log the gate itself writes, git
# worktree facts, and the sprint file. The offline tier needs no network and
# no gh; nothing here is a daemon, a SaaS, or a meeting.
#
# Usage:
#   scrum.sh sprint new [--days N] [--lanes N] [--rounds N] [--id SLUG]
#                                                   scaffold the next sprint file
#   scrum.sh sprint validate [file]                structural checks, fail-closed
#   scrum.sh sprint status [file]                  board: lanes, rounds, WIP, deadline
#   scrum.sh sprint close [file]                   carry unfinished, write review stub
#   scrum.sh standup [file] [--no-save]            shipped / in-flight / blockers / capacity
#   scrum.sh --selftest                            parser fixtures (no repo needed)
#
# Files live in <repo>/sprints/ (one open sprint at a time; standups in
# sprints/standups/). Lane data comes from the gate log
# (${GATE_LOG:-~/.local/state/rig-lite/gate-log.jsonl}) — rows the gate itself
# appends per verdict — plus `git worktree` facts. GATE_ROUND_CAP is the SAME
# env the gate reads (default 3): when a lane or PR burns the cap AND its
# newest verdict is a RECENT REVISE (a live stuck loop, not history), the
# standup raises the Law-11 fork (continue / park / pivot) for the human.
#
# Exit codes: 0 ok · 1 validation/refusal · 2 usage error.
set -uo pipefail
GATE_LOG="${GATE_LOG:-$HOME/.local/state/rig-lite/gate-log.jsonl}"
GATE_ROUND_CAP="${GATE_ROUND_CAP:-3}"
GATE_FRESH="${GATE_FRESH:-1800}"        # 30 min: the queue-ownership window
STALL_LO="${STALL_LO:-21600}"           # 6 h: stalled starts
STALL_HI="${STALL_HI:-259200}"          # 72 h: dropped starts
SPRINT_DAYS="${SPRINT_DAYS:-7}"
SPRINT_LANES="${SPRINT_LANES:-2}"
SPRINT_ROUNDS="${SPRINT_ROUNDS:-12}"

# generated ceremony output passes through this once: the standup render and
# sprint scaffolds. It must never emit a parseable VERDICT line (verdict
# parseability belongs to the gate alone) and must never echo a token shape.
# User-authored file text is NOT rewritten in place by ceremonies — it gets
# scrubbed when it flows through sprint new's carry-forward, which is why
# the sk- pattern needs a left boundary: unanchored, it eats ordinary words
# like "task-12345678" ("ta" + a fake key shape).
scrub() {
  sed -E -e 's/VERDICT:/VERDICT·/g' \
    -e 's/(ghp|gho|ghu|ghs)_[A-Za-z0-9]{20,}/REDACTED/g' \
    -e 's/(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{8,}/\1REDACTED/g'
}

usage() { sed -n '2,20p' "$0"; exit "${1:-0}"; }

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || { echo "scrum.sh: run me inside a git repo (sprints live in <repo>/sprints/)" >&2; exit 2; }
}

# ── pure: parse a sprint file into key<TAB>value lines ──────────────────────
# status|opened|closes|lanes|rounds · item<TAB><done 0|1><TAB>text ·
# carried<TAB><n><TAB>text. Structural violation → reasons on stderr, exit 1.
# (No bare } at column 0 inside the heredocs — the self-test awk-extracts
# these functions verbatim; a bare closing brace would truncate them.)
parse_sprint() {
  python3 - "$1" <<'PY'
import re, sys
try:
    txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError as e:
    print(f"sprint file unreadable: {e}", file=sys.stderr); sys.exit(1)
errs = []
def grab(pat, label, line):
    m = re.search(pat, line)
    if not m: errs.append(f"{label} line malformed: {line!r}")
    return (m.group(1).strip() if m else None)
status = opened = closes = lanes = rounds = None
items, carried, section = [], [], None
DATE = r"\d{4}-\d{2}-\d{2}"
for ln in txt.splitlines():
    if ln.startswith("Status:"):
        status = grab(r"Status:\s*(open|closed)\b", "Status", ln)
        if status:
            opened = grab(r"opened:\s*(" + DATE + ")", "opened", ln)
            closes = grab(r"closes:\s*(" + DATE + ")", "closes", ln)
    elif ln.startswith("Capacity:"):
        lanes = grab(r"lanes:\s*(\d+)", "Capacity lanes", ln)
        rounds = grab(r"rounds:\s*(\d+)", "Capacity rounds", ln)
    elif ln.startswith("## "):
        section = ln[3:].strip().lower()
    elif section == "in scope" and re.match(r"^- \[[ x]\] \S", ln):
        m = re.match(r"^- \[([ x])\] (.*)$", ln)
        items.append(("0" if m.group(1) == " " else "1", m.group(2).strip()))
    elif section == "carried" and re.match(r"^- \S", ln):
        m = re.match(r"^- (.*?)(?:\s*\(carried:\s*(\d+)\))?\s*$", ln)
        carried.append((int(m.group(2) or "1"), m.group(1)))
if not status: errs.append("no 'Status: open|closed ...' line")
if status and not (opened and closes): errs.append("Status line missing opened:/closes: dates")
if opened and closes and closes < opened: errs.append(f"closes {closes} before opened {opened}")
if lanes is None or rounds is None: errs.append("no 'Capacity: lanes: N · rounds: N' line")
if errs:
    for e in errs: print(f"sprint: {e}", file=sys.stderr)
    sys.exit(1)
out = [f"status\t{status}", f"opened\t{opened}", f"closes\t{closes}",
       f"lanes\t{lanes}", f"rounds\t{rounds}"]
for d, t in items: out.append(f"item\t{d}\t{t}")
for n, t in carried: out.append(f"carried\t{n}\t{t}")
print("\n".join(out))
PY
}

# ── pure: gate-log rows for one target (branch:<name> / pr#N) ───────────────
# Rows count only when the row's repo matches one of the repo basenames the
# gate could have logged under (gate.sh logs basename(TOP): the main
# checkout when gated there, the lane's own name when gated from its
# worktree — see gate_repolist, which supplies both plus every sibling). A
# comma-list is accepted; two clones of the same project on one machine
# share the machine-local log, and a lane must never inherit another
# clone's rounds. Optional $4 = ISO cutoff — rows older than it don't count
# (used for the fork decision, so a reused branch name inherits at most one
# stale window of escalation). Fields are always fully populated ("-"
# placeholders — tab-splitting with IFS merges empty fields). Prints:
#   <rounds>\t<last_ts|->\t<last_result|->
rounds_for() {
  python3 - "$1" "$2" "$3" "${4:-}" <<'PY'
import json, os, sys
log, target, repo_arg, cutoff = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
repos = [r for r in repo_arg.split(",") if r]
n, last_ts, last_res = 0, "-", "-"
if log and os.path.isfile(log):
    for line in open(log, encoding="utf-8", errors="replace"):
        try: r = json.loads(line)
        except Exception: continue
        if r.get("target") != target: continue
        if repos and (r.get("repo") or "") not in repos: continue
        ts = r.get("ts") or ""
        if cutoff and ts and ts < cutoff: continue
        n += 1
        if ts >= (last_ts if last_ts != "-" else ""):
            last_ts, last_res = (ts if ts else "-"), (r.get("result") or "-")
print(f"{n}\t{last_ts}\t{last_res}")
PY
}

# ── pure: lane state machine (offline tier, mirrors the loop-board spec) ────
# in: last_ts last_result merged(0|1) dirty(0|1) tip_age_s rounds cap
# out: one state string
lane_state() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$GATE_FRESH" "$STALL_LO" "$STALL_HI" <<'PY'
import datetime, sys
last_ts, last_res, merged, dirty, tip_age, rounds, cap = sys.argv[1:8]
fresh, stall_lo, stall_hi = float(sys.argv[8]), float(sys.argv[9]), float(sys.argv[10])
def age_s(ts):
    try:
        t = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
        return (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()
    except Exception:
        return None
if merged == "1": print("done (merged)"); sys.exit(0)
a = age_s(last_ts)
if not last_ts or a is None:
    old = (tip_age == "?" or float(tip_age) >= 7*86400) and dirty == "0"
    print("dormant (no gate rows)" if old else "building (pre-gate)"); sys.exit(0)
res = "REVISE" if "REVISE" in last_res else ("APPROVED" if "APPROVED" in last_res else "other")
if res == "REVISE" and a < fresh: print(f"gating (round {rounds}/{cap})")
elif res == "APPROVED" and a < fresh: print("gated · PR imminent")
elif res == "APPROVED": print("awaiting-human (merge)")
elif stall_lo <= a < stall_hi: print("stalled")
elif a >= stall_hi: print("dropped (>=72h silent)")
else: print("fixing (unknown result)" if res == "other" else "fixing (REVISE)")
PY
}

fmt_age() {
  python3 - "$1" <<'PY'
import sys
try: a = float(sys.argv[1])
except Exception: print("?"); sys.exit(0)
print(f"{a/3600:.0f}h" if a >= 3600 else f"{a/60:.0f}m")
PY
}

days_left() {
  python3 - "$1" <<'PY'
import datetime, sys
try: print((datetime.date.fromisoformat(sys.argv[1]) - datetime.date.today()).days)
except Exception: print("?")
PY
}

age_seconds_of() { # ISO ts → seconds-since (stdout), "?" when unparsable
  python3 - "$1" <<'PY'
import datetime, sys
try:
    t = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    print(f"{(datetime.datetime.now(datetime.timezone.utc) - t).total_seconds():.0f}")
except Exception:
    print("?")
PY
}

# ── sprint discovery ────────────────────────────────────────────────────────
# Sprints anchor at the MAIN checkout: they are the PO's artifacts, one set
# per repo — untracked files in the main checkout are invisible from inside
# a worktree, so a worktree run must resolve the main path, not $PWD.
sprints_dir() {
  local root mainpath
  root="$(repo_root)"
  mainpath="$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)"
  printf '%s/sprints\n' "${mainpath:-$root}"
}

find_open_sprint() { # prints path · exit 1 if none (or if >1 — one at a time)
  local dir f found=""
  dir="$(sprints_dir)"
  [[ -d "$dir" ]] || { echo "scrum.sh: no sprints/ directory — run: tf sprint new" >&2; return 1; }
  while IFS= read -r f; do
    if grep -qE '^Status:\s*open\b' "$f" 2>/dev/null; then
      if [[ -n "$found" ]]; then echo "scrum.sh: two open sprints ($found, $f) — close one first" >&2; return 1; fi
      found="$f"
    fi
  done < <(ls "$dir"/*.md 2>/dev/null | sort)
  if [[ -z "$found" ]]; then echo "scrum.sh: no open sprint — run: tf sprint new" >&2; return 1; fi
  printf '%s\n' "$found"
}

next_sprint_id() { # <YYYY-MM>-<letter>, bumping; --id overrides before this runs
  local dir base letters="" letter f id bumped
  dir="$(sprints_dir)"; base="$(date -u +%Y-%m)"
  for f in "$dir/$base"-*.md; do
    [[ -e "$f" ]] || continue
    id="$(basename "$f" .md)"
    letters="$letters ${id##*-}"
  done
  if [[ -z "${letters// /}" ]]; then printf '%s-A\n' "$base"; return 0; fi
  # max by (length, value): string-compare alone puts Z9 after Z10. Only
  # auto-generated letter shapes vote — a custom --id (2026-11-hotfix) must
  # never poison the sequence.
  bumped="$(python3 - ${letters} <<'PY'
import re, sys
cs = [c for c in sys.argv[1:] if re.match(r"^([A-Z]|Z\d+)$", c)]
if not cs:
    print("A")
else:
    max_c = max(cs, key=lambda c: (len(c), c))
    if len(max_c) == 1:
        print(chr(ord(max_c) + 1) if max_c < "Z" else "Z2")
    else:
        m = re.match(r"^Z(\d+)$", max_c)
        print(f"Z{int(m.group(1)) + 1}" if m else max_c)
PY
)"
  printf '%s-%s\n' "$base" "$bumped"
}

# ── worktree lane facts ─────────────────────────────────────────────────────
# TSV per kit worktree: name<TAB>merged(0|1)<TAB>dirty(0|1)<TAB>tip_age_s|"?"
# The MAIN worktree is `git worktree list`'s FIRST entry — not the checkout
# we happen to stand in (wt.sh's own flow has you run ceremonies from inside
# a worktree). Lanes are the entries under <main>/.worktrees/ — standing in
# .worktrees/x must show lane x AND its siblings, so the filter anchors on
# the main checkout, never on $PWD.
lane_facts() {
  local root main mainpath wt br
  root="$(repo_root)"
  mainpath="$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)"
  main="$(git -C "${mainpath:-$root}" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  git -C "$root" worktree list --porcelain 2>/dev/null | awk '
    $1 == "worktree" { wt = $0; sub(/^worktree /, "", wt) }
    $1 == "branch"   { sub("refs/heads/", "", $2); print wt "\t" $2 }
  ' | while IFS="$(printf '\t')" read -r wt br; do
    [[ -z "$br" ]] && continue
    [[ "$wt" == "$mainpath" ]] && continue                                 # the main checkout is not a lane
    case "$wt" in "$mainpath/.worktrees"/*) ;; *) continue ;; esac   # kit worktrees only, anchored at main
    local merged=0 dirty=0 age="?" ts bt mt
    # untouched branch (tip == main tip) is NOT merged work — an ancestor
    # check alone would call every fresh wt.sh lane "done"
    bt="$(git -C "$root" rev-parse -q --verify "$br")"
    mt="$(git -C "$root" rev-parse -q --verify "$main")"
    if [[ -n "$bt" && -n "$mt" && "$bt" != "$mt" ]] && git -C "$root" merge-base --is-ancestor "$bt" "$mt" 2>/dev/null; then
      merged=1
    fi
    # the LANE's own tree is dirty or not — the caller's checkout says
    # nothing about the lane (after a standup saves, $root is always dirty)
    [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]] && dirty=1
    ts="$(git -C "$root" log -1 --format=%ct "$br" 2>/dev/null)"
    [[ -n "$ts" ]] && age=$(( $(date -u +%s) - ts ))
    printf '%s\t%s\t%s\t%s\n' "$br" "$merged" "$dirty" "$age"
  done
}

gate_repolist() { # basenames the gate could have logged rows under for THIS repo:
  # the main checkout, the caller's checkout, AND every kit worktree —
  # gate.sh logs basename(TOP), and "TOP" is whichever checkout the gate
  # ran in. Gating from .worktrees/foo logs repo:"foo"; without the lane
  # names in the set, a lane gated from its own worktree shows rounds 0/3
  # forever and the Law-11 fork can never fire.
  local root mainpath wt mb rb names=""
  root="$(repo_root)"
  mainpath="$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)"
  mb="$(basename "${mainpath:-$root}")"; rb="$(basename "$root")"
  names="$mb"
  [[ "$rb" != "$mb" ]] && names="$names,$rb"
  while IFS= read -r wt; do
    [[ -z "$wt" || "$wt" == "$mainpath" ]] && continue
    names="$names,$(basename "$wt")"
  done < <(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  printf '%s\n' "$names"
}

# ── the board: gate-log + worktree facts per lane ───────────────────────────
# Machine lines (consumers filter): LANE\t<br|pr#N>\t<state>\t<rounds>\t<cap>\t<age> ·
# BLOCKER\t<msg> · ACTIVE\t<n>
# PR-mode rows (target pr#N — sweeps, PR re-gates) render as their own lanes
# when they are RECENT (last row newer than STALL_HI); the append-only log
# otherwise turns every merged PR into a permanent false blocker. PR rows
# never count into ACTIVE (a worktree lane and its PR are the same work).
# The Law-11 fork is a STUCK-loop signal, not a round counter: it fires only
# when rounds >= cap AND the newest verdict is REVISE AND that verdict is
# recent. A lane whose last gate said APPROVED needs a merge, not a fork —
# and reused branch names must not inherit a dead loop's escalation.
lanes_board() {
  local root repolist br merged dirty age r r_win ts res st age_s active=0 pr_t pr_r pr_ts pr_res pr_age
  root="$(repo_root)"; repolist="$(gate_repolist)"
  # the fork decision window — same cutoff the PR path filters by
  local pr_cutoff
  pr_cutoff="$(STALL_HI="$STALL_HI" python3 -c "
import datetime, os
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=float(os.environ.get('STALL_HI', '259200')))).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  while IFS="$(printf '\t')" read -r br merged dirty age; do
    [[ -z "$br" ]] && continue
    IFS="$(printf '\t')" read -r r ts res <<< "$(rounds_for "$GATE_LOG" "branch:$br" "$repolist")"
    st="$(lane_state "$ts" "$res" "$merged" "$dirty" "$age" "$r" "$GATE_ROUND_CAP")"
    if [[ "$st" == done* ]]; then
      printf 'LANE\t%s\t%s\t%s\t%s\t%s\n' "$br" "$st" "$r" "$GATE_ROUND_CAP" "—"
      continue
    fi
    active=$(( active + 1 ))   # dormant lanes count: unfinished work occupying a lane is WIP by definition
    age_s="never"
    [[ -n "$ts" && "$ts" != "-" ]] && age_s="$(fmt_age "$(age_seconds_of "$ts")") ago"
    printf 'LANE\t%s\t%s\t%s\t%s\t%s\n' "$br" "$st" "$r" "$GATE_ROUND_CAP" "$age_s"
    # fork decision counts only ROUNDS IN THE WINDOW — all-time rounds would
    # let a reused branch name inherit a dead loop's escalation
    r_win="$(rounds_for "$GATE_LOG" "branch:$br" "$repolist" "$pr_cutoff" | cut -f1)"
    pr_age="999999999"
    [[ -n "$ts" && "$ts" != "-" ]] && pr_age="$(age_seconds_of "$ts")"
    if [[ "${r_win:-0}" -ge "$GATE_ROUND_CAP" && "$res" == *REVISE* && "$pr_age" != "?" && "$pr_age" -lt "$STALL_HI" ]]; then
      printf 'BLOCKER\tFORK NEEDED (Law 11): lane %s hit %s gate rounds (cap %s), still REVISE — continue / park / pivot is the PO call (GATE_FORCE=1 overrides consciously)\n' "$br" "$r_win" "$GATE_ROUND_CAP"
    fi
  done < <(lane_facts)
  # PR-mode rows: no worktree facts exist for them offline — merged/dirty are
  # unknown and deliberately not guessed. Rows older than STALL_HI are
  # history and leave the board entirely.
  while IFS="$(printf '\t')" read -r pr_t pr_r pr_ts pr_res; do
    st="$(lane_state "$pr_ts" "$pr_res" 0 0 "?" "$pr_r" "$GATE_ROUND_CAP")"
    age_s="$(fmt_age "$(age_seconds_of "$pr_ts")") ago"
    printf 'LANE\t%s\t%s\t%s\t%s\t%s\n' "$pr_t" "$st" "$pr_r" "$GATE_ROUND_CAP" "$age_s"
    if [[ "$pr_r" -ge "$GATE_ROUND_CAP" && "$pr_res" == *REVISE* ]]; then
      printf 'BLOCKER\tFORK NEEDED (Law 11): %s hit %s gate rounds (cap %s), still REVISE — continue / park / pivot is the PO call (GATE_FORCE=1 overrides consciously)\n' "$pr_t" "$pr_r" "$GATE_ROUND_CAP"
    fi
  done < <(python3 - "$GATE_LOG" "$repolist" "$pr_cutoff" <<'PY'
import json, os, sys
log, repolist, cutoff = sys.argv[1], [x for x in sys.argv[2].split(",") if x], sys.argv[3]
rows = {}
if log and os.path.isfile(log):
    for line in open(log, encoding="utf-8", errors="replace"):
        try: r = json.loads(line)
        except Exception: continue
        t = r.get("target") or ""
        if not t.startswith("pr#"): continue
        if repolist and (r.get("repo") or "") not in repolist: continue
        ts2 = r.get("ts") or ""
        if ts2 < cutoff: continue   # history: a merged/closed PR must not haunt every future standup
        n, ts, res = rows.get(t, (0, "-", "-"))
        n += 1
        if ts2 >= (ts if ts != "-" else ""):
            ts, res = (ts2 if ts2 else "-"), (r.get("result") or "-")
        rows[t] = (n, ts, res)
for t in sorted(rows):
    n, ts, res = rows[t]
    print(f"{t}\t{n}\t{ts}\t{res}")
PY
)
  printf 'ACTIVE\t%s\n' "$active"
}

render_lanes() { grep '^LANE' | awk -F'\t' '{ printf "  • lane %s: %s · rounds %s/%s · last %s\n", $2, $3, $4, $5, $6 }'; }

# ── sprint new ──────────────────────────────────────────────────────────────
sprint_new() {
  local days="$SPRINT_DAYS" lanes="$SPRINT_LANES" rounds="$SPRINT_ROUNDS" id="" dir root file opens closes open
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)   [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "scrum.sh: --days needs a nonneg integer" >&2; return 2; }; days="$2"; shift 2 ;;
      --lanes)  [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "scrum.sh: --lanes needs a nonneg integer" >&2; return 2; }; lanes="$2"; shift 2 ;;
      --rounds) [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "scrum.sh: --rounds needs a nonneg integer" >&2; return 2; }; rounds="$2"; shift 2 ;;
      --id)     [[ "${2:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "scrum.sh: --id charset: letters/digits/dot/underscore/dash" >&2; return 2; }; id="$2"; shift 2 ;;
      *) echo "scrum.sh: unknown sprint-new flag '$1'" >&2; return 2 ;;
    esac
  done
  root="$(repo_root)"
  dir="$(sprints_dir)"   # anchored at the MAIN checkout — from inside a worktree, sprints/ exists only there
  mkdir -p "$dir" || return 1
  [[ -z "$id" ]] && id="$(next_sprint_id)"
  file="$dir/$id.md"
  if [[ -e "$file" ]]; then echo "scrum.sh: sprint exists: $file" >&2; return 1; fi
  # refuse on ONE open sprint — and on two (already-broken state must not
  # gain a third; find_open_sprint alone can't tell "none" from "two")
  local nopen=0
  if ls "$dir"/*.md >/dev/null 2>&1; then
    nopen="$(grep -lE '^Status:\s*open\b' "$dir"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if [[ "$nopen" -gt 0 ]]; then
    echo "scrum.sh: $nopen open sprint(s) already exist — one open sprint at a time; close it first (see: tf sprint status)" >&2
    return 1
  fi
  opens="$(date -u +%F)"
  closes="$(python3 - "$opens" "$days" <<'PY'
import datetime, sys
print((datetime.date.fromisoformat(sys.argv[1]) + datetime.timedelta(days=int(sys.argv[2]))).isoformat())
PY
)"
  cat > "$file" <<EOF
# Sprint $id — TODO: one-sentence goal

Status: open · opened: $opens · closes: $closes
Capacity: lanes: $lanes · rounds: $rounds

## In scope
<!-- one checkbox per task; optional join tag (lane: <worktree-name>); optional (acceptance: <criteria>) -->
- [ ] TODO first task (acceptance: how we know it is done)

## Out of scope
<!-- explicit no's; anything written here is a decision, not a wish -->

## Carried
<!-- carried in from earlier sprints — the PO promotes items to In scope at planning; 2+ carries auto-flags -->

## Review
<!-- filled by sprint close: shipped vs goal, velocity block -->
EOF
  # carry-forward: the latest closed sprint's Carried items travel into the
  # new sprint's backlog section — work is never silently dropped between
  # sprints, and the carried-2+ PO flag can actually trigger. "Latest" is
  # the file's own closes: date (id as tiebreaker) — never mtimes, which
  # lie after a late PO edit of an older review stub and after any clone.
  local prev="" f
  prev="$(python3 - "$dir" <<'PY'
import glob, os, re, sys
best = None
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.md"))):
    try:
        txt = open(f, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    m = re.search(r"(?m)^Status:\s*closed\b", txt)
    if not m: continue
    d = re.search(r"closes:\s*(\d{4}-\d{2}-\d{2})", txt)
    key = (d.group(1) if d else "", len(os.path.basename(f)), os.path.basename(f))
    if best is None or key > best[0]:
        best = (key, f)
print(best[1] if best else "")
PY
)"
  if [[ -n "$prev" ]]; then
    python3 - "$prev" "$file" <<'PY'
import os, re, sys
prev, new = sys.argv[1], sys.argv[2]
txt = open(new, encoding="utf-8", errors="replace").read()
items, section = [], None
for ln in open(prev, encoding="utf-8", errors="replace").read().splitlines():
    if ln.startswith("## "):
        section = ln[3:].strip().lower(); continue
    if section == "carried" and ln.startswith("- "):
        items.append(ln.rstrip())
if items:
    block = "\n".join(items)
    if re.search(r"(?m)^## Carried\b", txt):
        txt = re.sub(r"(?m)^(## Carried\b.*)$", lambda m: m.group(1) + "\n" + block, txt, count=1)
    else:
        txt = txt + "\n## Carried\n" + block + "\n"
    tmp = new + ".tmp"
    open(tmp, "w", encoding="utf-8").write(txt + ("" if txt.endswith("\n") else "\n"))
    os.replace(tmp, new)
    print(f"sprint: carried {len(items)} item(s) forward from {os.path.basename(prev)}")
PY
  fi
  scrub < "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  echo "sprint: created $file"
  echo "sprint: closes $closes · lanes $lanes · rounds $rounds · fill the goal and scope, then: tf sprint validate"
  return 0
}

# ── sprint validate ─────────────────────────────────────────────────────────
sprint_validate() {
  local file="${1:-}" out
  [[ -n "$file" ]] || { file="$(find_open_sprint)" || return 1; }
  [[ -f "$file" ]] || { echo "scrum.sh: no such sprint file: $file" >&2; return 2; }
  out="$(parse_sprint "$file")" || return 1
  # structural parse passed; now the honesty checks a parser can make
  # (scoped to ## In scope — a checkbox under Out of scope proves nothing;
  # POSIX classes only — awk has no \S)
  if ! awk '/^## /{s=tolower(substr($0,4))} s=="in scope" && /^- \[[x ]\] [^ ]/{found=1} END{exit !found}' "$file"; then
    echo "sprint: no in-scope items — an empty sprint is not a sprint" >&2; return 1
  fi
  if grep -qiE '^# Sprint .*TODO' "$file"; then echo "sprint: goal is still TODO" >&2; return 1; fi
  if grep -qE '^- \[ \] TODO' "$file"; then echo "sprint: placeholder scope item still present" >&2; return 1; fi
  if grep -qE '\(carried:\s*([2-9]|[0-9]{2})\)' "$file"; then
    echo "sprint: ⚠ an item has been carried 2+ times — flag it to the PO in the next standup (it was sprint-sized wrong)"
  fi
  echo "sprint: $file is structurally valid"
  printf '%s\n' "$out" | awk -F'\t' '{ if ($1=="item" && $2=="0") n++; if ($1=="carried") c++ } END { printf "sprint: %d open items · %d carried\n", n+0, c+0 }'
}

# ── sprint status ───────────────────────────────────────────────────────────
sprint_status() {
  local file="${1:-}" closes left
  [[ -n "$file" ]] || { file="$(find_open_sprint)" || return 1; }
  [[ -f "$file" ]] || { echo "scrum.sh: no such sprint file: $file" >&2; return 2; }
  parse_sprint "$file" >/dev/null || return 1
  closes="$(parse_sprint "$file" | awk -F'\t' '$1=="closes"{print $2}')"
  {
    echo "# $(head -1 "$file" | sed 's/^# //')"
    grep -E '^Status:' "$file"
    echo ""
    echo "## Sprint items"
    grep -E '^- \[' "$file" | sed 's/^/  /'
    echo ""
    echo "## Lanes (gate log + worktrees, offline tier)"
    local board
    board="$(lanes_board)"
    if grep -q '^LANE' <<< "$board"; then render_lanes <<< "$board"; else echo "  (no kit worktrees yet — lanes appear when tf wt <name> runs)"; fi
    echo ""
    left="$(days_left "$closes")"
    if [[ "$left" == "?" ]]; then echo "closes: $closes"
    elif [[ "$left" -lt 0 ]]; then echo "⚠ sprint OVERDUE by $(( -left ))d (closes $closes) — close or re-scope"
    else echo "closes $closes · ${left}d left"; fi
  } | scrub
}

# ── sprint close ────────────────────────────────────────────────────────────
sprint_close() {
  local file="${1:-}"
  [[ -n "$file" ]] || { file="$(find_open_sprint)" || return 1; }
  [[ -f "$file" ]] || { echo "scrum.sh: no such sprint file: $file" >&2; return 2; }
  parse_sprint "$file" >/dev/null || { echo "sprint: fix the structure before closing (tf sprint validate)" >&2; return 1; }
  python3 - "$file" "$GATE_LOG" "$(gate_repolist)" <<'PY'
import datetime, json, os, re, sys
file, log = sys.argv[1], sys.argv[2]
repos = [r for r in sys.argv[3].split(",") if r]
txt = open(file, encoding="utf-8", errors="replace").read()
# carry: unchecked in-scope items move under ## Carried, counter increments
carried_moved = []
lines, section, out = txt.splitlines(), None, []
for ln in lines:
    if ln.startswith("## "):
        section = ln[3:].strip().lower()
        out.append(ln); continue
    if section == "in scope":
        m = re.match(r"^- \[ \] (.*)$", ln)
        if m:
            mm = re.match(r"^(.*?)(?:\s*\(carried:\s*(\d+)\))?\s*$", m.group(1))
            # an IN-SCOPE item has been carried ZERO times so far — the first
            # carry writes (carried: 1); 2+ is the PO-flag threshold
            n = int(mm.group(2) or "0")
            carried_moved.append(f"- {mm.group(1)} (carried: {n + 1})")
            continue
        m2 = re.match(r"^- \[x\] (.*)$", ln)
        if m2:
            out.append(f"- [x] {m2.group(1)}"); continue
    out.append(ln)
txt = "\n".join(out)
if carried_moved:
    block = "\n".join(carried_moved)
    if re.search(r"(?m)^## Carried\b", txt):
        txt = re.sub(r"(?m)^(## Carried\b.*)$", lambda mm2: mm2.group(1) + "\n" + block, txt, count=1)
    else:
        txt = txt + "\n## Carried\n" + block + "\n"
# velocity: offline gate-log facts inside the sprint window, this repo only
opened = closes = ""
m = re.search(r"opened:\s*(\d{4}-\d{2}-\d{2})", txt)
if m: opened = m.group(1)
m = re.search(r"closes:\s*(\d{4}-\d{2}-\d{2})", txt)
if m: closes = m.group(1)
approved = revised = gate_rounds = 0
if opened and os.path.isfile(log):
    for line in open(log, encoding="utf-8", errors="replace"):
        try: r = json.loads(line)
        except Exception: continue
        ts = (r.get("ts") or "")[:10]
        if not (opened <= ts <= (closes or "9999-99-99")): continue
        if repos and (r.get("repo") or "") not in repos: continue
        res = r.get("result") or ""
        if "APPROVED" in res: approved += 1
        elif "REVISE" in res: revised += 1
        gate_rounds += 1
# anchored to the Status line, not any prose that might contain the phrase
txt, n_sub = re.subn(r"(?m)^Status: open\b", "Status: closed", txt, count=1)
if n_sub == 0:
    print("sprint: no 'Status: open' line found — nothing to close", file=sys.stderr)
    sys.exit(1)
review_note = (f"Closed {datetime.date.today().isoformat()}. Offline velocity (gate log, this repo, sprint window): "
               f"{approved} APPROVED · {revised} REVISE · {gate_rounds} gate rounds total. "
               f"{len(carried_moved)} item(s) carried. Merge truth lives with gh/merge-qa — this stub is the offline tier.")
if re.search(r"(?m)^## Review\b", txt):
    txt = re.sub(r"(?m)^(## Review\b.*)$", lambda mm2: mm2.group(1) + "\n" + review_note, txt, count=1)
else:
    txt = txt + "\n## Review\n" + review_note + "\n"
tmp = file + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write(txt + ("" if txt.endswith("\n") else "\n"))
os.replace(tmp, file)
print(f"sprint: closed {file}")
print(f"sprint: {len(carried_moved)} item(s) carried to the backlog section")
print(review_note)
PY
  if ! grep -qE '^Status:\s*closed\b' "$file"; then
    echo "sprint: close failed to flip status — refusing to claim success" >&2
    return 1
  fi
}

# ── standup ─────────────────────────────────────────────────────────────────
standup() {
  local save=1 file="" root out out_f sdir sfile bl=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-save) save=0; shift ;;
      -h|--help) usage 0 ;;
      *) if [[ -z "$file" ]]; then file="$1"; shift; else echo "scrum.sh: unexpected standup arg '$1'" >&2; return 2; fi ;;
    esac
  done
  root="$(repo_root)"
  out="$(mktemp)"; out_f="$out.f"
  # expand NOW and clear on exit — a mid-standup failure must not litter /tmp
  trap "rm -f '$out' '$out_f'" EXIT
  local filemsg=""
  if [[ -z "$file" ]]; then
    filemsg="$(find_open_sprint 2>&1)" || true   # a path means found; otherwise it's the honest error
    [[ "$filemsg" == */* && -f "$filemsg" ]] && file="$filemsg"
  fi
  {
    echo "# Standup $(date -u +%F)"
    echo ""
    if [[ -n "$file" && -f "$file" ]]; then
      head -1 "$file" | sed 's/^# /## sprint: /'
      grep -E '^Status:' "$file" | sed 's/^/  /'
    elif [[ "$filemsg" == *"two open sprints"* || "$filemsg" == *"open sprint(s)"* ]]; then
      echo "## sprint state broken"
      echo "  $filemsg"
    else
      echo "## no open sprint"
      echo "  ceremony discipline: the fleet is working without a goal on the wall — run: tf sprint new"
    fi
    echo ""
    echo "## Shipped (offline tier: APPROVED verdicts; merge truth = gh / merge-qa)"
    python3 - "$GATE_LOG" "$(gate_repolist)" "$file" <<'PY'
import json, os, re, sys
log, repos, sprint = sys.argv[1], [x for x in sys.argv[2].split(",") if x], sys.argv[3]
since = ""
if sprint and os.path.isfile(sprint):
    t = open(sprint, encoding="utf-8", errors="replace").read()
    m = re.search(r"opened:\s*(\d{4}-\d{2}-\d{2})", t)
    if m: since = m.group(1)
rows = {}
if os.path.isfile(log):
    for line in open(log, encoding="utf-8", errors="replace"):
        try: r = json.loads(line)
        except Exception: continue
        if repos and (r.get("repo") or "") not in repos: continue
        if "APPROVED" not in (r.get("result") or ""): continue
        ts = r.get("ts") or ""
        if since and ts[:10] < since: continue
        tgt = r.get("target") or "?"
        if ts >= rows.get(tgt, ""): rows[tgt] = ts
if rows:
    for tgt in sorted(rows):
        print(f"  ✓ {tgt} — APPROVED {rows[tgt][:10]}")
else:
    print("  (none in window — honest empty, not all-clear)")
PY
    echo ""
    echo "## In flight"
    local board
    board="$(lanes_board)"
    if grep -q '^LANE' <<< "$board"; then
      render_lanes <<< "$board"
    else
      echo "  (no kit worktrees yet — lanes appear when tf wt <name> runs)"
    fi
    local active
    active="$(awk -F'\t' '$1=="ACTIVE"{print $2}' <<< "$board")"
    echo "  active lanes: ${active:-0}"
    echo ""
    echo "## Blockers"
    bl=0
    while IFS= read -r msg; do echo "  ⚠ $msg"; bl=$((bl + 1)); done < <(grep '^BLOCKER' <<< "$board" | cut -f2- || true)
    if [[ -n "$file" && -f "$file" ]]; then
      local lanes
      lanes="$(parse_sprint "$file" | awk -F'\t' '$1=="lanes"{print $2}')"
      # WIP vs capacity only when the sprint parsed a lane budget — a
      # malformed file must not fabricate a breach for every active lane
      if [[ -n "$lanes" && "${active:-0}" -gt "$lanes" ]]; then
        echo "  ⚠ WIP ${active} > lanes ${lanes} — scope is ahead of capacity"
        bl=$((bl + 1))
      fi
      while IFS= read -r t; do
        echo "  ⚠ carried 2+ times (planning smell, PO call): $t"
        bl=$((bl + 1))
      done < <(grep -E '^- .*\(carried:\s*([2-9]|[0-9]{2})\)' "$file" | sed 's/^- //' || true)
      local closes left
      closes="$(parse_sprint "$file" | awk -F'\t' '$1=="closes"{print $2}')"
      left="$(days_left "$closes")"
      if [[ "$left" =~ ^-?[0-9]+$ && "$left" -lt 0 ]]; then
        echo "  ⚠ sprint overdue by $(( -left ))d — close or re-scope"
        bl=$((bl + 1))
      fi
    fi
    if [[ $bl -eq 0 ]]; then echo "  (none — verified, not assumed)"; fi
    echo ""
    echo "## Capacity"
    if [[ -n "$file" && -f "$file" ]]; then
      parse_sprint "$file" | awk -F'\t' -v cap="$GATE_ROUND_CAP" '$1=="lanes"{l=$2} $1=="rounds"{r=$2} END{printf "  lanes %s · round budget %s · per-lane gate cap %s\n", l, r, cap}'
      echo "  token burn: tf tokens (the dashboard owns burn — no second meter here)"
    else
      echo "  (no sprint — no budget to report)"
    fi
  } > "$out"
  scrub < "$out" > "$out_f"
  if [[ $save -eq 1 ]]; then
    sdir="$(sprints_dir)/standups"; mkdir -p "$sdir"
    sfile="$sdir/$(date -u +%F).md"
    cp "$out_f" "$sfile"
    echo "standup: saved $sfile" >&2
  fi
  cat "$out_f"
  rm -f "$out" "$out_f"
  trap - EXIT
}

# ── selftest: parser fixtures, no git repo required ─────────────────────────
scrum_selftest() {
  FAIL=0
  t() { if [[ "$2" == "$3" ]]; then echo "✓ $1"; else echo "✗ $1 — expected [$2] got [$3]"; FAIL=1; fi; }
  local F L out
  F="$(mktemp)"; F="$(cd "$(dirname "$F")" && pwd -P)/$(basename "$F")"
  L="$(mktemp)"; L="$(cd "$(dirname "$L")" && pwd -P)/$(basename "$L")"
  # expand NOW: at EXIT-trip time the function's locals are gone (set -u)
  trap "rm -f '$F' '$L'" EXIT

  cat > "$F" <<'EOF'
# Sprint 2026-11-A — ship the scrum pack

Status: open · opened: 2026-11-11 · closes: 2026-11-18
Capacity: lanes: 2 · rounds: 12

## In scope
- [ ] build scrum.sh (acceptance: suite green) (lane: scrum-pack)
- [x] write PRD (acceptance: mp verdict)
- [ ] second open item

## Out of scope
- retro ceremony

## Carried
- old thing (carried: 2)

## Review
EOF
  out="$(parse_sprint "$F")"
  t "parse: valid file → 0" 0 $?
  t "parse: status" "open" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="status"{print $2}')"
  t "parse: lanes" "2" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="lanes"{print $2}')"
  t "parse: open items" "2" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="item" && $2=="0"' | wc -l | tr -d ' ')"
  t "parse: carried count" "1" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="carried"' | wc -l | tr -d ' ')"
  t "parse: carried n" "2" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="carried"{print $2}')"

  printf '# Sprint x\n\nStatus: banana · opened: 2026-11-11 · closes: 2026-11-18\nCapacity: lanes: 2 · rounds: 12\n## In scope\n- [ ] a\n' > "$F"
  parse_sprint "$F" >/dev/null 2>&1; t "parse: bad status word → 1" 1 $?

  printf '# Sprint x\n\nStatus: open · opened: 2026-11-18 · closes: 2026-11-11\nCapacity: lanes: 2 · rounds: 12\n## In scope\n- [ ] a\n' > "$F"
  parse_sprint "$F" >/dev/null 2>&1; t "parse: closes before opened → 1" 1 $?

  printf '# Sprint x\n\nStatus: open · opened: 2026-11-11\n## In scope\n- [ ] a\n' > "$F"
  parse_sprint "$F" >/dev/null 2>&1; t "parse: missing closes → 1" 1 $?

  printf '# Sprint x\n\nStatus: open · opened: 2026-11-11 · closes: 2026-11-18\n## In scope\n- [ ] a\n' > "$F"
  parse_sprint "$F" >/dev/null 2>&1; t "parse: missing capacity → 1" 1 $?

  cat > "$L" <<'EOF'
{"ts":"2026-11-11T01:00:00Z","repo":"turbo-flow-claude","gh_repo":"","target":"branch:alpha","result":"GATE: REVISE","reviewer":"claude"}
{"ts":"2026-11-11T02:00:00Z","repo":"turbo-flow-claude","gh_repo":"","target":"branch:alpha","result":"GATE: APPROVED","reviewer":"claude"}
{"ts":"2026-11-11T03:00:00Z","repo":"other-clone","gh_repo":"","target":"branch:alpha","result":"GATE: REVISE","reviewer":"claude"}
{"ts":"2026-11-11T04:00:00Z","repo":"turbo-flow-claude","gh_repo":"me/other","target":"pr#7","result":"GATE: REVISE","reviewer":"claude"}
not json at all
{"ts":"2026-11-11T05:00:00Z","repo":"turbo-flow-claude","gh_repo":"","target":"branch:beta","result":"GATE: APPROVED","reviewer":"codex"}
EOF
  t "rounds: same repo+target counted" "2" "$(rounds_for "$L" "branch:alpha" "turbo-flow-claude" | cut -f1)"
  t "rounds: other clone excluded" "0" "$(rounds_for "$L" "branch:alpha" "elsewhere" | cut -f1)"
  t "rounds: pr target counted" "1" "$(rounds_for "$L" "pr#7" "turbo-flow-claude" | cut -f1)"
  t "rounds: last result wins" "GATE: APPROVED" "$(rounds_for "$L" "branch:alpha" "turbo-flow-claude" | cut -f3)"
  t "rounds: missing log → 0" "0" "$(rounds_for "/nonexistent/log" "branch:alpha" "r" | cut -f1)"

  local NOW BEFORE
  NOW="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  BEFORE="$(python3 -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=8)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  t "state: merged → done" "done (merged)" "$(lane_state "$NOW" "GATE: REVISE" 1 1 100 1 3)"
  t "state: fresh revise → gating" "gating (round 2/3)" "$(lane_state "$NOW" "GATE: REVISE" 0 1 100 2 3)"
  t "state: fresh approved → gated" "gated · PR imminent" "$(lane_state "$NOW" "GATE: APPROVED" 0 0 100 1 3)"
  t "state: old approved → awaiting-human" "awaiting-human (merge)" "$(lane_state "$BEFORE" "GATE: APPROVED" 0 0 3600 1 3)"
  t "state: old revise → stalled" "stalled" "$(lane_state "$BEFORE" "GATE: REVISE" 0 0 3600 2 3)"
  t "state: no rows dirty → building" "building (pre-gate)" "$(lane_state "" "" 0 1 "?" 0 3)"
  t "state: no rows old+clean → dormant" "dormant (no gate rows)" "$(lane_state "" "" 0 0 "999999" 0 3)"

  if [[ $FAIL -ne 0 ]]; then echo "scrum selftest: FAILURES"; exit 1; fi
  echo "scrum selftest: ALL PASS"
  return 0
}

# ── dispatch ────────────────────────────────────────────────────────────────
case "${1:-help}" in
  sprint)
    shift
    case "${1:-}" in
      new)      shift; sprint_new "$@" ;;
      validate) shift; sprint_validate "$@" ;;
      status)   shift; sprint_status "$@" ;;
      close)    shift; sprint_close "$@" ;;
      *) echo "scrum.sh: sprint subcommand? new|validate|status|close" >&2; exit 2 ;;
    esac ;;
  standup)    shift; standup "$@" ;;
  --selftest) scrum_selftest ;;
  help|-h|--help) usage 0 ;;
  *) usage 2 ;;
esac
