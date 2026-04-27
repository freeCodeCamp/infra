#!/usr/bin/env python3
"""trim-field-notes — archive dated journal entries older than N days.

Usage:
    scripts/trim-field-notes.py <field-notes.md> [--age-days N] [--dry-run] [--list]

Per `docs/GUIDELINES.md` §Monthly doc trim. Idempotent. Operates only on
canonical journal entries with the heading shape:

    ### YYYY-MM-DD — <title>

Older non-canonical sections (e.g. `## Operational Findings`,
`## Pitfalls Reference`) are NOT touched — those need manual distillation
into the Invariants block per the monthly-trim ritual.

Output:
    - rewrites <field-notes.md> in place, dropping archived entries
    - writes (or appends to) <dir>/journal-archive/YYYY-MM.md per bucket

Exit codes:
    0  success (or no-op when nothing aged out)
    1  bad input
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

ENTRY_RE = re.compile(r"^### (\d{4}-\d{2}-\d{2}) — (.+)$", re.MULTILINE)


def split_entries(text: str):
    """Yield (start, end, date_str, title) for each canonical journal entry."""
    matches = list(ENTRY_RE.finditer(text))
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        yield m.start(), end, m.group(1), m.group(2).rstrip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("file", type=Path, help="field-notes markdown file")
    ap.add_argument(
        "--age-days",
        type=int,
        default=30,
        help="archive entries older than this many days (default: 30)",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="print plan; do not write",
    )
    ap.add_argument(
        "--list",
        action="store_true",
        help="list canonical journal entries with ages; no writes",
    )
    args = ap.parse_args()

    if not args.file.is_file():
        print(f"error: not a file: {args.file}", file=sys.stderr)
        return 1

    text = args.file.read_text()
    cutoff = date.today() - timedelta(days=args.age_days)
    archive_dir = args.file.parent / "journal-archive"

    entries = list(split_entries(text))
    if not entries:
        print(f"no canonical journal entries found in {args.file}", file=sys.stderr)
        return 0

    if args.list:
        today = date.today()
        for _, _, date_str, title in entries:
            age = (today - date.fromisoformat(date_str)).days
            print(f"  {date_str}  ({age:>4}d)  {title}")
        return 0

    archive_buckets: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
    new_text = text[: entries[0][0]]
    last_pos = entries[0][0]

    for start, end, date_str, title in entries:
        entry_date = date.fromisoformat(date_str)
        if entry_date < cutoff:
            month = date_str[:7]
            archive_buckets[month].append((date_str, title, text[start:end]))
            new_text += text[last_pos:start]
        else:
            new_text += text[last_pos:end]
        last_pos = end
    new_text += text[last_pos:]

    if not archive_buckets:
        print(f"no entries older than {args.age_days} days. nothing to do.")
        return 0

    print(f"plan (cutoff {cutoff.isoformat()}, --age-days {args.age_days}):")
    for month in sorted(archive_buckets):
        bucket = archive_buckets[month]
        print(f"  → {archive_dir}/{month}.md  ({len(bucket)} entries)")
        for date_str, title, _ in bucket:
            print(f"      • {date_str} — {title}")
    src_lines = len(text.splitlines())
    dst_lines = len(new_text.splitlines())
    print(
        f"  → rewrite {args.file}  "
        f"({src_lines} → {dst_lines} lines, "
        f"{len(text)} → {len(new_text)} bytes)"
    )

    if args.dry_run:
        print("(dry-run; no writes)")
        return 0

    archive_dir.mkdir(exist_ok=True)
    for month, items in sorted(archive_buckets.items()):
        path = archive_dir / f"{month}.md"
        if path.exists():
            existing = path.read_text()
            if not existing.endswith("\n"):
                existing += "\n"
        else:
            existing = (
                f"# Journal Archive — {month}\n\n"
                f"Moved from `{args.file.name}` per "
                f"`docs/GUIDELINES.md` §Monthly doc trim. Append-only.\n\n"
            )
        path.write_text(existing + "".join(body for _, _, body in items))
        print(f"  wrote {path}")

    args.file.write_text(new_text)
    print(f"  wrote {args.file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
