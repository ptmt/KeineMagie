"""Portable integration guards; native pixels remain the parent's UI gate."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ActivityIntegrationTests(unittest.TestCase):
    def test_synthetic_activity_matches_source_breakdown(self):
        source=(ROOT/'App/SimulatorSessionFixture.swift').read_text()
        activity=source.split('// Explicit synthetic UI evidence only;')[1].split('if request.url?.path == "/v1/learning/coach"')[0]
        self.assertIn('"counts":', activity)
        self.assertIn('"translator":"retained"', activity)

    def test_day_details_expose_source_counts_and_coverage(self):
        source = (ROOT/'App/ActivityStrip.swift').read_text()
        self.assertIn('entry?.counts?[source]', source)
        self.assertIn('snapshot?.sources[source]', source)
        self.assertIn('text("undated")', source)
        self.assertIn('breakdown(entry:', source)
        self.assertIn('snapshot: snapshotKey == key ? snapshot : nil', source)
        self.assertIn('.onChange(of: model.session.generation)', source)
        catalog=json.loads((ROOT/'App/Activity.xcstrings').read_text())['strings']
        for key in ['coach','dictation','translator','podcasts','retained','unavailable','unsupported','undated']:
            self.assertEqual(set(catalog[key]['localizations']), {'de','en','ru','es','fr'})
        self.assertEqual(catalog['unsupported']['localizations']['en']['stringUnit']['value'], 'Completion not tracked')
        self.assertNotIn('checks', catalog['partial']['localizations']['en']['stringUnit']['value'])
        for loc in ['de','en','ru','es','fr']:
            self.assertNotIn('Translator and Podcasts have no',catalog['semantics']['localizations'][loc]['stringUnit']['value'])
if __name__=='__main__':unittest.main()
