#!/usr/bin/env python3
"""Keep supabase/migrations/ in sync with docs/backend/migrations/ (the single source of truth).

`supabase db push` wants `<timestamp>_<name>.sql` files in supabase/migrations/. We keep the numbered
files in docs/backend/migrations/ authoritative (that is what the docs, CI and the backend tests use)
and generate the timestamped copies. A fixed timestamp per number keeps the order stable and the
generated names deterministic.

    python3 scripts/sync_supabase_migrations.py           # (re)generate
    python3 scripts/sync_supabase_migrations.py --check   # exit 1 if they differ (CI)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "backend" / "migrations"
DST = ROOT / "supabase" / "migrations"
BASE = 20261010000000  # 0001 -> 20261010000001, 0002 -> 20261010000002, ...


def expected() -> dict[str, str]:
    out = {}
    for f in sorted(SRC.glob("[0-9][0-9][0-9][0-9]_*.sql")):
        m = re.match(r"(\d{4})_(.+)\.sql$", f.name)
        assert m, f.name
        out[f"{BASE + int(m.group(1))}_{m.group(2)}.sql"] = f.read_text()
    return out


def main() -> int:
    want = expected()
    have = {f.name: f.read_text() for f in DST.glob("*.sql")} if DST.exists() else {}
    if "--check" in sys.argv:
        problems = [f"missing or different: {n}" for n, t in want.items() if have.get(n) != t]
        problems += [f"stale (no source): {n}" for n in have if n not in want]
        for p in problems:
            print(p)
        if problems:
            print("Run: python3 scripts/sync_supabase_migrations.py")
        return 1 if problems else 0
    DST.mkdir(parents=True, exist_ok=True)
    for n in have:
        if n not in want:
            (DST / n).unlink()
    for n, t in want.items():
        (DST / n).write_text(t)
    print(f"synced {len(want)} migrations into {DST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
