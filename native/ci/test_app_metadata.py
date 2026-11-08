"""Regression for App Store validation error 90474."""
import plistlib
import unittest
from pathlib import Path

class AppMetadataTests(unittest.TestCase):
    def test_ipad_multitasking_has_all_four_orientations(self):
        required = {'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
                    'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}
        for name in ('Info.plist', 'Info-Debug.plist'):
            with self.subTest(name=name):
                data = plistlib.loads((Path(__file__).resolve().parents[1] / 'Config' / name).read_bytes())
                actual = set(data.get('UISupportedInterfaceOrientations~ipad', data['UISupportedInterfaceOrientations']))
                self.assertTrue(required <= actual, f'Missing iPad orientations: {required - actual}')
