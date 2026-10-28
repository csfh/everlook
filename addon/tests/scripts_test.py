import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
import unittest


ADDON = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ADDON / "scripts"))
import auto_release  # noqa: E402


class AddonScriptsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="everlook-scripts-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.addon = self.base / "repo with spaces" / "addon"
        self.core = self.addon / "Everlook"
        (self.addon / "scripts").mkdir(parents=True)
        self.core.mkdir()
        self.addons = self.base / "game with spaces" / "AddOns"
        self.destination = self.addons / "Everlook"
        (self.core / "Everlook.toc").write_text("## Interface: 16001\n## Title: Everlook\n## Version: 0.1.0\n")
        (self.core / "world.lua").write_text("local _, Everlook = ...\n")
        (self.addon.parent / "LICENSE").write_text("MIT License\n")
        self.module = self.addon / "Everlook_SellJunk"
        self.module.mkdir()
        (self.module / "Everlook_SellJunk.toc").write_text(
            "## Interface: 16001\n## Title: Sell junk\n## Dependencies: Everlook\n\nsell_junk.lua\n")
        (self.module / "sell_junk.lua").write_text("local addon_name = ...\n")
        for name in ("sync.sh", "pack.sh"):
            shutil.copyfile(ADDON / "scripts" / name, self.addon / "scripts" / name)
        script = self.addon / "scripts" / "sync.sh"
        script.write_text(re.sub(r'^addons=.*$', f'addons="{self.addons}"', script.read_text(), flags=re.MULTILINE))

    def sync(self, succeeds=True):
        result = subprocess.run(
            ["bash", str(self.addon / "scripts" / "sync.sh")],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode == 0, succeeds, result.stderr)

    def pack(self, output, version="0.1.0"):
        environment = {**os.environ, "UV_CACHE_DIR": str(self.base / "uv-cache"), "UV_PYTHON": sys.executable}
        result = subprocess.run(
            ["bash", str(self.addon / "scripts" / "pack.sh"), version, str(output)],
            capture_output=True, text=True, env=environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return tarfile.open(output / f"Everlook-{version}.tar.gz")

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

    def test_release_carries_the_license_inside_the_core_folder(self):
        with self.pack(self.base / "licensed") as archive:
            self.assertEqual(archive.extractfile("Everlook/LICENSE").read().decode(), "MIT License\n")
            self.assertNotIn("LICENSE", archive.getnames())

    def test_pack_refuses_to_run_without_a_license(self):
        (self.addon.parent / "LICENSE").unlink()
        result = subprocess.run(
            ["bash", str(self.addon / "scripts" / "pack.sh"), "0.1.0", str(self.base / "unlicensed")],
            capture_output=True, text=True,
            env={**os.environ, "UV_CACHE_DIR": str(self.base / "uv-cache"), "UV_PYTHON": sys.executable},
        )
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
            result = subprocess.run(
                ["bash", str(self.addon / "scripts" / "pack.sh"), "2.3.4", str(self.base / name)],
                capture_output=True, text=True,
                env={**stamped, "UV_CACHE_DIR": str(self.base / "uv-cache"), "UV_PYTHON": sys.executable},
            )
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
            environment = {**os.environ, "UV_CACHE_DIR": str(base / "uv-cache"), "UV_PYTHON": sys.executable}
            result = subprocess.run(["bash", str(ADDON / "scripts" / "pack.sh"), "9.9.9", str(base / "dist")],
                                    capture_output=True, text=True, env=environment)
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
            shutil.copytree(ADDON / "tests", unpacked / "tests", ignore=shutil.ignore_patterns("__pycache__", "*.py"))
            suite = subprocess.run(["lua5.1", "tests/run.lua"], cwd=unpacked, capture_output=True, text=True)
            self.assertEqual(suite.returncode, 0, suite.stdout + suite.stderr)


class LayoutTest(unittest.TestCase):
    """Each folder in addon/ named Everlook or Everlook_<Name> is one addon the game loads."""

    @staticmethod
    def fields(toc):
        fields, files = {}, []
        for line in toc.read_text().splitlines():
            if line.startswith("## "):
                key, _, value = line[3:].partition(":")
                fields[key.strip()] = value.strip()
            elif line.strip() and not line.startswith("#"):
                files.append(line.strip())
        return fields, files

    def folders(self):
        return sorted(path for path in ADDON.iterdir() if path.is_dir() and re.fullmatch(r"Everlook(_[A-Za-z0-9]+)?", path.name))

    def test_every_media_path_exists_and_every_asset_is_named(self):
        sources = {path: path.read_text(encoding="utf-8") for folder in self.folders()
                   for path in list(folder.glob("*.lua")) + list(folder.glob("*.xml")) + list(folder.glob("*.toc"))}
        everything = "\n".join(sources.values())
        for path, text in sources.items():
            for folder, rest in re.findall(r'Interface\\+AddOns\\+(Everlook\w*)\\+([^"\'\s)]*)', text):
                target = ADDON / folder / rest.replace("\\\\", "/").replace("\\", "/")
                with self.subTest(source=f"{path.relative_to(ADDON)}", path=rest):
                    # A path that ends at a folder is a prefix the code finishes with a file name.
                    self.assertTrue(target.exists(), f"{path.relative_to(ADDON)} names {folder}\\{rest}, which does not exist")
        for folder in self.folders():
            media = [path for path in sorted((folder / "assets").glob("*")) if path.suffix in {".tga", ".ttf", ".blp", ".png", ".ogg", ".mp3", ".wav"}] if (folder / "assets").is_dir() else []
            for asset in media:
                with self.subTest(asset=f"{folder.name}/assets/{asset.name}"):
                    self.assertTrue(asset.name in everything or asset.stem in everything,
                                    f"{folder.name}/assets/{asset.name} is not named by any Lua, XML or TOC file")

    def test_every_listed_file_exists_and_every_file_is_listed(self):
        for folder in self.folders():
            with self.subTest(addon=folder.name):
                toc = folder / f"{folder.name}.toc"
                self.assertTrue(toc.is_file(), f"{folder.name} needs {toc.name}")
                _, files = self.fields(toc)
                for name in files:
                    path = name.replace("\\", "/")
                    self.assertTrue((folder / path).is_file(), f"{folder.name}.toc lists missing {name}")
                listed = {name.replace("\\", "/") for name in files}
                for path in folder.rglob("*"):
                    relative = path.relative_to(folder).as_posix()
                    if path.suffix in (".lua", ".xml") and path.name != "Bindings.xml":
                        self.assertIn(relative, listed, f"{folder.name}.toc does not load {relative}")

    # The addon list shows these titles. "Everlook" is in the gold of the game's
    # own titles, and the folder's name after it is colored by kind: the island
    # and its modules in the island's accent, every other module in blue.
    GOLD, MODULE, ISLAND = "ffd100", "66bbff", "ad76ef"

    @staticmethod
    def is_island(name):
        return name.startswith("Island")

    def test_titles_name_the_folder_and_color_its_kind(self):
        prefix = f"|cff{self.GOLD}Everlook|r"
        for folder in self.folders():
            with self.subTest(addon=folder.name):
                fields, _ = self.fields(folder / f"{folder.name}.toc")
                if folder.name == "Everlook":
                    self.assertEqual(fields.get("Title"), prefix)
                    continue
                name = folder.name.removeprefix("Everlook_")
                color = self.ISLAND if self.is_island(name) else self.MODULE
                words = re.sub(r"(?<!^)(?=[A-Z])", " ", name).lower().capitalize()
                self.assertEqual(fields.get("Title"), f"{prefix} |cff{color}{words}|r")

    def test_the_core_version_is_written_the_way_the_release_reads_and_bumps_it(self):
        # auto_release knows one form, "## Version: x.y.z", so any other spelling fails here, before a push.
        self.assertTrue(auto_release.SEMVER.fullmatch(auto_release.current_addon_version(ADDON)))

    def test_a_module_id_is_its_folder_name(self):
        # A module lives in Everlook_<Name>, where the name is its id in CamelCase. Extensions call
        # module.extend instead and are left out.
        for folder in self.folders():
            ids = []
            for path in sorted(folder.glob("*.lua")):
                text = path.read_text()
                for call in re.finditer(r"module\.register\(\{(.{0,600})", text, re.S):
                    found = re.search(r'\bid = "([a-z_]+)"', call.group(1)) or re.search(r'^local id = "([a-z_]+)"', text, re.M)
                    ids.append(found.group(1) if found else None)
            if not ids or folder.name == "Everlook":
                continue
            with self.subTest(addon=folder.name):
                expected = re.sub(r"(?<!^)(?=[A-Z])", "_", folder.name.removeprefix("Everlook_")).lower()
                self.assertEqual(ids, [expected])

    def test_files_and_tables_are_named_for_the_module(self):
        # A module's files are <id>.lua and <id>_<part>.lua, an Island extension's is island_<id>.lua,
        # and a file puts on Everlook only the module's table, Everlook.<id>, or one named for itself.
        for folder in self.folders():
            if folder.name == "Everlook":
                continue
            name = folder.name.removeprefix("Everlook_")
            extension = self.is_island(name) and name != "Island"
            module_id = re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()
            for path in sorted(folder.glob("*.lua")):
                with self.subTest(file=f"{folder.name}/{path.name}"):
                    if extension:
                        self.assertEqual(path.stem, module_id)
                    else:
                        self.assertTrue(path.stem == module_id or path.stem.startswith(module_id + "_"), path.stem)
                    defined = re.findall(r"^\s*(?:function\s+Everlook\.([a-z_]+)\s*\(|Everlook\.([a-z_]+)\s*=(?!=))", path.read_text(), re.M)
                    tables = {function or assigned for function, assigned in defined}
                    self.assertLessEqual(tables, {module_id, path.stem})

    def test_a_module_is_called_what_its_folder_says(self):
        # Settings names a module as the addon list does: the folder's words, in sentence case.
        for folder in self.folders():
            for path in sorted(folder.glob("*.lua")):
                text = path.read_text()
                call = text.find("module.register(")
                if call < 0:
                    continue
                found = re.search(r'\bname = "([^"]+)"', text[call:call + 800])
                expected = re.sub(r"(?<!^)(?=[A-Z])", " ", folder.name.removeprefix("Everlook_")).lower().capitalize()
                with self.subTest(addon=folder.name):
                    self.assertEqual(found and found.group(1), expected)

    def test_every_test_file_is_named_for_a_shipped_file_and_runs(self):
        # A test file is named for the core file, module, module part or Island extension it tests,
        # and run.lua runs every one of them.
        shipped = {path.stem for folder in self.folders() for path in folder.glob("*.lua")}
        tests = sorted(path.stem for path in (ADDON / "tests").glob("*.lua") if path.name != "run.lua")
        for stem in tests:
            with self.subTest(test=stem):
                self.assertIn(stem, shipped)
        runner = (ADDON / "tests" / "run.lua").read_text()
        start = runner.index("local suites = {")
        listed = re.findall(r'"([a-z_]+)"', runner[start:runner.index("}", start)])
        self.assertEqual(listed, sorted(listed), "run.lua lists its suites in order")
        self.assertEqual(listed, tests)

    NAMEPLATE_PROVIDERS = {"QuestNameplates", "NameplateTitles"}

    def test_modules_depend_on_everlook_and_sit_in_its_group(self):
        core, _ = self.fields(ADDON / "Everlook" / "Everlook.toc")
        names = {folder.name for folder in self.folders()}
        for folder in self.folders():
            if folder.name == "Everlook":
                continue
            with self.subTest(addon=folder.name):
                fields, _ = self.fields(folder / f"{folder.name}.toc")
                name = folder.name.removeprefix("Everlook_")
                island_module = self.is_island(name) and name != "Island"
                dependencies = [part.strip() for part in fields.get("Dependencies", "").split(",")]
                # A module that gives marks or lines to the island, or to the nameplate view, needs the one it gives to.
                expected = ["Everlook", "Everlook_Island"] if island_module else ["Everlook", "Everlook_Nameplates"] if name in self.NAMEPLATE_PROVIDERS else ["Everlook"]
                self.assertEqual(dependencies, expected)
                for dependency in dependencies:
                    self.assertIn(dependency, names)
                self.assertEqual(fields.get("Interface"), core["Interface"])
                self.assertEqual(fields.get("Group"), "Everlook")
                self.assertTrue(fields.get("Notes"))
                self.assertNotIn("Version", fields, "pack.sh stamps the version")
                self.assertNotIn("SavedVariables", fields, "settings live in EverlookSaved")


if __name__ == "__main__":
    unittest.main()
