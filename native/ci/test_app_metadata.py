"""Regressions for App Store metadata and recurring Missing Compliance."""
import os
import plistlib
import unittest
from pathlib import Path

class AppMetadataTests(unittest.TestCase):
    def test_source_plists_declare_only_exempt_encryption(self):
        # Reassess docs/TESTFLIGHT.md when native crypto/dependencies change.
        for name in ('Info.plist', 'Info-Debug.plist'):
            with self.subTest(name=name):
                data = plistlib.loads((Path(__file__).resolve().parents[1] / 'Config' / name).read_bytes())
                self.assertIs(data.get('ITSAppUsesNonExemptEncryption'), False,
                              'Declare exempt encryption with a plist Boolean, not a string or missing key')

    @unittest.skipUnless(os.environ.get('KM_BUILT_APP_PLIST'),
                         'Set KM_BUILT_APP_PLIST after xcodebuild to check effective app metadata')
    def test_effective_built_plist_declares_only_exempt_encryption(self):
        path = Path(os.environ['KM_BUILT_APP_PLIST'])
        data = plistlib.loads(path.read_bytes())
        self.assertEqual(data.get('CFBundleIdentifier'), 'de.keinemagie.app')
        self.assertIs(data.get('ITSAppUsesNonExemptEncryption'), False,
                      f'Processed app plist lost the exempt-encryption declaration: {path}')

    def test_ipad_multitasking_has_all_four_orientations(self):
        required = {'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
                    'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}
        for name in ('Info.plist', 'Info-Debug.plist'):
            with self.subTest(name=name):
                data = plistlib.loads((Path(__file__).resolve().parents[1] / 'Config' / name).read_bytes())
                actual = set(data.get('UISupportedInterfaceOrientations~ipad', data['UISupportedInterfaceOrientations']))
                self.assertTrue(required <= actual, f'Missing iPad orientations: {required - actual}')
