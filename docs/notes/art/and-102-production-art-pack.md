# AND-102 production art pack manifest

Spec §2 package A, produced 2026-08-08 under the operator-approved AND-101 cute-defenders direction.
The visual authority is `docs/notes/visual-spikes/and-101/cute-defenders/`; its shared visual contract and processing contract apply verbatim here.
All new raster sources were generated with the built-in imagegen pipeline; the tool does not expose a model identifier, so the model is `[UNKNOWN]`.

## Symbol and color mapping

The operator approved extending `BubbleColor` from five to six values (2026-08-08) and this mapping.
The engraved symbols are the identity channel; color is secondary, per the spec §5 rule that bubbles differ by symbol, not color alone.

| `BubbleColor`  | Fill                 | Engraved symbol | Asset               | Origin                              |
| -------------- | -------------------- | --------------- | ------------------- | ----------------------------------- |
| `red`          | Coral red            | Five-point star | `bubble_red.png`    | Promoted AND-101 accepted asset     |
| `blue`         | Azure blue `#0078F8` | Ring + slash    | `bubble_blue.png`   | Promoted AND-101 asset, hue-rotated |
| `yellow`       | Warm amber `#FFBF47` | Crescent moon   | `bubble_yellow.png` | New generation                      |
| `green`        | Mint `#79E2C2`       | Triangle        | `bubble_green.png`  | New generation                      |
| `purple`       | Lilac `#B39DEA`      | Diamond         | `bubble_purple.png` | New generation                      |
| `orange` (new) | Peach `#FF9E6B`      | Lightning bolt  | `bubble_orange.png` | New generation                      |

[The 22 px proof](and-102-bubble-22px-proof.png) shows all six accepted sprites at the exact minimum render size, nearest-neighbor enlarged, across the three spec §5 acceptance conditions: full color and grayscale on the dark field, plus color and grayscale over bright radial pop-flash fields (coral and cyan); every symbol stays legible in all four rows.

## Promoted AND-101 assets

Five accepted spike assets were promoted into `assets/images/`; background, idle body, and launcher arm are unmodified byte copies, while the two bubbles were subsequently trimmed to their alpha bounding boxes (see below), and the ring bubble was later hue-rotated from cyan teal to azure blue (`magick -modulate 100,100,120`) after playtesting showed the cyan fill sat too close to the mint triangle in the four-color in-play set (operator decision, 2026-08-08). All provenance chains remain those recorded in the AND-101 manifest.

| Production asset        | Copied from               |
| ----------------------- | ------------------------- |
| `background.png`        | `background-concept.png`  |
| `bubble_red.png`        | `bubble-star.png`         |
| `bubble_blue.png`       | `bubble-ring.png`         |
| `shooter_body_idle.png` | `defender-squad-body.png` |
| `shooter_arm.png`       | `cosmo-launcher-arm.png`  |

The previous `background.png` (AND-99 era, pre-direction) was replaced in place; the neutral `bubble.png` tint sprite was retained for the tint renderer until the AND-102 renderer PR, which removed the tint renderer and deleted `bubble.png` in favor of the per-color engraved sprites.

## New generations

Each call prepended the AND-101 shared visual contract and referenced the accepted star and ring sprites for scale, outline weight, and highlight.
Raw source hashes are SHA-256 over the imagegen output before chroma-key processing; accepted hashes are the committed post-hook files (Trunk oxipng can rewrite bytes without visual change).

| Asset                       | Raw source SHA-256                                                 | Chroma key | Attempts |
| --------------------------- | ------------------------------------------------------------------ | ---------- | -------- |
| `bubble_yellow.png`         | `e14ab14a6ee39d86015b5955995cecf9eee1c86acadb896137eae5e020ffc469` | `#00ff00`  | 1        |
| `bubble_green.png`          | `65baa04db669a3d856464884ed6ed87c2d103df7e30f47ff6c825ada8ee1a3b5` | `#ff00ff`  | 1        |
| `bubble_purple.png`         | `53ff565c0b82f45374536da01f6dae40307c4a9c6d47e5b956943cf02b5322d5` | `#00ff00`  | 1        |
| `bubble_orange.png`         | `d704d66532723a0196ab9c9a93464a2b395a9ed09eca4f16cca3b371c7ff5d4d` | `#00ff00`  | 1        |
| `shooter_body_shooting.png` | `ecc868f7aac92d7c0ce0d8b73c1f9d5fb3f24a6b0751bd5ea5589d0e1496f58c` | `#00ff00`  | 3        |
| `app_icon.png` (branding)   | `4836c952e02d80a514076a8afe4eba5ae231b3f428feb0c6af13637e3c25f950` | none       | 1        |

The green bubble uses the magenta key because a mint fill on the green key would despill the sprite itself.
The shooting state's first attempt drifted to an exaggerated sticker style with a wrong base; the second lost the socket post; the third (accepted) keeps the four characters, the dish, and the gray socket post with its ring eyelet while changing only poses and mouths, with the idle sprite's wrench removed.

The four bubble cutouts used the AND-101 processing contract command (`remove_chroma_key.py --auto-key border --soft-matte --transparent-threshold 12 --opaque-threshold 220 --despill`).
The shooting body instead uses the AND-101 ImageMagick fallback (`magick <raw> -alpha on -fuzz 26% -transparent '#00ff00'`) — the same chain that produced the idle cutout — because the Pillow despill/soft-matte pass misread the pale mint alien bodies as chroma spill, leaving them gray at roughly half alpha.
Like the idle sprite, its fully transparent pixels retain green RGB values, which is invisible at runtime but tints thumbnail previews that ignore alpha.

## Registration alignment note

Early whole-post centroid samples suggested a per-state drift (`(606, 952)` idle vs `(625, 963)` shooting), but those samples were polluted — the idle sprite's gray wrench overlaps the post band and drags its centroid left and down.
Re-measured on the eyelet band alone (gray annulus pixels, `y 855–935`, wrench excluded), the ring centers are `(627, 901)` idle and `(627, 905)` shooting: identical in x and 4 px apart in y, about 0.3 percent of the canvas.
No per-state offsets are needed, but the body and arm register differently: the body layers seat by the eyelet midpoint `(627, 903)`, while the arm rotates around its hub knob, whose circular bulge centers at `(627, ~920)` by row-width profile (the AND-101 layer contract records `(627, 925)`); the renderer therefore keeps a body anchor and an arm pivot as separate constants.

## Splash and app icon

The splash is a deterministic local composition, not a generation:

```bash
magick assets/images/background.png \( assets/images/shooter_body_idle.png -trim +repage -resize 640x \) -gravity south -geometry +0+120 -composite assets/branding/splash.png
```

The app icon reproduces the operator-selected bottom-right cell of the AND-101 icon contact sheet (defender holding the star and ring bubbles), with the important elements held inside the central 80 percent for mask safety.
Masters live in `assets/branding/`, which is deliberately not registered in `pubspec.yaml` — platform icon and splash artifacts are generated from these masters in a follow-up commit, and the masters themselves must not ship inside the app bundle.

## Committed asset hashes

SHA-256 of the files exactly as committed, measured from the git objects after the pre-commit hook's oxipng pass and the bubble trim commit:
The six bubble sprites are committed trimmed to their alpha bounding boxes (roughly `810 × 823`), so the renderer can map the full texture onto the bubble's `radius * 2` box without per-sprite source rectangles; the promoted spike originals remain untrimmed in the AND-101 packet.

| File                                      | SHA-256                                                            |
| ----------------------------------------- | ------------------------------------------------------------------ |
| `assets/images/background.png`            | `2e65c1e2b0d83481f6dc714355123fcef1cae2ca3d2ca4f16f5a325e71ad4dae` |
| `assets/images/bubble_red.png`            | `f3d2c9f0752d5cc98c6ad949540e16945c1ae5f6cb0627d438093e87795661c9` |
| `assets/images/bubble_blue.png`           | `3f9a0b58dbc5de4d953dc7aee0de74501c4825e1c37ddcf954a268679c7a8dae` |
| `assets/images/bubble_yellow.png`         | `4a57bc2ac2c9a0acd6e341f4932421161013e6cb3ee70fb766b65878a0e593a3` |
| `assets/images/bubble_green.png`          | `50318c3064976ac866cea52ac716354942e6ef8c1816e2437601c855f69e7667` |
| `assets/images/bubble_purple.png`         | `7d471c6a73054f4504c5e87e739b8a0a08dc57e072f816b05387fe3a43151a2c` |
| `assets/images/bubble_orange.png`         | `3b483e247af33e2f9a3d5be916ceef2e9d476b2269f4301e2ba27f2c5523abe2` |
| `assets/images/shooter_body_idle.png`     | `e666a7781f2e43acc083e53a5624b7e9da25914c2e2522470b8d64213a856b32` |
| `assets/images/shooter_body_shooting.png` | `270fcbcd32f2201b818838cb29b5533fe1c76bffe1532e5390940274e3864afd` |
| `assets/images/shooter_arm.png`           | `ad5335f278abe00c935d89957fc3d425d52ee8f8c15d520a4ece0b9d5b9246f7` |
| `assets/branding/app_icon.png`            | `61e0eb6062aa1c3c148b2006f38654c33a447004aa269987cb635dde6881d7c0` |
| `assets/branding/splash.png`              | `98411ee0afab782a47a8dddf6532ad7a93e85575323208837e1c7dfff4094041` |

## Scope boundary

This manifest covers asset production and FlutterGen registration only.
The renderer integration — six-value `BubbleColor`, per-symbol sprite rendering, body idle/shooting states, and the rotating launcher arm as the permanent aim cue — lands in the follow-up AND-102 renderer PR.

## Platform branding

Android launcher icons are generated per flavor with `flutter_launcher_icons` 0.14.4 (`dart run flutter_launcher_icons -f flutter_launcher_icons-<flavor>.yaml`): legacy mipmaps from the flavor's badged master and adaptive icons from the padded `#010638` foreground masters.
iOS uses Xcode 26 Icon Composer `.icon` bundles, which the tool cannot write; each bundle's single layer now references the flavor's master PNG directly (`AppIcon.png` inside the bundle's `Assets/`).
The native splash is generated once for all flavors with `flutter_native_splash` 2.4.8 from `flutter_native_splash.yaml`: `#0E0E3F` field with the trimmed squad centered, and an `android_12` block using the 1152 px safe-zone variant.
The `DEV`/`STG` banner badges and all derived masters are composed with ImageMagick from the approved `app_icon.png` and the idle squad sprite; masters stay unbundled in `assets/branding/`.
