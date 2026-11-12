import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_voice as gv  # noqa: E402


class GenerateVoiceSecurityTests(unittest.TestCase):
    def test_clip_name_matches_bundled_manifest(self):
        manifest_path = Path(__file__).resolve().parents[1] / "assets" / "voice" / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        name = gv.clip_name(manifest["voice_id"], manifest["model_id"], {"key": "a", "text": "a", "kind": "letter"})
        self.assertEqual(name, manifest["clips"]["a"])

    def test_resolve_workspace_path_rejects_traversal_and_outside_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(ValueError):
                gv.resolve_workspace_path("../outside.json", base_dir=root, expect_file=True)
            with self.assertRaises(ValueError):
                gv.resolve_workspace_path("../../etc/passwd", base_dir=root, expect_file=True)
            with self.assertRaises(ValueError):
                gv.resolve_workspace_path(".", base_dir=root, expect_file=True)
            ok = gv.resolve_workspace_path("assets/voice", base_dir=root)
            self.assertEqual(ok, (root / "assets" / "voice").resolve())

    def test_resolve_output_file_rejects_invalid_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ["../evil.mp3", "a/b.mp3", "not-hex.mp3", "a" * 15 + ".mp3", "manifest.json"]:
                with self.assertRaises(ValueError, msg=bad):
                    gv.resolve_output_file(tmp, bad)
            valid = gv.resolve_output_file(tmp, "e74a9bf5378c0d48.mp3")
            self.assertTrue(valid.endswith("e74a9bf5378c0d48.mp3"))

    def test_cli_rejects_path_traversal_arguments(self):
        script = Path(__file__).resolve().parent / "generate_voice.py"
        for args in [
            ["--catalog", "../../outside.json", "--voice", "v1", "--dry-run"],
            ["--out", "../escaped_out", "--voice", "v1", "--dry-run"],
        ]:
            proc = subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 2, msg=proc.stderr)
            self.assertIn("INVALID PATH", proc.stderr)


if __name__ == "__main__":
    unittest.main()
