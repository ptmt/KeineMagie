"""Compact Coach UI contracts; no provider calls."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
class CoachCompactTests(unittest.TestCase):
    def test_feedback_is_visible_and_review_moves_to_profile(self):
        view = (ROOT/'App/CoachView.swift').read_text()
        bubble, profile = view.split('struct CoachObservationsView: View')
        self.assertNotIn('Menu("coach.review")', bubble)
        self.assertIn('Menu("coach.review")', profile)
        self.assertIn('turn.showsInstruction', bubble)
        self.assertIn('if let explanation = turn.explanation, turn.attempt != nil', bubble)
        self.assertIn('coach.savedTranslation', bubble)
        self.assertNotIn('Text(LocalizedStringKey("coach.target.', bubble)
    def test_native_labels_have_five_locales(self):
        strings = json.loads((ROOT/'App/Localizable.xcstrings').read_text())['strings']
        for key in ['coach.hint','coach.source','coach.savedTranslation','coach.savedPassage','coach.ambiguous']:
            self.assertEqual(set(strings[key]['localizations']), {'de','en','ru','es','fr'})
        self.assertEqual(strings['coach.ambiguous']['localizations']['ru']['stringUnit']['value'], 'Не могу уверенно проверить')

if __name__ == '__main__': unittest.main()
