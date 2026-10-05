"""Package the Windows runtime and its required attribution files."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

TITLE = ''.join(chr(codepoint) for codepoint in (0x5821, 0x5792, 0x4E4B, 0x4E0B))
LICENSE_DIR = ''.join(chr(codepoint) for codepoint in (0x6388, 0x6743, 0x8BF4, 0x660E))
TRIAL = ''.join(chr(codepoint) for codepoint in (0x8BD5, 0x73A9, 0x7248))


def document_files(project: Path) -> list[tuple[Path, str]]:
    return [
        (project / 'docs/release/windows-demo.md', ''.join(chr(cp) for cp in (0x8BD5, 0x73A9, 0x8BF4, 0x660E)) + '.txt'),
        (project / 'docs/release/asset-credits.md', LICENSE_DIR + '/' + ''.join(chr(cp) for cp in (0x7D20, 0x6750, 0x6765, 0x6E90)) + '.txt'),
        (project / 'tools/export_templates/Godot-LICENSE.txt', LICENSE_DIR + '/Godot-LICENSE.txt'),
        (project / 'tools/export_templates/Godot-THIRD-PARTY.txt', LICENSE_DIR + '/Godot-THIRD-PARTY.txt'),
        (project / 'game/assets/licenses/FreeCharactersAnimationsAssetPack-License.txt', LICENSE_DIR + '/FreeCharactersAnimationsAssetPack-License.txt'),
        (project / 'game/assets/audio/music/Licensing.txt', LICENSE_DIR + '/Minifantasy-Licensing.txt'),
        (project / 'game/assets/audio/music/Acknowledgements.txt', LICENSE_DIR + '/Minifantasy-Acknowledgements.txt'),
    ]


def package_release(project: Path, binaries: Path, destination: Path, version: str = '1.8') -> dict:
    if not version or any(char not in '0123456789.' for char in version):
        raise ValueError('Invalid release version')
    archive = destination / (TITLE + '_' + TRIAL + '_v' + version + '_Windows.zip')
    package = destination / 'package' / TITLE
    if archive.exists() or package.exists():
        raise FileExistsError('Package output already exists')
    files = [(binaries / (TITLE + suffix), TITLE + suffix) for suffix in ('.exe', '.pck')]
    files += document_files(project)
    font_licenses = project / 'game/assets/fonts/licenses/fusion-local-12px'
    if not font_licenses.is_dir():
        raise FileNotFoundError(font_licenses)
    files += [(file, LICENSE_DIR + '/Fusion-Pixel-Font/' + file.relative_to(font_licenses).as_posix()) for file in font_licenses.rglob('*') if file.is_file()]
    for source, _name in files:
        if not source.is_file():
            raise FileNotFoundError(source)
    for source, name in files:
        target = package / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        for file in sorted(package.rglob('*')):
            if file.is_file():
                out.write(file, file.relative_to(package.parent).as_posix())
    with zipfile.ZipFile(archive) as out:
        if out.testzip() is not None:
            raise RuntimeError('Archive CRC validation failed')
        for source, name in files:
            if out.read(TITLE + '/' + name) != source.read_bytes():
                raise RuntimeError('Archive content differs from validated build: ' + name)
    result = {'archive': str(archive), 'bytes': archive.stat().st_size, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'files': len(files), 'crc_verified': True, 'contents_verified': True}
    (destination / 'archive-verification.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--binaries', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(package_release(args.project, args.binaries, args.output)))


if __name__ == '__main__':
    main()
