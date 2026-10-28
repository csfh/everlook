"""pack.sh builds a release: every addon folder, with the core's version and the license, as a tarball,
a zip and their checksums."""
import hashlib
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPOSITORY = SCRIPTS.parent
ADDON = REPOSITORY / "addon"


class PackTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="everlook-pack-")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.repository = self.base / "repo with spaces"
        self.addon = self.repository / "addon"
        self.core = self.addon / "Everlook"
        self.module = self.addon / "Everlook_SellJunk"
        for folder in (self.repository / "scripts", self.core, self.module):
            folder.mkdir(parents=True)
        (self.core / "Everlook.toc").write_text("## Interface: 16001\n## Title: Everlook\n## Version: 0.1.0\n")
        (self.core / "world.lua").write_text("local _, Everlook = ...\n")
        (self.module / "Everlook_SellJunk.toc").write_text(
            "## Interface: 16001\n## Title: Sell junk\n## Dependencies: Everlook\n\nsell_junk.lua\n")
        (self.module / "sell_junk.lua").write_text("local addon_name = ...\n")
        (self.repository / "LICENSE").write_text("MIT License\n")
        shutil.copyfile(SCRIPTS / "pack.sh", self.repository / "scripts" / "pack.sh")

    def run_pack(self, output, version="0.1.0", environment=None):
        return subprocess.run(
            ["bash", str(self.repository / "scripts" / "pack.sh"), version, str(output)],
            capture_output=True, text=True, env=environment,
        )

    def pack(self, output, version="0.1.0"):
        result = self.run_pack(output, version)
        self.assertEqual(result.returncode, 0, result.stderr)
        return tarfile.open(output / f"Everlook-{version}.tar.gz")

    def test_release_carries_the_license_inside_the_core_folder(self):
        with self.pack(self.base / "licensed") as archive:
            self.assertEqual(archive.extractfile("Everlook/LICENSE").read().decode(), "MIT License\n")
            self.assertNotIn("LICENSE", archive.getnames())

    def test_pack_refuses_to_run_without_a_license(self):
        (self.repository / "LICENSE").unlink()
        result = self.run_pack(self.base / "unlicensed")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing LICENSE", result.stderr)

    def test_release_ships_every_folder_with_the_core_version(self):
        with self.pack(self.base / "release", version="2.3.4") as archive:
            names = archive.getnames()
            self.assertIn("Everlook/world.lua", names)
            self.assertIn("Everlook_SellJunk/sell_junk.lua", names)
            toc = archive.extractfile("Everlook_SellJunk/Everlook_SellJunk.toc").read().decode()
        self.assertEqual(toc.count("## Version:"), 1)
        self.assertIn("## Interface: 16001\n## Version: 2.3.4\n", toc)
        self.assertNotIn("## Version", (self.module / "Everlook_SellJunk.toc").read_text())

    def test_the_same_commit_packs_to_the_same_bytes_and_ships_checksums(self):
        stamped = {**os.environ, "SOURCE_DATE_EPOCH": "1700000000"}
        for name in ("first", "second"):
            result = self.run_pack(self.base / name, "2.3.4", stamped)
            self.assertEqual(result.returncode, 0, result.stderr)
            if name == "first":
                # Touching a file must not change the archive: only the commit's time and the contents count.
                os.utime(self.core / "world.lua", (1_800_000_000, 1_800_000_000))
        for archive in ("Everlook-2.3.4.tar.gz", "Everlook-2.3.4.zip"):
            self.assertEqual((self.base / "first" / archive).read_bytes(), (self.base / "second" / archive).read_bytes(), archive)
        sums = (self.base / "first" / "SHA256SUMS").read_text().splitlines()
        self.assertEqual(len(sums), 2)
        for line in sums:
            digest, name = line.split(None, 1)
            self.assertEqual(digest, hashlib.sha256((self.base / "first" / name.strip()).read_bytes()).hexdigest())

    def test_release_also_ships_a_zip_with_the_same_folders(self):
        output = self.base / "release-zip"
        self.pack(output, version="2.3.4").close()
        with zipfile.ZipFile(output / "Everlook-2.3.4.zip") as archive:
            names = archive.namelist()
            self.assertIn("Everlook/Everlook.toc", names)
            self.assertIn("Everlook/world.lua", names)
            self.assertIn("Everlook/LICENSE", names)
            self.assertIn("Everlook_SellJunk/sell_junk.lua", names)
            # Windows Explorer needs forward slashes and no leading folder above the addons.
            self.assertTrue(all("\\" not in entry and not entry.startswith("/") for entry in names))
            toc = archive.read("Everlook_SellJunk/Everlook_SellJunk.toc").decode()
        self.assertIn("## Version: 2.3.4", toc)


class ReleaseArchiveTest(unittest.TestCase):
    """The packed release of the real addon, unpacked, with the suite run against the unpacked folders."""

    def test_the_unpacked_release_has_every_addon_folder_and_passes_the_suite(self):
        declared = [path.name for path in ADDON.iterdir() if path.is_dir() and re.fullmatch(r"Everlook(_[A-Za-z0-9]+)?", path.name)]
        with tempfile.TemporaryDirectory(prefix="everlook-release-") as temporary:
            base = Path(temporary)
            result = subprocess.run(["bash", str(SCRIPTS / "pack.sh"), "9.9.9", str(base / "dist")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            unpacked = base / "unpacked"
            with tarfile.open(base / "dist" / "Everlook-9.9.9.tar.gz") as archive:
                archive.extractall(unpacked, filter="data")
            self.assertEqual(sorted(path.name for path in unpacked.iterdir()), sorted(declared))
            for folder in declared:
                toc = (unpacked / folder / f"{folder}.toc").read_text()
                if folder != "Everlook":
                    self.assertIn("## Version: 9.9.9", toc, folder)
                for line in toc.splitlines():
                    match = re.match(r"^([\w./\\-]+\.(?:lua|xml))\s*$", line)
                    if match:
                        self.assertTrue((unpacked / folder / match.group(1).replace("\\", "/")).is_file(), f"{folder} lists {match.group(1)}")
            suite = subprocess.run(["lua5.1", "addon/tests/run.lua", str(unpacked)], cwd=REPOSITORY, capture_output=True, text=True)
            self.assertEqual(suite.returncode, 0, suite.stdout + suite.stderr)


if __name__ == "__main__":
    unittest.main()
