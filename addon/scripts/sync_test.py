"""sync.sh links every addon folder into the game's AddOns folder."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent


class SyncTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="everlook-sync-")
        self.addCleanup(temporary.cleanup)
        base = Path(temporary.name)
        self.addon = base / "repo with spaces" / "addon"
        self.core = self.addon / "Everlook"
        self.module = self.addon / "Everlook_SellJunk"
        for folder in (self.addon / "scripts", self.core, self.module):
            folder.mkdir(parents=True)
        (self.core / "Everlook.toc").write_text("## Interface: 16001\n")
        (self.module / "Everlook_SellJunk.toc").write_text("## Interface: 16001\n")
        shutil.copyfile(SCRIPTS / "sync.sh", self.addon / "scripts" / "sync.sh")
        self.addons = base / "game with spaces" / "AddOns"
        self.destination = self.addons / "Everlook"

    def sync(self):
        result = subprocess.run(
            ["bash", str(self.addon / "scripts" / "sync.sh")],
            capture_output=True, text=True, env={**os.environ, "EVERLOOK_ADDONS_DIR": str(self.addons)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_creates_symlink(self):
        self.sync()
        self.assertTrue(self.destination.is_symlink())
        self.assertEqual(self.destination.resolve(), self.core)

    def test_links_every_module_folder(self):
        self.sync()
        linked = self.addons / "Everlook_SellJunk"
        self.assertTrue(linked.is_symlink())
        self.assertEqual(linked.resolve(), self.module)

    def test_backs_up_a_real_module_folder(self):
        (self.addons / "Everlook_SellJunk").mkdir(parents=True)
        (self.addons / "Everlook_SellJunk" / "old.lua").write_text("old")
        self.sync()
        backups = list(self.addons.glob("Everlook_SellJunk.backup.*/Everlook_SellJunk"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "old.lua").read_text(), "old")
        self.assertTrue((self.addons / "Everlook_SellJunk").is_symlink())

    def test_removes_a_link_whose_module_folder_is_gone(self):
        self.sync()
        dropped = self.addon / "Everlook_Dropped"
        dropped.mkdir()
        (dropped / "Everlook_Dropped.toc").write_text("## Interface: 16001\n")
        self.sync()
        shutil.rmtree(dropped)
        self.sync()
        self.assertFalse(os.path.lexists(self.addons / "Everlook_Dropped"))
        self.assertTrue((self.addons / "Everlook_SellJunk").is_symlink())


if __name__ == "__main__":
    unittest.main()
