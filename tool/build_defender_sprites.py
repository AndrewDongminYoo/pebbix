#!/usr/bin/env python3
"""Rebuild the defender atlas from complete source components and curation."""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

UPSTREAM_REVISION = "9935d674128e512ea9727168252bb544e68c8f69"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sprite-gen-root", required=True, type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = root / "assets/source/defenders"
    skill = args.sprite_gen_root.resolve()
    provenance = json.loads((skill / "UPSTREAM.json").read_text())
    if provenance["revision"] != UPSTREAM_REVISION:
        raise SystemExit("Unexpected sprite-gen revision; review before rebuilding")
    request = json.loads((source / "request.json").read_text())
    for state in request["states"]:
        if not (source / "rows" / f"{state}.png").is_file():
            raise SystemExit(f"Missing source row: {state}")

    run = root / "build/defender-sprites"
    cli = skill / ".venv/bin/sprite-gen"
    subprocess.run(
        [
            str(cli),
            "prepare",
            "--out-dir",
            str(run),
            "--character-id",
            "pebbix-defenders",
            "--base-image",
            str(root / "assets/images/shooter_body_idle.png"),
            "--request",
            str(source / "request.json"),
            "--chroma-key",
            "#00FF00",
            "--force",
        ],
        check=True,
    )
    for state in request["states"]:
        shutil.copyfile(source / "rows" / f"{state}.png", run / "raw" / f"{state}.png")
    subprocess.run([str(cli), "extract", "--run-dir", str(run)], check=True)

    # Run this script with the skill's locked Python environment.
    sys.path.insert(0, str(skill))
    from PIL import Image
    from sprite_gen.curate.curation import write_curation_atomic

    write_curation_atomic(run, json.loads((source / "curation.json").read_text()))
    subprocess.run([str(cli), "compose-atlas", "--run-dir", str(run)], check=True)
    manifest = json.loads((run / "manifest.json").read_text())
    rows = manifest["frame_layout"]["rows"]
    atlas = Image.open(run / "sprite-sheet-alpha.png")
    if atlas.size != (
        manifest["frame_layout"]["sheetWidth"],
        manifest["frame_layout"]["sheetHeight"],
    ):
        raise SystemExit("Atlas dimensions disagree with the manifest")

    dart = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND",
        "// Source: assets/source/defenders/manifest.json",
        "// Rebuild: tool/build_defender_sprites.py",
        "// coverage:ignore-file",
        "",
        "import 'dart:ui';",
        "",
        "const defenderFrameRects = <String, List<Rect>>{",
    ]
    for state, frames in rows.items():
        if len(frames) != request["states"][state]["frames"]:
            raise SystemExit(f"Unexpected frame count: {state}")
        dart.append(f"  '{state}': [")
        for index, frame in enumerate(frames):
            x, y, w, h = (frame[key] for key in ("x", "y", "w", "h"))
            cell = atlas.crop((x, y, x + w, y + h))
            box = cell.getchannel("A").getbbox()
            if box is None or min(box[0], box[1], w - box[2], h - box[3]) < 8:
                raise SystemExit(f"Empty or clipped frame: {state}/{index}")
            dart.append(f"    Rect.fromLTWH({x}, {y}, {w}, {h}),")
        dart.append("  ],")
    dart.extend(["};", ""])

    outputs = {
        root
        / "assets/images/defender_squad.png": (
            run / "sprite-sheet-alpha.png"
        ).read_bytes(),
        source / "manifest.json": (json.dumps(manifest, indent=2) + "\n").encode(),
        root / "lib/gen/defender_atlas.gen.dart": "\n".join(dart).encode(),
    }
    for destination, content in outputs.items():
        if args.check:
            matches = destination.is_file()
            if matches and destination.suffix == ".png":
                # Lossless PNG optimizers may change compression, not pixels.
                with Image.open(destination) as existing:
                    matches = (
                        existing.size == atlas.size
                        and existing.convert("RGBA").tobytes()
                        == atlas.convert("RGBA").tobytes()
                    )
            elif matches and destination.suffix == ".json":
                matches = json.loads(destination.read_bytes()) == json.loads(content)
            elif matches:
                matches = destination.read_bytes() == content
            if not matches:
                raise SystemExit(
                    f"Generated output is stale: {destination.relative_to(root)}"
                )
        else:
            destination.write_bytes(content)
    print("Defender atlas matches sources" if args.check else "Defender atlas rebuilt")


if __name__ == "__main__":
    main()
