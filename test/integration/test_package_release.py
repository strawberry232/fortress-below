"""Verify playable archive composition and failure handling."""
import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


class PackageReleaseTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('package_release', PROJECT / 'tools/package_release.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'project'
        self.binaries = self.root / 'binaries'
        self.binaries.mkdir()
        for suffix in ('.exe', '.pck'):
            (self.binaries / (self.module.TITLE + suffix)).write_bytes(b'Fixture' + suffix.encode())
        for source, _destination in self.module.document_files(self.project):
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text('Required attribution fixture')
        font = self.project / 'game/assets/fonts/licenses/fusion-local-12px/OFL.txt'
        font.parent.mkdir(parents=True, exist_ok=True)
        font.write_text('Font fixture')

    def test_archive_has_runtime_files_and_documents_and_passes_crc(self):
        result = self.module.package_release(self.project, self.binaries, self.root / 'output')
        with zipfile.ZipFile(result['archive']) as archive:
            self.assertIsNone(archive.testzip())
            names = archive.namelist()
            self.assertIn(self.module.TITLE + '/' + self.module.TITLE + '.exe', names)
            self.assertIn(self.module.TITLE + '/' + self.module.TITLE + '.pck', names)
            self.assertTrue(any(path.endswith('/OFL.txt') for path in names))
            self.assertFalse(any('/game/' in path or '/test/' in path or '/.godot/' in path for path in names))

    def test_missing_pck_does_not_create_archive(self):
        (self.binaries / (self.module.TITLE + '.pck')).unlink()
        with self.assertRaises(FileNotFoundError):
            self.module.package_release(self.project, self.binaries, self.root / 'output')
        self.assertFalse((self.root / 'output').exists())

    def test_existing_package_is_not_overwritten(self):
        self.module.package_release(self.project, self.binaries, self.root / 'output')
        with self.assertRaises(FileExistsError):
            self.module.package_release(self.project, self.binaries, self.root / 'output')


if __name__ == '__main__':
    unittest.main()
