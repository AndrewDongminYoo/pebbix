# Third-party notices and provenance

The game's noncommercial default does not replace the licenses below.
Retain applicable copyright notices and license texts when redistributing covered material.

| Material                  | Paths                                                                                          | Source and author                                                                                                                                      | Existing terms                                                 |
| ------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| Template-derived portions | Very Good CLI flame_game scaffolding, including lib/loading/widgets/animated_progress_bar.dart | [Very Good Templates](https://github.com/VeryGoodOpenSource/very_good_templates/tree/main/very_good_flame_game), Copyright (c) 2022 Very Good Ventures | MIT; upstream notice retained in LICENSES/MIT.txt              |
| Pop effect                | assets/audio/pop.mp3                                                                           | Kenney Interface Sounds, drop_003.ogg                                                                                                                  | CC0-1.0                                                        |
| Shot effect               | assets/audio/shoot.mp3                                                                         | Kenney Impact Sounds, impactGeneric_light_001.ogg                                                                                                      | CC0-1.0                                                        |
| Ceiling effect            | assets/audio/descent.mp3                                                                       | Kenney Digital Audio, lowDown.ogg                                                                                                                      | CC0-1.0                                                        |
| Game-over effect          | assets/audio/gameover.mp3                                                                      | Kenney Music Jingles, jingles_PIZZI03.ogg                                                                                                              | CC0-1.0                                                        |
| Background loop           | assets/audio/background.mp3                                                                    | Synth-thetic, [Cosmic Navigation](https://opengameart.org/content/cosmic-navigation)                                                                   | CC0-1.0                                                        |
| Pretendard fonts          | assets/fonts/PretendardVariable.ttf and store_headline_bold.ttf                                | Pretendard v1.3.9, Copyright (c) 2021 Kil Hyung-jin, Reserved Font Name Pretendard                                                                     | OFL-1.1; original notice in assets/licenses/pretendard/OFL.txt |
| Original synthesized cues | assets/audio/bomb.mp3 and rainbow.mp3                                                          | This project's tool/generate_special_shot_audio.py; no external samples                                                                                | MIT, as exact project exceptions                               |

The [audio manifest](assets/licenses/audio/MANIFEST.md) records source links, transformations, and regeneration commands.
The [font manifest](assets/licenses/pretendard/MANIFEST.md) records the two files and provenance.
Original game graphics came from image generation and editing; [the motion source README](assets/source/defenders/README.md) and [the art manifest](docs/notes/art/and-102-production-art-pack.md) record source inputs.
No exclusive copyright protection for generated images is promised.

Flutter, Flame, audioplayers, Firebase, Google Mobile Ads, billing plugins, and other dependencies retain their own licenses.
Their source is not relicensed by this repository; preserve required notices when distributing a built app.
Dependency versions are in pubspec.lock and the native package resolution files.
The Flutter license registry includes dependency notices and the explicitly registered Pretendard license.

Quoted Apple responses and other third-party prose remain the rights of their respective owners and are excluded from the selected public snapshot unless separately reviewed and authorized.
Neither the original root MIT file nor a later change establishes ownership of outside contributions or revokes rights granted with earlier versions.
