"""Verify that dungeon monster frames remain byte-identical original assets."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


MONSTERS: dict[str, tuple[str, str]] = {
    "skeleton": ("skeleton1", "skeleton"),
    "armored_skeleton": ("skeleton2", "skeleton2"),
    "skull": ("skull", "skull"),
    "vampire": ("vampire", "vampire"),
}


def audit(source_root: Path, project_root: Path) -> dict[str, object]:
    records: list[dict[str, object]] = []
    failures: list[str] = []
    for kind, (source_folder, prefix) in MONSTERS.items():
        for index in range(1, 5):
            filename = f"{prefix}_v2_{index}.png"
            source = source_root / source_folder / "v2" / filename
            target = project_root / "game/assets/dungeon/monsters" / kind / filename
            if not source.is_file() or not target.is_file():
                failures.append(f"Missing original or target frame: {kind}/{filename}")
                continue
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            target_hash = hashlib.sha256(target.read_bytes()).hexdigest()
            with Image.open(target) as image:
                frame = image.convert("RGBA")
                size = list(frame.size)
                bbox = frame.getchannel("A").getbbox()
                corner_alpha = frame.getpixel((0, 0))[3]
            valid = source_hash == target_hash and size == [16, 16] and corner_alpha == 0
            if not valid:
                failures.append(f"Changed frame, dimensions or transparency: {kind}/{filename}")
            records.append({
                "kind": kind,
                "source": str(source),
                "target": str(target.relative_to(project_root)),
                "source_sha256": source_hash,
                "target_sha256": target_hash,
                "size": size,
                "alpha_bbox": bbox,
                "corner_alpha": corner_alpha,
                "byte_identical": source_hash == target_hash,
            })
    return {"frames_checked": len(records), "failures": failures, "records": records}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.source_root, args.project_root)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(json.dumps({"frames_checked": report["frames_checked"], "failures": report["failures"]}))
    return 1 if report["failures"] or report["frames_checked"] != 16 else 0


if __name__ == "__main__":
    raise SystemExit(main())
