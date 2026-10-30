# SPDX-FileCopyrightText: 2026 kr.donminzzi
# SPDX-License-Identifier: MIT

"""Generate original short special-shot cues; no external audio samples are used."""

import argparse
import math
import random
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

SAMPLE_RATE = 44100
PEAK = 0.45


def bomb_samples():
    rng = random.Random(105)
    rumble = 0.0
    samples = []
    for index in range(round(SAMPLE_RATE * 0.58)):
        time = index / SAMPLE_RATE
        noise = rng.uniform(-1, 1)
        rumble = 0.94 * rumble + 0.06 * noise
        attack = min(time / 0.0015, 1)
        # Sharp broadband impact, falling bass body, and a rough blast tail.
        crack = noise * math.exp(-time * 95)
        phase = 2 * math.pi * (42 * time + 90 * 0.07 * (1 - math.exp(-time / 0.07)))
        body = math.sin(phase) * math.exp(-time * 8)
        blast = (noise * 0.3 + rumble * 3) * math.exp(-time * 10)
        reflection = (
            math.sin(2 * math.pi * 83 * time)
            * min(time / 0.035, 1)
            * math.exp(-time * 16)
        )
        tail = min((0.58 - time) / 0.04, 1)
        samples.append(
            attack * tail * (1.1 * crack + 0.9 * body + blast + 0.25 * reflection)
        )
    return samples


def rainbow_samples():
    rng = random.Random(106)
    samples = []
    phase = 0.0
    air = 0.0
    for index in range(round(SAMPLE_RATE * 0.68)):
        time = index / SAMPLE_RATE
        absorption = min(time / 0.36, 1)
        # Continuous spectral rise follows absorption; a stable tone seals the change.
        frequency = 260 + 720 * absorption * absorption if time < 0.36 else 660
        phase += 2 * math.pi * frequency / SAMPLE_RATE
        air = 0.8 * air + 0.2 * rng.uniform(-1, 1)
        attack = min(time / 0.035, 1)
        release = 1 if time < 0.36 else math.exp(-(time - 0.36) * 10)
        shimmer = math.sin(phase + 0.65 * math.sin(2 * math.pi * 7 * time))
        value = shimmer + 0.26 * math.sin(2 * phase) + 0.12 * math.sin(3 * phase)
        seal_age = max(time - 0.36, 0)
        seal = 0.25 * math.sin(2 * math.pi * 1320 * seal_age) * math.exp(-seal_age * 18)
        tail = min((0.68 - time) / 0.035, 1)
        samples.append(
            tail * (attack * release * (value + 0.3 * air * (1 - absorption)) + seal)
        )
    return samples


def encode(samples, destination, temporary_directory):
    maximum = max(abs(sample) for sample in samples)
    pcm = b"".join(
        struct.pack("<h", round(sample / maximum * PEAK * 32767)) for sample in samples
    )
    source = temporary_directory / (destination.stem + ".wav")
    with wave.open(str(source), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(SAMPLE_RATE)
        stream.writeframes(pcm)
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-map_metadata",
            "-1",
            "-c:a",
            "libmp3lame",
            "-q:a",
            "4",
            str(destination),
        ],
        check=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pebbix-special-audio-") as directory:
        for name, samples in (("bomb", bomb_samples()), ("rainbow", rainbow_samples())):
            destination = arguments.output_dir / (name + ".mp3")
            encode(samples, destination, Path(directory))
            print(destination)


if __name__ == "__main__":
    main()
