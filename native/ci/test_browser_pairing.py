import json, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class PairingUI(unittest.TestCase):
 def test_explicit_approval_and_locales(self):
  view=(ROOT/'App/BrowserPairingView.swift').read_text()
  self.assertIn('approve: true',view);self.assertIn('approve: false',view)
  catalog=json.loads((ROOT/'App/Localizable.xcstrings').read_text())['strings']
  for key in ['browser.connect','browser.code','browser.review','browser.title','browser.warning','browser.approve','browser.deny','browser.done']:
   self.assertEqual(set(catalog[key]['localizations']),{'de','en','ru','es','fr'})
if __name__=='__main__':unittest.main()
