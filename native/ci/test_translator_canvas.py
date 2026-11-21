"""Presentation-only guard; native XCTest verifies rendered geometry separately."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ContinuousCanvasTests(unittest.TestCase):
    def test_canvas_has_no_separate_cards_and_direction_is_in_header(self):
        view = (ROOT/'App/TranslatorView.swift').read_text()
        tabs = (ROOT/'App/MainTabsView.swift').read_text()
        self.assertNotIn('.background(.thinMaterial', view)
        self.assertNotIn('.overlay(RoundedRectangle', view)
        self.assertIn('.safeAreaInset(edge: .bottom', view)
        self.assertNotIn('TranslatorDirectionMenu(direction:', view)
        self.assertIn('TranslatorDirectionMenu(direction:', tabs)
        self.assertNotIn('minimumScaleFactor', tabs)
        self.assertNotIn('adjustsFontSizeToFitWidth = true', tabs)
        self.assertIn('.sheet(isPresented: $showStyles)', view)
    def test_styles_sync_remains_owned_by_visible_translator_not_closed_sheet(self):
        view = (ROOT/'App/TranslatorView.swift').read_text()
        styles = (ROOT/'App/TranslationShortcutsView.swift').read_text()
        self.assertIn('await model.syncShortcuts()', view)
        self.assertNotIn('.task(id:', styles)
if __name__ == '__main__': unittest.main()
