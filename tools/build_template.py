"""Build a pinned custom template with explicit feature flags."""
import argparse
import ast
import os
import runpy
import shutil
import subprocess
import sys
from pathlib import Path


def build_arguments(profile: Path) -> list[str]:
    values = runpy.run_path(str(profile))
    return [key + '=' + ('yes' if value else 'no') if isinstance(value, bool) else key + '=' + str(value) for key, value in values.items() if not key.startswith('_')]


def validate_engine_version(source: Path) -> None:
    values = {}
    for statement in ast.parse((source / 'version.py').read_text()).body:
        if isinstance(statement, ast.Assign) and isinstance(statement.value, ast.Constant):
            for target in statement.targets:
                if isinstance(target, ast.Name):
                    values[target.id] = statement.value.value
    if tuple(values.get(name) for name in ('major', 'minor', 'patch')) != (4, 7, 2):
        raise ValueError('The template must match Godot 4.7.2 exactly')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine-source', type=Path, required=True)
    parser.add_argument('--scons-path', type=Path)
    parser.add_argument('--jobs', type=int, default=3)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    source = args.engine_source.resolve()
    validate_engine_version(source)
    env = os.environ.copy()
    env['PYTHONIOENCODING'] = 'utf-8'
    env['SCONS_CACHE_MSVC_CONFIG'] = 'true'
    if args.scons_path:
        env['PYTHONPATH'] = str(args.scons_path.resolve()) + os.pathsep + env.get('PYTHONPATH', '')
    command = [sys.executable, '-m', 'SCons', '-j' + str(max(1, args.jobs)), 'progress=no'] + build_arguments(project / 'config/fortress_2d_template.py')
    print('Building Godot 4.7.2 dedicated 2D template', flush=True)
    subprocess.run(command, cwd=source, env=env, check=True)
    candidates = list((source / 'bin').glob('godot.windows.template_release.x86_64*fortress_2d*.exe'))
    candidates = [path for path in candidates if not path.name.endswith('.console.exe')]
    if len(candidates) != 1:
        raise RuntimeError('Expected exactly one compiled release template')
    target = project / 'tools/export_templates/fortress_2d_4.7.2.exe'
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidates[0], target)
    print('Template ready: ' + str(target), flush=True)


if __name__ == '__main__':
    main()
