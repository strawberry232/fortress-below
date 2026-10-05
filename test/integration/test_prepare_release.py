"""Exercise release isolation, raw locale retention, and strict resource selection."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


class PrepareReleaseTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('prepare_release', PROJECT / 'tools/prepare_release.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.target = self.root / 'release'
        self.source.mkdir()
        self.write('project.godot', 'config_version=5\n[application]\nconfig/name="Sample"\n[autoload]\nMCPRuntimeProbe="*res://addons/godot_mcp/runtime/mcp_runtime_probe.gd"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")\n')
        self.write('export_presets.cfg', '[preset.0]\nname="Windows Desktop"\n')
        self.write('game/scripts/main.gd', 'extends Node\n')
        self.write('game/scenes/main.tscn', '[gd_scene format=3]\n')
        self.write('game/assets/used.png', 'used')
        self.write('game/assets/old.png', 'unused')
        self.write('game/data/animations/asset_metadata.json', '{}')
        self.write('docs/localization/game.zh.csv', 'key,zh_CN\nA,Test\n')
        self.write('docs/localization/game.zh.csv.import', '[remap]\nimporter="keep"\n')
        self.write('test/unit/secret.gd', 'extends Node\n')
        self.write('config/runtime_assets.json', json.dumps({'version': 1, 'files': ['game/assets/used.png', 'docs/localization/game.zh.csv']}))

    def write(self, path, value):
        dest = self.source / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(value)

    def test_only_runtime_dependencies_are_copied_and_source_probe_is_preserved(self):
        original = (self.source / 'project.godot').read_bytes()
        result = self.module.prepare_release(self.source, self.target)
        self.assertGreater(result['files'], 0)
        self.assertTrue((self.target / 'game/assets/used.png').exists())
        self.assertTrue((self.target / 'game/scripts/main.gd').exists())
        self.assertTrue((self.target / 'game/scenes/main.tscn').exists())
        self.assertTrue((self.target / 'docs/localization/game.zh.csv.import').exists())
        self.assertFalse((self.target / 'game/assets/old.png').exists())
        self.assertFalse((self.target / 'game/data/animations/asset_metadata.json').exists())
        self.assertFalse((self.target / 'test').exists())
        config = (self.target / 'project.godot').read_text()
        self.assertNotIn('MCPRuntimeProbe=', config)
        self.assertIn('enabled=PackedStringArray()', config)
        self.assertEqual(original, (self.source / 'project.godot').read_bytes())

    def test_missing_asset_fails_before_creating_destination(self):
        (self.source / 'game/assets/used.png').unlink()
        with self.assertRaises(FileNotFoundError):
            self.module.prepare_release(self.source, self.target)
        self.assertFalse(self.target.exists())

    def test_escaping_manifest_paths_are_rejected(self):
        self.write('config/runtime_assets.json', json.dumps({'version': 1, 'files': ['../outside.png']}))
        with self.assertRaises(ValueError):
            self.module.prepare_release(self.source, self.target)
        self.assertFalse(self.target.exists())

    def test_existing_destination_is_not_overwritten(self):
        self.target.mkdir()
        with self.assertRaises(FileExistsError):
            self.module.prepare_release(self.source, self.target)

    def test_missing_template_field_cannot_silently_use_official_runtime(self):
        template = self.root / 'template.exe'
        template.write_bytes(b'MZ')
        with self.assertRaises(ValueError):
            self.module.prepare_release(self.source, self.target, template)
        self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
