# Defender motion sources

<!-- cspell:words venv fluttergen -->

The approved crew keeps the four mint and peach aliens from [the production art pack](../../../docs/notes/art/and-102-production-art-pack.md).
The built-in imagegen tool generated the five transparent source rows from `assets/images/shooter_body_idle.png`.
The tool did not expose a model identifier.
Exact generation prompts are in [prompts.json](prompts.json).

## Pose contract

| Row           | Facing | Pose order                              |
| ------------- | ------ | --------------------------------------- |
| `loader`      | Left   | Ready, first step, opposite step, place |
| `mechanic`    | Right  | Neutral wrench, pull, push, recoil      |
| `mint_cheer`  | Front  | Ready, blink, crouch/clap, raised arms  |
| `peach_cheer` | Front  | Ready, blink, crouch/clap, raised arms  |
| `base`        | Front  | Fixed pedestal and socket               |

Cells are 256×256 with requested horizontal/vertical margins of 14/20 pixels.
Extraction uses connected components and bounding-box centering to retain the complete wrench.
Curation restores a shared source scale within each row, then registers feet at y=236, x=128 for the carrier and cheerers and x=100 for the mechanic.
The crouches are deliberately shorter than the standing poses.
The renderer registers the loader's hands, the mechanic's wrench, and the pedestal eyelet separately.
It owns all travel and jumps; these pose palettes are not autonomous animation loops.

## Rebuild

The processing dependency is the installed `sprite-gen` subset pinned to upstream revision `9935d674128e512ea9727168252bb544e68c8f69` (2.43.0).
Install its locked environment using the skill's README, then run from the repository root:

```sh
SPRITE_GEN_ROOT=/absolute/path/to/sprite-gen
"$SPRITE_GEN_ROOT/.venv/bin/python" tool/build_defender_sprites.py --sprite-gen-root "$SPRITE_GEN_ROOT"
"$SPRITE_GEN_ROOT/.venv/bin/python" tool/build_defender_sprites.py --sprite-gen-root "$SPRITE_GEN_ROOT" --check
```

The script runs `prepare`, `extract`, `write_curation_atomic`, and `compose-atlas` in the dedicated `build/defender-sprites` directory.
It rejects missing rows, incorrect frame counts, and empty or edge-clipped cells before publishing.
The check compares decoded PNG pixels and parsed JSON so lossless compression and formatting do not invalidate the result.
It generates `assets/images/defender_squad.png`, this directory's `manifest.json`, and `lib/gen/defender_atlas.gen.dart` from the manifest's explicit rectangles.
Do not edit those outputs by hand.
Source rows, the request, and the unstamped curation recipe are the inputs.
Only the atlas PNG is bundled; this source directory is not in the Flutter asset list.

Register a newly named image with FlutterGen 5.15.0 using the repository's `tool/fluttergen.yaml` options.
That version preserves the existing asset API.
The image generator is only needed to change artwork; rebuilding accepted rows makes no image-generation calls.

## Runtime validation

Run the complete desktop game for an interactive review with no recording time limit:

```sh
flutter run -d macos --flavor development --target lib/main_development.dart
```

Use the production game and renderer through the local QA entrypoint:

```sh
flutter build web --no-web-resources-cdn --no-wasm-dry-run --target tool/defender_motion_preview.dart --output build/defender-preview
python3 -m http.server 8794 --bind 127.0.0.1 -d build/defender-preview
```

The browser's `defenderPreview` control can prepare `drop`, `miss`, or `short` fixtures, aim, fire, pause, and resume.
Fixtures use the real solver and projectile, not fabricated landing results.
`status()` reports the actual game phase, queue kinds, delivery progress, codec decode time, decoded RGBA bytes, and CPU update/render timings.
Decoded RGBA bytes are not GPU memory measurements.
This entrypoint excludes audio and external services and is not a production release target.
Structural checks do not establish visual quality: inspect grip contact, the socket handoff, foot registration, facing, return travel, pause, reduced motion, and both 320×568 and 568×320 viewports in the running consumer.
