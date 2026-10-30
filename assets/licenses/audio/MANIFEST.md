# Audio asset provenance

<!-- cspell:ignore astats -->

Every shipped file in `assets/audio/`, with the source it was cut from.
The five externally sourced files are CC0 1.0 (public domain dedication).
The two original procedural special-shot cues are exact MIT exceptions under [the licensing scope](../../../LICENSE).
The game itself is not MIT.
The rows below preserve sourcing and regeneration details; attribution is not rendered in the app.

| File             | Source                                                                                   | Author         | License                  | URL                                               | Modifications                                                      |
| ---------------- | ---------------------------------------------------------------------------------------- | -------------- | ------------------------ | ------------------------------------------------- | ------------------------------------------------------------------ |
| `pop.mp3`        | Kenney Interface Sounds, `drop_003.ogg`                                                  | Kenney         | CC0 1.0                  | https://kenney.nl/assets/interface-sounds         | ogg → mp3 44.1 kHz VBR; gain −1.89 dB to −3.0 dBFS peak; no trim   |
| `shoot.mp3`      | Kenney Impact Sounds, `impactGeneric_light_001.ogg`                                      | Kenney         | CC0 1.0                  | https://kenney.nl/assets/impact-sounds            | ogg → mp3 44.1 kHz VBR; gain −6.00 dB to −6.9 dBFS peak; no trim   |
| `descent.mp3`    | Kenney Digital Audio, `lowDown.ogg`                                                      | Kenney         | CC0 1.0                  | https://kenney.nl/assets/digital-audio            | ogg → mp3 44.1 kHz VBR; gain −2.37 dB to −3.0 dBFS peak; no trim   |
| `gameover.mp3`   | Kenney Music Jingles, `Pizzicato jingles/jingles_PIZZI03.ogg`                            | Kenney         | CC0 1.0                  | https://kenney.nl/assets/music-jingles            | ogg → mp3 44.1 kHz VBR; gain +1.16 dB to −3.0 dBFS peak; no trim   |
| `background.mp3` | Cosmic Navigation, `cosmic_navigation_loop.flac`                                         | Synth-thetic   | CC0 1.0                  | https://opengameart.org/content/cosmic-navigation | flac → mp3 44.1 kHz VBR; gain −5.21 dB to −10.1 dBFS peak; no trim |
| `bomb.mp3`       | `tool/generate_special_shot_audio.py`, sharp impact, falling bass and seeded blast noise | Pebbix project | MIT (`LICENSES/MIT.txt`) | Original synthesis; no source samples             | mono 44.1 kHz VBR; 0.58 s; decoded peak −6.52 dBFS                 |
| `rainbow.mp3`    | `tool/generate_special_shot_audio.py`, continuous spectral rise and conversion seal      | Pebbix project | MIT (`LICENSES/MIT.txt`) | Original synthesis; no source samples             | mono 44.1 kHz VBR; 0.68 s; decoded peak −6.54 dBFS                 |

## Loudness

There is no runtime mixing beyond the on/off toggles, so the balance is baked into the files.

- SFX sit at about −3 dBFS peak. `shoot.mp3` is held ~4 dB under the rest because it fires on every single shot.
- `background.mp3` sits at −10.1 dBFS peak, −25.7 LUFS integrated — roughly 7 dB under the cues, mid-range of the 6–9 dB the plan calls for.
- Special activation cues sit near −6.5 dBFS peak so the activation remains audible alongside `pop.mp3`.
  Peak measurements do not establish perceived loudness; game playback still requires listening.
  Their PCM peaks are normalized to 0.45 before MP3 encoding; decoded peaks above were measured using FFmpeg `astats`.

## Deviations from the sourcing brief

- `background.mp3` is **153.6 s**, not the 60–120 s the brief targets. The source ships a purpose-made loop file, and trimming it to fit the range would break the seam that makes it loop — a longer loop is the lesser cost. Deviation accepted deliberately, not overlooked.
- No file was trimmed. Every source already fell inside its target length, so cutting would only have risked clipping a natural decay.

## Generating the special-shot cues

Python's standard library synthesizes both signals, with short attack and tail envelopes.
FFmpeg with `libmp3lame` encodes them; no downloaded sounds or Python dependencies are required.

```sh
python3 tool/generate_special_shot_audio.py --output-dir assets/audio
ffmpeg -hide_banner -i assets/audio/bomb.mp3 -af astats -f null -
ffmpeg -hide_banner -i assets/audio/rainbow.mp3 -af astats -f null -
```

## Re-cutting a cue

The unmodified downloads are not committed. Re-fetch from the URL above, then apply the recorded gain:

```sh
ffmpeg -i <source> -af "volume=<gain>dB" -ar 44100 -c:a libmp3lame -q:a 4 assets/audio/<file>
```

Kenney ships a per-pack `License.txt` inside each archive; it is the standard CC0 text plus "Support us by crediting Kenney or www.kenney.nl (this is not mandatory)".
Since CC0 imposes no condition, that text is not vendored here.
