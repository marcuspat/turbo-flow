#!/usr/bin/env python3
"""Schema lint — Turbo Brain (D3, refined).

Zero dependencies (hand-rolled frontmatter parse; no PyYAML requirement).

Checks, per curated vault file:
  F1  frontmatter present and closed
  F2  required keys: name, description, sources, sensitivity
  F3  name == path stem
  F4  name unique across the vault
  F5  sensitivity in {private, shareable, public}
  F6  description is one line, <= 200 chars, non-empty
  B1  every body fact line is "- [tag] ..." with tag in {stated,ingested,derived}
  B2  [ingested] carries "(src: ...)"
  B3  [derived] carries "(from: ...)"
  B4  no line exceeds 400 chars (facts stay compact)
  B5  no injection-shaped facts (tripwire, not classifier)
  F7  INDEX.md stays within always-loaded cap (200 lines / 25 KB)
  B6  [superseded] format if present: (superseded YYYY-MM-DD -> ...)
  F8  .turbo-brain.toml schema validation
  L1  every [[wikilink]] resolves to a known name
  L2  every (from: ...) citation resolves to a real vault file

Usage:
    lint.py VAULT_ROOT
    lint.py --json VAULT_ROOT
"""
import json
import os
import re
import sys

CURATED_DIRS = ("profile", "areas", "people", "projects", "topics", "daily")
TAGS = ("stated", "ingested", "derived")
SENS = ("private", "shareable", "public")

FACT = re.compile(r"^- \[(?P<tag>[a-z]+)\]\s+(?P<body>.+)$")
RELATED = re.compile(r"^- Related:\s+")
WIKILINK = re.compile(r"\[\[([^\]]+)\]\]")
FROM_REF = re.compile(r"\(from:\s*([^)]+?)\s*\)")
SUPERSEDED = re.compile(r"\(superseded\s+(\d{4}-\d{2}-\d{2})\s*->\s*([^)]+)\)")
EVENT_DATE = re.compile(r"\((?:event|evt)[:\s]+(\d{4}-\d{2}-\d{2})\)")

# B5 — injection-shaped content. Narrow and high-signal by design.
# Every pattern appears in a demonstrated memory-poisoning attack.
INJECTION = [
    ("instruction-override",
     re.compile(r"(?i)\b(?:ignore|disregard|forget)\b.{0,30}\b(?:previous|prior|all|above|earlier)\b.{0,20}\b(?:instruction|prompt|rule|context)s?\b")),
    ("persona-hijack",
     re.compile(r"(?i)\byou are (?:now|actually|no longer)\b")),
    ("prompt-probe",
     re.compile(r"(?i)\b(?:system prompt|developer message|hidden instruction)s?\b")),
    ("agent-directive",
     re.compile(r"(?i)^\s*-\s*\[[a-z]+\]\s+(?:you (?:must|should|will|need to)|always respond|when(?:ever)? (?:you|the (?:agent|assistant|model)) (?:read|see|encounter))\b")),
    ("exfil-markdown-image",
     re.compile(r"!\[[^\]]*\]\(https?://")),
    ("exfil-url-in-fact",
     re.compile(r"(?i)\b(?:https?://|ftp://)\S+\.(?:com|net|org|io|xyz|top)\b")),
]


def citation_targets(fact):
    """Names cited by a [derived] fact's (from: ...) clause."""
    out = []
    for m in FROM_REF.finditer(fact):
        for part in m.group(1).split(","):
            part = part.strip()
            if not part or part.startswith("[["):
                continue
            stem = os.path.splitext(os.path.basename(part))[0]
            if stem:
                out.append(stem)
    return out


def parse_frontmatter(text):
    """Return (dict, body_lines, body_offset, error_or_None)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, lines, 1, "F1 no frontmatter"
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return {}, lines, 1, "F1 frontmatter not closed"
    fm = {}
    for raw in lines[1:end]:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if ":" not in raw:
            continue
        k, v = raw.split(":", 1)
        v = v.strip()
        if v.startswith("[") and v.endswith("]"):
            v = [x.strip() for x in v[1:-1].split(",") if x.strip()]
        fm[k.strip()] = v
    return fm, lines[end + 1:], end + 2, None


def parse_toml(path):
    """Minimal TOML parser for .turbo-brain.toml. Returns (dict, errors)."""
    errors = []
    data = {}
    try:
        with open(path, "r", errors="replace") as f:
            text = f.read()
    except OSError:
        return None, [f"F8 cannot read {path}"]

    for i, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        m = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$', stripped)
        if not m:
            errors.append(f"F8 {path}:{i}: invalid TOML line")
            continue
        key, val = m.group(1), m.group(2).strip()
        # Strip quotes
        if (val.startswith('"') and val.endswith('"')) or \
           (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        elif val.isdigit():
            val = int(val)
        elif val.lower() in ("true", "false"):
            val = val.lower() == "true"
        data[key] = val

    # Validate required keys
    if "tool_version" not in data:
        errors.append("F8 missing required key: tool_version")
    return data, errors


def lint_file(path, root):
    errs = []
    rel = os.path.relpath(path, root)
    with open(path, "r", errors="replace") as fh:
        text = fh.read()

    fm, body, offset, fmerr = parse_frontmatter(text)
    if fmerr:
        return [(rel, 1, fmerr)], None

    for key in ("name", "description", "sources", "sensitivity"):
        if key not in fm:
            errs.append((rel, 1, f"F2 missing frontmatter key: {key}"))

    stem = os.path.splitext(os.path.basename(path))[0]
    name = fm.get("name")
    if name and name != stem:
        errs.append((rel, 1, f"F3 name '{name}' != path stem '{stem}'"))

    sens = fm.get("sensitivity")
    if sens and sens not in SENS:
        errs.append((rel, 1, f"F5 sensitivity '{sens}' not in {SENS}"))

    desc = fm.get("description")
    if isinstance(desc, str):
        if not desc.strip():
            errs.append((rel, 1, "F6 description empty"))
        elif len(desc) > 200:
            errs.append((rel, 1, f"F6 description {len(desc)} chars (max 200)"))

    links = set()
    cites = []
    fact_count = 0
    for i, line in enumerate(body, offset):
        s = line.rstrip()
        if not s.strip() or s.startswith("#") or s.startswith(">"):
            continue
        if len(s) > 400:
            errs.append((rel, i, f"B4 line {len(s)} chars (max 400)"))
        for iname, irx in INJECTION:
            if irx.search(s):
                errs.append((rel, i, f"B5 injection-shaped content ({iname}) — "
                                     "facts are third-person declaratives, not "
                                     "instructions to a future reader"))
                break
        links |= set(WIKILINK.findall(s))
        if RELATED.match(s):
            continue
        # B6 — superseded format check
        if SUPERSEDED.search(s):
            sm = SUPERSEDED.search(s)
            date_str = sm.group(1)
            try:
                from datetime import date as d
                y, m, d_day = map(int, date_str.split("-"))
                d(y, m, d_day)  # validate
            except (ValueError, OverflowError):
                errs.append((rel, i, f"B6 invalid superseded date: {date_str}"))
            continue
        # Event date validation
        ed = EVENT_DATE.search(s)
        if ed:
            try:
                from datetime import date as d
                y, m, d_day = map(int, ed.group(1).split("-"))
                d(y, m, d_day)
            except (ValueError, OverflowError):
                errs.append((rel, i, f"B6 invalid event date: {ed.group(1)}"))

        m = FACT.match(s)
        if not m:
            errs.append((rel, i, "B1 not a tagged fact line"))
            continue
        fact_count += 1
        tag, fact = m.group("tag"), m.group("body")
        if tag not in TAGS:
            errs.append((rel, i, f"B1 unknown tag [{tag}]"))
        elif tag == "ingested" and "src:" not in fact:
            errs.append((rel, i, "B2 [ingested] missing (src: ...)"))
        elif tag == "derived" and "from:" not in fact:
            errs.append((rel, i, "B3 [derived] missing (from: ...)"))
        elif tag == "derived":
            cites += [(i, c) for c in citation_targets(fact)]

    return errs, (name or stem, rel, links, cites, fact_count)


def main(argv):
    as_json = "--json" in argv
    argv = [a for a in argv if a != "--json"]
    root = argv[0] if argv else "."

    files = []
    for d in CURATED_DIRS:
        dp = os.path.join(root, d)
        if not os.path.isdir(dp):
            continue
        for dirpath, _, names in os.walk(dp):
            files += [os.path.join(dirpath, n) for n in sorted(names)
                      if n.endswith(".md")]

    errs = []

    # F8 — toml schema validation
    toml_path = os.path.join(root, ".turbo-brain.toml")
    if os.path.isfile(toml_path):
        _, toml_errs = parse_toml(toml_path)
        errs += [(f".turbo-brain.toml", 1, e) for e in toml_errs]

    # F7 — always-loaded index cap
    idx = os.path.join(root, "INDEX.md")
    if os.path.isfile(idx):
        with open(idx, "r", errors="replace") as fh:
            itext = fh.read()
        nlines, nbytes = itext.count("\n") + 1, len(itext.encode())
        if nlines > 200:
            errs.append(("INDEX.md", 1, f"F7 index is {nlines} lines (cap 200)"))
        if nbytes > 25 * 1024:
            errs.append(("INDEX.md", 1, f"F7 index is {nbytes} bytes (cap 25600)"))

    names, linkmap = {}, []
    total_facts = 0
    for f in files:
        e, meta = lint_file(f, root)
        errs += e
        if meta:
            n, rel, links, cites, fc = meta
            total_facts += fc
            if n in names:
                errs.append((rel, 1, f"F4 duplicate name '{n}' (also {names[n]})"))
            else:
                names[n] = rel
            linkmap.append((rel, links, cites))

    known_sources = {"ledger", "wa-signal", "cowork", "seed", "intake"}

    for rel, links, cites in linkmap:
        for l in sorted(links):
            if l not in names:
                errs.append((rel, 1, f"L1 unresolved wikilink [[{l}]]"))
        for lineno, c in cites:
            if c not in names and c not in known_sources:
                errs.append((rel, lineno,
                             f"L2 dangling citation (from: {c}) — no such vault file"))

    if as_json:
        result = {
            "files": len(files),
            "total_facts": total_facts,
            "errors": [{"file": f, "line": n, "msg": m} for f, n, m in errs]
        }
        print(json.dumps(result, indent=2))
    else:
        for f, n, m in errs:
            print(f"{f}:{n}: {m}")
        print(f"\nlint: {len(files)} files, {total_facts} facts, {len(errs)} errors")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
