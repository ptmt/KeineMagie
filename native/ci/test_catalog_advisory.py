"""Catalog diagnostics are localized, secondary, and settings-scoped."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CatalogAdvisoryTests(unittest.TestCase):
    def test_settings_only_secondary_diagnostic(self):
        settings = (ROOT/'App/ChatGPTConnectionView.swift').read_text()
        translator = (ROOT/'App/TranslatorView.swift').read_text()
        self.assertIn('NavigationLink("ChatGPT") { ChatGPTConnectionView() }', (ROOT/'App/SettingsView.swift').read_text())
        self.assertIn('model.providerDiagnostic', settings)
        self.assertIn('.accessibilityIdentifier("provider-diagnostic")', settings)
        self.assertNotIn('model.providerDiagnostic', translator)
        diagnostic = settings.split('if let diagnostic = model.providerDiagnostic')[1].split('}')[0]
        self.assertIn('.foregroundStyle(.secondary)', diagnostic)
        self.assertNotIn('ErrorNotice', diagnostic)

    def test_localized_diagnostics_do_not_prescribe_reconnection(self):
        strings = json.loads((ROOT/'App/Localizable.xcstrings').read_text())['strings']
        for key in ('chatgpt.catalog.unavailable', 'chatgpt.status.unavailable'):
            self.assertIn(key, strings)
            self.assertEqual(set(strings[key]['localizations']), {'de','en','ru','es','fr'})
            english = strings[key]['localizations']['en']['stringUnit']['value']
            self.assertNotIn('reconnect', english.lower())

if __name__ == '__main__': unittest.main()
