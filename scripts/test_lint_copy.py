"""Self-test for scripts/lint_copy.py. Run: python3 scripts/test_lint_copy.py"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LINT = Path(__file__).with_name("lint_copy.py")


def run(files: dict[str, str]) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "lib" / "l10n").mkdir(parents=True)
        (root / "scripts").mkdir()
        for rel, content in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(LINT), str(root)], capture_output=True, text=True
        )


class LintCopyTest(unittest.TestCase):
    def test_clean_project_passes(self):
        r = run({
            "lib/l10n/app_en.arb": json.dumps({"hello": "Send money", "@hello": {"description": "Greeting"}}),
            "lib/a.dart": "import 'package:crypto/crypto.dart';\nfinal s = 'Your MoneyA balance';\n// USDC in a comment is ignored\n",
        })
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_arb_value_and_description_are_checked(self):
        r = run({"lib/l10n/app_en.arb": json.dumps({"k": "Pay in USDC", "@k": {"description": "wallet text"}})})
        self.assertEqual(r.returncode, 1)
        self.assertIn("USDC", r.stderr)
        self.assertIn("wallet", r.stderr)

    def test_dart_literal_is_checked_but_comments_are_not(self):
        r = run({"lib/a.dart": "// stellar\nconst t = 'Powered by Stellar';\n"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("a.dart:2", r.stderr)
        self.assertNotIn("a.dart:1", r.stderr)

    def test_multiline_and_double_quoted_and_adjacent_strings(self):
        r = run({"lib/a.dart": "const a = \"x\"\n    'on the blockchain';\n"})
        self.assertEqual(r.returncode, 1)

    def test_asset_name_is_checked_but_asset_path_literals_are_not(self):
        r = run({"assets/images/USD Coin_3D.png": "", "lib/a.dart": "const p = 'assets/images/Coin Wallet.png';\n"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("asset name", r.stderr)
        self.assertNotIn("a.dart", r.stderr)

    def test_reviewed_exception_is_honoured(self):
        r = run({
            "lib/a.dart": "const t = 'See the Stellar terms';\n",
            "scripts/lint_copy_allow.txt": "lib/a.dart::See the Stellar terms\n",
        })
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_word_boundaries_avoid_false_positives(self):
        r = run({"lib/a.dart": "const t = 'cryptic stellarated gasoline';\n"})
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
