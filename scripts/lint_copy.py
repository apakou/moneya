#!/usr/bin/env python3
"""Stablecoin-invisibility copy lint (plan §1.1, ticket INV-02).

MoneyA users must never learn that stablecoins or a blockchain are used. This
fails (exit 1) if user-facing copy or imagery reveals it:

  1. every string in lib/l10n/*.arb (values AND @metadata descriptions),
  2. every Dart string literal under lib/ (comments are ignored; import/export/
     part directives are skipped; lib/l10n/generated is skipped),
  3. asset file names under assets/.

Reviewed exceptions go in scripts/lint_copy_allow.txt, one per line:
    <repo-relative-path>::<exact literal or arb value>
Lines starting with # are comments.

Usage: python3 scripts/lint_copy.py [repo_root]
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

TERM = re.compile(
    r"\b(usdc|usd\s*coin|stablecoins?|solana|stellar|xlm|lumens?|blockchain|"
    r"crypto(?:currency|currencies)?|on-?chain|wallets?|gas\s+fees?)\b",
    re.IGNORECASE,
)
ASSET_TERM = re.compile(
    r"(usd[\s_-]*coin|usdc|stablecoin|crypto|blockchain|bitcoin|ethereum|solana|stellar)",
    re.IGNORECASE,
)


def load_allow(root: Path) -> set[tuple[str, str]]:
    path = root / "scripts" / "lint_copy_allow.txt"
    allow: set[tuple[str, str]] = set()
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "::" in line:
                file, literal = line.split("::", 1)
                allow.add((file.strip(), literal))
    return allow


def strings_in_json(node, out: list[str]) -> None:
    if isinstance(node, str):
        out.append(node)
    elif isinstance(node, dict):
        for value in node.values():
            strings_in_json(value, out)
    elif isinstance(node, list):
        for value in node:
            strings_in_json(value, out)


def dart_literals(source: str):
    """Yield (line_number, literal_text) for each string literal, skipping comments."""
    i, n, line = 0, len(source), 1
    while i < n:
        c = source[i]
        if c == "\n":
            line += 1
            i += 1
        elif source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
        elif source.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    if source[i] == "\n":
                        line += 1
                    i += 1
        elif c in "'\"":
            raw = i > 0 and source[i - 1] == "r"
            quote = source[i : i + 3] if source.startswith(c * 3, i) else c
            start_line = line
            i += len(quote)
            buf = []
            while i < n and not source.startswith(quote, i):
                if source[i] == "\\" and not raw and i + 1 < n:
                    buf.append(source[i : i + 2])
                    if source[i + 1] == "\n":
                        line += 1
                    i += 2
                    continue
                if source[i] == "\n":
                    line += 1
                buf.append(source[i])
                i += 1
            i += len(quote)
            yield start_line, "".join(buf)
        else:
            i += 1


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    allow = load_allow(root)
    problems: list[str] = []

    def check(rel: str, where: str, text: str) -> None:
        match = TERM.search(text)
        if match and (rel, text) not in allow:
            snippet = text if len(text) <= 80 else text[:77] + "..."
            problems.append(f"{rel}:{where}: forbidden term '{match.group(0)}' in: {snippet!r}")

    for arb in sorted((root / "lib" / "l10n").glob("*.arb")):
        rel = arb.relative_to(root).as_posix()
        texts: list[str] = []
        strings_in_json(json.loads(arb.read_text(encoding="utf-8")), texts)
        for text in texts:
            check(rel, "arb", text)

    for dart in sorted((root / "lib").rglob("*.dart")):
        rel = dart.relative_to(root).as_posix()
        if rel.startswith("lib/l10n/generated/"):
            continue
        source = dart.read_text(encoding="utf-8")
        directive_lines = {
            number
            for number, text in enumerate(source.splitlines(), start=1)
            if re.match(r"\s*(import|export|part)\s", text)
        }
        for line, literal in dart_literals(source):
            if line in directive_lines or literal.startswith("assets/"):
                continue  # asset paths are not copy; asset NAMES are checked below
            check(rel, str(line), literal)

    assets = root / "assets"
    if assets.exists():
        for asset in sorted(p for p in assets.rglob("*") if p.is_file()):
            rel = asset.relative_to(root).as_posix()
            if ASSET_TERM.search(asset.name) and (rel, asset.name) not in allow:
                problems.append(f"{rel}: asset name reveals a forbidden concept")

    if problems:
        print("Stablecoin-invisibility lint FAILED:\n", file=sys.stderr)
        print("\n".join(problems), file=sys.stderr)
        print(f"\n{len(problems)} problem(s). See docs/backend/stellar-mvp-plan.md §1.1.", file=sys.stderr)
        return 1
    print("Stablecoin-invisibility lint passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
