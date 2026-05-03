#!/usr/bin/env python3
"""Convert OpenAPI 3.0 `nullable: true` to OpenAPI 3.1 `type: [..., "null"]`.

Handles three patterns:

1. Block form:
       foo:
         type: string
         nullable: true
   →
       foo:
         type: [string, "null"]

2. Inline form:
       foo: { type: string, nullable: true }
   →
       foo: { type: [string, "null"] }

3. Inline with extra keys:
       foo: { type: string, format: date-time, nullable: true }
   →
       foo: { type: [string, "null"], format: date-time }

Idempotent. Run from repo root: `python3 scripts/openapi_nullable_fix.py`.
"""
import re
import sys
from pathlib import Path

SPEC = Path("docs/backend/openapi.yaml")


def fix_inline(line: str) -> str:
    # Match `{ ... type: <T>, ... nullable: true ... }`
    m = re.match(r"^(\s*\S+:\s*\{)\s*(.*)\s*\}\s*$", line)
    if not m:
        return line
    head, inner = m.group(1), m.group(2)
    parts = [p.strip() for p in inner.split(",")]
    if not any(p == "nullable: true" for p in parts):
        return line
    # Drop nullable, find type
    parts = [p for p in parts if p != "nullable: true"]
    new_parts = []
    for p in parts:
        m2 = re.match(r"^type:\s*(\S+)$", p)
        if m2 and not m2.group(1).startswith("["):
            new_parts.append(f'type: [{m2.group(1)}, "null"]')
        else:
            new_parts.append(p)
    return f"{head} {', '.join(new_parts)} }}\n"


def fix_block(lines: list[str]) -> list[str]:
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # Look for `nullable: true` and walk back to find the sibling `type:` at same indent.
        m = re.match(r"^(\s+)nullable:\s*true\s*$", line)
        if m:
            indent = m.group(1)
            # Walk back through `out` for a line `<indent>type: <T>`
            patched = False
            for j in range(len(out) - 1, -1, -1):
                prev = out[j]
                # Stop if we leave the same indent block
                prev_indent_m = re.match(r"^(\s*)\S", prev)
                if prev_indent_m and len(prev_indent_m.group(1)) < len(indent):
                    break
                if prev_indent_m and len(prev_indent_m.group(1)) == len(indent):
                    tm = re.match(rf"^{indent}type:\s*(\S+)\s*$", prev)
                    if tm and not tm.group(1).startswith("["):
                        out[j] = f'{indent}type: [{tm.group(1)}, "null"]\n'
                        patched = True
                        break
            if patched:
                # Skip the `nullable: true` line
                i += 1
                continue
            else:
                # Couldn't find a sibling `type:` — leave the line; lint will surface it.
                out.append(line)
                i += 1
                continue

        # Inline form
        if "nullable: true" in line and "{" in line:
            line = fix_inline(line)
        out.append(line)
        i += 1
    return out


def main() -> int:
    text = SPEC.read_text()
    lines = text.splitlines(keepends=True)
    new_lines = fix_block(lines)
    new_text = "".join(new_lines)
    if new_text == text:
        print("No changes.")
        return 0
    SPEC.write_text(new_text)
    before = text.count("nullable: true")
    after = new_text.count("nullable: true")
    print(f"Patched: {before - after} sites; {after} remaining.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
