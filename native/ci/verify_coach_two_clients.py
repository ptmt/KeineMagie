"""Two independent production AppModels, one actual Go authenticated fixture store."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]

def main():
    with tempfile.TemporaryDirectory(prefix='coach-two-', dir=os.environ['TMPDIR']) as tmp:
        folder = Path(tmp)
        env = {**os.environ, 'KM_COACH_TWO_CLIENT_DIR': tmp}
        with (folder/'go.log').open('w+') as log:
            server = subprocess.Popen(['go', 'test', '-race', '-run', '^TestCoachTwoClientBridge$', '-count=1', '.'], cwd=ROOT/'server', env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 40
                while not (folder/'ready.json').exists():
                    if server.poll() is not None or time.monotonic() > deadline:
                        log.seek(0)
                        raise RuntimeError(log.read())
                    time.sleep(.05)
                subprocess.run(['python3', str(ROOT/'native/ci/test_connection_lifecycle.py')], env=env, check=True, timeout=80)
            finally:
                (folder/'stop').touch()
                server.wait(timeout=15)
                log.seek(0)
                print(log.read())
            assert server.returncode == 0

if __name__ == '__main__':
    main()
