"""Generate synthetic JSON with the actual Go store, then decode it in Swift.
No backend sources are modified and no provider/network application calls occur.
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    scratch = Path(os.environ.get("TMPDIR", str(Path.home() / ".hermes/cache/scratch")))
    with tempfile.TemporaryDirectory(prefix="podcast-wire-", dir=scratch) as directory:
        path = Path(directory)
        overlay = path / "overlay.json"
        overlay.write_text(json.dumps({"Replace": {
            str(ROOT / "server/native_wire_fixture_test.go"): str(ROOT / "native/ci/podcast_wire_fixture_test.go")
        }}))
        env = dict(os.environ, KM_PODCAST_WIRE_DIR=directory)
        subprocess.run(["go", "test", "-overlay", str(overlay), "-run", "^TestNativePodcastWireFixture$", "-count=1", "-v", "."], cwd=ROOT / "server", env=env, check=True)
        subprocess.run(["swift", "test", "--package-path", str(ROOT / "native/Core"), "--filter", "PodcastWireShapeTests"], env=env, check=True)


if __name__ == "__main__":
    main()
