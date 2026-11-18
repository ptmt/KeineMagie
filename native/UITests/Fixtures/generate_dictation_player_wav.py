"""Generate the eight-second PCM transport fixture for DictationPlayerUITests.

Example (use a fresh synthetic fixture directory before each full UI suite):
  python3 native/UITests/Fixtures/generate_dictation_player_wav.py \
    --output /Users/tinyserve/.hermes/cache/scratch/dictation-camera-player/clock-fixture.wav

Start server/TestDictationLocalFixture with DICTATION_FIXTURE_CACHED_WAV set to
that file and DICTATION_FIXTURE_DIR set to the sibling fixture directory.
The UI tests use loopback 8799 and fixture/fixture.json. Production admission
and the 30-item history cap remain unchanged. A long combined run needs a
scratch-only timeout overlay, not a change to production limits or handlers.

This is a generated low-level tone, not speech synthesis or provider output.
"""
import argparse
import math
from pathlib import Path
import struct
import wave


def generate(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    sample_rate = 16000
    seconds = 8
    frames = b"".join(
        struct.pack("<h", int(300 * math.sin(2 * math.pi * 220 * i / sample_rate)))
        for i in range(sample_rate * seconds)
    )
    with wave.open(str(output), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(sample_rate)
        audio.writeframes(frames)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    generate(arguments.output)
    with wave.open(str(arguments.output), "rb") as audio:
        print(f"{arguments.output}: {audio.getnframes() / audio.getframerate():.3f}s PCM")
