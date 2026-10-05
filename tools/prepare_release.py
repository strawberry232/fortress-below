"""Assemble an isolated release project from explicit runtime dependencies."""
import argparse
import json
import re
import shutil
from pathlib import Path


def prepare_release(source: Path, destination: Path, template: Path | None = None) -> dict:
    source = source.resolve()
    destination = destination.resolve()
    if destination.exists():
        raise FileExistsError(destination)
    if destination.is_relative_to(source):
        raise ValueError('Release output must be outside the source project')
    manifest = json.loads((source / 'config/runtime_assets.json').read_text(encoding='utf-8'))
    if manifest.get('version') != 1 or not isinstance(manifest.get('files'), list):
        raise ValueError('Unsupported runtime manifest')
    files = {'project.godot', 'export_presets.cfg'}
    for name in manifest['files']:
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name:
            raise ValueError('Unsafe manifest path: ' + name)
        if not (source / path).resolve().is_relative_to(source):
            raise ValueError('Manifest path escapes source: ' + name)
        files.add(path.as_posix())
        if path.suffix == '.csv':
            files.add(path.as_posix() + '.import')
    for path in (source / 'game').rglob('*'):
        if path.is_file() and path.suffix in ('.gd', '.tscn', '.tres', '.uid'):
            files.add(path.relative_to(source).as_posix())
    for name in sorted(files):
        if not (source / name).is_file():
            raise FileNotFoundError(source / name)
    if template is not None:
        template = template.resolve()
        if not template.is_file():
            raise FileNotFoundError(template)
        preset = (source / 'export_presets.cfg').read_text(encoding='utf-8')
        preset, substitutions = re.subn(r'^custom_template/release=.*$', 'custom_template/release="' + template.as_posix() + '"', preset, flags=re.MULTILINE)
        if substitutions != 1:
            raise ValueError('Expected exactly one release template field in the preset')
    for name in sorted(files):
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, target)
    project_path = destination / 'project.godot'
    project = project_path.read_text(encoding='utf-8')
    project = re.sub(r'^MCPRuntimeProbe=.*(?:\n|$)', '', project, flags=re.MULTILINE)
    project = re.sub(r'^enabled=PackedStringArray\([^\n]*\)', 'enabled=PackedStringArray()', project, flags=re.MULTILINE)
    project_path.write_text(project, encoding='utf-8')
    if template is not None:
        preset_path = destination / 'export_presets.cfg'
        preset_path.write_text(preset, encoding='utf-8')
    return {'source': str(source), 'destination': str(destination), 'files': len(files), 'runtime_assets': len(manifest['files']), 'template': str(template) if template else None}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--template', type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare_release(args.source, args.output, args.template), indent=2))


if __name__ == '__main__':
    main()
