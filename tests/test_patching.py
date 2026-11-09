"""Regression checks for patch boundaries and failure atomicity (no SDK needed)."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from prepare_upstream import ROOT, prepare


class PatchingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.target = self.root / 'target'
        shutil.copytree(ROOT / 'vendor/PSReadLine', self.source)

    def test_complete_and_repeat(self):
        prepare(self.source, self.target)
        render = (self.target / 'PSReadLine/Render.cs').read_text()
        self.assertEqual(render.count('_commandHighlighter.Analyze'), 1)
        self.assertEqual(render.count('private string GetDefaultTokenColor'), 1)
        with self.assertRaisesRegex(ValueError, 'already patched'):
            prepare(self.target, self.root / 'again')
        self.assertFalse((self.root / 'again').exists())

    def test_missing_duplicate_and_wrong_context_are_atomic(self):
        plan = json.loads((ROOT / 'tools/patches.json').read_text())
        # Damage the last hook after the two earlier operations would succeed.
        entry = plan[-1]
        path = self.source / entry['file']
        original = path.read_text(encoding='utf-8-sig')
        for damaged in (original.replace(entry['before'], ''), original + entry['before'],
                        original.replace('private void Initialize(Runspace', 'private void Different(Runspace')):
            with self.subTest():
                path.write_text(damaged)
                with self.assertRaisesRegex(ValueError, 'anchor mismatch'):
                    prepare(self.source, self.target)
                self.assertFalse(self.target.exists())
                self.assertFalse(list(self.root.glob('target.pending-*')))
                self.assertNotIn('_commandHighlighter', (self.source / 'PSReadLine/Render.cs').read_text())

    def test_metadata_drift_and_existing_destination(self):
        path = self.source / 'PSReadLine/PSReadLine.csproj'
        original = path.read_text(encoding='utf-8-sig')
        path.write_text(original.replace('<FileVersion>2.4.5</FileVersion>', '<FileVersion>2.9.0</FileVersion>'))
        with self.assertRaisesRegex(ValueError, 'Version anchor mismatch'):
            prepare(self.source, self.target)
        self.assertFalse(self.target.exists())
        prepare(self.source, self.target, experimental=True)
        before = (self.target / 'PSReadLine/Render.cs').read_bytes()
        path.write_text(original)
        with self.assertRaisesRegex(ValueError, 'must not exist'):
            prepare(self.source, self.target)
        self.assertEqual(before, (self.target / 'PSReadLine/Render.cs').read_bytes())


if __name__ == '__main__':
    unittest.main()
