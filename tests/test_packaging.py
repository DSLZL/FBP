import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pack_mod import build


ROOT = Path(__file__).resolve().parents[1]


class PackagingTests(unittest.TestCase):
    def test_package_bytes_ignore_source_timestamps(self):
        info = {"name": "Test_Mod", "version": "0.3.2", "factorio_version": "2.0"}
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            control = source / "control.lua"
            control.write_bytes(b"-- same runtime\n")
            output = build(source, source / "first", info, "2.0")
            first = output.read_bytes()
            os.utime(output, (1700000000, 1700000000))
            original_mtime = output.stat().st_mtime_ns
            build(source, source / "first", info, "2.0")
            self.assertEqual(output.stat().st_mtime_ns, original_mtime)
            os.utime(control, (1700000000, 1700000000))
            self.assertEqual(first, build(source, source / "second", info, "2.0").read_bytes())
            control.write_bytes(b"-- changed runtime\n")
            self.assertNotEqual(first, build(source, source / "third", info, "2.0").read_bytes())

    def test_both_packages_share_runtime_and_preserve_source(self):
        before = (ROOT / "info.json").read_bytes()
        info = json.loads(before)
        folder = f"{info['name']}_{info['version']}"
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            command = [sys.executable, str(ROOT / "pack_mod.py"), "--factorio-version", "both", "--output-dir", str(output)]
            contents = []
            for _ in range(2):
                subprocess.run(command, cwd=ROOT.parent, check=True, capture_output=True)
            for target in ("2.0", "2.1"):
                with zipfile.ZipFile(output / target / f"{folder}.zip") as archive:
                    files = {name: archive.read(name) for name in archive.namelist()}
                self.assertTrue(all(name.startswith(folder + "/") and "\\" not in name for name in files))
                self.assertEqual(len(files), len(set(files)))
                manifest = json.loads(files.pop(f"{folder}/info.json"))
                self.assertEqual(manifest, dict(info, factorio_version=target))
                self.assertIn(f"{folder}/scripts/player_state.lua", files)
                self.assertIn(f"{folder}/graphics/icons/icon_placement.png", files)
                self.assertFalse(any(part in ("tests", "dist", ".git", ".trellis", ".codegraph", "pack_mod.py")
                                     for name in files for part in name.split("/")))
                contents.append(files)
            self.assertEqual(contents[0], contents[1])
        self.assertEqual((ROOT / "info.json").read_bytes(), before)

    def test_default_from_parent_excludes_development_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            source = parent / "mod"
            source.mkdir()
            for name in ("pack_mod.py", "info.json", "control.lua"):
                shutil.copyfile(ROOT / name, source / name)
            for name in ("tests/fixture.lua", ".codegraph/private.json", "old.zip", "secret.txt"):
                path = source / name
                path.parent.mkdir(exist_ok=True)
                path.write_text("excluded", encoding="utf-8")
            subprocess.run([sys.executable, str(source / "pack_mod.py")], cwd=parent, check=True, capture_output=True)
            archive_path, = source.glob("Factorio_Blueprint_Printer_*.zip")
            with zipfile.ZipFile(archive_path) as archive:
                self.assertEqual(len(archive.namelist()), 2)
                self.assertEqual(json.loads(archive.read(f"{archive_path.stem}/info.json"))["factorio_version"], "2.0")

    def test_invalid_metadata_and_target_fail_without_artifacts(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            shutil.copyfile(ROOT / "pack_mod.py", source / "pack_mod.py")
            (source / "control.lua").write_text("", encoding="utf-8")
            (source / "info.json").write_text(json.dumps({"name": "../escape", "version": "0.2.1", "factorio_version": "2.0"}))
            command = [sys.executable, str(source / "pack_mod.py")]
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertNotEqual(subprocess.run(command + ["--factorio-version", "3.0"], capture_output=True).returncode, 0)
            self.assertEqual(list(source.rglob("*.zip")), [])


if __name__ == "__main__":
    unittest.main()
