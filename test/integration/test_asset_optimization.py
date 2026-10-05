"""Regression tests for the reproducible resource build and runtime manifest."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("optimize_assets", PROJECT / "tools/optimize_assets.py")
OPT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OPT)


class AssetOptimizationTests(unittest.TestCase):
    def test_glyph_collection_covers_literal_escaped_and_numeric_chinese(self):
        sample = "button=\"\u5821\u5792\"; escaped=\"\\u4E4B\\u4E0B\"; String.chr(0x9AB7)"
        actual = OPT.codepoints_from_text(sample)
        self.assertTrue({0x5821, 0x5792, 0x4E4B, 0x4E0B, 0x9AB7}.issubset(actual))
        self.assertFalse(any(cp < 32 for cp in actual))

    def test_subset_has_every_runtime_glyph_and_identical_outlines_and_metrics(self):
        font = PROJECT / OPT.FONT_DERIVATIVE
        self.assertTrue(font.exists())
        required = OPT.required_codepoints(PROJECT)
        source = OPT.TTFont(PROJECT / OPT.FONT_SOURCE)
        derivative = OPT.TTFont(font)
        original_map = source.getBestCmap()
        compact_map = derivative.getBestCmap()
        self.assertTrue(required.issubset(compact_map))
        for cp in required:
            self.assertEqual(OPT.glyph_signature(source, original_map[cp]), OPT.glyph_signature(derivative, compact_map[cp]), f"U+{cp:04X}")
        self.assertEqual(source["hhea"].ascent, derivative["hhea"].ascent)
        self.assertEqual(source["hhea"].descent, derivative["hhea"].descent)
        self.assertLess(font.stat().st_size, (PROJECT / OPT.FONT_SOURCE).stat().st_size / 5)

    def test_manifest_keeps_dynamic_animation_and_numbered_dungeon_files(self):
        manifest = json.loads((PROJECT / "config/runtime_assets.json").read_text(encoding="utf-8"))
        files = set(manifest["files"])
        self.assertEqual(len(files), len(manifest["files"]))
        profiles = json.loads((PROJECT / "game/data/monsters/animation_profiles.json").read_text(encoding="utf-8"))
        for profile in profiles.values():
            for animation in profile["animations"].values():
                for resource in animation["paths"]:
                    self.assertIn(resource.removeprefix("res://"), files)
        for family in ("mini_chest", "chest"):
            for n in range(1, 5):
                self.assertIn(f"game/assets/dungeon/items/{family}/{family}_{n}.png", files)
                self.assertIn(f"game/assets/dungeon/items/{family}/{family}_open_{n}.png", files)
        self.assertIn("docs/localization/game.zh.csv", files)
        self.assertNotIn(OPT.FONT_SOURCE, files)
        self.assertNotIn("game/data/animations/asset_metadata.json", files)
        for icon in ("coin", "tower", "shield", "bell", "heart", "bag", "key", "sound"):
            self.assertIn(f"game/assets/icons/{icon}.png", files)
        for script in (PROJECT / "game").rglob("*.gd"):
            for resource in re.findall(r'"(res://game/assets/[^\"]+)"', script.read_text(encoding="utf-8")):
                path = resource.removeprefix("res://")
                if (PROJECT / path).is_file() and path != OPT.FONT_SOURCE:
                    self.assertIn(path, files, f"Runtime literal in {script.name}")
        for path in files:
            self.assertFalse(path.startswith("/") or ".." in Path(path).parts)
            self.assertTrue((PROJECT / path).is_file(), path)

    def test_original_assets_match_pre_optimization_fingerprints(self):
        manifest = json.loads((PROJECT / "config/runtime_assets.json").read_text(encoding="utf-8"))
        for entry in manifest["preserved_sources"]:
            self.assertEqual(OPT.sha256(PROJECT / entry["path"]), entry["sha256"])

    def test_invalid_project_fails_instead_of_emitting_incomplete_manifest(self):
        with tempfile.TemporaryDirectory(prefix="fortress-assets-") as directory:
            with self.assertRaises(FileNotFoundError):
                OPT.runtime_files(Path(directory))


if __name__ == "__main__":
    unittest.main(verbosity=2)
