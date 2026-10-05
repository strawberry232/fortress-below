"""Audit the supplied font cmap tables without third-party dependencies."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import struct
from pathlib import Path


EXTRA_CODEPOINTS = {
    0x9AB7, 0x9AC5, 0x91CD, 0x7532, 0x6D6E, 0x7A7A, 0x9B54, 0x9885,
    0x5438, 0x8840, 0x9B3C, 0x54E5, 0x5E03, 0x6797, 0x70B8, 0x5F39,
    0x91D1, 0x5E01, 0x5F13, 0x7BAD, 0x5854, 0x5C01, 0x5370, 0x589E, 0x63F4,
}


def read_cmap(path: Path) -> set[int]:
    data = path.read_bytes()
    directory = 0
    if data[:4] == b"ttcf":
        directory = struct.unpack_from(">I", data, 12)[0]
    count = struct.unpack_from(">H", data, directory + 4)[0]
    cmap = None
    for index in range(count):
        record = directory + 12 + 16 * index
        tag, _, offset, _ = struct.unpack_from(">4sIII", data, record)
        if tag == b"cmap":
            cmap = offset
            break
    if cmap is None:
        raise ValueError(f"No cmap: {path}")
    supported: set[int] = set()
    subtable_count = struct.unpack_from(">H", data, cmap + 2)[0]
    for index in range(subtable_count):
        platform, encoding, relative = struct.unpack_from(">HHI", data, cmap + 4 + 8 * index)
        if platform != 0 and not (platform == 3 and encoding in (1, 10)):
            continue
        subtable = cmap + relative
        format_id = struct.unpack_from(">H", data, subtable)[0]
        if format_id == 4:
            segment_count = struct.unpack_from(">H", data, subtable + 6)[0] // 2
            ends = subtable + 14
            starts = ends + 2 * segment_count + 2
            deltas = starts + 2 * segment_count
            ranges = deltas + 2 * segment_count
            for segment in range(segment_count):
                end = struct.unpack_from(">H", data, ends + 2 * segment)[0]
                start = struct.unpack_from(">H", data, starts + 2 * segment)[0]
                delta = struct.unpack_from(">h", data, deltas + 2 * segment)[0]
                glyph_range = struct.unpack_from(">H", data, ranges + 2 * segment)[0]
                for codepoint in range(start, min(end, 0xFFFE) + 1):
                    if glyph_range == 0:
                        glyph = (codepoint + delta) & 0xFFFF
                    else:
                        address = ranges + 2 * segment + glyph_range + 2 * (codepoint - start)
                        glyph = struct.unpack_from(">H", data, address)[0]
                        if glyph:
                            glyph = (glyph + delta) & 0xFFFF
                    if glyph:
                        supported.add(codepoint)
        elif format_id == 12:
            groups = struct.unpack_from(">I", data, subtable + 12)[0]
            for group in range(groups):
                start, end, glyph = struct.unpack_from(">III", data, subtable + 16 + 12 * group)
                supported.update(range(start + (glyph == 0), end + 1))
        else:
            raise ValueError(f"Unsupported Unicode cmap format {format_id}: {path}")
    return supported


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(source: Path, project: Path, report_path: Path) -> dict:
    verified_report = report_path if report_path.exists() else project / "docs/assets/font-audit.json"
    previous = json.loads(verified_report.read_text(encoding="utf-8")) if verified_report.exists() else {}
    with (project / "docs/localization/game.zh.csv").open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.reader(handle))[1:]
    needed = {ord(character) for row in rows if len(row) >= 2 for character in row[1] if ord(character) > 32}
    needed.update(EXTRA_CODEPOINTS)
    needed.update(range(33, 127))
    han = {character for character in needed if 0x3400 <= character <= 0x9FFF}
    records = []
    maps = {}
    for path in sorted(source.glob("*.ttf")):
        support = read_cmap(path)
        maps[path.name] = support
        records.append({
            "name": path.name,
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
            "total_unicode_glyphs": len(support),
            "han_glyphs": sum(0x3400 <= character <= 0x9FFF for character in support),
            "ui_glyphs_supported": len(needed & support),
            "ui_han_supported": len(han & support),
        })
    historical_bundle_available = bool(records)
    if not historical_bundle_available:
        records = previous.get("all_source_fonts", [])
        maps["Rockboxcond12.ttf"] = read_cmap(project / "game/assets/fonts/rockbox_cond12.ttf")
        maps["BasicChineseLine.ttf"] = read_cmap(project / "game/assets/fonts/basic_chinese_line.ttf")
    primary = maps["Rockboxcond12.ttf"]
    chinese = maps["BasicChineseLine.ttf"]
    bundled = primary | chinese
    fusion_originals = list(source.rglob("fusion-pixel-12px-monospaced-zh_hans.ttf"))
    if len(fusion_originals) != 1:
        raise ValueError("Exactly one user-provided Simplified Chinese 12px font must exist")
    fusion_original = fusion_originals[0]
    fusion_path = project / "game/assets/fonts/fusion_pixel_12px_zh_hans.ttf"
    fusion = read_cmap(fusion_path)
    runtime_support = fusion
    original_copies = {
        "TinyUnicode.ttf": project / "game/assets/fonts/tiny_unicode.ttf",
        "Rockboxcond12.ttf": project / "game/assets/fonts/rockbox_cond12.ttf",
        "BasicChineseLine.ttf": project / "game/assets/fonts/basic_chinese_line.ttf",
        "_README.md": project / "docs/assets/font_bundle_readme.md",
    }
    previous_copies = {record["source"]: record for record in previous.get("original_copies", [])}
    copied_hashes = []
    for name, path in original_copies.items():
        original = source / name
        copied_hashes.append({
            "source": name,
            "project_path": str(path.relative_to(project)).replace("\\", "/"),
            "sha256": sha256(path),
            "original_present": original.exists(),
            "matches_original": sha256(original) == sha256(path) if original.exists() else None,
            "matches_prior_verified_copy": previous_copies.get(name, {}).get("sha256") == sha256(path),
        })
    copied_hashes.append({
        "source": str(fusion_original.relative_to(source)).replace("\\", "/"),
        "project_path": str(fusion_path.relative_to(project)).replace("\\", "/"),
        "sha256": sha256(fusion_path),
        "matches_original": sha256(fusion_original) == sha256(fusion_path),
    })
    license_source = fusion_original.parent
    license_project = project / "game/assets/fonts/licenses/fusion-local-12px"
    license_files = [license_source / "OFL.txt", *sorted((license_source / "LICENSES").rglob("*"))]
    license_copies = [{
        "source": str(path.relative_to(license_source)).replace("\\", "/"),
        "sha256": sha256(path),
        "matches_original": sha256(path) == sha256(license_project / path.relative_to(license_source)),
    } for path in license_files if path.is_file()]
    result = {
        "source_directory": str(source),
        "historical_bundle_available_now": historical_bundle_available,
        "all_source_fonts_record_scope": "Historical 20-font audit retained" if not historical_bundle_available else "Current source files",
        "selected_primary": "fusion_pixel_12px_zh_hans.ttf",
        "selected_counter": "fusion_pixel_12px_zh_hans.ttf",
        "provided_bundle_historical_counter": "Rockboxcond12.ttf",
        "provided_bundle_audit_only": "BasicChineseLine.ttf",
        "font_base_size": 12,
        "minimum_ui_size": 24,
        "counter_font_base_size": 12,
        "historical_rockbox_digit_zero_ink_height_at_16": 12,
        "historical_tinyunicode_digit_zero_ink_height_at_16": 5,
        "csv_entries": len(rows),
        "ui_unique_glyphs_with_new_labels": len(needed),
        "ui_unique_han_with_new_labels": len(han),
        "primary_ui_han_coverage": len(han & primary),
        "secondary_ui_han_coverage": len(han & chinese),
        "bundled_ui_han_coverage": len(han & bundled),
        "bundled_missing_han_count": len(han - bundled),
        "bundled_missing_codepoints": [f"U+{character:04X}" for character in sorted(needed - bundled)],
        "runtime_bundled_han_coverage": len(han & runtime_support),
        "runtime_missing_codepoints": [f"U+{character:04X}" for character in sorted(needed - runtime_support)],
        "runtime_system_font_dependency": False,
        "fusion_sha256": sha256(fusion_path),
        "fusion_original_path": str(fusion_original),
        "fusion_total_unicode_glyphs": len(fusion),
        "fusion_han_glyphs": sum(0x3400 <= character <= 0x9FFF for character in fusion),
        "fusion_license": "OFL-1.1",
        "fusion_original_licenses": license_copies,
        "license_statement_source": "font_bundle_readme.md",
        "license_statement": "The provided bundle README declares all 20 fonts public domain and permits personal/commercial use, modification and redistribution without attribution.",
        "original_copies": copied_hashes,
        "all_source_fonts": records,
    }
    assert all(record["matches_original"] or record.get("matches_prior_verified_copy") for record in copied_hashes)
    assert all(record["matches_original"] for record in license_copies)
    assert not result["runtime_missing_codepoints"], result["runtime_missing_codepoints"]
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(result, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    source_report = {
        "source_type": "User-provided local original",
        "source_path": str(fusion_original),
        "original_filename": fusion_original.name,
        "adopted_path": "res://game/assets/fonts/fusion_pixel_12px_zh_hans.ttf",
        "font_sha256": sha256(fusion_path),
        "bytes": fusion_path.stat().st_size,
        "font_base_size": 12,
        "minimum_ui_size": 24,
        "hud_and_body_share_primary_font": True,
        "required_glyphs": len(needed),
        "required_han_glyphs": len(han),
        "missing_codepoints": result["runtime_missing_codepoints"],
        "license": "OFL-1.1",
        "license_source": str(license_source / "OFL.txt"),
        "preserved_license_directory": "res://game/assets/fonts/licenses/fusion-local-12px",
        "preserved_original_licenses": license_copies,
        "modified_font_bytes": False,
        "subset_font": False,
        "system_font_dependency": False,
        "superseded_download_record": "fusion-font-source-8px-history.json",
    }
    (project / "docs/assets/fusion-font-source.json").write_text(
        json.dumps(source_report, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.source, args.project, args.out)
    print(json.dumps({key: result[key] for key in (
        "ui_unique_glyphs_with_new_labels", "ui_unique_han_with_new_labels",
        "bundled_ui_han_coverage", "bundled_missing_han_count", "runtime_bundled_han_coverage", "runtime_missing_codepoints",
    )}, ensure_ascii=True))


if __name__ == "__main__":
    main()
