"""Verify original map atlas, two complete chest families and wall torch frames."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', type=Path, default=Path.cwd())
    parser.add_argument('--out', type=Path, default=Path('docs/verification/v15/original-map-art.json'))
    args = parser.parse_args()
    manifest = json.loads((args.project / 'docs/assets/v15-map-sources.json').read_text(encoding='utf-8'))
    errors = []
    records = []
    for record in manifest['assets'] + [manifest['atlas']]:
        source = Path(record['source_absolute'])
        target = args.project / record['project_path'].removeprefix('res://')
        equal = source.read_bytes() == target.read_bytes()
        verified = hashlib.sha256(target.read_bytes()).hexdigest() == record['sha256']
        if not equal or not verified:
            errors.append('Source byte mismatch: ' + record['project_path'])
        with Image.open(target) as image:
            if 'frame_size' in record and image.size != tuple(record['frame_size']):
                errors.append('Frame size mismatch: ' + record['project_path'])
            if 'regions' in record:
                for name, (x, y, width, height) in record['regions'].items():
                    if x < 0 or y < 0 or x + width > image.width or y + height > image.height or not image.crop((x, y, x + width, y + height)).getbbox():
                        errors.append('Invalid map region: ' + name)
        records.append({'path': record['project_path'], 'byte_identical': equal, 'sha256_verified': verified})
    for role in ['ordinary_chest', 'sealed_chest']:
        for action in ['closed', 'opening']:
            frames = sorted(record['frame_zero_based'] for record in manifest['assets'] if record.get('role') == role and record.get('action') == action)
            if frames != [0, 1, 2, 3]:
                errors.append('Incomplete four-frame source action: ' + role + '/' + action)
    report = {'passed': not errors, 'original_files_checked': len(records), 'source_chest_frames': 16, 'source_torch_frames': 4,
              'atlas_regions': manifest['atlas']['regions'], 'records': records, 'errors': errors}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: report[key] for key in ['passed', 'original_files_checked', 'errors']}))
    raise SystemExit(0 if not errors else 1)

if __name__ == '__main__':
    main()
