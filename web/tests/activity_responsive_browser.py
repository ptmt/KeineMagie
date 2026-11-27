"""Compatibility entry point: viewport month rule was superseded by Profile placement."""
from pathlib import Path
import runpy
ROOT=Path(__file__).resolve().parent
runpy.run_path(str(ROOT/'activity_profile_browser.py'),run_name='__main__')
runpy.run_path(str(ROOT/'activity_lifecycle_browser.py'),run_name='__main__')
