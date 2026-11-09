"""Runnable localization and login-surface contracts; no Xcode dependency."""
import json
import plistlib
import re
import unittest
from pathlib import Path

NATIVE = Path(__file__).resolve().parents[1]
LOCALES = {'de', 'en', 'ru', 'es', 'fr'}

class LoginSurfaceTests(unittest.TestCase):
    def test_four_capability_rows_and_native_bottom_auth(self):
        source = (NATIVE / 'App/KeineMagieApp.swift').read_text()
        gate = source.split('struct LoginGate: View')[1].split('private struct FeatureRow: View')[0]
        self.assertEqual(re.findall(r'FeatureRow\("(feature\.[^"]+)"', gate),
                         ['feature.translator', 'feature.dictation', 'feature.podcasts', 'feature.coach'])
        self.assertIn('.safeAreaInset(edge: .bottom)', gate)
        self.assertIn('NativeAppleButton', gate)
        self.assertNotIn('ChatGPT', gate)
        self.assertNotIn('.accessibilityLabel(', gate)  # Apple supplies matching native localized label.
        for phase in ['offline', 'restoring', 'preparing', 'authorizing', 'exchanging', 'loggingOut']:
            self.assertIn('case .' + phase, gate)
        self.assertIn('cancelLogin()', gate)
        self.assertIn('session.message', gate)

class LocalizationTests(unittest.TestCase):
    def test_app_catalog_covers_every_ui_literal_and_five_locales(self):
        catalog = json.loads((NATIVE / 'App/Localizable.xcstrings').read_text())
        self.assertEqual(catalog['sourceLanguage'], 'de')
        keys = set(catalog['strings'])
        for path in (NATIVE / 'App').glob('*.swift'):
            source = path.read_text()
            literals = re.findall(r'(?:Text|Label|Button|Section|ProgressView|FeatureRow|navigationTitle|accessibilityLabel)\(\s*"([^"\n]*)"', source)
            for key in literals:
                if key.startswith('https://') or key == 'Keine Magie':
                    continue
                self.assertIn(key, keys, (path.name, key))
        for path in (NATIVE / 'App').glob('*.swift'):
            for key in re.findall(r'AppL10n\.text\("([^"]+)"', path.read_text()):
                self.assertIn(key, keys, (path.name, key))
        for key, entry in catalog['strings'].items():
            self.assertEqual(set(entry['localizations']), LOCALES, key)
            baseline = entry['localizations']['de']['stringUnit']['value']
            for language, value in entry['localizations'].items():
                self.assertTrue(value['stringUnit']['value'].strip(), (key, language))
                self.assertEqual(value['stringUnit']['state'], 'translated')
                self.assertEqual(re.findall(r'%(?:\d+\$)?[di@]', value['stringUnit']['value']),
                                 re.findall(r'%(?:\d+\$)?[di@]', baseline), (key, language))
        for locale in LOCALES:
            info = (NATIVE / 'App' / (locale + '.lproj') / 'InfoPlist.strings').read_text()
            self.assertIn('NSLocalNetworkUsageDescription', info)

    def test_core_resources_complete_and_placeholder_safe(self):
        root = NATIVE / 'Core/Sources/KeineMagieCore'
        tables = {}
        for locale in sorted(LOCALES):
            path = root / 'Resources' / (locale + '.lproj') / 'Localizable.strings'
            self.assertTrue(path.exists(), str(path))
            tables[locale] = dict(re.findall(r'"([^"\n]+)"\s*=\s*"((?:\\.|[^"\\])*)";', path.read_text()))
        for locale, table in tables.items():
            self.assertEqual(set(table), set(tables['de']), locale)
            for key, value in table.items():
                self.assertTrue(value.strip(), (key, locale))
                self.assertEqual(re.findall(r'%(?:\d+\$)?[di@]', value),
                                 re.findall(r'%(?:\d+\$)?[di@]', tables['de'][key]), (key, locale))
        used = set()
        for path in root.glob('*.swift'):
            used.update(re.findall(r'CoreL10n\.text\("([^"]+)"', path.read_text()))
        self.assertTrue(used)
        self.assertEqual(used, set(tables['de']))
        helper = (root / 'Localization.swift').read_text()
        self.assertIn('bundle: .module', helper)
        package = (NATIVE / 'Core/Package.swift').read_text()
        self.assertIn('defaultLocalization: "de"', package)
        self.assertIn('.process("Resources")', package)

    def test_bundle_language_negotiation_metadata(self):
        for name in ['Info.plist', 'Info-Debug.plist']:
            data = plistlib.loads((NATIVE / 'Config' / name).read_bytes())
            self.assertEqual(data['CFBundleDevelopmentRegion'], 'de')
            self.assertEqual(set(data['CFBundleLocalizations']), LOCALES)
        # Validate the tracked source, not an ignored generated project which
        # is deliberately absent before XcodeGen in a clean CI checkout.
        project = (NATIVE / 'project.yml').read_text()
        self.assertRegex(project, r'developmentLanguage:\s*de\b')
        regions = re.search(r'knownRegions:\s*\[([^\]]+)\]', project)
        self.assertIsNotNone(regions)
        self.assertEqual({item.strip() for item in regions.group(1).split(',')}, LOCALES)

if __name__ == '__main__':
    unittest.main()
