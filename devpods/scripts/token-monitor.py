#!/usr/bin/env python3
# token-monitor.py — live Claude Code token-count dashboard for the tmux monitor window.
# Ported from Turbo Rig's (private) tokens.py — Claude adapter lineage, simplified to
# one provider. Reads ~/.claude/projects/*/*.jsonl read-only; never writes anywhere.
#
# Usage:
#   token-monitor.py                 one-shot dashboard, 5-hour window
#   token-monitor.py --watch         live view, 5s refresh (keys: q 1 2 3)
#   token-monitor.py --since 30m    window: 30m|1h|2h|5h|today|7d
#   token-monitor.py --json          machine snapshot, no ANSI
#   token-monitor.py --selftest      fixture golden tests
#
# Env override: TOKENS_CLAUDE_ROOT (defaults ~/.claude)
# Exit codes: 0 ok · 1 usage error · 3 selftest failure

import glob
import json
import os
import select
import sys
import time
from datetime import datetime, timedelta

PROVIDER = "claude"
WINDOWS = [
    ("30m", "30 minutes (rolling)"), ("1h", "1 hour (rolling)"), ("2h", "2 hours (rolling)"),
    ("5h", "5-hour window (rolling)"), ("today", "today (local midnight)"),
    ("7d", "7-day window (rolling)"),
]
DEFAULT_WINDOW = "5h"
RETENTION = 7 * 86400  # ignore files older than 7d + 1h slack

def iso_to_epoch(s):
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=__import__("datetime").timezone.utc)
    return dt.timestamp()

def repo_label(cwd, branch):
    if not cwd:
        return "(no cwd)"
    name = os.path.basename(cwd.rstrip("/")) or cwd
    return f"{name}@{branch}" if branch else name

def fmt_tokens(n):
    for unit, div in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if n >= div:
            return f"{n / div:.2f}{unit}"
    return str(n)

class Monitor:
    """Incremental scanner with in-memory offsets — live refreshes only read new bytes."""

    def __init__(self, root=None):
        self.root = root or os.environ.get("TOKENS_CLAUDE_ROOT") or os.path.expanduser("~/.claude")
        self.offsets = {}   # path -> (inode, mtime, size, byte offset)
        self.dedup = {}     # (requestId, message.id) -> row (fullest usage wins)

    def collect(self, now):
        pattern = os.path.join(self.root, "projects", "*", "*.jsonl")
        files = sorted(glob.glob(pattern))
        if not files and not os.path.isdir(self.root):
            return []
        cutoff = now - RETENTION - 3600
        for path in files:
            try:
                st = os.stat(path)
            except OSError:
                continue
            if st.st_mtime < cutoff:
                continue
            prev = self.offsets.get(path)
            if prev and prev[1] == st.st_mtime and prev[2] == st.st_size:
                continue  # unchanged since last pass
            # reset on inode change (rotation/rewrite) or shrink (truncate);
            # same-inode regrow past the old offset is indistinguishable from
            # append without reading — accept with this comment
            if not prev or prev[0] != st.st_ino or st.st_size < prev[2]:
                offset = 0
            else:
                offset = prev[3]
            try:
                with open(path, "rb") as fh:
                    fh.seek(offset)
                    chunk = fh.read()
            except OSError:
                continue
            # only consume complete lines — a torn tail stays for the next pass
            last_nl = chunk.rfind(b"\n")
            if last_nl == -1:
                continue  # no complete line yet
            body, new_off = chunk[:last_nl], offset + last_nl + 1
            self.offsets[path] = (st.st_ino, st.st_mtime, st.st_size, new_off)
            for line in body.split(b"\n"):
                if b'"assistant"' not in line:
                    continue
                try:
                    j = json.loads(line)
                except ValueError:
                    continue
                if j.get("type") != "assistant":
                    continue
                msg = j.get("message") or {}
                if msg.get("model") == "<synthetic>" or j.get("isApiErrorMessage") or msg.get("id") is None:
                    continue
                u = msg.get("usage") or {}
                try:
                    ts = iso_to_epoch(j["timestamp"])
                except (KeyError, ValueError, TypeError, OverflowError, OSError):
                    continue
                key = (j.get("requestId"), msg.get("id"))
                row = {
                    "ts": ts, "model": msg.get("model") or "?",
                    "tin": u.get("input_tokens") or 0,
                    "cc": u.get("cache_creation_input_tokens") or 0,
                    "cr": u.get("cache_read_input_tokens") or 0,
                    "tout": u.get("output_tokens") or 0,
                    "proj": repo_label(j.get("cwd"), j.get("gitBranch")),
                }
                row["total"] = row["tin"] + row["cc"] + row["cr"] + row["tout"]
                # fullest usage wins; on a tie keep the EARLIEST ts (original request
                # time) so replays don't re-attribute old burn to a new window
                prevrow = self.dedup.get(key)
                if (prevrow is None or row["total"] > prevrow["total"]
                        or (row["total"] == prevrow["total"] and row["ts"] < prevrow["ts"])):
                    self.dedup[key] = row
        # evict WIDER than the widest renderable window (7d + 1h) so a
        # long-running --watch never under-reports vs a fresh process
        horizon = now - RETENTION - 3600
        for k in [k for k, r in self.dedup.items() if r["ts"] < horizon]:
            del self.dedup[k]
        return list(self.dedup.values())

def window_bounds(name, now):
    n = now
    lt = datetime.fromtimestamp(n)
    if name == "today":
        start = datetime(lt.year, lt.month, lt.day).timestamp()
    else:
        qty = int(name[:-1])
        unit_s = {"m": 60, "h": 3600, "d": 86400}[name[-1]]
        start = n - qty * unit_s
    return start, n

def aggregate(rows, start, end):
    per_model, per_proj = {}, {}
    for r in rows:
        if not (start <= r["ts"] <= end):
            continue
        m = per_model.setdefault(r["model"], {"req": 0, "tin": 0, "cc": 0, "cr": 0, "tout": 0})
        m["req"] += 1
        for f in ("tin", "cc", "cr", "tout"):
            m[f] += r[f]
        p = per_proj.setdefault(r["proj"], {"req": 0, "total": 0})
        p["req"] += 1
        p["total"] += r["total"]
    return per_model, per_proj

C = {"dim": "\x1b[2m", "teal": "\x1b[36m", "green": "\x1b[32m", "amber": "\x1b[33m",
     "white": "\x1b[97m", "reset": "\x1b[0m", "bold": "\x1b[1m"}

def render(mon, win, now, ansi=True):
    c = C if ansi else {k: "" for k in C}
    start, end = window_bounds(win, now)
    per_model, per_proj = aggregate(mon.collect(now), start, end)
    label = dict(WINDOWS)[win]
    L = []
    L.append(f"{c['bold']}{c['teal']}CLAUDE TOKEN MONITOR{c['reset']} {c['dim']}· {label}{c['reset']}")
    L.append(f"{c['dim']}updated {datetime.fromtimestamp(now):%H:%M:%S} · {PROVIDER} adapter · q quit · 1/2/3 window{c['reset']}")
    if not per_model:
        L.append(f"{c['amber']}no usage in this window — run a Claude session and refresh{c['reset']}")
        return "\n".join(L)
    grand = sum(m["tin"] + m["cc"] + m["cr"] + m["tout"] for m in per_model.values())
    total_out = sum(m["tout"] for m in per_model.values())
    L.append("")
    for model, m in sorted(per_model.items(), key=lambda kv: -sum(v for k, v in kv[1].items() if k != "req")):
        tot = m["tin"] + m["cc"] + m["cr"] + m["tout"]
        bar = "█" * max(1, int(28 * tot / max(grand, 1)))
        L.append(f"{c['white']}{model:<28}{c['reset']}{c['green']}{bar:<28}{c['reset']}{c['bold']}{fmt_tokens(tot):>9}{c['reset']} {c['dim']}({m['req']} req){c['reset']}")
        L.append(f"{c['dim']}  in {fmt_tokens(m['tin'])} · cache+{fmt_tokens(m['cc'])} · cache-read {fmt_tokens(m['cr'])} · out {fmt_tokens(m['tout'])}{c['reset']}")
    L.append("")
    L.append(f"{c['bold']}TOTAL {fmt_tokens(grand)}{c['reset']} {c['dim']}· output {fmt_tokens(total_out)} · {len(per_proj)} project(s){c['reset']}")
    for proj, p in sorted(per_proj.items(), key=lambda kv: -kv[1]["total"])[:5]:
        L.append(f"  {c['teal']}{proj:<34}{c['reset']}{fmt_tokens(p['total']):>10} {c['dim']}({p['req']} req){c['reset']}")
    return "\n".join(L)

def watch(mon, win, refresh):
    import termios, tty
    fd = sys.stdin.fileno()
    try:
        old = termios.tcgetattr(fd)
    except termios.error:
        print(render(mon, win, time.time()) + "\n(non-tty: one-shot render — --watch needs a terminal)")
        return
    try:
        tty.setcbreak(fd)
        while True:
            sys.stdout.write("\x1b[2J\x1b[H")
            sys.stdout.write(render(mon, win, time.time()) + "\n")
            sys.stdout.flush()
            r, _, _ = select.select([fd], [], [], refresh)
            if r:
                ch = sys.stdin.read(1)
                if ch in ("q", "\x03"):
                    return
                # window keys: 1→30m 2→1h 3→5h (simple, memorable)
                win = {"1": "30m", "2": "1h", "3": "5h"}.get(ch, win)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

def selftest():
    import tempfile
    tmp = tempfile.mkdtemp()
    proj = os.path.join(tmp, "projects", "p1")
    os.makedirs(proj)
    now = time.time()
    def env(ts_off, model, tin, tout, rid, mid):
        ts = datetime.fromtimestamp(now - ts_off, tz=__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        return json.dumps({"type": "assistant", "timestamp": ts, "requestId": rid,
                           "cwd": "/x/projA", "gitBranch": "main",
                           "message": {"id": mid, "model": model,
                                       "usage": {"input_tokens": tin, "output_tokens": tout,
                                                 "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}}})
    with open(os.path.join(proj, "s.jsonl"), "w") as f:
        f.write(env(600, "claude-opus", 1000, 500, "r1", "m1") + "\n")
        f.write(env(600, "claude-opus", 1000, 500, "r1", "m1") + "\n")   # dup: fullest wins
        f.write(env(7200, "claude-sonnet", 200, 100, "r2", "m2") + "\n")  # outside 1h
    mon = Monitor(root=tmp)
    rows = mon.collect(now)
    assert len(rows) == 2, rows
    start, end = window_bounds("1h", now)
    pm, _ = aggregate(rows, start, end)
    assert "claude-opus" in pm and "claude-sonnet" not in pm, pm
    assert pm["claude-opus"]["req"] == 1, pm  # deduped
    txt = render(mon, "7d", now, ansi=False)
    assert "claude-sonnet" in txt and "TOTAL" in txt
    # torn tail: ignored while incomplete, counted once completed (own monitor)
    torn = os.path.join(proj, "torn.jsonl")
    with open(torn, "w") as f:
        f.write(env(300, "claude-opus", 10, 5, "r9", "m9")[:40])
    mon2 = Monitor(root=tmp)
    assert len(mon2.collect(now)) == 2
    with open(torn, "w") as f:
        f.write(env(300, "claude-opus", 10, 5, "r9", "m9") + "\n")
    assert len(mon2.collect(now)) == 3
    # truncate+rewrite through a WARM monitor (has offsets): shrink must reset
    with open(os.path.join(proj, "s.jsonl"), "w") as f:
        f.write(env(120, "claude-haiku", 50, 20, "r8", "m8") + "\n")
    rows3 = mon2.collect(now)   # same monitor — exercises the reset branch
    models3 = {r["model"] for r in rows3}
    # reset makes the post-truncate content readable (haiku present); sonnet
    # correctly LINGERS — dedup retains history until the 7d+1h eviction horizon
    assert "claude-haiku" in models3 and "claude-sonnet" in models3, models3
    # cross-file rewrite merge: same (requestId, message.id), fullest usage wins
    p2 = os.path.join(tmp, "projects", "p2"); os.makedirs(p2)
    def envelope(rid, mid, tin, tout):
        return env(400, "claude-opus", tin, tout, rid, mid)
    with open(os.path.join(p2, "a.jsonl"), "w") as f:
        f.write(envelope("rr", "mm", 100, 50) + "\n")
    with open(os.path.join(p2, "b.jsonl"), "w") as f:
        f.write(envelope("rr", "mm", 500, 250) + "\n")   # cumulative rewrite
    mon5 = Monitor(root=tmp)
    r5 = [r for r in mon5.collect(now) if r["proj"] == "projA" or r["tin"] in (500,)]
    rows5 = mon5.collect.__self__ if False else None
    all5 = Monitor(root=tmp); _ = None
    m5 = Monitor(root=tmp)
    got = [r for r in m5.collect(now) if (r["tin"], r["tout"]) in ((100, 50), (500, 250))]
    assert len(got) == 1 and got[0]["tin"] == 500, got  # merged, fullest won
    # parse_args: every documented form + every rejection path
    a = parse_args(["--watch", "5"])
    assert a["watch"] and a["refresh"] == 5.0 and not a["errors"], a
    a = parse_args(["--since=30m"])
    assert a["win"] == "30m" and not a["errors"], a
    a = parse_args(["--since", "1h", "--json"])
    assert a["win"] == "1h" and a["json"], a
    assert parse_args(["--since"])["errors"], "missing value must error"
    assert parse_args(["--bogus"])["errors"], "unknown flag must error"
    assert parse_args(["stray"])["errors"], "stray positional must error"
    # eviction: rows older than 7d+1h evicted; boundary rows kept
    mon4 = Monitor(root=tmp)
    mon4.dedup[("old", "x")] = {"ts": now - RETENTION - 7200, "model": "m", "tin": 0, "cc": 0, "cr": 0, "tout": 0, "total": 0, "proj": "p"}
    mon4.dedup[("edge", "y")] = {"ts": now - RETENTION, "model": "m", "tin": 0, "cc": 0, "cr": 0, "tout": 0, "total": 0, "proj": "p"}
    mon4.collect(now)
    assert ("old", "x") not in mon4.dedup and ("edge", "y") in mon4.dedup, mon4.dedup.keys()
    print("self-test: ALL PASS")
    return 0

def parse_args(argv):
    """accepts --since X, --since=X, --watch, --watch N, --watch=N, --json, --color[=always], --selftest"""
    out = {"watch": False, "json": False, "selftest": False, "color": False,
           "errors": None, "win": DEFAULT_WINDOW, "refresh": 5.0}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--selftest":
            out["selftest"] = True
        elif a == "--watch":
            out["watch"] = True
            if i + 1 < len(argv) and argv[i + 1].replace(".", "", 1).isdigit():
                i += 1
                out["refresh"] = float(argv[i])
        elif a.startswith("--watch="):
            out["watch"] = True
            try:
                out["refresh"] = float(a.split("=", 1)[1])
            except ValueError:
                pass
        elif a == "--since":
            if i + 1 >= len(argv):
                out["errors"] = "--since needs a value (30m|1h|2h|5h|today|7d)"
            else:
                i += 1
                out["win"] = argv[i]
        elif not a.startswith("-"):
            out["errors"] = f"unexpected argument: {a}"
        elif a.startswith("--since="):
            out["win"] = a.split("=", 1)[1]
        elif a == "--json":
            out["json"] = True
        elif a == "--color" or a == "--color=always":
            out["color"] = True
        elif a.startswith("-"):
            out["errors"] = f"unknown flag: {a}"
        i += 1
    return out

def main(argv):
    args = parse_args(argv)
    if args["selftest"]:
        try:
            return selftest()
        except AssertionError as e:
            print(f"self-test: FAILURES — {e}", file=sys.stderr)
            return 3
    if args["errors"]:
        print(args["errors"], file=sys.stderr)
        return 1
    win = args["win"]
    refresh = args["refresh"]
    if win not in dict(WINDOWS):
        print(f"unknown window '{win}' — use one of: " + ", ".join(w for w, _ in WINDOWS), file=sys.stderr)
        return 1
    mon = Monitor()
    if args["watch"]:
        try:
            watch(mon, win, refresh)
            return 0
        except KeyboardInterrupt:
            return 0
        except ImportError:
            print("--watch needs a tty with termios (run inside tmux/terminal)", file=sys.stderr)
            return 1
    if args["json"]:
        now = time.time()
        start, end = window_bounds(win, now)
        per_model, per_proj = aggregate(mon.collect(now), start, end)
        print(json.dumps({"window": win, "models": per_model, "projects": per_proj,
                          "generated": datetime.fromtimestamp(now).isoformat()}, indent=2))
        return 0
    print(render(mon, win, time.time(), ansi=args["color"] or sys.stdout.isatty()))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
