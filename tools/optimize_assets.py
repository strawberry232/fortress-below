"""Build derived runtime assets while retaining the artist's original files.

Requires fonttools, imageio-ffmpeg and numpy. Install them in a separate tools
environment; none are runtime dependencies of the game. Run this after editing
localized text, numeric character literals, animation profiles or asset paths.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import wave

from fontTools import subset
from fontTools.ttLib import TTFont
import imageio_ffmpeg
import numpy as np

FONT_SOURCE = "game/assets/fonts/fusion_pixel_12px_zh_hans.ttf"
FONT_DERIVATIVE = "game/assets/fonts/optimized/fortress_pixel_12px_zh_hans.ttf"
MUSIC_NAMES = ("goblins_den", "goblins_dance")
EXTRA_CODEPOINTS = {0xFF01, 0x9AB7, 0x9AC5, 0x91CD, 0x7532, 0x6D6E, 0x7A7A,
                    0x9B54, 0x9885, 0x5438, 0x8840, 0x9B3C, 0x54E5, 0x5E03,
                    0x6797, 0x70B8, 0x5F39, 0x91D1, 0x5E01, 0x5F13, 0x7BAD,
                    0x5854, 0x5C01, 0x5370, 0x589E, 0x63F4}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def codepoints_from_text(text: str) -> set[int]:
    result = {ord(character) for character in text if ord(character) >= 32}
    result.update(int(value, 16) for value in re.findall(r"\\u([0-9a-fA-F]{4})", text))
    result.update(int(value, 16) for value in re.findall(r"\\U([0-9a-fA-F]{8})", text))
    result.update(int(value, 16) for value in re.findall(r"\b0x([0-9a-fA-F]{2,6})\b", text))
    return {cp for cp in result if 32 <= cp <= 0x10FFFF and not 0xD800 <= cp <= 0xDFFF}


def required_codepoints(project: Path) -> set[int]:
    inputs = [project / "project.godot", project / "docs/localization/game.zh.csv",
              project / "game/data/monsters/animation_profiles.json"]
    inputs += sorted((project / "game").rglob("*.gd"))
    result = set(range(32, 127)) | EXTRA_CODEPOINTS
    for path in inputs:
        result.update(codepoints_from_text(path.read_text(encoding="utf-8-sig")))
    return result


def glyph_signature(font: TTFont, name: str) -> tuple:
    coordinates, endpoints, flags = font["glyf"][name].getCoordinates(font["glyf"])
    return (tuple(map(tuple, coordinates)), tuple(endpoints), tuple(flags), font["hmtx"][name])


def build_font(project: Path) -> dict:
    source_path = project / FONT_SOURCE
    source_sha = sha256(source_path)
    font = TTFont(source_path, recalcTimestamp=False)
    codepoints = required_codepoints(project)
    cmap = font.getBestCmap()
    missing = sorted(codepoints - set(cmap))
    if missing:
        raise ValueError("Source font lacks required glyphs: " + ", ".join(f"U+{cp:04X}" for cp in missing))
    signatures = {cp: glyph_signature(font, cmap[cp]) for cp in codepoints}
    options = subset.Options()
    options.hinting = True
    options.glyph_names = True
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.recalc_timestamp = False
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=sorted(codepoints))
    worker.subset(font)
    # Name the derived subset independently; preserve copyright/license records.
    for record in font["name"].names:
        replacement = {1: "Fortress Below Pixel", 2: "Regular", 3: "FortressBelowPixel-12px-Subset-1",
                       4: "Fortress Below Pixel 12px", 6: "FortressBelowPixel12px",
                       16: "Fortress Below Pixel", 17: "Regular"}.get(record.nameID)
        if replacement is not None:
            record.string = replacement.encode(record.getEncoding())
    output = project / FONT_DERIVATIVE
    output.parent.mkdir(parents=True, exist_ok=True)
    font.save(output)
    compact = TTFont(output)
    compact_map = compact.getBestCmap()
    for cp in codepoints:
        if glyph_signature(compact, compact_map[cp]) != signatures[cp]:
            raise ValueError(f"Subsetting altered U+{cp:04X} pixel outlines/metrics")
    if sha256(source_path) != source_sha:
        raise RuntimeError("The original font changed during generation")
    return {"path": FONT_DERIVATIVE, "source": FONT_SOURCE, "source_sha256": source_sha,
            "sha256": sha256(output), "source_bytes": source_path.stat().st_size,
            "bytes": output.stat().st_size, "glyph_count": len(codepoints),
            "codepoints": sorted(codepoints), "outline_and_advance_verified": True}


def decode_pcm(ffmpeg: str, path: Path) -> np.ndarray:
    command = [ffmpeg, "-v", "error", "-i", str(path), "-f", "f32le", "-acodec", "pcm_f32le", "-"]
    return np.frombuffer(subprocess.check_output(command), dtype="<f4")


def build_music(project: Path, name: str) -> dict:
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    original = project / f"game/assets/audio/music/{name}.wav"
    output = project / f"game/assets/audio/music/optimized/{name}.ogg"
    source_sha = sha256(original)
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(original), "-map_metadata", "-1",
                    "-c:a", "libvorbis", "-q:a", "5", str(output)], check=True)
    with wave.open(str(original), "rb") as audio:
        channels, sample_rate, frames = audio.getnchannels(), audio.getframerate(), audio.getnframes()
    source = decode_pcm(ffmpeg, original).reshape(-1, channels)
    compact = decode_pcm(ffmpeg, output).reshape(-1, channels)
    # Vorbis granule positions trim encoder padding; each loop keeps its duration.
    if compact.shape != source.shape:
        raise ValueError(f"Music duration/frame count changed for {name}: {source.shape} -> {compact.shape}")
    signal_rms = float(np.sqrt(np.mean(np.square(source, dtype=np.float64))))
    error_rms = float(np.sqrt(np.mean(np.square(source - compact, dtype=np.float64))))
    if signal_rms <= 0.0 or error_rms / signal_rms > 0.06:
        raise ValueError(f"Music codec verification failed for {name}")
    source_seam = float(np.max(np.abs(source[-1] - source[0])))
    derived_seam = float(np.max(np.abs(compact[-1] - compact[0])))
    if derived_seam > source_seam + 0.005:
        raise ValueError(f"Music conversion introduced a larger loop discontinuity for {name}")
    if sha256(original) != source_sha:
        raise RuntimeError("The original music changed during generation")
    return {"path": output.relative_to(project).as_posix(), "source": original.relative_to(project).as_posix(),
            "source_sha256": source_sha, "sha256": sha256(output), "source_bytes": original.stat().st_size,
            "bytes": output.stat().st_size, "codec": "Ogg Vorbis", "quality": 5,
            "sample_rate": sample_rate, "channels": channels, "frames": frames,
            "duration_seconds": frames / sample_rate,
            "signal_to_codec_error_db": float(20 * np.log10(signal_rms / max(error_rms, 1e-12))),
            "source_loop_seam_peak": source_seam,
            "derived_loop_seam_peak": derived_seam,
            "sample_count_preserved": True}


def runtime_files(project: Path) -> list[str]:
    profiles = json.loads((project / "game/data/monsters/animation_profiles.json").read_text(encoding="utf-8"))
    files = {FONT_DERIVATIVE, "game/data/monsters/animation_profiles.json",
             "docs/localization/game.zh.csv", "game/assets/icons/game_icon.png"}
    files.update(f"game/assets/icons/{name}.png" for name in ("coin", "tower", "shield", "bell", "heart", "bag", "key", "sound"))
    # Monster paths come from runtime JSON, not the scene dependency graph.
    for profile in profiles.values():
        for animation in profile["animations"].values():
            files.update(path.removeprefix("res://") for path in animation["paths"])
    files.update(f"game/assets/tiny_swords/{name}.png" for name in ("tilemap_flat", "castle", "wood_tower", "tree", "explosions"))
    files.update(f"game/assets/tiny_swords_ui/{name}.png" for name in ("panel", "button", "button_hover", "button_pressed", "button_disabled"))
    files.update(f"game/assets/tiny_rpg/soldier_{name}.png" for name in ("idle", "walk", "attack", "bow", "hurt", "death"))
    files.add("game/assets/tiny_rpg/arrow.png")
    files.update(f"game/assets/dungeon/{name}.png" for name in ("tileset", "chest", "chest_open", "key", "potion", "spikes_idle", "spikes_active"))
    for family in ("chest", "mini_chest"):
        for n in range(1, 5):
            files.add(f"game/assets/dungeon/items/{family}/{family}_{n}.png")
            files.add(f"game/assets/dungeon/items/{family}/{family}_open_{n}.png")
    files.update(f"game/assets/dungeon/items/torch/torch_{n}.png" for n in range(1, 5))
    files.update(f"game/assets/fx/{name}.png" for name in ("hit", "arrow_hit", "heal", "burst", "skull_cast", "skull_bolt", "skull_impact"))
    files.update(f"game/assets/audio/music/optimized/{name}.ogg" for name in MUSIC_NAMES)
    files.update(f"game/assets/audio/sfx/{name}.wav" for name in ("sword", "sword_hit", "bow", "player_hurt", "player_death", "enemy_hurt", "enemy_death", "chest", "heal", "supply", "rally"))
    files.add("game/assets/audio/sfx/gate.mp3")
    for path in files:
        if not (project / path).is_file():
            raise FileNotFoundError("Required runtime asset: " + path)
    return sorted(files)


def write_manifest(project: Path, generated: list[dict]) -> dict:
    source_paths = [FONT_SOURCE] + [f"game/assets/audio/music/{name}.wav" for name in MUSIC_NAMES]
    manifest = {"version": 1, "files": runtime_files(project),
                "scripts_scenes_balance": "Include all game/**/*.gd, game/**/*.tscn and game/**/*.tres separately.",
                "csv_import_mode": "keep",
                "preserved_sources": [{"path": path, "sha256": sha256(project / path)} for path in source_paths],
                "generated_assets": generated,
                "requires_modules": ["vorbis", "ogg", "mp3", "text_server_adv", "freetype"],
                "note": "Original assets remain in development; only derived fonts/music ship. Gameplay data and dynamic sprites are explicit."}
    destination = project / "config/runtime_assets.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    if args.verify_only:
        manifest = json.loads((project / "config/runtime_assets.json").read_text(encoding="utf-8"))
        for item in manifest["preserved_sources"] + manifest["generated_assets"]:
            if sha256(project / item["path"]) != item["sha256"]:
                raise ValueError("Asset fingerprint mismatch: " + item["path"])
        derivative = TTFont(project / FONT_DERIVATIVE)
        missing = required_codepoints(project) - set(derivative.getBestCmap())
        if missing:
            raise ValueError("New UI glyphs require rebuilding the font subset")
        if runtime_files(project) != manifest["files"]:
            raise ValueError("Runtime assets changed; regenerate the manifest")
        print("Asset hashes, runtime glyph coverage and manifest verified.")
        return
    generated = [build_font(project)] + [build_music(project, name) for name in MUSIC_NAMES]
    manifest = write_manifest(project, generated)
    print(json.dumps({"assets": [{key: item[key] for key in ("path", "source_bytes", "bytes")} for item in generated],
                      "runtime_file_count": len(manifest["files"])}, indent=2))


if __name__ == "__main__":
    main()
