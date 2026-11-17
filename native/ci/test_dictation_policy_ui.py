"""Source/localization guardrails only; NOT native pixels or interaction proof."""
import json
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class DictationPolicyUI(unittest.TestCase):
 maxDiff=600
 def test_focused_hierarchy_and_explicit_original(self):
  source=(ROOT/'App/DictationView.swift').read_text()
  self.assertIn('Menu {',source)
  self.assertIn('systemImage: "ellipsis"',source)
  self.assertIn('confirmReveal = true',source)
  self.assertIn('value.assisted || originalVisible == value.id',source)
  self.assertIn('TextField("", text:',source)
  self.assertNotIn('Button("Pause")',source)
  self.assertNotIn(': "Pause"',source)
  self.assertNotIn('Text("dictation.paid.notice").font(.caption)',source)
  self.assertIn('DictationRules',source)
  self.assertIn('DictationAudioToolbar',source)
  self.assertIn('HStack { Spacer(); Button("Check")',source)
 def test_web_rules_and_status_have_five_exact_translations(self):
  catalog=json.loads((ROOT/'App/Localizable.xcstrings').read_text())['strings']
  for key in ['dictation.policy.hint.whole','dictation.policy.hint.sentences','dictation.hint.whole','dictation.hint.sentences','dictation.listens','dictation.resume','dictation.pause','dictation.limit','dictation.budget.notice','Audio details','Show original','More options','Showing the original counts as help for this attempt. Continue?']:
   self.assertTrue(key in catalog,key)
   self.assertEqual(set(catalog[key]['localizations']),{'de','en','ru','es','fr'})
 def test_os_interruptions_do_not_complete(self):
  source=(ROOT/'App/DictationView.swift').read_text()
  self.assertIn('policyPlayer?.suspend()',source)
  self.assertIn('mediaServicesWereResetNotification',source)
  self.assertIn('audioPlayerDecodeErrorDidOccur',source)
if __name__=='__main__': unittest.main()
