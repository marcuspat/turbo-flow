#!/usr/bin/env python3
# tokens.py — real-time token usage & plan-utilization dashboard across your harnesses.
# First open-core drop from Turbo Rig (the private rig's scripts/tokens.py, matured
# since 2026-09-20; replaces the Claude-only token-monitor.py removed with the v4 era).
#
# Reads (read-only; this tool never writes anywhere):
#   zcode  ~/.zcode/cli/db/db.sqlite        table model_usage (per-request, epoch-ms UTC)
#   claude ~/.claude/projects/*/*.jsonl     assistant-message usage envelopes
#   codex  ~/.codex/sessions/*/*/*.jsonl    token_count events (+ plan rate_limits)
#   gate   ~/.local/state/rig-lite/gate-log.jsonl   review burn (ts is LOCAL time) —
#         the kit gate's log; same path gate.sh writes and GATE_LOG overrides
#   quota  Anthropic oauth usage endpoint   via macOS Keychain (gate.sh pattern)
#
# Usage:
#   rig-lite/tokens.py                     one-shot dashboard, 5-hour window
#   rig-lite/tokens.py --watch             live view, 2s refresh  (keys: q 1 2 3 J)
#   rig-lite/tokens.py --watch 5           live view, 5s refresh
#   rig-lite/tokens.py --since 30m        window: 30m|1h|2h|5h|today|7d|30d (24h=today)
#   rig-lite/tokens.py --json              machine snapshot, no ANSI
#   rig-lite/tokens.py --no-quota          skip Keychain + network entirely
#   rig-lite/tokens.py --color always      force ANSI color (e.g. piping into less -R)
#   rig-lite/tokens.py --cap zcode=2e9      manual token cap -> utilization bar (e.g. GLM plan)
#   rig-lite/tokens.py --selftest          fixture golden tests
#
# Path overrides (debugging): TOKENS_ZCODE_DB, TOKENS_CLAUDE_ROOT, TOKENS_CODEX_ROOT,
#   TOKENS_GATE_LOG (honors the gate's own GATE_LOG too).
#
# Exit codes: 0 ok · 1 usage error · 2 rendered but >=1 provider degraded · 3 selftest failure.
#
# Non-goals (from the original spec): no cost tables, no daemon, no
# config-file plugins, no history DB, no alerting. New provider = new adapter here.

import argparse
import glob
import json
import math
import os
import select
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.parse
from datetime import datetime, timedelta, timezone

PROVIDERS = ("zcode", "claude", "codex", "gate")
CAP_PROVIDERS = ("zcode", "claude", "codex")  # cap bars render on model panels only
# Providers whose `tin` is TOTAL prompt tokens (cache reads already included,
# OpenAI-style convention) vs fresh-miss-only (Anthropic reports reads
# separately from usage.input_tokens). Verified 09-25 empirically: zcode
# cr<=tin in 34,603/34,603 calls (hard ratio ceiling 1.000); codex
# total_tokens == input+output exactly in 55/55 calls (cached is a subset of
# input). Hit rate for these is cr/tin, not cr/(cr+tin).
INCLUSIVE_INPUT = frozenset({"zcode", "codex"})
WINDOWS = [
    ("30m", "30 minutes (rolling)"), ("1h", "1 hour (rolling)"), ("2h", "2 hours (rolling)"),
    ("5h", "5-hour window (rolling)"), ("today", "today (local midnight)"),
    ("7d", "7-day window (rolling)"), ("30d", "30-day window (rolling)"),
]
RETENTION = 30 * 86400  # widest renderable window bounds every adapter's scan
QUOTA_URL = "https://api.anthropic.com/api/oauth/usage"
DAY = 86400

# ---------- small helpers ----------

def num(x):
    try:
        return float(x or 0)
    except (TypeError, ValueError):
        return 0.0


def _f(x):
    """Safe float for network/session-derived values: None unless cleanly numeric."""
    try:
        v = float(x)
    except (TypeError, ValueError):
        return None
    return None if v != v else v  # NaN -> None


def fmt_tok(n):
    n = num(n)
    if n >= 1e9:
        return f"{n / 1e9:.2f}B"
    if n >= 1e6:
        return f"{n / 1e6:.1f}M"
    if n >= 1e3:
        return f"{n / 1e3:.1f}K"
    return str(int(n))


def fmt_dur(sec):
    sec = max(0, int(sec))
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m{sec % 60:02d}s"
    if sec < 48 * 3600:
        return f"{sec // 3600}h{(sec % 3600) // 60:02d}m"
    return f"{sec // 86400}d{(sec % 86400) // 3600:02d}h"


def fmt_window(minutes):
    """Rate-limit window_minutes -> honest label. Only names the provider itself defines."""
    m = _f(minutes)
    if m is None or m <= 0:
        return None
    names = {60: "hourly", 300: "5-hour", 1440: "daily", 10080: "weekly", 43200: "30-day"}
    if m in names:
        return names[m]
    if m % 1440 == 0:
        return f"{int(m // 1440)}-day"
    if m % 60 == 0:
        return f"{int(m // 60)}h"
    return f"{int(m)}m"


def iso_to_epoch(s):
    """ISO-8601 (Claude/Codex, 'Z' suffix, UTC) -> epoch seconds. Naive input assumed UTC."""
    s = s.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def naive_local_to_epoch(s):
    """Gate-log ts -> epoch seconds. Handles BOTH formats the kit can meet:
    the private rig's naive LOCAL wall time AND the kit gate's UTC 'Z' time
    (aware timestamps carry their own offset; naive ones are read as system-local)."""
    t = s.strip()
    if t.endswith("Z"):
        t = t[:-1] + "+00:00"
    dt = datetime.fromisoformat(t)
    return dt.astimezone().timestamp()  # astimezone() on naive assumes system-local


def window_start(name, now):
    rolling = {"30m": 1800, "1h": 3600, "2h": 2 * 3600, "5h": 5 * 3600,
               "7d": 7 * DAY, "30d": RETENTION}
    if name in rolling:
        return now - rolling[name]
    if name in ("today", "24h"):  # 24h stays as a legacy alias of today
        local_midnight = datetime.fromtimestamp(now).astimezone().replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        return local_midnight.timestamp()
    return now - 5 * 3600


class Scan:
    """In-process per-file bookkeeping so watch ticks only read grown bytes.
    An offset is resumed ONLY on a pure append: inode unchanged, size strictly
    grew, and the head+tail fingerprints of the already-processed region still
    match (catches shrink, same-size rewrite, and rewrite-with-growth). Any
    other change re-reads from 0. Nothing is persisted — the tool is read-only."""

    FP = 64

    def __init__(self):
        self.files = {}

    def seek_offset(self, path, st):
        rec = self.files.get(path)
        if rec and rec["mtime"] == st.st_mtime and rec["size"] == st.st_size:
            return None  # unchanged
        off = 0
        if (rec is not None and rec.get("ino") == st.st_ino and rec["off"] > 0
                and st.st_size > rec["size"] and rec.get("head") and rec.get("tail")):
            try:
                with open(path, "rb") as fh:
                    fh.seek(0)
                    if fh.read(len(rec["head"])) == rec["head"]:
                        fh.seek(rec["off"] - len(rec["tail"]))
                        if fh.read(len(rec["tail"])) == rec["tail"]:
                            off = rec["off"]  # pure append — head+tail intact
            except OSError:
                off = 0
        self.files[path] = {"mtime": st.st_mtime, "size": st.st_size, "ino": st.st_ino,
                            "off": off, "head": b"", "tail": b""}
        return off

    def commit(self, path, off):
        rec = self.files[path]
        rec["off"] = off
        rec["head"] = rec["tail"] = b""
        try:
            with open(path, "rb") as fh:
                rec["head"] = fh.read(self.FP)
                fh.seek(max(0, off - self.FP))
                rec["tail"] = fh.read(self.FP)
        except OSError:
            pass


def read_new_lines(path, offset):
    """Yield complete new text lines from `offset`. Returns (lines, new_offset);
    a torn final line (no newline yet) is left for the next tick."""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        fh.seek(offset)
        data = fh.read()
        cut = data.rfind("\n")
        if cut < 0:
            return [], offset
        new_off = offset + cut + 1
        lines = data[:cut].split("\n")
    return lines, new_off


def read_new_byte_lines(path, offset):
    """Byte-mode variant for the hot adapters (hundreds of MB of transcripts):
    no whole-file decode; only pre-filtered lines ever reach json.loads."""
    with open(path, "rb") as fh:
        fh.seek(offset)
        data = fh.read()
        cut = data.rfind(b"\n")
        if cut < 0:
            return [], offset
        new_off = offset + cut + 1
        lines = data[:cut].split(b"\n")
    return lines, new_off


# ---------- adapters: each returns {"rows": [...], "meta": {...}, "degraded": str|None} ----------
# row = {"ts": epoch-s UTC, "model": str, "tin": int, "tout": int,
#        "cr": int (cache read), "cc": int (cache creation), "total": int (provider convention)}


class ZcodeAdapter:
    """~/.zcode/cli/db/db.sqlite -> model_usage. One indexed range query per scan
    (model_usage_started_model_idx). query_source='session_title' excluded."""

    def __init__(self, db=None):
        self.db = db or os.environ.get("TOKENS_ZCODE_DB") or os.path.expanduser("~/.zcode/cli/db/db.sqlite")

    def collect(self, now):
        if not os.path.isfile(self.db):
            return {"rows": [], "meta": {"absent": self.db}, "degraded": None}
        uri = "file:" + urllib.parse.quote(self.db) + "?mode=ro"
        conn = None
        try:
            conn = sqlite3.connect(uri, uri=True, timeout=2)
            cutoff_ms = int((now - RETENTION) * 1000)
            cur = conn.execute(
                "SELECT mu.model_id, mu.started_at, mu.input_tokens, mu.output_tokens,"
                " mu.reasoning_tokens, mu.cache_creation_input_tokens, mu.cache_read_input_tokens,"
                " mu.computed_total_tokens, mu.duration_ms, mu.time_to_first_token_ms,"
                " mu.status, mu.context_exceeded, COALESCE(s.title, mu.session_id)"
                " FROM model_usage mu LEFT JOIN session s ON s.id = mu.session_id"
                " WHERE mu.started_at >= ? AND mu.query_source != 'session_title'",
                (cutoff_ms,),
            )
            rows = []
            for (model, started_ms, tin, tout, reason, cc, cr, total, dur, ttft,
                 status, ctx_wall, sess) in cur:
                rows.append({
                    "ts": started_ms / 1000.0, "model": model or "?",
                    "tin": tin or 0, "tout": tout or 0, "cr": cr or 0, "cc": cc or 0,
                    "total": total or 0,  # zcode convention: computed_total_tokens
                    "reason": reason or 0, "dur_ms": dur, "ttft_ms": ttft,
                    "status": status, "ctx_wall": 1 if ctx_wall else 0,
                    "proj": sess or "?",  # session title (or id when untitled)
                })
            conn.close()
            return {"rows": rows, "meta": {"db": self.db}, "degraded": None}
        except sqlite3.Error as e:
            if conn is not None:
                try:
                    conn.close()
                except Exception:
                    pass
            return {"rows": [], "meta": {}, "degraded": f"sqlite: {e}"}


class ClaudeAdapter:
    """~/.claude/projects/*/*.jsonl, type=='assistant' lines only.
    Skip synthetic/error lines; dedup (requestId, message.id, file) keep-last.
    Files unmodified beyond RETENTION cannot hold in-window rows -> skipped by mtime."""

    def __init__(self, root=None):
        self.root = root or os.environ.get("TOKENS_CLAUDE_ROOT") or os.path.expanduser("~/.claude")
        self.scan = Scan()
        self.dedup = {}

    def collect(self, now):
        pattern = os.path.join(self.root, "projects", "*", "*.jsonl")
        files = sorted(glob.glob(pattern))
        if not files and not os.path.isdir(self.root):
            return {"rows": [], "meta": {"absent": self.root}, "degraded": None}
        mtime_cutoff = now - RETENTION - 3600
        skipped = 0
        for path in files:
            try:
                st = os.stat(path)
            except OSError:
                continue
            if st.st_mtime < mtime_cutoff:
                skipped += 1
                continue
            offset = self.scan.seek_offset(path, st)
            if offset is None:
                continue
            lines, new_off = read_new_byte_lines(path, offset)
            for line in lines:
                if b'"assistant"' not in line:  # cheap pre-filter; quoted token survives any spacing
                    continue
                try:
                    j = json.loads(line)  # bytes ok; UnicodeDecodeError is a ValueError
                except ValueError:
                    continue  # torn/garbage line
                if not isinstance(j, dict) or j.get("type") != "assistant":
                    continue
                msg = j.get("message")
                msg = msg if isinstance(msg, dict) else {}
                if msg.get("model") == "<synthetic>" or j.get("isApiErrorMessage"):
                    continue
                u = msg.get("usage")
                if not isinstance(u, dict):
                    continue  # malformed usage envelope: not ours to count
                details = u.get("output_tokens_details")
                details = details if isinstance(details, dict) else {}
                try:
                    ts = iso_to_epoch(j["timestamp"])
                except Exception:  # missing / null / non-string / unparseable
                    continue
                if msg.get("id") is None:  # not a real API envelope -> no dedup key, skip
                    continue
                # spec: dedup (requestId, message.id) — cross-file safe (forked/resumed
                # sessions rewrite prior turns into a new .jsonl). Fullest usage wins
                # (corrected rewrites are cumulative); tie -> earliest ts, the original
                # request time, so replays don't re-attribute old burn to a new window.
                key = (j.get("requestId"), msg.get("id"))
                row = {
                    "ts": ts, "model": msg.get("model") or "?",
                    "tin": num(u.get("input_tokens")),
                    "cc": num(u.get("cache_creation_input_tokens")),
                    "cr": num(u.get("cache_read_input_tokens")),
                    "tout": num(u.get("output_tokens")),
                }
                row["total"] = row["tin"] + row["cc"] + row["cr"] + row["tout"]
                prev = self.dedup.get(key)
                if (prev is None or row["total"] > prev["total"]
                        or (row["total"] == prev["total"] and row["ts"] < prev["ts"])):
                    row["reason"] = details.get("thinking_tokens") or 0
                    row["proj"] = repo_label(j.get("cwd"), j.get("gitBranch"))
                    self.dedup[key] = row
            self.scan.commit(path, new_off)
        rows = list(self.dedup.values())
        # bound memory to the widest window we can render: drop keys older than RETENTION
        horizon = now - RETENTION
        stale = [k for k, r in self.dedup.items() if r["ts"] < horizon]
        for k in stale:
            del self.dedup[k]
        meta = {"files": len(files), "stale_skipped": skipped}
        return {"rows": rows, "meta": meta, "degraded": None}


class CodexAdapter:
    """~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl.
    token_count events: last_token_usage = per-turn delta (windowable);
    rate_limits.primary = plan utilization (free-tier info can be null -> coverage note).
    Never parse filenames (local time); in-file timestamps are UTC."""

    def __init__(self, root=None):
        self.root = root or os.environ.get("TOKENS_CODEX_ROOT") or os.path.expanduser("~/.codex")
        self.scan = Scan()
        self.sessions = {}  # path -> {"model":, "final_total":, "has_usage":, "rate":, "rows":}

    def collect(self, now):
        pattern = os.path.join(self.root, "sessions", "*", "*", "*", "rollout-*.jsonl")
        files = sorted(glob.glob(pattern))
        if not files and not os.path.isdir(self.root):
            return {"rows": [], "meta": {"absent": self.root}, "degraded": None}
        mtime_cutoff = now - RETENTION - 3600
        eligible = 0  # files that can hold in-window rows (coverage denominator)
        for path in files:
            try:
                st = os.stat(path)
            except OSError:
                continue
            if st.st_mtime < mtime_cutoff:
                continue
            eligible += 1
            offset = self.scan.seek_offset(path, st)
            if offset is None:
                continue
            sess = self.sessions.setdefault(
                path, {"model": None, "final_total": None, "has_usage": False, "rate": None, "rows": []})
            lines, new_off = read_new_byte_lines(path, offset)
            if offset == 0:
                # re-read from start (first sight or truncation): replace, don't append —
                # and clear per-session meta so events removed by the rewrite don't linger
                sess["rows"] = []
                sess["primary"] = None
                sess["secondary"] = None
                sess["credits"] = None
                sess["ctx"] = None
                sess["has_usage"] = False
                sess["final_total"] = None
            for line in lines:
                if b'"token_count"' not in line and b'"turn_context"' not in line \
                        and b'"session_meta"' not in line:  # pre-filter
                    continue
                try:
                    j = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(j, dict):
                    continue
                p = j.get("payload")
                p = p if isinstance(p, dict) else {}
                if j.get("type") == "session_meta":
                    sess["cwd"] = p.get("cwd") or ""
                elif j.get("type") == "turn_context" and p.get("model"):
                    sess["model"] = p["model"]
                elif j.get("type") == "event_msg" and p.get("type") == "token_count":
                    try:
                        ts = iso_to_epoch(j["timestamp"])
                    except Exception:  # missing / null / non-string / unparseable
                        continue
                    rate = p.get("rate_limits")
                    rate = rate if isinstance(rate, dict) else {}
                    rp = rate.get("primary"); rp = rp if isinstance(rp, dict) else {}
                    rs = rate.get("secondary"); rs = rs if isinstance(rs, dict) else {}
                    p_used = _f(rp.get("used_percent"))
                    s_used = _f(rs.get("used_percent"))
                    cr_info = rate.get("credits")
                    cr_info = cr_info if isinstance(cr_info, dict) else {}
                    has_credits = bool(cr_info.get("unlimited")
                                       or (cr_info.get("has_credits") and cr_info.get("balance") is not None))
                    # snapshot fields update independently: a newer block reporting only
                    # one of primary / secondary / credits refreshes that field without
                    # erasing the others; true placeholders (none) displace nothing.
                    if p_used is not None:
                        prev = sess.get("primary")
                        if prev is None or ts >= prev[0]:
                            sess["primary"] = (ts, rp)
                    if s_used is not None:
                        prev = sess.get("secondary")
                        if prev is None or ts >= prev[0]:
                            sess["secondary"] = (ts, rs)
                    if has_credits:
                        prevc = sess.get("credits")
                        if prevc is None or ts >= prevc[0]:
                            sess["credits"] = (ts, cr_info)
                    info = p.get("info")
                    if not isinstance(info, dict) or not info:
                        continue  # free plan often emits info:null -> undercount, shown as coverage
                    sess["has_usage"] = True
                    delta = info.get("last_token_usage")
                    delta = delta if isinstance(delta, dict) else {}
                    ttu = info.get("total_token_usage")
                    ttu = ttu if isinstance(ttu, dict) else {}
                    sess["final_total"] = num(ttu.get("total_tokens")) or sess["final_total"] or 0
                    win = info.get("model_context_window")
                    if win:
                        used = num(delta.get("input_tokens")) + num(delta.get("cached_input_tokens")) \
                            + num(delta.get("cache_write_input_tokens"))
                        pctx = sess.get("ctx")
                        if pctx is None or ts >= pctx[0]:
                            sess["ctx"] = (ts, used, win)
                    sess["rows"].append({
                        "ts": ts, "model": sess["model"] or "codex",
                        "tin": num(delta.get("input_tokens")),
                        "cr": num(delta.get("cached_input_tokens")),
                        "cc": num(delta.get("cache_write_input_tokens")),
                        "tout": num(delta.get("output_tokens")),
                        "reason": num(delta.get("reasoning_output_tokens")),
                        "proj": repo_label(sess.get("cwd")),
                        "total": num(delta.get("total_tokens"))
                        or num(delta.get("input_tokens")) + num(delta.get("output_tokens"))
                        + num(delta.get("cached_input_tokens")) + num(delta.get("cache_write_input_tokens")),
                    })
            self.scan.commit(path, new_off)
        # per-session row lists are replaced on re-read-from-zero and extended on
        # growth, so a watch never double-counts. Memory is bounded by the
        # token_count events seen since process start (aggregation is windowed);
        # rollout files are append-only, never rotated.
        all_rows = [r for s in self.sessions.values() for r in s["rows"]]
        with_usage = sum(1 for s in self.sessions.values() if s["has_usage"])
        best_p = best_s = best_cr = None
        best_ctx = None
        for s in self.sessions.values():
            p = s.get("primary")
            if p and (best_p is None or p[0] > best_p[0]):
                best_p = p
            sd = s.get("secondary")
            if sd and (best_s is None or sd[0] > best_s[0]):
                best_s = sd
            c = s.get("credits")
            if c and (best_cr is None or c[0] > best_cr[0]):
                best_cr = c
            x = s.get("ctx")
            if x and (best_ctx is None or x[0] > best_ctx[0]):
                best_ctx = x
        rl = {}
        if best_p:
            rl["primary"] = best_p[1]
        if best_s:
            rl["secondary"] = best_s[1]
        if best_cr:
            rl["credits"] = best_cr[1]
        meta = {
            "sessions_total": eligible,  # eligible files; with_usage counts parsed ones
            "sessions_with_usage": with_usage,
            "final_totals": {os.path.basename(p): s["final_total"] for p, s in self.sessions.items()},
            "rate_limits": rl or None,
            "context": {"used": best_ctx[1], "window": best_ctx[2]} if best_ctx else None,
        }
        return {"rows": all_rows, "meta": meta, "degraded": None}


class GateAdapter:
    """The kit gate's JSONL log (~/.local/state/rig-lite/gate-log.jsonl) — ts is LOCAL time."""

    def __init__(self, path=None):
        self.path = path or os.environ.get("TOKENS_GATE_LOG") or os.environ.get("GATE_LOG") \
            or os.path.expanduser("~/.local/state/rig-lite/gate-log.jsonl")

    def collect(self, now):
        if not os.path.isfile(self.path):
            return {"rows": [], "meta": {"absent": self.path}, "degraded": None, "gate": True}
        rows = []
        try:
            with open(self.path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    try:
                        j = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(j, dict):
                        continue
                    try:
                        ts = naive_local_to_epoch(j["ts"])
                    except Exception:  # missing / null / non-string / unparseable
                        continue
                    rows.append({"ts": ts, "j": j})
        except OSError as e:
            return {"rows": [], "meta": {}, "degraded": f"read: {e}", "gate": True}
        return {"rows": rows, "meta": {"file": self.path}, "degraded": None, "gate": True}


class QuotaProbe:
    """Claude plan quota via macOS Keychain + Anthropic oauth endpoint.
    gate.sh pattern: token reaches curl through its stdin config (-K -), never argv.
    60s result cache so watch doesn't hammer the endpoint."""

    TTL = 60

    def __init__(self):
        self._at = 0.0
        self._data = None

    def get(self, force=False):
        now = time.time()
        if not force and self._data is not None and now - self._at < self.TTL:
            return self._data
        self._data = self._probe()
        self._at = now
        return self._data

    def _probe(self):
        if sys.platform != "darwin" or not shutil.which("security") or not shutil.which("curl"):
            return None
        try:
            qo = subprocess.run(
                ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                capture_output=True, text=True, timeout=8,
            ).stdout.strip()
            if not qo:
                return None
            creds = json.loads(qo)
            if not isinstance(creds, dict):
                return None
            oa = creds.get("claudeAiOauth")
            tok = oa.get("accessToken") if isinstance(oa, dict) else None
            if not tok:
                return None
            # the token is pasted into a curl -K config; refuse anything that
            # could break out of the header line
            _ok = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~+/=-")
            if any(c not in _ok for c in tok):
                return None
            cfg = f'header = "Authorization: Bearer {tok}"\n'
            out = subprocess.run(
                ["curl", "-s", "--max-time", "8", "-K", "-", QUOTA_URL,
                 "-H", "anthropic-beta: oauth-2025-04-20"],
                input=cfg, capture_output=True, text=True, timeout=10,
            ).stdout
            d = json.loads(out)
            if not isinstance(d, dict):
                return None
            keep = {}
            for k in ("five_hour", "seven_day"):
                blk = d.get(k)
                blk = blk if isinstance(blk, dict) else {}
                keep[k] = {"utilization": blk.get("utilization"), "resets_at": blk.get("resets_at")}
            return keep
        except Exception:  # any keystore/network/shape surprise -> treat as no data, never crash the dashboard
            return None


# ---------- aggregation ----------

def aggregate(rows, since, now):
    """rows -> {model: {tin,tout,cr,cc,total,count}} for ts >= since."""
    out = {}
    for r in rows:
        if r["ts"] < since:
            continue
        m = out.setdefault(r["model"], {"tin": 0, "tout": 0, "cr": 0, "cc": 0, "total": 0, "count": 0})
        for k in ("tin", "tout", "cr", "cc", "total"):
            m[k] += r.get(k) or 0
        m["count"] += 1
    return out


def provider_tps(rows, now):
    return sum(r.get("tout") or 0 for r in rows if r["ts"] >= now - 60) / 60.0


def gate_totals(rows, since):
    count = 0
    cost = 0.0
    tin = cached = out = 0
    approved = 0
    durs = []
    repos = {}
    for r in rows:
        if r["ts"] < since:
            continue
        j = r["j"]
        count += 1
        cost += num(j.get("cost_usd"))
        tin += int(round(num(j.get("in"))))
        cached += int(round(num(j.get("cached"))))
        out += int(round(num(j.get("out"))))
        if "APPROVED" in str(j.get("result") or ""):
            approved += 1
        if j.get("duration_ms") is not None:
            durs.append(num(j["duration_ms"]))
        rk = str(j.get("repo") or "?")
        repos[rk] = repos.get(rk, 0) + 1
    top_repo = sorted(repos.items(), key=lambda kv: (-kv[1], kv[0]))[0][0] if repos else None
    return {"count": count, "cost_usd": round(cost, 2), "in": tin, "cached": cached, "out": out,
            "approved_pct": round(approved / count * 100) if count else None,
            "avg_ms": round(sum(durs) / len(durs)) if durs else None,
            "top_repo": top_repo}


def parse_caps(items):
    """--cap PROVIDER=TOKENS, repeatable. Unknown providers are a usage error,
    not a silent no-op."""
    caps = {}
    for c in items:
        try:
            name, val = c.split("=", 1)
        except ValueError:
            raise ValueError(f"--cap expects PROVIDER=TOKENS, got {c!r}")
        name = name.strip()
        if name not in CAP_PROVIDERS:
            raise ValueError(f"--cap provider must be one of {', '.join(CAP_PROVIDERS)}; got {name!r}")
        try:
            caps[name] = int(float(val))
        except (ValueError, OverflowError):
            raise ValueError(f"--cap TOKENS must be a finite number, got {val!r}")
    return caps


SPARK_CHARS = "▁▂▃▄▅▆▇█"


def _spark_vals(rows, since, now, buckets=24):
    span = max(1.0, now - since)
    vals = [0] * buckets
    for r in rows:
        if r["ts"] < since:
            continue
        i = min(buckets - 1, int((r["ts"] - since) / span * buckets))
        vals[i] += r.get("total") or 0
    return vals


def sparkline(rows, since, now, buckets=24):
    vals = _spark_vals(rows, since, now, buckets)
    mx = max(vals) if vals else 0
    if mx == 0:
        return "·" * buckets
    out = []
    for v in vals:
        if v == 0:
            out.append("·")
        else:
            out.append(SPARK_CHARS[max(1, round(v / mx * (len(SPARK_CHARS) - 1)))])
    return "".join(out)


def percentile(vals, p):
    if not vals:
        return None
    s = sorted(vals)
    k = max(0, min(len(s) - 1, int(round(p / 100 * (len(s) - 1)))))
    return s[k]


def fmt_sec(ms):
    if ms is None:
        return "—"
    s = ms / 1000.0
    return f"{s:.1f}s" if s < 10 else f"{s:.0f}s"


def repo_label(cwd, branch=None):
    c = (cwd or "").rstrip("/")
    name = c.split("/")[-1] if c else "?"
    if branch:
        name = f"{name}:{branch}"
    return name or "?"


def top_consumers(rows, since, n=3):
    """[(label, tokens, pct-of-provider)] — the 'where did my tokens go' panel."""
    agg = {}
    for r in rows:
        if r["ts"] < since:
            continue
        k = r.get("proj") or "?"
        agg[k] = agg.get(k, 0) + (r.get("total") or 0)
    tot = sum(agg.values())
    top = sorted(agg.items(), key=lambda kv: (-kv[1], kv[0]))[:n]
    return [(k, v, (v / tot * 100.0 if tot else 0.0)) for k, v in top]


def day_over_day(rows, now):
    """(pct, today_total, yesterday_same_hour_total) or None when yesterday is empty."""
    t0 = window_start("today", now)
    t = y = 0
    for r in rows:
        tot = r.get("total") or 0
        if r["ts"] >= t0:
            t += tot
        elif r["ts"] >= t0 - DAY and r["ts"] <= now - DAY:
            y += tot
    if y == 0:
        return None
    return (t - y) / y * 100.0, t, y


# ---------- rendering ----------

def _c(code, s, on):
    return f"\033[{code}m{s}\033[0m" if on else s


ACCENT = {"zcode": "36", "claude": "35", "codex": "34"}  # cyan · magenta · blue (base ANSI)


def _level(v, warn, bad, higher_is_bad=True):
    """Green/yellow/red code for a value against warn/bad thresholds (None-safe)."""
    if v is None:
        return None
    if higher_is_bad:
        return "31" if v >= bad else ("33" if v >= warn else "32")
    return "31" if v <= bad else ("33" if v <= warn else "32")


def color_enabled(mode):
    if mode == "never":
        return False
    if mode == "always":
        return True  # explicit flag beats NO_COLOR
    return sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def pct_color(pct):
    return 31 if pct >= 90 else (33 if pct >= 75 else 32)  # matches GATE_QUOTA_THRESHOLD convention


def bar(pct, width, color_on):
    pct = max(0.0, min(100.0, pct))
    filled = round(pct / 100 * width)
    b = "▓" * filled + "░" * (width - filled)
    return _c(pct_color(pct), b, color_on)


def resets_countdown(raw):
    """resets_at: epoch seconds (int/float/str-digit) or ISO string -> seconds from now."""
    try:
        target = float(raw)
        if not math.isfinite(target):
            return None  # 'inf'/'1e400' parse to infinity; never let it reach fmt_dur
        return max(0, target - time.time())
    except (TypeError, ValueError):
        pass
    try:
        return max(0, iso_to_epoch(str(raw)) - time.time())
    except ValueError:
        return None


def render_dashboard(shot, color_on, caps, watch=None):
    L = []
    dim, bold = (lambda s: _c(2, s, color_on)), (lambda s: _c(1, s, color_on))
    now_dt = datetime.fromtimestamp(shot["now"]).astimezone()
    hdr = f"KIT TOKENS · {shot['window_label']} · {now_dt.strftime('%a %H:%M:%S')}"
    if watch:
        hdr += f" · {watch:g}s"
    L.append(bold(hdr))
    L.append(dim(f"since {datetime.fromtimestamp(shot['window_start']).astimezone().strftime('%a %H:%M')} · read-only"))

    provs = shot["providers"]
    labels = {"zcode": "GLM · zcode", "claude": "Claude · claude-code", "codex": "Codex · codex-cli"}

    for prov in ("zcode", "claude", "codex"):
        p = provs.get(prov)
        if p is None:
            continue
        L.append("")
        if p.get("absent"):
            L.append(dim(f"{labels[prov]} — not installed ({prov})"))
            continue
        tps = p.get("tps", 0.0)
        head = f"{labels[prov]}"
        suffix = f"{tps:.1f} tok/s" if tps > 0 else "idle"
        spark = (p.get("extras") or {}).get("sparkline") or ""
        accent = ACCENT.get(prov, "1")
        L.append(f"{_c('1;' + accent, head, color_on)}  "
                 f"{_c('32' if tps > 0 else '2', '(' + suffix + ')', color_on)}  "
                 f"{_c(accent, spark, color_on)}")
        for m in p.get("models", {}):
            agg = p["models"][m]
            L.append(
                f"  {_c(accent, m[:25].ljust(25), color_on)} in {fmt_tok(agg['tin']):>7} · out {fmt_tok(agg['tout']):>7}"
                f" · cacheR {fmt_tok(agg['cr']):>7} · total {fmt_tok(agg['total']):>7}"
                f" · {agg['count']} req"
            )
        ex = p.get("extras") or {}
        bits = []
        if ex.get("cache_hit") is not None:
            bits.append(_c(_level(ex["cache_hit"], 60, 30, higher_is_bad=False),
                           f"cache hit {ex['cache_hit']:.1f}%", color_on))
        if ex.get("reason_share") is not None:
            bits.append(f"reasoning {ex['reason_share']:.1f}%")
        d2 = ex.get("d2d")
        if d2 is not None:
            txt = f"{d2[0]:+.0f}% vs same hour yesterday" if d2[0] else "flat vs yesterday"
            bits.append(_c(_level(d2[0], 25, 100), txt, color_on))
        if bits:
            L.append(_c(2, "  stats  ", color_on) + " · ".join(bits))
        lat = ex.get("latency")
        if lat:
            lbits = []
            if lat.get("p50_ms") is not None:
                lbits.append(f"p50 {fmt_sec(lat['p50_ms'])}")
            if lat.get("p95_ms") is not None:
                lbits.append(_c(_level(lat["p95_ms"], 60_000, 120_000),
                                f"p95 {fmt_sec(lat['p95_ms'])}", color_on))
            if lat.get("ttft_p50_ms") is not None:
                lbits.append(f"ttft {fmt_sec(lat['ttft_p50_ms'])}")
            if lat.get("running"):
                lbits.append(_c(32, f"{lat['running']} live req", color_on))
            if lat.get("ctx_wall"):
                lbits.append(f"ctx-wall ×{lat['ctx_wall']}")
            if lbits:
                wall = " · ".join(lbits)
                if lat.get("ctx_wall"):
                    wall = _c(31, wall + " ⚠", color_on)  # context exhaustion is a warning
                L.append(_c(2, "  perf   ", color_on) + wall)
        top = ex.get("top")
        if top:
            parts = []
            for i, (k, _v, pct) in enumerate(top):
                ptxt = f"{pct:.0f}%"
                label = k[:19] + "…" if len(k) > 20 else k
                parts.append(f"{label} " + (_c('1;' + accent, ptxt, color_on) if i == 0 else ptxt))
            L.append(_c(2, "  top    ", color_on) + " · ".join(parts))
        cap = caps.get(prov)
        if cap:
            used = sum(a["total"] for a in p.get("models", {}).values())
            pct = used / cap * 100 if cap else 0
            L.append(f"  cap     {bar(pct, 14, color_on)} {pct:5.1f}% of {fmt_tok(cap)} (manual)")
        elif prov == "zcode":
            L.append(dim("  limits  none exposed by the plan — use --cap zcode=<tokens> for a manual bar"))
        if prov == "claude" and shot.get("quota"):
            q = shot["quota"]
            for key, lbl in (("five_hour", "5-hour"), ("seven_day", "7-day")):
                blk = q.get(key) or {}
                u = _f(blk.get("utilization"))  # remote JSON: never trust the type
                if u is None:
                    continue
                cd = resets_countdown(blk.get("resets_at"))
                cds = f" · resets {fmt_dur(cd)}" if cd is not None else ""
                L.append(f"  {lbl} quota {bar(u, 14, color_on)} {u:5.1f}%{cds}")
        if prov == "codex":
            meta = p.get("meta") or {}
            rate = meta.get("rate_limits") or {}
            cov = (meta.get("sessions_with_usage"), meta.get("sessions_total"))
            ctxm = meta.get("context") or {}
            w = _f(ctxm.get("window"))
            uctx = _f(ctxm.get("used"))
            if w and uctx is not None:
                pctc = uctx / w * 100
                L.append(_c(2, "  ctx    ", color_on)
                         + f"last request {fmt_tok(uctx)} / {fmt_tok(w)} "
                         + _c(_level(pctc, 70, 90), f"({pctc:.0f}% of window)", color_on))
            rate = meta.get("rate_limits") or {}
            for key in ("primary", "secondary"):  # every window the provider defines
                blk = rate.get(key) or {}
                used = _f(blk.get("used_percent"))  # session-derived: guard the type
                if used is None:
                    continue
                lbl = fmt_window(blk.get("window_minutes")) or "limit"
                cd = resets_countdown(blk.get("resets_at"))
                cds = f" · resets {fmt_dur(cd)}" if cd is not None else ""
                L.append(f"  {lbl:<7} {bar(used, 14, color_on)} {used:5.1f}%{cds}")
            cr = rate.get("credits") or {}
            if cr.get("unlimited"):
                L.append(dim("  credits unlimited"))
            elif cr.get("has_credits") and cr.get("balance") is not None:
                L.append(dim(f"  credits  balance {cr['balance']}"))
            if cov[1]:
                note = "usage reported" if cov[0] == cov[1] else f"⚠ usage in {cov[0]}/{cov[1]} sessions"
                L.append(dim(f"  {note} (free tier can emit null usage)"))
        if p.get("degraded"):
            L.append(_c(31, f"  degraded: {p['degraded']}", color_on))

    g = shot.get("gate")
    L.append("")
    if g:
        gbits = [f"{g['count']} reviews"]
        if g.get("approved_pct") is not None:
            ap = g["approved_pct"]
            gbits.append(_c(_level(ap, 40, 70, higher_is_bad=False), f"{ap:.0f}% approved", color_on))
        if g.get("avg_ms") is not None:
            gbits.append(f"avg {fmt_sec(g['avg_ms'])}")
        gbits.append(f"${g['cost_usd']:.2f} API-equiv")
        if g.get("top_repo"):
            gbits.append(f"top: {g['top_repo']}")
        L.append(_c(2, "gate · ", color_on) + " · ".join(gbits))
    if shot.get("degraded"):
        L.append(_c(33, f"degraded: {', '.join(shot['degraded'])}", color_on))
    if watch:
        L.append(dim("q quit · " + " · ".join(f"{i + 1} {w[0]}" for i, w in enumerate(WINDOWS)) + " · J json"))
    return L


# ---------- snapshot ----------

def build_snapshot(window, now, adapters, probe=None, no_quota=False):
    shot = {
        "generated_at": datetime.fromtimestamp(now, timezone.utc).isoformat(),
        "now": now,
        "window": window,
        "window_label": dict(WINDOWS)[window],
        "window_start": window_start(window, now),
        "providers": {},
        "degraded": [],
    }
    since = shot["window_start"]
    for prov in PROVIDERS:
        if prov == "gate":
            continue
        try:
            res = adapters[prov].collect(now)
        except Exception as e:  # a broken provider never kills the dashboard
            res = {"rows": [], "meta": {}, "degraded": f"{type(e).__name__}: {e}"}
        if res.get("degraded"):
            shot["degraded"].append(f"{prov}: {res['degraded']}")
        if res.get("meta", {}).get("absent") is not None:
            shot["providers"][prov] = {"absent": True}
            continue
        aggs = aggregate(res["rows"], since, now)
        rows = res["rows"]

        def wsum(key):
            return sum(r.get(key) or 0 for r in rows if r["ts"] >= since)

        tin_w, cr_w, tout_w = wsum("tin"), wsum("cr"), wsum("tout")
        hit_denom = tin_w if prov in INCLUSIVE_INPUT else cr_w + tin_w
        extras = {
            "sparkline": sparkline(rows, since, now),
            # clamp: a drifted row (cr > tin) must render 100%, not more
            "cache_hit": round(min(cr_w / hit_denom, 1.0) * 100, 1) if hit_denom else None,
            "reason_share": round(wsum("reason") / tout_w * 100, 1) if tout_w else None,
            "d2d": day_over_day(rows, now),
            "top": top_consumers(rows, since),
        }
        if prov == "zcode":  # the only source with per-request timing
            durs = [r["dur_ms"] for r in rows if r.get("dur_ms") and r["ts"] >= since]
            ttfts = [r["ttft_ms"] for r in rows if r.get("ttft_ms") and r["ts"] >= since]
            extras["latency"] = {
                "p50_ms": percentile(durs, 50), "p95_ms": percentile(durs, 95),
                "ttft_p50_ms": percentile(ttfts, 50),
                "running": sum(1 for r in rows
                               if r.get("status") == "running" and r["ts"] >= now - 3600),
                "ctx_wall": sum(1 for r in rows if r.get("ctx_wall") and r["ts"] >= since),
            }
        p = {"models": {m: aggs[m] for m in sorted(aggs, key=lambda k: -aggs[k]["total"])},
             "tps": round(provider_tps(res["rows"], now), 2),
             "extras": extras}
        if res.get("meta"):
            p["meta"] = res["meta"]
        if res.get("degraded"):
            p["degraded"] = res["degraded"]
        shot["providers"][prov] = p

    try:
        gres = adapters["gate"].collect(now)
    except Exception as e:
        gres = {"rows": [], "degraded": f"{type(e).__name__}: {e}"}
    if gres.get("degraded"):
        shot["degraded"].append(f"gate: {gres['degraded']}")
    shot["gate"] = gate_totals(gres["rows"], since) if not gres.get("meta", {}).get("absent") else None

    if not no_quota and probe is not None:
        q = probe.get()
        if q:
            shot["quota"] = q
    return shot


# ---------- watch loop ----------

def watch_loop(window, interval, adapters, probe, caps, json_mode, no_quota, color_mode="auto"):
    if not sys.stdout.isatty() or not sys.stdin.isatty():
        print("tokens.py: --watch needs a tty", file=sys.stderr)
        return 1
    import termios
    import tty
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    color = color_enabled(color_mode)
    show_json = json_mode
    print("\033[?25l", end="", flush=True)  # hide cursor
    try:
        tty.setcbreak(fd)
        while True:
            shot = build_snapshot(window, time.time(), adapters, probe, no_quota)
            if show_json:
                text = json.dumps(shot, indent=2)
            else:
                text = "\n".join(render_dashboard(shot, color, caps, watch=interval))
            print("\033[H\033[J" + text, flush=True)
            r, _, _ = select.select([sys.stdin], [], [], interval)
            if r:
                ch = sys.stdin.read(1)
                if ch in ("q", "Q"):
                    break
                if ch in tuple("1234567"):
                    window = WINDOWS[int(ch) - 1][0]
                elif ch in ("j", "J"):
                    show_json = not show_json
    except KeyboardInterrupt:
        pass
    finally:
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
        except termios.error:
            pass
        print("\033[?25h\033[0m", end="", flush=True)  # cursor + attrs back
    return 0


# ---------- selftest ----------

FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests", "tokens-fixtures")


def _mk_fixtures(tmp):
    """Materialize the fixture tree under tmp with timestamps relative to NOW."""
    now = datetime(2026, 9, 20, 18, 0, tzinfo=timezone.utc)
    z = now.timestamp()

    def iso(minutes_ago):
        return datetime.fromtimestamp(z - minutes_ago * 60, timezone.utc).isoformat().replace("+00:00", "Z")

    cl_dir = os.path.join(tmp, "claude", "projects", "proj-a")
    os.makedirs(cl_dir)
    CA = "/Users/mp/ancuria"  # dominant repo today

    def cl(ts, rid, mid, model, usage, cwd=CA, branch="fix/sat", **kw):
        d = {"type": "assistant", "timestamp": ts, "requestId": rid, "cwd": cwd,
             "gitBranch": branch, **kw}
        d["message"] = {"id": mid, "model": model, "usage": usage}
        return json.dumps(d)

    lines = [
        json.dumps({"type": "user", "timestamp": iso(300)}),  # non-assistant: ignored
        cl(iso(30), "r1", "m1", "claude-opus-5",
           {"input_tokens": 100, "cache_creation_input_tokens": 50,
            "cache_read_input_tokens": 200, "output_tokens": 300,
            "output_tokens_details": {"thinking_tokens": 0}}),
        cl(iso(29), None, "mE", "<synthetic>", {"input_tokens": 999, "output_tokens": 999},
           isApiErrorMessage=True),
        cl(iso(200), "r2", "m2", "claude-opus-5", {"input_tokens": 10, "output_tokens": 10}),
        cl(iso(190), "r2", "m2", "claude-opus-5", {"input_tokens": 20, "output_tokens": 70}),  # dup: last wins
        cl(iso(60), "r3", "m3", "claude-haiku-4-5", {"input_tokens": 40, "output_tokens": 25},
           cwd="/Users/mp/rig", branch=None, isSidechain=True),
        cl(iso(45), "r5", "m5", "claude-opus-5", {"input_tokens": 5, "output_tokens": 11}),
        cl(iso(25), "r6", "m6", "claude-3-haiku", {"input_tokens": 4, "output_tokens": 12},
           cwd="/Users/mp/rig", branch=None),
        cl(iso(20), "r9", None, "claude-opus-5", {"input_tokens": 1, "output_tokens": 500}),
        cl("2026-09-18T00:00:00Z", "r4", "m4", "claude-opus-5",
           {"input_tokens": 1000, "output_tokens": 1000}),  # 7d-only
        cl("2026-09-19T11:30:00Z", "r8", "m8", "claude-opus-5",
           {"input_tokens": 100, "output_tokens": 100}),  # yesterday same-hour (d2d)
        cl("2026-08-31T12:00:00Z", "r10", "m10", "claude-opus-5",
           {"input_tokens": 450, "output_tokens": 450}),  # 20d old: 30d window only
        # malformed shapes — every one must be skipped without killing the tick
        json.dumps(["not", "an", "object"]),  # JSON array line
        json.dumps({"type": "assistant", "timestamp": None, "requestId": "rX", "cwd": CA,
                    "message": {"id": "mX", "model": "claude-opus-5",
                                "usage": {"input_tokens": 888, "output_tokens": 888}}}),  # null timestamp
        json.dumps({"type": "assistant", "timestamp": "2026-09-20T17:45:00Z",
                    "requestId": "rY", "message": "not-a-dict"}),  # non-dict message
        json.dumps({"type": "assistant", "timestamp": "2026-09-20T17:46:00Z", "requestId": "rZ",
                    "cwd": CA,
                    "message": {"id": "mZ", "model": "claude-opus-5",
                                "usage": "not-a-dict"}}),  # non-dict usage
    ]
    with open(os.path.join(cl_dir, "s1.jsonl"), "w") as fh:
        fh.write("\n".join(lines) + "\n" + '{"type":"assi')  # torn tail: skipped
    cl_b = os.path.join(tmp, "claude", "projects", "proj-b")
    os.makedirs(cl_b)
    with open(os.path.join(cl_b, "s2.jsonl"), "w") as fh:  # (r5,m5) later+fuller -> wins outright
        fh.write(cl(iso(15), "r5", "m5", "claude-opus-5", {"input_tokens": 6, "output_tokens": 22}) + "\n")
        # (r6,m6) same total as file-a's copy but LATER ts -> tie-break keeps a's earlier-ts copy
        fh.write(cl(iso(5), "r6", "m6", "claude-3-haiku", {"input_tokens": 8, "output_tokens": 8},
                    cwd="/Users/mp/rig", branch=None) + "\n")
    cl_c = os.path.join(tmp, "claude", "projects", "proj-c")  # rewrite-test file
    os.makedirs(cl_c)
    with open(os.path.join(cl_c, "s3.jsonl"), "w") as fh:
        fh.write(cl(iso(10), "rc1", "mc1", "claude-rw", {"input_tokens": 10, "output_tokens": 10},
                   cwd="/w/rw", branch=None) + "\n")
    cl_d = os.path.join(tmp, "claude", "projects", "proj-d")  # retention boundary: OLD file mtime
    os.makedirs(cl_d)
    old = os.path.join(cl_d, "s4.jsonl")
    with open(old, "w") as fh:
        fh.write(cl("2026-08-31T14:00:00Z", "r11", "m11", "claude-opus-5",
                    {"input_tokens": 400, "output_tokens": 400}) + "\n")
    os.utime(old, (z - 20 * DAY, z - 20 * DAY))

    cx_dir = os.path.join(tmp, "codex", "sessions", "2026", "09", "20")
    os.makedirs(cx_dir)

    def codex_file(name, model, events):
        out = [json.dumps({"timestamp": events[0][1], "type": "session_meta",
                           "payload": {"id": name, "cwd": "/Users/mp/cx-" + name}}),
               json.dumps({"timestamp": events[0][1], "type": "turn_context", "payload": {"model": model}})]
        for ts, info, rate in events:
            out.append(json.dumps({"timestamp": ts, "type": "event_msg",
                                   "payload": {"type": "token_count", "info": info, "rate_limits": rate}}))
        path = os.path.join(cx_dir, name)
        with open(path, "w") as fh:
            fh.write("\n".join(out) + "\n")
        return path

    def usage(i, ca, o, t, r=0):
        return {"model_context_window": 258400,
                "total_token_usage": {"input_tokens": i, "cached_input_tokens": ca,
                                      "output_tokens": o, "total_tokens": t},
                "last_token_usage": {"input_tokens": i, "cached_input_tokens": ca,
                                     "cache_write_input_tokens": 0, "output_tokens": o,
                                     "reasoning_output_tokens": r, "total_tokens": t}}
    codex_file("rollout-a.jsonl", "gpt-5.6-terra",
               [(iso(300), None, None),  # info:null -> skipped, no usage credit
                (iso(270), usage(500, 100, 40, 640, r=30),
                 {"primary": {"used_percent": 99.0, "window_minutes": 43200, "resets_at": 1792263887},
                  "secondary": {"used_percent": 42.0, "window_minutes": 300, "resets_at": 1792263887},
                  "credits": {"has_credits": False, "unlimited": False, "balance": None}})])
    codex_file("rollout-b.jsonl", "gpt-5.6-terra",
               [(iso(120), usage(50, 0, 10, 60, r=10), None)])
    with open(os.path.join(cx_dir, "rollout-bad.jsonl"), "w") as fh:  # malformed shapes
        fh.write("\n".join([
            json.dumps(["not", "an", "object"]),
            json.dumps({"timestamp": "2026-08-11T00:00:00Z", "type": "event_msg",
                        "payload": "not-a-dict"}),
            json.dumps({"timestamp": "2026-08-11T00:01:00Z", "type": "event_msg",
                        "payload": {"type": "token_count",
                                    "info": {"last_token_usage": {"input_tokens": "12",
                                                                  "output_tokens": "3",
                                                                  "total_tokens": "15"},
                                             "total_token_usage": {"total_tokens": "99"},
                                             "model_context_window": 258400},
                                    "rate_limits": {"primary": {"used_percent": 50.0,
                                                                "resets_at": "1e400"}}}}),
        ]) + "\n")
    codex_file("rollout-c.jsonl", "gpt-5.6-terra",   # 7d-only (30h ago)
               [("2026-09-19T12:00:00Z", usage(7, 0, 999, 1006), None)])
    codex_file("rollout-d.jsonl", "gpt-5.6-terra",   # never reports usage
               [(iso(10), None, None)])
    stale = codex_file("rollout-e.jsonl", "gpt-5.6-terra",  # has usage, but 40d stale -> outside retention
                       [(iso(60), usage(1, 0, 1, 2), None)])
    os.utime(stale, (z - 40 * DAY, z - 40 * DAY))
    codex_file("rollout-g.jsonl", "gpt-5.6-terra",  # rewrite-test session (older than b)
               [(iso(200), usage(100, 0, 0, 100), None)])
    old_cx = codex_file("rollout-h.jsonl", "gpt-5.6-terra",  # retention boundary: OLD file mtime
                        [("2026-08-31T14:00:00Z", usage(250, 0, 0, 250), None)])
    os.utime(old_cx, (z - 20 * DAY, z - 20 * DAY))

    gate_rows = [
        json.dumps({"ts": "2026-09-20T10:44:15", "repo": "ancuria", "target": "pr#1", "reviewer": "claude",
                    "result": "GATE: APPROVED", "in": 2, "cached": 57673, "out": 1597,
                    "cost_usd": 0.5, "duration_ms": 30000}),
        json.dumps({"ts": "2026-09-20T05:00:00", "repo": "rig", "target": "pr#2", "reviewer": "codex",
                    "result": "GATE: REVISE", "in": 1, "cached": 10, "out": 20,
                    "duration_ms": 20000}),  # no cost_usd
        json.dumps({"ts": "2026-09-19T20:00:00", "repo": "ancuria", "target": "pr#3", "reviewer": "claude",
                    "result": "GATE: APPROVED", "in": 4, "cached": 5, "out": 6,
                    "cost_usd": 2.0, "duration_ms": 40000}),
    ]
    gate_path = os.path.join(tmp, "gate-log.jsonl")
    with open(gate_path, "w") as fh:
        fh.write("\n".join(gate_rows) + "\n")

    sql = """
    CREATE TABLE session (id text primary key, project_id text not null default 'p',
      slug text not null default '', directory text not null default '', title text);
    INSERT INTO session VALUES ('s1','p','','','Dash build');
    INSERT INTO session VALUES ('s2','p','','','Other work');
    CREATE TABLE model_usage (id text primary key, logical_request_id text, attempt_index integer,
      session_id text, query_source text, provider_id text, model_id text,
      status text, started_at integer, completed_at integer, duration_ms integer,
      time_to_first_token_ms integer, context_exceeded integer,
      input_tokens integer, output_tokens integer, reasoning_tokens integer,
      cache_creation_input_tokens integer, cache_read_input_tokens integer,
      computed_total_tokens integer);
    INSERT INTO model_usage VALUES ('1','lr1',0,'s1','main_turn','p','GLM-5.3','completed',{t30},NULL,5000,500,0, 1000,200,100,0,5000,1200);
    INSERT INTO model_usage VALUES ('2','lr2',0,'s1','main_turn','p','GLM-5.3','completed',{t3h},NULL,4000,400,1, 500,100,50,0,0,600);
    INSERT INTO model_usage VALUES ('3','lr3',0,'s1','session_title','p','GLM-5.3','completed',{t10m},NULL,10,1,0, 99999,0,0,0,0,999999);
    INSERT INTO model_usage VALUES ('4','lr4',0,'s1','main_turn','p','GLM-5.3','cancelled',{t40h},NULL,3000,300,0, 700,0,0,0,0,700);
    INSERT INTO model_usage VALUES ('5','lr5',0,'s2','main_turn','p','GLM-5.3','cancelled',{t1h},NULL,50,5,0, 40,10,0,0,0,50);
    INSERT INTO model_usage VALUES ('6','lr6',0,'s2','main_turn','p','GLM-5.3','running',{t2m},NULL,NULL,NULL,0, 0,0,0,0,0,0);
    INSERT INTO model_usage VALUES ('7','lr7',0,'s2','main_turn','p','GLM-5.3','completed',{tY},NULL,2000,200,0, 400,0,0,0,0,400);
    INSERT INTO model_usage VALUES ('8','lr8',0,'s1','main_turn','p','GLM-5.3','completed',{t20d},NULL,1500,150,0, 250,50,0,0,0,300);
    """.format(t30=int((z - 1800) * 1000), t3h=int((z - 10800) * 1000), t10m=int((z - 600) * 1000),
               t40h=int((z - 40 * 3600) * 1000), t1h=int((z - 3600) * 1000),
               t20d=int((z - 20 * DAY) * 1000),
               t2m=int((z - 120) * 1000), tY=int((z - 31 * 3600) * 1000))
    db = os.path.join(tmp, "zcode.sqlite")
    conn = sqlite3.connect(db)
    conn.executescript(sql)
    conn.commit()
    conn.close()
    return {"now": z, "claude_root": os.path.join(tmp, "claude"), "codex_root": os.path.join(tmp, "codex"),
            "gate": gate_path, "zcode_db": db}


def selftest():
    """Fixture golden tests. TZ is PINNED (POSIX MST7MDT string — no tzdata
    dependency; UTC-6 in September, matching the fixtures) so the suite passes
    identically in UTC CI, slim containers, and any local timezone."""
    _old_tz = os.environ.get("TZ")
    os.environ["TZ"] = "MST7MDT,M3.2.0,M11.1.0"
    time.tzset()
    try:
        return _selftest_body()
    finally:
        if _old_tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = _old_tz
        time.tzset()


def _selftest_body():
    tmp = tempfile.mkdtemp(prefix="tokens-selftest-")
    try:
        return _selftest_run(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _selftest_run(tmp):
    fx = _mk_fixtures(tmp)
    now = fx["now"]
    checks = []

    def case(name, fn):
        try:
            fn()
            checks.append(name)
        except Exception as e:  # any failure inside a case is a selftest failure
            print(f"selftest FAIL: {name}: {type(e).__name__}: {e}")
            sys.exit(3)

    # --- zcode adapter ---
    zx = ZcodeAdapter(db=fx["zcode_db"]).collect(now)
    case("zcode excludes session_title + windows", lambda: (
        (lambda agg: (
            _ae(agg["GLM-5.3"]["tin"], 1000 + 500 + 40, "5h tin"),
            _ae(agg["GLM-5.3"]["total"], 1200 + 600 + 50, "5h computed_total"),
            _ae(agg["GLM-5.3"]["count"], 4, "5h count (incl. 1 running, 0 tokens)"),
        ))(aggregate(zx["rows"], now - 5 * 3600, now)),
    ))
    case("zcode 7d includes older rows", lambda: _ae(
        aggregate(zx["rows"], now - 7 * DAY, now)["GLM-5.3"]["total"], 1200 + 600 + 50 + 700 + 400, "7d total"))
    case("zcode 30d window", lambda: _ae(
        aggregate(zx["rows"], window_start("30d", now), now)["GLM-5.3"]["total"],
        1200 + 600 + 50 + 700 + 400 + 300, "30d total (20d row included, 7d not)"))

    def _windows():
        fixed = 1789934400.0
        rows = [{"ts": fixed - a, "model": "m", "tin": 1, "tout": 1, "cr": 0, "cc": 0, "total": 1}
                for a in (600, 2700, 5400, 3 * 3600, 6 * 3600, 26 * 3600, 20 * DAY, 40 * DAY)]
        tot = lambda name: aggregate(rows, window_start(name, fixed), now=fixed)["m"]["count"]
        _ae(tot("30m"), 1, "30m")
        _ae(tot("1h"), 2, "1h")
        _ae(tot("2h"), 3, "2h")
        _ae(tot("5h"), 4, "5h")
        _ae(tot("7d"), 6, "7d")
        _ae(tot("30d"), 7, "30d")
        _ae(window_start("24h", fixed), window_start("today", fixed), "24h alias == today")
    case("seven windows boundaries", _windows)

    def _zx_latency():
        rows5 = [r for r in zx["rows"] if r["ts"] >= now - 5 * 3600]
        durs = sorted(r["dur_ms"] for r in rows5 if r.get("dur_ms"))
        _ae(percentile(durs, 50), 4000, "p50")
        _ae(percentile(durs, 95), 5000, "p95")
        ttfts = sorted(r["ttft_ms"] for r in rows5 if r.get("ttft_ms"))
        _ae(percentile(ttfts, 50), 400, "ttft p50")
        _ae(sum(1 for r in zx["rows"] if r.get("status") == "running" and r["ts"] >= now - 3600), 1, "running")
        _ae(sum(1 for r in rows5 if r.get("ctx_wall")), 1, "ctx wall hits")
    case("zcode latency/running/ctx-wall", _zx_latency)
    case("zcode attribution top session", lambda: _ae(
        top_consumers(zx["rows"], now - 5 * 3600)[0][0], "Dash build", "top consumer"))
    case("zcode shares + d2d + sparkline", lambda: (
        _ae(round(sum(r["cr"] for r in zx["rows"] if r["ts"] >= now - 5 * 3600)
                  / sum(r["cr"] + r["tin"] for r in zx["rows"] if r["ts"] >= now - 5 * 3600) * 100, 1),
            76.5, "cache hit"),
        _ae(round(sum(r.get("reason") or 0 for r in zx["rows"] if r["ts"] >= now - 5 * 3600)
                  / sum(r["tout"] for r in zx["rows"] if r["ts"] >= now - 5 * 3600) * 100, 1),
            48.4, "reasoning share"),
        _ae(day_over_day(zx["rows"], now)[0], 362.5, "d2d pct"),
        _ae(sum(_spark_vals(zx["rows"], now - 5 * 3600, now)), 1850, "sparkline bucket-sum == window total"),
    ))

    # --- cache-hit convention: inclusive tin (zcode/codex) vs exclusive (claude) ---
    class _StubAdapter:
        def __init__(self, rows):
            self._rows = rows

        def collect(self, now):
            return {"rows": self._rows, "meta": {}, "degraded": None}

    def _hit_conventions():
        mk = lambda tin, cr: [{"ts": now - 60, "model": "m", "tin": tin, "tout": 10,
                               "cr": cr, "cc": 0, "total": tin + 10}]
        ad = {p: _StubAdapter([]) for p in PROVIDERS}
        ad["zcode"] = _StubAdapter(mk(1000, 500))   # inclusive: cr/tin = 50.0
        ad["claude"] = _StubAdapter(mk(100, 500))   # exclusive: cr/(cr+tin) = 83.3
        shot = build_snapshot("5h", now, ad, no_quota=True)
        _ae(shot["providers"]["zcode"]["extras"]["cache_hit"], 50.0, "inclusive hit = cr/tin")
        _ae(shot["providers"]["claude"]["extras"]["cache_hit"], 83.3, "exclusive hit = cr/(cr+tin)")
        ad["zcode"] = _StubAdapter(mk(100, 500))    # drifted rows (cr > tin) must clamp
        shot = build_snapshot("5h", now, ad, no_quota=True)
        _ae(shot["providers"]["zcode"]["extras"]["cache_hit"], 100.0, "inclusive clamped at 100")
    case("cache-hit per-provider convention + clamp", _hit_conventions)

    # --- claude adapter ---
    ca = ClaudeAdapter(root=fx["claude_root"]).collect(now)
    def _claude_5h():
        agg = aggregate(ca["rows"], now - 5 * 3600, now)
        _ae(agg["claude-opus-5"]["tout"], 300 + 70 + 22, "keep-last dup(in-file) + cross-file + main")
        _ae(agg["claude-opus-5"]["tin"], 100 + 20 + 6, "tin (cross-file keep-last row)")
        _ae(agg["claude-opus-5"]["total"], 100 + 50 + 200 + 300 + 20 + 70 + 6 + 22,
            "total=4-bucket sum")
        _ae(agg["claude-haiku-4-5"]["tout"], 25, "sidechain counted")
        _ae(agg["claude-opus-5"]["count"], 3, "count")
        _ae(agg["claude-rw"]["tin"], 10, "rewrite-fixture baseline row")
    case("claude dedup/synthetic/sidechain", _claude_5h)
    case("claude cross-file keep-last", lambda: _ae(
        sum(1 for r in ca["rows"] if r["tout"] == 11), 0, "superseded file-a copy gone"))
    case("claude id-less envelope skipped", lambda: _ae(
        sum(1 for r in ca["rows"] if r["tout"] == 500), 0, "no dedup key -> excluded"))
    case("claude 7d-only row", lambda: _ae(
        aggregate(ca["rows"], now - 7 * DAY, now)["claude-opus-5"]["tin"],
        100 + 20 + 6 + 1000 + 100, "7d tin (incl. yesterday d2d row)"))
    case("claude torn tail tolerated", lambda: _ae(
        len([r for r in ca["rows"] if r["model"] == "claude-opus-5"]), 7, "no row from torn line"))
    case("claude 30d window", lambda: _ae(
        aggregate(ca["rows"], window_start("30d", now), now)["claude-opus-5"]["tin"],
        100 + 20 + 6 + 1000 + 100 + 450 + 400, "30d tin (20d rows in, adapter parsed old mtime)"))
    case("claude attribution + d2d", lambda: (
        _ae(top_consumers(ca["rows"], now - 5 * 3600)[0][0].startswith("ancuria"), True, "top repo"),
        _ae(day_over_day(ca["rows"], now)[0], 334.5, "d2d pct"),
    ))

    # --- codex adapter ---
    cxa = CodexAdapter(root=fx["codex_root"])
    cx = cxa.collect(now)
    def _codex():
        agg = aggregate(cx["rows"], now - 5 * 3600, now).get("gpt-5.6-terra")
        _ae(agg is not None, True, "model key present")
        _ae(agg["tin"], 500 + 50 + 100, "delta inputs")
        _ae(agg["tout"], 40 + 10, "delta outputs")
        _ae(agg["total"], 640 + 60 + 100, "delta totals")
        _ae(cx["meta"]["sessions_with_usage"], 6,
            "coverage used (4 real + 20d-old + rollout-bad's num()-coerced string-token session)")
        _ae(cx["meta"]["sessions_total"], 7, "coverage total (6 with-usage-eligible + rollout-bad)")
        _ae(cx["meta"]["final_totals"]["rollout-a.jsonl"], 640, "final cumulative")
        _ae(cx["meta"]["rate_limits"]["primary"]["used_percent"], 99.0, "primary window parsed")
        _ae(cx["meta"]["rate_limits"]["secondary"]["used_percent"], 42.0, "secondary window parsed")
        _ae("credits" in cx["meta"]["rate_limits"], False, "unusable credits (false/null) not stored")
    case("codex deltas/coverage/rate_limits", _codex)
    case("codex 7d-only session", lambda: _ae(
        aggregate(cx["rows"], now - 7 * DAY, now).get("gpt-5.6-terra", {}).get("total"),
        640 + 60 + 1006 + 100, "7d total (20d session excluded)"))
    case("codex 30d window (adapter retention)", lambda: _ae(
        aggregate(cx["rows"], window_start("30d", now), now)["gpt-5.6-terra"]["total"],
        640 + 60 + 1006 + 100 + 250, "30d total (20d-old-mtime session parsed)"))
    case("codex reasoning + context window", lambda: (
        _ae(cx["meta"]["context"], {"used": 50, "window": 258400}, "freshest context"),
        _ae(round(sum(r.get("reason") or 0 for r in cx["rows"] if r["ts"] >= now - 5 * 3600)
                  / aggregate(cx["rows"], now - 5 * 3600, now)["gpt-5.6-terra"]["tout"] * 100, 1),
            80.0, "reasoning share"),
    ))

    def _codex_reread():
        cx_dir_f = os.path.join(fx["codex_root"], "sessions", "2026", "09", "20")
        a_path = os.path.join(cx_dir_f, "rollout-a.jsonl")
        b_path = os.path.join(cx_dir_f, "rollout-b.jsonl")
        # shrink rollout-a (drop its usage event) -> re-read from 0 must REPLACE, not append
        lines = open(a_path).read().splitlines()
        with open(a_path, "w") as fh:
            fh.write("\n".join(l for l in lines if '"total_token_usage"' not in l) + "\n")
        rows = cxa.collect(now)["rows"]
        _ae(aggregate(rows, now - 5 * 3600, now)["gpt-5.6-terra"]["total"], 160,
            "shrunk re-read replaced session rows (no double-count)")
        rl = cxa.collect(now)["meta"]["rate_limits"]
        _ae(rl["primary"]["used_percent"], 50.0,
            "shrunk re-read clears rollout-a's stale 99% (freshest = rollout-bad's 50)")
        # append one new event to rollout-b -> totals grow by exactly that delta
        ev = {"input_tokens": 0, "cached_input_tokens": 0, "cache_write_input_tokens": 0,
              "output_tokens": 5, "total_tokens": 5}
        with open(b_path, "a") as fh:
            fh.write(json.dumps({"timestamp": iso_at(now, 5 * 60), "type": "event_msg",
                                 "payload": {"type": "token_count",
                                             "info": {"total_token_usage": ev, "last_token_usage": ev},
                                             "rate_limits": None}}) + "\n")
        rows = cxa.collect(now)["rows"]
        _ae(aggregate(rows, now - 5 * 3600, now)["gpt-5.6-terra"]["total"], 165, "append adds exactly the new event")
    case("codex watch re-read/append", _codex_reread)

    def _grow_rewrite():
        # grow-rewrite with a CHANGED prefix must re-read from 0 (r8 gate fix)
        def rw_line(tid, i, o):
            return json.dumps({"type": "assistant", "timestamp": "2026-09-20T17:50:00Z",
                               "requestId": tid, "cwd": "/w/rw",
                               "message": {"id": tid + "m", "model": "claude-rw",
                                           "usage": {"input_tokens": i, "output_tokens": o}}})
        s3 = os.path.join(fx["claude_root"], "projects", "proj-c", "s3.jsonl")
        ca2 = ClaudeAdapter(root=fx["claude_root"])
        first = ca2.collect(now)
        _ae(aggregate(first["rows"], now - 5 * 3600, now)["claude-rw"]["tin"], 10, "fixture baseline")
        with open(s3, "w") as fh:  # rewritten prefix + extra line -> file GROWS
            fh.write(rw_line("rc2", 30, 30) + "\n" + rw_line("rc3", 40, 40) + "\n")
        agg = aggregate(ca2.collect(now)["rows"], now - 5 * 3600, now)["claude-rw"]
        _ae(agg["tin"], 80, "no dropped prefix: both new lines counted (stale rc1 lingers in-process)")
        _ae(agg["count"], 3, "rc1+rc2+rc3 present in the running process")
        fresh = ClaudeAdapter(root=fx["claude_root"]).collect(now)  # one-shot view = on-disk truth
        _ae(aggregate(fresh["rows"], now - 5 * 3600, now)["claude-rw"]["tin"], 70,
            "fresh process matches the rewritten file exactly")
        with open(s3, "w") as fh:  # same-size rewrite: rc2 usage digits swapped, same byte length
            fh.write(rw_line("rc2", 31, 30) + "\n" + rw_line("rc3", 40, 40) + "\n")
        agg = aggregate(ca2.collect(now)["rows"], now - 5 * 3600, now)["claude-rw"]
        _ae(agg["tin"], 81, "same-size rewrite detected via tail fingerprint (dedup updated)")
        # codex grow-rewrite: changed prefix + appended event on rollout-g
        g_path = os.path.join(fx["codex_root"], "sessions", "2026", "09", "20", "rollout-g.jsonl")
        ev2 = {"input_tokens": 200, "cached_input_tokens": 0, "cache_write_input_tokens": 0,
               "output_tokens": 0, "total_tokens": 200}
        ev3 = {"input_tokens": 1, "cached_input_tokens": 0, "cache_write_input_tokens": 0,
               "output_tokens": 0, "total_tokens": 1}
        with open(g_path, "w") as fh:
            out = [json.dumps({"timestamp": "2026-09-20T14:40:00Z", "type": "session_meta",
                               "payload": {"id": "rollout-g", "cwd": "/w/rw"}}),
                   json.dumps({"timestamp": "2026-09-20T14:40:00Z", "type": "turn_context",
                               "payload": {"model": "gpt-5.6-terra"}})]
            g_rate = {"primary": {"used_percent": 7.0, "window_minutes": 43200, "resets_at": 1792263887},
                      "secondary": {"used_percent": 3.0, "window_minutes": 300, "resets_at": 1792263887},
                      "credits": {"has_credits": False, "unlimited": False, "balance": None}}
            for ts, ev, rate in (("2026-09-20T14:41:00Z", ev2, None), ("2026-09-20T14:42:00Z", ev3, g_rate)):
                out.append(json.dumps({"timestamp": ts, "type": "event_msg",
                                       "payload": {"type": "token_count",
                                                   "info": {"total_token_usage": ev,
                                                            "last_token_usage": ev,
                                                            "model_context_window": 258400},
                                                   "rate_limits": rate}}))
            fh.write("\n".join(out) + "\n")
        rows = cxa.collect(now)["rows"]  # g was 100; now 200+1, prefix changed
        _ae(aggregate(rows, now - 5 * 3600, now)["gpt-5.6-terra"]["total"], 266,
            "codex grow-rewrite replaces session rows (165 - 100 + 201)")
        # a newer PLACEHOLDER rate block (all windows null) must not displace real data
        empty = {"limit_id": "premium", "primary": None, "secondary": None, "credits": None}
        with open(g_path, "a") as fh:
            fh.write(json.dumps({"timestamp": "2026-09-20T14:43:00Z", "type": "event_msg",
                                 "payload": {"type": "token_count", "info": None,
                                             "rate_limits": empty}}) + "\n")
        meta = cxa.collect(now)["meta"]
        _ae(meta["rate_limits"]["primary"]["used_percent"], 7.0,
            "placeholder rate block (null windows) never wins")
        # a credits-bearing block is data too (credits-only accounts must render)
        paid = {"limit_id": "premium", "primary": None, "secondary": None,
                "credits": {"has_credits": True, "unlimited": False, "balance": 42.5}}
        with open(g_path, "a") as fh:
            fh.write(json.dumps({"timestamp": "2026-09-20T14:44:00Z", "type": "event_msg",
                                 "payload": {"type": "token_count", "info": None,
                                             "rate_limits": paid}}) + "\n")
        with open(g_path, "a") as fh:  # and a placeholder AFTER it still can't displace
            fh.write(json.dumps({"timestamp": "2026-09-20T14:45:00Z", "type": "event_msg",
                                 "payload": {"type": "token_count", "info": None,
                                             "rate_limits": empty}}) + "\n")
        meta = cxa.collect(now)["meta"]
        _ae(meta["rate_limits"]["credits"]["balance"], 42.5, "credits-bearing block kept")
        _ae(meta["rate_limits"]["primary"]["used_percent"], 7.0,
            "credits-only update does NOT erase known windows")
        # a newer block carrying ONLY primary must not erase the known secondary
        p_only = {"limit_id": "premium",
                  "primary": {"used_percent": 55.0, "window_minutes": 43200, "resets_at": 1792263887},
                  "secondary": None, "credits": None}
        with open(g_path, "a") as fh:
            fh.write(json.dumps({"timestamp": "2026-09-20T14:46:00Z", "type": "event_msg",
                                 "payload": {"type": "token_count", "info": None,
                                             "rate_limits": p_only}}) + "\n")
        meta = cxa.collect(now)["meta"]
        _ae(meta["rate_limits"]["primary"]["used_percent"], 55.0, "primary-only update wins")
        _ae(meta["rate_limits"]["secondary"]["used_percent"], 3.0, "secondary survives primary-only update")
    case("grow/same-size rewrite detection", _grow_rewrite)

    case("claude dup tie -> earliest ts wins", lambda: (
        _ae(sum(1 for r in ca["rows"] if r["model"] == "claude-3-haiku"), 1, "single row"),
        _ae(aggregate(ca["rows"], now - 5 * 3600, now)["claude-3-haiku"]["tin"], 4,
            "earlier-ts copy (original request time) kept, later same-total copy dropped"),
    ))

    def _render_smoke():
        adapters_f = {"zcode": ZcodeAdapter(db=fx["zcode_db"]),
                      "claude": ClaudeAdapter(root=fx["claude_root"]),
                      "codex": CodexAdapter(root=fx["codex_root"]),
                      "gate": GateAdapter(path=fx["gate"])}

        class Boom:  # pin the --no-quota claim: probe must never be touched
            def get(self, force=False):
                raise AssertionError("probe must not be touched with --no-quota")

        shot = build_snapshot("5h", now, adapters_f, probe=Boom(), no_quota=True)
        _ae("quota" in shot, False, "no-quota snapshot carries no quota")
        # labeled limit windows from the fixture's full rate_limits block (no caps -> GLM hint)
        out0 = "\n".join(render_dashboard(shot, color_on=False, caps={}))
        _ae("  30-day" in out0, True, "codex primary window labeled 30-day")
        _ae("  5-hour " in out0, True, "codex secondary window labeled 5-hour")
        _ae("none exposed by the plan" in out0, True, "GLM uncapped -> honest --cap hint")
        # hostile remote values: render must skip, not crash (guard via _f)
        shot["quota"] = {"five_hour": {"utilization": "high!", "resets_at": None},
                         "seven_day": {"utilization": 43.0, "resets_at": "2026-09-20T21:30:00Z"}}
        shot["providers"]["codex"]["meta"]["rate_limits"] = {
            "primary": {"used_percent": "ninety-nine", "window_minutes": 43200, "resets_at": None}}
        out = "\n".join(render_dashboard(shot, color_on=False, caps={"zcode": 2000}))
        _ae("KIT TOKENS" in out, True, "header renders")
        _ae("43.0%" in out, True, "numeric 7-day quota renders")
        _ae("  5-hour quota" not in out, True, "non-numeric claude quota skipped, no crash")
        _ae("  30-day" not in out, True, "non-numeric codex window skipped, no crash")
        _ae("none exposed by the plan" not in out, True, "capped GLM hides the hint")
        _ae("▓" in out, True, "cap bar renders")
        _ae("  stats " in out, True, "stats line (cache/reason/d2d)")
        _ae("  top " in out, True, "attribution line")
        _ae("  perf " in out, True, "zcode perf line (p50/p95/ttft)")
        # color pass: accents present in color mode, zero ANSI in plain mode
        out_c = "\n".join(render_dashboard(shot, color_on=True, caps={"zcode": 2000}))
        for prov, code in (("zcode", "\033[36m"), ("claude", "\033[35m"), ("codex", "\033[34m")):
            _ae(code in out_c, True, f"{prov} accent renders")
        _ae("\033[32m" in out_c or "\033[33m" in out_c or "\033[31m" in out_c,
            True, "semantic green/amber/red present")
        _ae("\033[" not in out, True, "plain render carries zero ANSI escapes")
    case("render smoke + bad quota types + color", _render_smoke)

    def _caps():
        _ae(parse_caps(["zcode=2e9"])["zcode"], 2_000_000_000, "sci notation")
        try:
            parse_caps(["zocde=100"])
            _ae(True, False, "unknown provider must raise")
        except ValueError:
            pass
    case("cap parsing/validation", _caps)

    # --- gate adapter (local-time ts) ---
    gr = GateAdapter(path=fx["gate"]).collect(now)
    case("gate local-ts windows + null cost", lambda: (
        _ae(gate_totals(gr["rows"], now - 5 * 3600)["count"], 1, "5h count (10:44 local = 16:44Z)"),
        _ae(gate_totals(gr["rows"], now - 5 * 3600)["cost_usd"], 0.5, "5h cost, null-safe"),
        _ae(gate_totals(gr["rows"], now - 7 * DAY)["count"], 3, "7d count"),
        _ae(gate_totals(gr["rows"], now - 7 * DAY)["cost_usd"], 2.5, "7d cost"),
    ))
    case("gate footer extras", lambda: (
        _ae(gate_totals(gr["rows"], now - 5 * 3600)["approved_pct"], 100.0, "5h approved"),
        _ae(gate_totals(gr["rows"], now - 5 * 3600)["avg_ms"], 30000, "5h avg duration"),
        _ae(gate_totals(gr["rows"], now - 5 * 3600)["top_repo"], "ancuria", "5h top repo"),
        _ae(gate_totals(gr["rows"], now - 7 * DAY)["approved_pct"], 67.0, "7d approved (2/3)"),
        _ae(gate_totals(gr["rows"], now - 7 * DAY)["avg_ms"], 30000, "7d avg duration"),
    ))

    # --- tz boundary: rows either side of LOCAL midnight, machine-agnostic ---
    def _tz_boundary():
        local = datetime.now().astimezone()
        midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
        now = (midnight + timedelta(hours=12)).timestamp()  # synthetic local noon
        r_in = naive_local_to_epoch((midnight + timedelta(hours=11, minutes=30)).strftime("%Y-%m-%dT%H:%M:%S"))
        r_out = naive_local_to_epoch((midnight - timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%S"))
        rows = [{"ts": r_in, "j": {}}, {"ts": r_out, "j": {}}]
        _ae(gate_totals(rows, window_start("today", now))["count"], 1, "today window splits at local midnight")
        off = local.utcoffset().total_seconds() / 3600
        print(f"  (info) machine tz {off:+g}h — gate-log naive ts parsed as system-local")
    case("tz boundary local-midnight", _tz_boundary)

    def _kit_gate_schema():
        # exactly what rig-lite/gate.sh writes: UTC 'Z' ts, NO token/cost fields
        p2 = os.path.join(tmp, "kit-gate-log.jsonl")
        with open(p2, "w") as fh:
            fh.write(json.dumps({"ts": "2026-09-20T17:30:00Z", "repo": "turbo-flow",
                                 "target": "pr#9", "reviewer": "claude",
                                 "result": "GATE: APPROVED"}) + "\n")
            # hostile shapes: non-string result, list repo, plus a non-object line
            fh.write(json.dumps({"ts": "2026-09-20T17:40:00Z", "repo": ["evil"],
                                 "result": 1, "reviewer": None}) + "\n")
            fh.write(json.dumps(["gate", "log", "array"]) + "\n")
        krows = GateAdapter(path=p2).collect(now)["rows"]
        gt = gate_totals(krows, window_start("5h", now))
        _ae(gt["count"], 2, "kit schema: UTC-Z ts counted; hostile rows survive")
        _ae(gt["approved_pct"], 50, "kit schema: approved parsed from result; non-string coerces clean")
        _ae(gt["in"], 0, "kit schema: absent token fields read as 0, no crash")
        _ae(gt["cost_usd"], 0.0, "kit schema: absent cost read as 0.0")
        _ae(isinstance(gt["top_repo"], str), True, "kit schema: list repo coerced to hashable str")
    case("gate adapter reads kit-gate schema (UTC-Z, minimal fields)", _kit_gate_schema)

    def _probe_shapes():
        import subprocess as _sp
        class _R:
            def __init__(self, stdout): self.stdout = stdout
        orig_run = _sp.run
        orig_plat = sys.platform
        orig_which = shutil.which
        try:
            # 1st call = keystore, 2nd = endpoint. platform+which pinned so the
            # case exercises the same code path on Linux CI / the devcontainer.
            seq = [_R('{"claudeAiOauth": "not-a-dict"}'),
                   _R('{"claudeAiOauth": {"accessToken": "tok123"}}'),
                   _R('{"five_hour": "n/a", "seven_day": [1, 2]}')]
            _sp.run = lambda *a, **k: seq.pop(0)
            sys.platform = "darwin"
            shutil.which = lambda n: "/usr/bin/" + n
            qp = QuotaProbe()
            _ae(qp.get(force=True), None, "probe: keystore shape garbage -> None, no crash")
            v = qp.get(force=True)
            _ae(isinstance(v, dict), True, "probe: endpoint shape garbage -> degraded dict, no crash")
            _ae(v.get("five_hour", {}).get("utilization"), None, "probe: non-dict block reads as absent")
        finally:
            _sp.run = orig_run
            sys.platform = orig_plat
            shutil.which = orig_which
    case("quota probe survives malformed keystore/endpoint shapes", _probe_shapes)

    def _codex_malformed():
        allrows = CodexAdapter(root=os.path.join(tmp, "codex")).collect(now)["rows"]
        outside = [r for r in allrows if r["ts"] < window_start("30d", now)]
        _ae(len(outside), 1, "codex malformed: string-token row num()-coerced (old ts, outside windows)")
        _ae(all(isinstance(r.get("total"), (int, float)) for r in allrows), True,
            "codex malformed: every total numeric — no string reaches aggregate()")
        again = CodexAdapter(root=os.path.join(tmp, "codex")).collect(now)["rows"]
        _ae(all(isinstance(r.get("total"), (int, float)) for r in again), True,
            "codex malformed: re-collect stable (no stale-skip crash loop)")
    case("codex adapter survives malformed shapes (strings, non-dict payload, array)", _codex_malformed)

    # --- helpers ---
    case("fmt helpers", lambda: (
        _ae(fmt_tok(262800000), "262.8M", "fmt M"),
        _ae(fmt_tok(564000), "564.0K", "fmt K"),
        _ae(fmt_dur(7500), "2h05m", "fmt dur"),
    ))
    case("window labels", lambda: (
        _ae(fmt_window(60), "hourly", "hourly"),
        _ae(fmt_window(300), "5-hour", "5-hour"),
        _ae(fmt_window(1440), "daily", "daily"),
        _ae(fmt_window(10080), "weekly", "weekly"),
        _ae(fmt_window(43200), "30-day", "30-day"),
        _ae(fmt_window(2880), "2-day", "2-day"),
        _ae(fmt_window("x"), None, "garbage -> None"),
        _ae(fmt_window(None), None, "absent -> None"),
    ))
    case("bar math", lambda: _ae(bar(42.5, 12, False).count("▓"), 5, "filled cells"))
    case("num null-safety", lambda: _ae(num(None) + num("x") + num(2), 2.0, "num"))

    print(f"selftest: {len(checks)}/{len(checks)} cases PASS")
    return 0


def iso_at(now_epoch, seconds_ago):
    """Epoch -> ISO-8601 Z (selftest helper for event timestamps)."""
    return datetime.fromtimestamp(now_epoch - seconds_ago, timezone.utc).isoformat().replace("+00:00", "Z")


def _ae(got, want, what):
    if got != want:
        raise AssertionError(f"{what}: got {got!r} want {want!r}")


# ---------- main ----------

class Parser(argparse.ArgumentParser):
    def error(self, message):  # exit 1 on usage errors (2 is reserved for degraded)
        self.print_usage(sys.stderr)
        print(f"tokens.py: error: {message}", file=sys.stderr)
        sys.exit(1)


def main(argv=None):
    ap = Parser(description="rig token usage dashboard (read-only)")
    ap.add_argument("--watch", nargs="?", const=2.0, type=float, metavar="SEC",
                    help="live view, refresh every SEC seconds (default 2)")
    ap.add_argument("--since", choices=[w[0] for w in WINDOWS] + ["24h"], default="5h",
                    help="window: 30m | 1h | 2h | 5h | today | 7d | 30d (24h = today)")
    ap.add_argument("--json", action="store_true", help="machine snapshot")
    ap.add_argument("--no-quota", action="store_true", help="skip Keychain + network")
    ap.add_argument("--color", choices=["auto", "always", "never"], default="auto",
                    help="ANSI color: auto (tty, honors NO_COLOR) | always | never")
    ap.add_argument("--cap", action="append", default=[], metavar="PROV=TOKENS",
                    help="manual cap, e.g. zcode=2000000000 (repeatable)")
    ap.add_argument("--selftest", action="store_true", help="run fixture golden tests")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    if args.since == "24h":  # legacy alias
        args.since = "today"

    caps = {}
    try:
        caps = parse_caps(args.cap)
    except ValueError as e:
        ap.error(str(e))

    adapters = {"zcode": ZcodeAdapter(), "claude": ClaudeAdapter(),
                "codex": CodexAdapter(), "gate": GateAdapter()}
    probe = QuotaProbe()

    if args.watch is not None:
        if args.watch <= 0:
            print("tokens: --watch needs a positive refresh interval (seconds)", file=sys.stderr)
            return 1
        return watch_loop(args.since, args.watch, adapters, probe, caps, args.json,
                          args.no_quota, args.color)

    shot = build_snapshot(args.since, time.time(), adapters, probe, args.no_quota)
    if args.json:
        print(json.dumps(shot, indent=2))
    else:
        color = color_enabled(args.color)
        print("\n".join(render_dashboard(shot, color, caps)))
    return 2 if shot.get("degraded") else 0


if __name__ == "__main__":
    sys.exit(main())
