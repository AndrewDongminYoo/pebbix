# Font asset provenance

The one shipped file in `assets/fonts/`, with the source it came from.

| File                      | Source            | Author        | License | URL                                       | Modifications |
| ------------------------- | ----------------- | ------------- | ------- | ----------------------------------------- | ------------- |
| `PretendardVariable.ttf`  | Pretendard v1.3.9 | Kil Hyung-jin | OFL 1.1 | https://github.com/orioncactus/pretendard | none          |
| `store_headline_bold.ttf` | Pretendard v1.3.9 | Kil Hyung-jin | OFL 1.1 | https://github.com/orioncactus/pretendard | renamed only  |

Both taken verbatim from tag `v1.3.9` — the variable file from `dist/public/variable/`, the headline face from `dist/public/static/alternative/Pretendard-Bold.ttf`.
`OFL.txt` here is that release's own `LICENSE.txt`.

## Why this font

The app renders English and Korean from the same theme, and Poppins — the previous theme font — carries no Hangul, so Korean fell through to whatever the platform substituted.
Pretendard covers both scripts with matching visual weight, which keeps the existing hierarchy rather than forcing a redesign around a second family.

OFL 1.1 permits bundling and redistribution inside an application; the Reserved Font Name clause only forbids shipping a _modified_ font under the name Pretendard, and this file is unmodified.
No attribution is rendered in the app, which OFL does not require — this manifest is what records the obligation.

## Why the variable file rather than statics

The UI uses three weights: regular, bold, and the black on the loading screen.
One variable file (6.7 MB) is a single `pubspec.yaml` entry that serves all three through its `wght` axis, and it removes the failure mode where a screen asks for a weight nobody remembered to bundle.

## Why the headline face is a second, static file

`tool/store_assets/store_assets.dart` composes store art with ImageMagick, which hands the font file to FreeType and cannot drive a variable axis: rendering `점수 Pebbix 1234` at 64pt with `-weight Bold`, `-weight 900`, and no weight flag at all produces byte-identical output from `PretendardVariable.ttf` (grayscale mean 0.949634 in every case). The static Bold measures 0.921667 on the same string — visibly more ink.

So the generator gets `Pretendard-Bold.ttf` under the name it already reads, `store_headline_bold.ttf` (2.7 MB).

It is registered in the `Pretendard` family at weight 700 rather than left in the working tree, because spec 0003 requires the headline face to be an **application-bundled** font (§25 at line 76, and again at 323 and 968) and the post-#41 capture has to prove that.
Store art and the app therefore draw the same bold face by construction, and the cost is 2.7 MB on top of the variable file's 6.7 MB.
Flutter prefers the static face for `FontWeight.w700` and still resolves w400 and w900 off the variable axis.
