"""Verify copied blue FX against source bytes and Godot runtime atlas data."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


EXPECTED = {
    "ranged_charge": {
        "path": "res://game/assets/fx/skull_cast.png",
        "sha256": "deebd66afd884e0be944aa3fd53786d00d676aed8c21f3cbeb6e6c230de867c0",
        "frames": list(range(8)),
        "runtime_key": "cast",
        "scale": [1.0, 1.0],
        "loop": False,
    },
    "ranged_projectile": {
        "path": "res://game/assets/fx/skull_bolt.png",
        "sha256": "3df44391e7cb7e51ff74773e328c3e701443c711196f8ff20bddd69981f376bf",
        "frames": list(range(1, 5)),
        "runtime_key": "bolt",
        "scale": [1.2, 1.2],
        "loop": True,
    },
    "ranged_impact": {
        "path": "res://game/assets/fx/skull_impact.png",
        "sha256": "d901ff89d47a8908bda6200a39c9d6ed457238e8ecc37e8afe53449e4443da1e",
        "frames": list(range(8)),
        "runtime_key": "impact",
        "scale": [1.2, 1.2],
        "loop": False,
    },
}


def check(condition, message, errors):
    if not condition:
        errors.append(message)


def verify_asset(project, record, runtime, errors):
    role = record["role"]
    expected = EXPECTED[role]
    source = Path(record["source_absolute"])
    copied = project / expected["path"].removeprefix("res://")
    source_bytes = source.read_bytes()
    copied_bytes = copied.read_bytes()
    source_sha = hashlib.sha256(source_bytes).hexdigest()
    copied_sha = hashlib.sha256(copied_bytes).hexdigest()
    check(source_sha == copied_sha == expected["sha256"], role + ": original SHA differs", errors)
    check(source_bytes == copied_bytes, role + ": copied bytes differ from original", errors)
    check(record["sha256"] == source_sha, role + ": manifest SHA differs", errors)
    check(record["project_path"] == expected["path"], role + ": manifest project path differs", errors)
    check(record["selected_row_zero_based"] == 2, role + ": manifest is not blue row two", errors)
    check(record["selected_frames_zero_based"] == expected["frames"], role + ": manifest frame range differs", errors)
    with Image.open(source) as original:
        image = original.convert("RGBA")
    check(image.size == (512, 576), role + ": source sheet size differs", errors)
    info = runtime[expected["runtime_key"]]
    check(info["frame_count"] == len(expected["frames"]), role + ": runtime frame count differs", errors)
    check(info["loop"] == expected["loop"], role + ": runtime loop policy differs", errors)
    check(all(abs(a - b) < 0.00001 for a, b in zip(info["scale"], expected["scale"])), role + ": runtime scale differs", errors)
    check(info.get("nearest", info.get("nearest_inherited", False)), role + ": runtime is not nearest filtered", errors)
    regions = []
    blue_alpha_bounds = []
    for index, source_frame in enumerate(expected["frames"]):
        frame = info["frames"][index]
        expected_region = [source_frame * 64, 128, 64, 64]
        check(frame["region"] == expected_region, role + ": runtime atlas region differs", errors)
        check(frame.get("source", info.get("source")) == expected["path"], role + ": runtime texture path differs", errors)
        check(frame.get("source_size", info.get("source_size")) == [512, 576], role + ": runtime source size differs", errors)
        if expected["runtime_key"] == "cast":
            check(frame["visible"], role + ": sampled charging frame is invisible", errors)
        region = [source_frame * 64, 128, source_frame * 64 + 64, 192]
        bbox = image.crop(region).getchannel("A").getbbox()
        check(bbox is not None, role + ": selected source frame is empty", errors)
        regions.append(expected_region)
        blue_alpha_bounds.append(list(bbox) if bbox else None)
    if expected["runtime_key"] == "cast":
        check(info["region_enabled"], role + ": runtime region clipping disabled", errors)
        check(abs(info["duration"] - 0.4) < 0.00001, role + ": charge duration differs", errors)
    else:
        check(info["fps"] == (12.0 if role == "ranged_projectile" else 20.0), role + ": runtime fps differs", errors)
    return {
        "role": role,
        "original": str(source),
        "copied": str(copied),
        "original_sha256": source_sha,
        "copied_sha256": copied_sha,
        "identical_bytes": source_bytes == copied_bytes,
        "runtime_regions": regions,
        "runtime_scale": info["scale"],
        "runtime_loop": info["loop"],
        "blue_alpha_bounds": blue_alpha_bounds,
        "license_status": record["license_status"],
    }, image


def preview_contact_sheet(project, images):
    """Render source blue rows for inspection using nearest scaling only."""
    scale = 2
    frame_size = 64 * scale
    width = 8 * frame_size + 32
    row_height = frame_size + 44
    sheet = Image.new("RGB", (width, row_height * 3 + 20), (24, 27, 38))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    labels = [
        "CHARGE - original 220.png, blue row 2, source frames 0-7",
        "FLIGHT - original 375.png, blue row 2, runtime loops highlighted frames 1-4",
        "IMPACT - original 376.png, blue row 2, source frames 0-7",
    ]
    for row, (role, image) in enumerate(images):
        y = 16 + row * row_height
        draw.text((16, y), labels[row], fill=(221, 229, 243), font=font)
        for frame in range(8):
            x = 16 + frame * frame_size
            top = y + 24
            for tile_y in range(0, frame_size, 16):
                for tile_x in range(0, frame_size, 16):
                    color = (32, 38, 51) if ((tile_y + tile_x) // 16) % 2 else (40, 47, 63)
                    draw.rectangle((x + tile_x, top + tile_y, x + tile_x + 15, top + tile_y + 15), fill=color)
            cell = image.crop((frame * 64, 128, frame * 64 + 64, 192))
            zoomed = cell.resize((frame_size, frame_size), Image.Resampling.NEAREST)
            sheet.paste(zoomed, (x, top), zoomed)
            selected = frame in EXPECTED[role]["frames"]
            draw.rectangle((x, top, x + frame_size - 1, top + frame_size - 1), outline=(96, 205, 248) if selected else (70, 76, 86), width=2)
            draw.text((x + 5, top + 3), str(frame), fill=(224, 231, 241), font=font)
    path = project / "docs/verification/v15/skull-blue-fx-preview.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--no-preview", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    runtime_path = args.runtime or project / "docs/verification/v15/runtime-blue-fx.json"
    output = args.output or project / "docs/verification/v15/original-blue-fx.json"
    manifest = json.loads((project / "docs/assets/v15-sources.json").read_text(encoding="utf-8"))
    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    errors = []
    check(runtime.get("runtime_capture") is True, "Missing Godot runtime capture evidence", errors)
    check(runtime.get("bolt_pausable") is True, "The runtime projectile is not pausable", errors)
    records = []
    images = []
    source_records = {record["role"]: record for record in manifest["assets"]}
    for role in EXPECTED:
        record, image = verify_asset(project, source_records[role], runtime, errors)
        records.append(record)
        images.append((role, image))
    preview = preview_contact_sheet(project, images) if not args.no_preview else None
    result = {
        "passed": not errors,
        "engine": runtime["engine"],
        "runtime_evidence": str(runtime_path),
        "project": str(project),
        "assets": records,
        "inspection_preview": str(preview) if preview else None,
        "preview_policy": "Inspection contact sheet only: original blue-row pixels over a checkerboard, exact integer nearest scaling, no game asset modification.",
        "errors": errors,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": not errors, "assets": len(records), "errors": errors, "output": str(output), "preview": str(preview) if preview else None}, ensure_ascii=True))
    raise SystemExit(0 if not errors else 1)


if __name__ == "__main__":
    main()
