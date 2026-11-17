import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
class DictationLocalization(unittest.TestCase):
 def test_paid_generation_disclosure(self):
  catalog=json.loads((ROOT/'App/Localizable.xcstrings').read_text())['strings']
  self.assertIn('dictation.paid.notice',catalog)
  self.assertEqual(set(catalog['dictation.paid.notice']['localizations']),{'de','en','ru','es','fr'})
  self.assertIn('Text("dictation.paid.notice")',(ROOT/'App/DictationPracticeComponents.swift').read_text())
 def test_reachable_dictation_controls_have_five_translations(self):
  catalog=json.loads((ROOT/'App/Localizable.xcstrings').read_text())['strings']
  for key in ['dictation.onboarding','Add text','Prepare audio','By sentences','What you heard','New attempt','Delete attempt','Not saved. Retry before leaving.','readings','step','Draft conflict','Your draft','Server draft','Export draft','Rebase my draft','Use server draft','Deleted on another device · draft saved locally']:
   self.assertIn(key,catalog)
   self.assertEqual(set(catalog[key]['localizations']),{'de','en','ru','es','fr'})
if __name__=='__main__':unittest.main()
