import importlib.util
import os
import pathlib
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("html_publish", ROOT / "scripts/publish-html-remote.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublishingTests(unittest.TestCase):
    def test_bad_zip_paths_are_rejected_before_writing(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive_path = pathlib.Path(temporary) / "bad.zip"
            for name in ["../outside.html", "/etc/example", "safe/../../escape"]:
                with zipfile.ZipFile(archive_path, "w") as archive:
                    archive.writestr(name, "bad")
                with zipfile.ZipFile(archive_path) as archive:
                    with self.assertRaises(ValueError):
                        publisher.checked_entries(archive)

    def test_runtime_scripts_cannot_build_on_server(self):
        for name in ["deploy-vps-remote.sh", "activate-upload-remote.sh", "publish-html-remote.py"]:
            source = (ROOT / "scripts" / name).read_text(encoding="utf-8")
            self.assertNotRegex(source, r"\bnpm\s+(ci|install|test|run)\b")
            self.assertNotIn("install-ubuntu-system-node", source)

    @unittest.skipUnless(os.name == "posix", "Atomic symlink publishing requires the Linux server filesystem")
    def test_snapshot_merge_and_failure_preserve_live_pages(self):
        import pwd
        import grp
        with tempfile.TemporaryDirectory() as temporary:
            data = pathlib.Path(temporary) / "data"
            live = data / "html"
            live.mkdir(parents=True)
            (live / "remote-only.html").write_text("keep")
            (live / "index.html").write_text("old")
            archive_path = pathlib.Path(temporary) / "pages.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("index.html", "new")
                archive.writestr("nested/image.gif", b"GIF89a")
            user = pwd.getpwuid(os.getuid()).pw_name
            group = grp.getgrgid(os.getgid()).gr_name
            publisher.publish(archive_path, data, user, group)
            self.assertTrue(live.is_symlink())
            self.assertEqual((live / "index.html").read_text(), "new")
            self.assertEqual((live / "remote-only.html").read_text(), "keep")
            previous = live.resolve()
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("../escape", "bad")
            with self.assertRaises(ValueError):
                publisher.publish(archive_path, data, user, group)
            self.assertEqual(live.resolve(), previous)
            self.assertEqual((live / "index.html").read_text(), "new")
            outside = pathlib.Path(temporary) / "outside"
            outside.mkdir()
            live.unlink()
            live.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                publisher.publish(archive_path, data, user, group)


if __name__ == "__main__":
    unittest.main()
