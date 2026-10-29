from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("check-lock.py")
REPO = Path(__file__).parents[2]

LOCKED_UV = """
[[tools.uv]]
version = "0.13.5"
backend = "aqua:astral-sh/uv"

[tools.uv."platforms.macos-arm64"]
checksum = "sha256:00"
url = "https://example.invalid/uv.tar.gz"
"""


class CheckLockTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def run_check(self, config, lock):
        config_path = self.root / "config.toml"
        lock_path = self.root / "mise.lock"
        config_path.write_text(config, encoding="utf-8")
        lock_path.write_text(lock, encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(config_path), str(lock_path)],
            capture_output=True,
            text=True,
        )

    def test_pinned_and_locked_passes(self):
        result = self.run_check('[tools]\nuv = "0.13.5"\n', LOCKED_UV)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_table_spec_passes(self):
        result = self.run_check('[tools]\nuv = { version = "0.13.5" }\n', LOCKED_UV)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_bump_without_lock_fails(self):
        result = self.run_check('[tools]\nuv = "0.13.6"\n', LOCKED_UV)
        self.assertEqual(result.returncode, 1)
        self.assertIn("uv: 0.13.6 is not locked", result.stderr)

    def test_unpinned_fails(self):
        result = self.run_check('[tools]\nuv = "latest"\n', LOCKED_UV)
        self.assertEqual(result.returncode, 1)
        self.assertIn("uv: latest is not locked", result.stderr)

    def test_missing_checksum_fails(self):
        lock = LOCKED_UV.replace('checksum = "sha256:00"\n', "")
        result = self.run_check('[tools]\nuv = "0.13.5"\n', lock)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no macos-arm64 checksum", result.stderr)

    def test_version_only_backend_passes_without_checksum(self):
        lock = '[[tools."gem:cocoapods"]]\nversion = "1.17.0"\nbackend = "gem:cocoapods"\n'
        result = self.run_check('[tools]\n"gem:cocoapods" = "1.17.0"\n', lock)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_version_only_backend_still_needs_lock_entry(self):
        result = self.run_check('[tools]\n"gem:cocoapods" = "1.17.0"\n', "")
        self.assertEqual(result.returncode, 1)
        self.assertIn("gem:cocoapods: 1.17.0 is not locked", result.stderr)

    def test_stale_lock_entry_fails(self):
        result = self.run_check("[tools]\n", LOCKED_UV)
        self.assertEqual(result.returncode, 1)
        self.assertIn("uv: locked but not configured", result.stderr)

    def test_repository_config_is_locked(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(REPO / "config.toml"), str(REPO / "mise.lock")],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
