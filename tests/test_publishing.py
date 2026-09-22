import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_mod


class PublishingTests(unittest.TestCase):
    def test_version_pair_and_fmtk_increment(self):
        info = {"name": "Test_Mod", "version": "0.3.2", "factorio_version": "2.0"}
        self.assertEqual(publish_mod.release_versions(info), {"2.0": "0.3.2", "2.1": "0.3.3"})
        for version in ("0.3.3", "0.3.65534", "0.3.65536", "0.03.2"):
            with self.assertRaises(ValueError):
                publish_mod.release_versions(dict(info, version=version))
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            (source / "control.lua").write_text("-- runtime\n")
            # FMTK performs the first increment before invoking our version hook.
            (source / "info.json").write_text(json.dumps(dict(info, version="0.3.3")))
            publish_mod.advance_version(source)
            next_info = json.loads((source / "info.json").read_text())
            self.assertEqual(next_info, dict(info, version="0.3.4"))
            with self.assertRaises(ValueError):
                publish_mod.advance_version(source)

    def test_partial_upload_resumes_without_duplicate_or_source_changes(self):
        releases = {}
        attempts = []
        fail_second = True

        def upload(name, path, key):
            nonlocal fail_second
            self.assertEqual(key, "test-key")
            with zipfile.ZipFile(path) as archive:
                self.assertEqual(len(archive.namelist()), 2)
                info = json.loads(archive.read(f"{path.stem}/info.json"))
            attempts.append(info["version"])
            if info["factorio_version"] == "2.1" and fail_second:
                fail_second = False
                raise RuntimeError("second upload interrupted")
            releases[info["version"]] = {"info_json": info, "file_name": path.name,
                                          "sha1": hashlib.sha1(path.read_bytes()).hexdigest()}

        def git(source, *args, **kwargs):
            return "main" if args == ("branch", "--show-current") else ""

        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            before = json.dumps({"name": "Test_Mod", "version": "0.3.2", "factorio_version": "2.0",
                                 "package": {"git_publish_branch": "main"}})
            (source / "info.json").write_text(before)
            (source / "control.lua").write_text("-- runtime\n")
            with (patch.object(publish_mod, "fetch_releases", side_effect=lambda name: dict(releases)),
                  patch.object(publish_mod, "upload_file", side_effect=upload),
                  patch.object(publish_mod, "git", side_effect=git),
                  patch.object(publish_mod, "push_remote", return_value="origin"),
                  patch.object(publish_mod, "check_tags"),
                  patch.object(publish_mod, "publish_tags") as tags,
                  patch.dict(os.environ, {"FACTORIO_UPLOAD_API_KEY": "test-key"})):
                with self.assertRaisesRegex(RuntimeError, "interrupted"):
                    publish_mod.publish(source, upload=True)
                tags.assert_not_called()
                publish_mod.publish(source, upload=True)
                self.assertEqual(attempts, ["0.3.2", "0.3.3", "0.3.3"])
                tags.assert_called_once()
                self.assertEqual((source / "info.json").read_text(), before)
                (source / "control.lua").write_text("-- conflicting runtime\n")
                with self.assertRaisesRegex(ValueError, "differs"):
                    publish_mod.publish(source, upload=True)
                self.assertEqual(len(attempts), 3)

    def test_wrong_game_target_or_hash_blocks_existing_version(self):
        packages = [("2.0", "0.3.2", Path("Test_Mod_0.3.2.zip"), "correct")]
        release = {"info_json": {"factorio_version": "2.0"}, "file_name": "Test_Mod_0.3.2.zip", "sha1": "correct"}
        self.assertEqual(publish_mod.pending_packages(packages, {"0.3.2": release}), [])
        for wrong in (dict(release, sha1="changed"), dict(release, info_json={"factorio_version": "2.1"})):
            with self.assertRaises(ValueError):
                publish_mod.pending_packages(packages, {"0.3.2": wrong})

    def test_upload_key_is_only_sent_to_init_endpoint(self):
        responses = [io.BytesIO(b'{"upload_url":"https://storage.factorio.com/upload/example"}'),
                     io.BytesIO(b'{"success":true}')]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Test_Mod_0.3.2.zip"
            path.write_bytes(b"package-data")
            with patch.object(publish_mod.urllib.request, "urlopen", side_effect=responses) as send:
                publish_mod.upload_file("Test_Mod", path, "test-key")
            init_request = send.call_args_list[0].args[0]
            upload_request = send.call_args_list[1].args[0]
            self.assertEqual(init_request.full_url, publish_mod.PORTAL + "/api/v2/mods/releases/init_upload")
            self.assertEqual(init_request.get_header("Authorization"), "Bearer test-key")
            self.assertIsNone(upload_request.get_header("Authorization"))
            self.assertIn(b'filename="Test_Mod_0.3.2.zip"', upload_request.data)
            self.assertIn(b"package-data", upload_request.data)
            self.assertNotIn(b"test-key", upload_request.data)
            with patch.object(publish_mod.urllib.request, "urlopen",
                              return_value=io.BytesIO(b'{"upload_url":"http://storage.factorio.com/upload"}')) as send:
                with self.assertRaisesRegex(ValueError, "invalid upload URL"):
                    publish_mod.upload_file("Test_Mod", path, "test-key")
                self.assertEqual(send.call_count, 1)


if __name__ == "__main__":
    unittest.main()
