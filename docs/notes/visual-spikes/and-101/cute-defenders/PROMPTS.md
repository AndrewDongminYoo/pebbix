# AND-101 cute defenders image-generation manifest

The operator approved the 9:16 gameplay prototype on 2026-08-08 before individual asset production began.
All accepted raster concepts use the built-in imagegen pipeline.
The tool does not expose a model identifier, so the model is `[UNKNOWN]`.

## Approved prototype provenance

| Asset                    | Source output                                   | Raw source SHA-256                                                 |
| ------------------------ | ----------------------------------------------- | ------------------------------------------------------------------ |
| `prototype-gameplay.png` | `exec-d5816e25-1fc8-45e9-af9b-2bcfdc1e4350.png` | `8b97eedd28c05b5e601488b0b4190340ce612475298141a5f668192f12f52b79` |

The accepted prototype is the second revision in its chain.
The first generated composition, `exec-3fc59d8d-92aa-47db-b0a1-f1ab7676a69c.png`, established the original squad and gameplay hierarchy but was rejected because the dotted preview did not match the launcher angle.
The alignment correction, `exec-509cdd4a-af57-4851-9574-f433175cd947.png`, was then rejected because the characters remained too large, detailed, and hero-mascot-like.
The final approved revision simplified the cast to four same-species neighbors and added an original non-Earth home planet.

The operator-supplied screenshots were used only to identify high-level mood traits: small harmless characters, minimal facial marks, a bright 2D casual surface, and an ensemble defending a planet.
No screenshot is redistributed in this packet.

## Shared visual contract

```plaintext
Pebbix cute defenders style, non-negotiable:
Bright flat 2D cartoon art for a general-casual cosmic puzzle game.
Tiny same-species bean-shaped alien neighbors with short limbs, simple dot or short-oval eyes, tiny line mouths, small blush marks, and varied antenna shapes.
Thin consistent dark indigo-brown outlines, clean solid fills, almost no shading, and at most one small hard highlight on bubbles.
The defenders look gentle, ordinary, comically unqualified, and lovable rather than heroic, armed, infant-like, monstrous, or plush.
Use deep indigo, turquoise, lilac, mint, muted peach, coral, cyan, and warm amber.
Keep silhouettes and symbols readable at phone size.

Never copy supplied characters, poses, cannon, Earth, bubble arrangement, HUD, typography, palette mapping, or composition.
Never use Bubble Bobble or Puzzle Bobble characters or motifs.
No 3D render, clay, glossy plastic, airbrushing, soft bloom, photorealism, painterly texture, realistic material, dramatic lighting, armor, firearm, military cannon, baby props, text, logo, or watermark unless an application prompt explicitly requests approved UI copy.
```

## Processing contract

Transparent source images use a uniform chroma-key background and the installed helper.

```bash
uv run --with pillow python3 "$IMAGEGEN_ROOT/scripts/remove_chroma_key.py" --input <source.png> --out <accepted.png> --auto-key border --soft-matte --transparent-threshold 12 --opaque-threshold 220 --despill
```

The Pillow helper could not run in this session because its default cache was not writable and the task-local cache could not reach PyPI.
The accepted cutouts therefore use the documented ImageMagick fallback below.

## Accepted outputs

| Accepted asset            | Source output                                   | Raw source SHA-256                                                 | Accepted SHA-256                                                   |
| ------------------------- | ----------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| `prototype-gameplay.png`  | `exec-d5816e25-1fc8-45e9-af9b-2bcfdc1e4350.png` | `8b97eedd28c05b5e601488b0b4190340ce612475298141a5f668192f12f52b79` | `cd0dca88ff03d206c00434727b67b826ef1804e5c3f1125b980db876a1ee67c7` |
| `background-concept.png`  | `exec-9351684c-b833-4d24-8c80-39a49e359c29.png` | `8c703cf6c7b8a31f6e8180ed12bd6a514cf0fe878fc927114bcf65e4dd1c3669` | `2e65c1e2b0d83481f6dc714355123fcef1cae2ca3d2ca4f16f5a325e71ad4dae` |
| `bubble-star.png`         | `exec-62c930da-ac3b-4bce-a679-39f7d796b8cf.png` | `ef4a36bd2cefb48153ed79af7c9cf0e28e382f11cd1c2bccaa77fdd5569cfec1` | `95fa1c7b4532b7d76c173677ac110735d1964d19c0cc4bd6ba7e52f153b1c2d1` |
| `bubble-ring.png`         | `exec-2469b4a3-c572-41bd-95c2-3e172b162e07.png` | `96bd98ff3db0f4154cf2594ee52b110a70a8f6c0ba526ca260a2f7d63ff3c1f3` | `928bfbcc149758cbca5ded67fcb4f70a2a1dfd759ab2ee03a75c3df4ef46fadb` |
| `defender-squad-body.png` | `exec-7b0f02d8-50a3-46c2-b67f-f2c1c83c57b1.png` | `5bfc223c2df6c692ad38a412f6807caa49424db8874fc63e47cdf8b6e15d6b11` | `e666a7781f2e43acc083e53a5624b7e9da25914c2e2522470b8d64213a856b32` |
| `cosmo-launcher-arm.png`  | `exec-d2024328-e10a-41ae-ae66-90dacda2a1a2.png` | `12773dcc7467083133b1faffab4bbb441d682c8f78e57f1c514787e579ebe0f5` | `ad5335f278abe00c935d89957fc3d425d52ee8f8c15d520a4ece0b9d5b9246f7` |
| `game-over-comp.png`      | `exec-e586a5e5-2179-4f4f-bbab-3cb537b49fca.png` | `1fb932e06bd0465ecc42fb74fbbc78ac41501e30504e48782c96b4e537cf5471` | `f2538bc5c1fc34c4576d8f6ae579a40a59f7fdcaa6f27f104030c534108ca7aa` |
| `app-icon-thumbnails.png` | `exec-8114e645-2fee-4341-82ca-e4465800854f.png` | `28deb0e2ddb1240e69c4105790594a8705c09d45fd6a2b89a0c881e2641623f2` | `d714912814d8737c4eb68b576c8dd155279db031c6c3859243caa503757de28e` |

The locally composed evidence outputs have these accepted hashes.

| Evidence asset                  | Accepted SHA-256                                                   |
| ------------------------------- | ------------------------------------------------------------------ |
| `cosmo-aim-angles.png`          | `c0b60c054cb098111698f90f06d5f5d2fbf2b7ace4c362c8f02d0cbfab6bb0b9` |
| `bubble-accessibility-22px.png` | `cee4db6e2aed1512bdaf23ec36770c1ccdb6089d61e76e7cb98a93b64d1adea6` |
| `and-101-approval-board.png`    | `c4c204dc84308a275a16186f1aeb433bb4d0e8f73a08b59ed5944b40e7ce7def` |

Trunk `1.25.0` optimized every accepted PNG with `oxipng` `10.1.1` before these derivative hashes were recorded, except the `2400 × 1600` approval board, which Trunk reported as an ignored large file.

## Reference chain

| Generation call             | Material references                                                                               |
| --------------------------- | ------------------------------------------------------------------------------------------------- |
| Approved gameplay prototype | Earlier prototype revision and operator feedback; supplied screenshot used as mood-only reference |
| Background                  | None                                                                                              |
| Star bubble                 | None                                                                                              |
| Ring bubble                 | Raw star bubble for scale, outline, and highlight consistency                                     |
| Defender squad body         | Approved gameplay prototype                                                                       |
| Launcher arm                | Approved gameplay prototype and raw defender body for silhouette and registration                 |
| Game-over composition       | Initial result composition for a scoped acting correction                                         |
| App-icon thumbnails         | Approved gameplay prototype, accepted body, star bubble, and ring bubble                          |

Two generated prototype sources were rejected before approval.
`exec-3fc59d8d-92aa-47db-b0a1-f1ab7676a69c.png`, SHA-256 `1fed439cae7133faa68ea9c2c32443a6563a3e272f26f4eda601f41981515a87`, had a trajectory preview that did not match its angled launcher.
`exec-509cdd4a-af57-4851-9574-f433175cd947.png`, SHA-256 `29b1c990ede89e3f933153f4664a286201e31dfe4328ffd5208770629b35c5b7`, corrected the aim but retained large, detailed hero-mascot characters.
The first isolated arm, `exec-d689b0f8-79ac-420c-9bf8-8e33e6948f1b.png`, SHA-256 `197a9d894a0e703176d7fe4a53aad01059f5139d2b97d93069f477a6d68fd84a`, was rejected because its thin rod silhouette did not match the approved prototype's thick telescope.
The first result composition, `exec-61f4040f-8a09-4eef-9550-f4406af42638.png`, SHA-256 `cad9de75cc35eb15ed8aed2bc118ae4400ca7671b9046d97a3a651a84fbb8dc1`, was revised because a smiling thumbs-up reaction read as celebration after a loss.

## Per-asset generation briefs

The shared visual contract above applies to every brief.
These blocks record the accepted generation requirements without tool-call syntax.

### Background

```plaintext
Create one portrait 2:3 background-only concept.
Keep a calm dark central play lane through the middle and lower two-thirds.
Concentrate two shallow flat nebula arcs and sparse geometric stars near the upper and outer edges.
Place only two or three tiny original ringed or striped planets near the margins.
Exclude characters, faces, a home-planet focal object, bubbles, launcher, UI, text, photographic space, and 3D rendering.
```

### Star bubble

```plaintext
Create exactly one front-facing coral-red round bubble on a square pure-green chroma-key canvas.
Use one thin indigo-brown outline, one restrained hard highlight, and one bold dark five-point star occupying about 48 percent of the diameter.
Keep the star legible in grayscale at 22 by 22 pixels.
Exclude faces, extra symbols, cast shadows, glow, transparent glass, candy styling, text, and clipped edges.
```

### Ring bubble

```plaintext
Edit the star bubble into a scale-matched cyan-teal companion on a square pure-magenta chroma-key canvas.
Replace the star with one bold open-centered ring plus one short diagonal orbital slash occupying about 48 percent of the diameter.
Keep the ring distinct in grayscale at 22 by 22 pixels and exclude warm colors from the bubble itself.
Preserve the circle, outline, highlight, and margin.
```

### Defender squad body

```plaintext
Using the approved gameplay prototype as the character reference, create one isolated square body layer.
Show the same four small alien neighbors in a shallow row across the lower half: a worried neighbor, a repair neighbor with a tiny wrench, seated Cosmo, and a cheering neighbor.
Include the small pedestal and support but remove the telescope arm, loaded bubble, projectile, and trajectory dots.
Leave one clean circular registration socket on the vertical centerline with empty space above it.
Use a pure-green chroma-key background and exclude ground, UI, text, heroic styling, and detailed accessories.
```

### Launcher arm

```plaintext
Using the approved gameplay prototype and body source for registration, create a same-size square layer containing only one compact repaired hobby-telescope arm pointing exactly straight up.
Place a quiet circular pivot hub over the body socket, extend one short thick silver-gray tube upward along the hub centerline, and use a muted repair sleeve, two flat tape patches, one cyan direction stripe, and a broad cyan-rimmed muzzle.
Match the approved prototype's chunky improvised telescope rather than a rod, wand, antenna, stick, or eyelet.
Use a pure-green chroma-key background.
Exclude characters, wrench, pedestal, support, bubble, projectile, trajectory dots, firearm, cannon, and military hardware.
```

### Game-over composition

```plaintext
Create one portrait 9:16 result screen using the approved gameplay prototype and background as visual authority.
Show a compressed engraved-symbol bubble ceiling, the original non-Earth home planet, one centered result panel, and the four small defenders around the harmless launcher at the bottom.
Render exactly GAME OVER, SCORE, 12,480, CONTINUE, and SKIP once each.
Keep the squad mildly frazzled but hopeful, with clasped hands and concerned expressions rather than raised arms, broad smiles, or a thumbs-up.
Exclude ads, prices, hearts, copied UI, large weapons, and extra text.
```

### App-icon thumbnails

```plaintext
Create one square two-by-two contact sheet with four mask-safe crops.
Explore Cosmo's face, Cosmo seated beside a small telescope, the four-neighbor squad, and Cosmo holding the star and ring bubbles.
Keep the approved species, simple expressions, flat mint and peach palette, and deep cosmic field readable at 64 pixels.
Exclude text, logos, badges, duplicate crops, heroic poses, detailed weapons, baby props, and familiar mascot designs.
```

## Transparent-cutout fallback

The installed Pillow helper was attempted first with the processing command documented above.
It failed before writing an output because the local uv cache was not writable, and a task-local `UV_CACHE_DIR` could not resolve `pypi.org` in the restricted environment.
The fallback used ImageMagick `7.1.2-29` with a key-specific transparency threshold.

```bash
magick <source.png> -alpha on -fuzz 26% -transparent '#00ff00' <accepted.png>
magick <source.png> -alpha on -fuzz 26% -transparent '#ff00ff' <accepted.png>
```

All four accepted cutouts are `1254 × 1254` sRGBA PNGs with `srgba(0,0,0,0)` at `(0, 0)`.
The star and ring were inspected together over a dark indigo field after processing.

The accepted raw launcher cutout trimmed to `279 × 818` pixels.
It was resized to `45%`, producing a `126 × 368` object, then placed at `(564, 611)` on a transparent `1254 × 1254` canvas.
This makes its hub center coincide with the body socket at the final pivot `(627, 925)`.

```bash
magick <launcher-cutout.png> -trim +repage -resize 45% <launcher-scaled.png>
magick -size 1254x1254 xc:none <launcher-scaled.png> -geometry +564+611 -composite cosmo-launcher-arm.png
```

## Aim-angle proof

The proof rotates only the accepted arm around `(627, 925)` and composites the result over unchanged copies of the body.

```bash
magick cosmo-launcher-arm.png -virtual-pixel transparent -distort SRT '627,925 1 -35 627,925' arm-minus35.png
magick cosmo-launcher-arm.png -virtual-pixel transparent -distort SRT '627,925 1 35 627,925' arm-plus35.png
```

The final board contains the negative, neutral, and positive composites in that order.
The accepted proof deliberately contains no embedded angle labels; its surrounding approval board supplies the labels and pivot.

## Accessibility proof

Each accepted bubble is trimmed, fitted inside an exact `22 × 22` transparent extent, and duplicated in grayscale.
A translucent diagonal cyan or amber pop flare is then composited over the grayscale bubble itself, crossing the symbol rather than sitting behind the sprite.
The six exact-size results are enlarged by a factor of ten with nearest-neighbor filtering for inspection.

```bash
magick <bubble.png> -trim +repage -resize 20x20 -gravity center -background none -extent 22x22 <bubble-22.png>
magick <bubble-22.png> -colorspace Gray <bubble-gray-22.png>
magick <proof-22.png> -filter point -resize 220x220 <proof-large.png>
```

The first full-strength flare trial obscured both symbols and was rejected.
The accepted two-pixel effect streaks cross the central geometry while leaving the star and ring distinguishable.

## Approval board

The `2400 × 1600` approval board is composed locally with ImageMagick and the system `SFNS.ttf` font.
It presents the approved gameplay prototype, result state, background, transparent bubbles, icon sheet, three-angle proof, accessibility proof, palette, pivot, and status labels without modifying any source image.
