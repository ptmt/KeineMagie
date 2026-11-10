"""Native podcast navigation and localization contracts."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PodcastSurfaceTests(unittest.TestCase):
    def test_library_is_list_not_import_form_or_nested_navigation(self):
        source = (ROOT / 'App/PodcastLibraryView.swift').read_text()
        library = source.split('private func addSheet')[0]
        self.assertNotIn('NavigationStack', library)
        self.assertIn('ContentUnavailableView', library)
        self.assertIn('NavigationLink', library)
        self.assertIn('.swipeActions', library)
        self.assertIn('podcast-add', (ROOT / 'App/MainTabsView.swift').read_text())
        self.assertNotIn('TextField', library)
        self.assertNotIn('podcast.privacy', library)

    def test_clean_labels_and_new_copy_in_all_locales(self):
        strings = json.loads((ROOT / 'App/Localizable.xcstrings').read_text())['strings']
        for locale in ['de', 'en', 'es', 'fr', 'ru']:
            expected = 'Подкасты' if locale == 'ru' else 'Podcasts'
            for key in ['podcast.title', 'feature.podcasts']:
                self.assertEqual(strings[key]['localizations'][locale]['stringUnit']['value'], expected)
        for key in ['podcast.add', 'podcast.none', 'podcast.none.hint', 'podcast.mode', 'podcast.mode.episode', 'podcast.mode.feed', 'podcast.info', 'podcast.url']:
            self.assertEqual(set(strings[key]['localizations']), {'de','en','ru','es','fr'})

if __name__ == '__main__':
    unittest.main()
