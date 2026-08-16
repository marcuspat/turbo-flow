#!/usr/bin/env python3
"""Secret scan gate — Turbo Brain (D8 Layer 2).

Zero dependencies. Exits 1 on any finding. Never prints the matched secret.

Usage:
    secret_scan.py FILE [FILE...]
    secret_scan.py --staged            # scan git staged content
"""
import base64
import math
import re
import subprocess
import sys

RULES = [
    ("aws-access-key-id", re.compile(r"\b(?:AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}\b"), None),
    ("aws-secret-access-key",
     re.compile(r"(?i)aws.{0,20}?(?:secret|key).{0,5}['\"]([A-Za-z0-9/+=]{40})['\"]"), 4.2),
    ("github-token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}\b"), None),
    ("gitlab-token", re.compile(r"\bglpat-[A-Za-z0-9_\-]{20,}\b"), None),
    ("slack-token", re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}\b"), None),
    ("anthropic-key", re.compile(r"\bsk-ant-[A-Za-z0-9_\-]{20,}\b"), None),
    ("openai-key", re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_\-]{32,}\b"), None),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b"), None),
    ("stripe-key", re.compile(r"\b(?:sk|rk)_(?:live|test)_[0-9A-Za-z]{20,}\b"), None),
    ("private-key-block",
     re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----"), None),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b"), None),
    ("generic-assignment",
     re.compile(r"(?i)\b(?:api[_-]?key|secret|passwd|password|token|bearer)\b\s*[:=]\s*"
                r"['\"]([A-Za-z0-9/+_\-=]{24,})['\"]"), 3.8),
    ("connection-string",
     re.compile(r"\b(?:postgres|postgresql|mysql|mongodb(?:\+srv)?|redis|amqp)://"
                r"[^\s:@/]+:[^\s:@/]{6,}@"), None),
]

ALLOW = re.compile(
    r"(?i)(example|placeholder|redacted|<your|xxxx|\.\.\.\.|dummy|sample|fake|"
    r"changeme|your[_-]?(?:key|token|secret))"
)


def entropy(s: str) -> float:
    if not s:
        return 0.0
    return -sum(
        (n := s.count(c) / len(s)) and n * math.log2(n) for c in set(s)
    )


def scan_text(text: str, label: str):
    findings = []
    for lineno, line in enumerate(text.splitlines(), 1):
        if len(line) > 4000:
            line = line[:4000]
        if ALLOW.search(line):
            continue
        for name, rx, min_ent in RULES:
            m = rx.search(line)
            if not m:
                continue
            if min_ent is not None:
                cap = m.group(1) if m.groups() else m.group(0)
                if entropy(cap) < min_ent:
                    continue
            findings.append((label, lineno, name))
            break
    return findings


def staged_files():
    out = subprocess.run(
        ["git", "diff", "--cached", "name-only", "--diff-filter=ACM"],
        capture_output=True, text=True, check=True).stdout
    return [f for f in out.splitlines() if f.strip()]


def read_staged(path: str) -> str:
    r = subprocess.run(["git", "show", f":{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def main(argv):
    findings = []
    if argv and argv[0] == "--staged":
        for f in staged_files():
            findings += scan_text(read_staged(f), f)
    else:
        for f in argv:
            try:
                with open(f, "r", errors="replace") as fh:
                    findings += scan_text(fh.read(), f)
            except (IsADirectoryError, FileNotFoundError):
                continue
    if findings:
        sys.stderr.write("SECRET-SCAN: blocked\n")
        for label, lineno, name in findings:
            sys.stderr.write(f"  {label}:{lineno}  {name}\n")
        sys.stderr.write("  (values withheld by design)\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
