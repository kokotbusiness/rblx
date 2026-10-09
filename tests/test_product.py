"""Runs the Roblox kit's own checks (Luau unit tests, strict type checks).
Skipped - and reported as skipped, not passed - when the free tools are not
installed (run tools/setup_dev_tools.sh). This is NOT a Roblox Studio test."""
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "products" / "roblox-creator-starter-kit"


class ProductChecks(unittest.TestCase):
    def test_kit_files_exist(self):
        for rel in ["README.md", "LICENSE.txt", "default.project.json", "src/Shared/KitConfig.luau",
                    "src/Server/StarterKitService.luau", "src/Client/StarterKitClient.client.luau",
                    "docs/STUDIO_TEST_CHECKLIST.md", "tests/run.luau"]:
            self.assertTrue((KIT / rel).exists(), rel)

    def test_kit_build_checks(self):
        if not (ROOT / ".tools" / "luau" / "luau").exists():
            self.skipTest("Luau tools not installed - run ./tools/setup_dev_tools.sh")
        p = subprocess.run([sys.executable, str(KIT / "tools" / "build.py"), "--check"],
                           capture_output=True, text=True, timeout=300)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertNotIn("[SKIPPED]", p.stdout, "a check was skipped")


if __name__ == "__main__":
    unittest.main()
