"""Guard the custom engine's necessary runtime features."""
import runpy
import importlib.util
import unittest
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


class TemplateProfileTests(unittest.TestCase):
    def test_engine_version_requires_exact_major_minor_patch(self):
        spec = importlib.util.spec_from_file_location('build_template', PROJECT / 'tools/build_template.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)
            for version in ((5, 7, 2), (4, 70, 2), (4, 7, 20), (4, 6, 2)):
                (source / 'version.py').write_text('major = %d\nminor = %d\npatch = %d\n' % version)
                with self.assertRaises(ValueError):
                    module.validate_engine_version(source)
            (source / 'version.py').write_text('major = 4\nminor = 7\npatch = 2\n')
            module.validate_engine_version(source)

    def test_flags_are_explicit_to_override_platform_defaults(self):
        spec = importlib.util.spec_from_file_location('build_template', PROJECT / 'tools/build_template.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        args = module.build_arguments(PROJECT / 'config/fortress_2d_template.py')
        self.assertIn('d3d12=no', args)
        self.assertIn('disable_3d=yes', args)
        self.assertIn('module_godot_physics_2d_enabled=yes', args)

    def test_runtime_features_remain_enabled(self):
        profile = runpy.run_path(str(PROJECT / 'config/fortress_2d_template.py'))
        for key in ('module_gdscript_enabled', 'module_godot_physics_2d_enabled', 'module_text_server_adv_enabled', 'module_freetype_enabled', 'module_webp_enabled', 'module_ogg_enabled', 'module_vorbis_enabled', 'module_mp3_enabled', 'opengl3', 'builtin_icu4c', 'use_static_cpp'):
            self.assertTrue(profile[key], key)
        self.assertFalse(profile['disable_physics_2d'])
        self.assertTrue(profile['disable_3d'])
        self.assertFalse(profile['modules_enabled_by_default'])
        self.assertFalse(profile['vulkan'])
        self.assertFalse(profile['d3d12'])
        self.assertEqual(profile['target'], 'template_release')
        self.assertEqual(profile['arch'], 'x86_64')


if __name__ == '__main__':
    unittest.main()
