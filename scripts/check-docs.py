#!/usr/bin/env python3

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
ROOT_README = ROOT / "README.md"

ROOT_RULES = {
    "journal-style section": re.compile(
        r"^##\s+(?:Status|Current Progress|Progress|Next|Roadmap)\b",
        re.IGNORECASE | re.MULTILINE,
    ),
    "public-log framing": re.compile(r"\bpublic log\b", re.IGNORECASE),
    "time-bound framing": re.compile(r"\bcoming months\b", re.IGNORECASE),
}

INLINE_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


def markdown_files():
    for path in sorted(ROOT.rglob("*.md")):
        relative = path.relative_to(ROOT)
        if ".git" in relative.parts or relative.parts[0] == "archive":
            continue
        yield path


def link_target(raw_target):
    target = raw_target.strip()
    if target.startswith("<") and ">" in target:
        return target[1 : target.index(">")]
    return target.split(maxsplit=1)[0]


def main():
    errors = []
    root_text = ROOT_README.read_text(encoding="utf-8")

    for name, pattern in ROOT_RULES.items():
        for match in pattern.finditer(root_text):
            line = root_text.count("\n", 0, match.start()) + 1
            errors.append(f"README.md:{line}: {name}: {match.group(0)!r}")

    checked = 0
    for path in markdown_files():
        checked += 1
        text = path.read_text(encoding="utf-8")
        for match in INLINE_LINK.finditer(text):
            target = link_target(match.group(1))
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or target.startswith("#"):
                continue

            link_path = unquote(parsed.path)
            if not link_path:
                continue

            if link_path.startswith("/"):
                destination = ROOT / link_path.lstrip("/")
            else:
                destination = path.parent / link_path

            if not destination.exists():
                line = text.count("\n", 0, match.start()) + 1
                relative = path.relative_to(ROOT)
                errors.append(
                    f"{relative}:{line}: missing relative link target: {link_path}"
                )

    if errors:
        print("Documentation checks failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Documentation checks passed for {checked} active Markdown files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
