"""Run native production API/controller against real Go handlers; no providers."""
from pathlib import Path
import os
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
scratch=Path.home()/'.hermes/cache/scratch'
with tempfile.TemporaryDirectory(prefix='dictation-native-wire-',dir=scratch) as folder:
    executable=Path(folder)/'server.test'
    subprocess.run(['go','test','-c','-o',str(executable)],cwd=ROOT/'server',check=True)
    env=dict(os.environ,DICTATION_NATIVE_BRIDGE_EXECUTABLE=str(executable))
    subprocess.run(['swift','test','--filter','DictationGoBridgeTests'],cwd=ROOT/'native/Core',env=env,check=True)
