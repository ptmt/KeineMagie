"""Portable discovery tests for signed-in tabs and account-local style UI."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LOCALES = {'de', 'en', 'ru', 'es', 'fr'}

class TabsAndShortcutsTests(unittest.TestCase):
    def test_all_style_keys_are_translated_in_five_locales(self):
        strings = json.loads((ROOT / 'App/Localizable.xcstrings').read_text())['strings']
        keys = [key for key in strings if key.startswith('shortcut.')] + ['feature.unavailable']
        self.assertGreater(len(keys), 1)
        for key in keys:
            with self.subTest(key=key):
                self.assertEqual(set(strings[key]['localizations']), LOCALES)
                for entry in strings[key]['localizations'].values():
                    self.assertTrue(entry['stringUnit']['value'].strip())

    def test_four_tabs_have_real_podcast_and_honest_unavailable_destinations(self):
        source = (ROOT / 'App/MainTabsView.swift').read_text()
        for label in ['translator', 'dictation', 'podcasts', 'coach']:
            self.assertIn(f'.tabItem {{ Label("feature.{label}"', source)
        self.assertIn('PodcastLibraryView(showAdd: $showPodcastAdd)', source)
        self.assertIn('Text("feature.unavailable")', source)

    def test_inline_tags_are_small_plain_text_with_full_accessible_targets(self):
        source = (ROOT / 'App/TranslationShortcutsView.swift').read_text().split('private struct ShortcutManager')[0]
        self.assertNotIn('.buttonStyle(.bordered)', source)
        self.assertNotIn('Capsule(', source)
        self.assertNotIn('.background(', source)
        self.assertIn('.font(.footnote)', source)
        self.assertIn('.frame(minHeight: 44)', source)
        self.assertIn('.fixedSize(horizontal: true, vertical: false)', source)
        self.assertIn('.accessibilityAddTraits(selected ? [.isSelected] : [])', source)

    def test_identity_epoch_resets_tabs_and_account_local_content(self):
        source = (ROOT / 'App/KeineMagieApp.swift').read_text()
        self.assertIn('MainTabsView().id(model.session.generation)', source)
        self.assertIn('model.resetSessionContent(); model.loadShortcuts()', source)

if __name__ == '__main__':
    unittest.main()
