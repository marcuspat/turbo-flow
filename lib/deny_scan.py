#!/usr/bin/env python3
"""Deny scan gate — Turbo Brain (D8 Layer 1).

Blocks client material from entering the vault. Reads a CLIENTS.deny file:
one term per line, '#' comments. Terms are matched case-insensitively on
word boundaries; a term containing '.' is also matched as a bare substring.

Usage:
    deny_scan.py --deny CLIENTS.deny FILE [FILE...]
    deny_scan.py --deny CLIENTS.deny --quarantine DIR FILE [FILE...]

Exit 0 = clean. Exit 1 = hits (files moved if --quarantine given).
Exit 2 = deny-list missing. Exit 3 = deny-list present but EMPTY.
"""
import argparse
import os
import re
import shutil
import sys


def load_terms(path):
    terms = []
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            t = line.split("#", 1)[0].strip()
            if t:
                terms.append(t)
    return terms


def build_matchers(terms):
    out = []
    for t in terms:
        if "." in t or "/" in t:
            out.append((t, re.compile(re.escape(t), re.I)))
        else:
            out.append((t, re.compile(r"\b" + re.escape(t) + r"\b", re.I)))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--deny", required=True)
    ap.add_argument("--quarantine")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args(argv)

    if not os.path.exists(a.deny):
        sys.stderr.write(f"DENY-SCAN: deny-list missing: {a.deny}\n")
        return 2

    matchers = build_matchers(load_terms(a.deny))
    if not matchers:
        sys.stderr.write(
            f"DENY-SCAN: {a.deny} has zero terms — refusing to pass vacuously.\n"
            "  An empty deny-list checks nothing while reporting green.\n"
            "  Populate it with client names, domains, and repo slugs.\n")
        return 3

    hits = {}
    for f in a.files:
        if not os.path.isfile(f):
            continue
        with open(f, "r", errors="replace") as fh:
            text = fh.read()
        found = sorted({term for term, rx in matchers if rx.search(text)})
        if found:
            hits[f] = found

    if not hits:
        return 0

    sys.stderr.write("DENY-SCAN: client material detected\n")
    for f, terms in hits.items():
        sys.stderr.write(f"  {f}  ->  {', '.join(terms)}\n")
        if a.quarantine:
            os.makedirs(a.quarantine, exist_ok=True)
            dest = os.path.join(a.quarantine, os.path.basename(f))
            n = 1
            while os.path.exists(dest):
                base, ext = os.path.splitext(os.path.basename(f))
                dest = os.path.join(a.quarantine, f"{base}.{n}{ext}")
                n += 1
            shutil.move(f, dest)
            sys.stderr.write(f"    quarantined -> {dest}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
