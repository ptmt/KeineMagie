"""Native translator-first surface and honest unsupported direct-login contract."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class TranslatorSurfaceTests(unittest.TestCase):
    def test_signed_in_route_is_translator_not_account_list(self):
        root = (ROOT / 'App/KeineMagieApp.swift').read_text()
        self.assertIn('MainTabsView()', root)
        tabs = (ROOT / 'App/MainTabsView.swift').read_text()
        self.assertIn('TranslatorView()', tabs)
        self.assertLess(tabs.index('TranslatorView()'), tabs.index('feature.dictation'))
        self.assertNotIn('struct AccountView: View', root)
        view = (ROOT / 'App/TranslatorView.swift').read_text()
        self.assertIn('TextEditor(text: $model.draft)', view)
        self.assertIn('await model.translate()', view)
        self.assertIn('model.provider?.connected != true', view)
        self.assertIn('NavigationLink', view)
        self.assertIn('ChatGPTConnectionView()', view)
        self.assertNotIn('bootstrapToken', view)

    def test_direct_login_is_not_a_mislabelled_cli_button(self):
        view = (ROOT / 'App/ChatGPTConnectionView.swift').read_text()
        self.assertNotIn('chatgpt.direct.blocked', view)
        self.assertIn('chatgpt.native.notice', view)
        self.assertIn('Button("Continue with ChatGPT")', view)
        self.assertIn('ChatGPTSafariView(', view)
        self.assertIn('await model.connectChatGPT()', view)
        self.assertNotIn('bootstrapToken', view)
        model = (ROOT / 'App/AppModel.swift').read_text()
        self.assertIn('client.bootstrapStart(', model)
        self.assertIn('client.bootstrapComplete(', model)
        self.assertIn('LoopbackPolicy.authorize(', model)
        self.assertIn('connectionID == id', model)
        self.assertIn('version == session.generation', model)
        self.assertIn('cancelChatGPT()', model)
        self.assertIn('await connectionTasks.run', model)
        self.assertIn('connectionTasks.cancel()', model)
        self.assertIn('!Task.isCancelled', model)
        self.assertIn('refreshTranslator(connection: id)', model)
        catalog = json.loads((ROOT / 'App/Localizable.xcstrings').read_text())['strings']
        for key in ['chatgpt.connect', 'chatgpt.direct.blocked', 'chatgpt.direct.reason',
                    'chatgpt.desktop.start', 'chatgpt.registration', 'chatgpt.desktop.instructions',
                    'chatgpt.desktop.title', 'chatgpt.requirement']:
            self.assertEqual(set(catalog[key]['localizations']), {'de', 'en', 'ru', 'es', 'fr'})

if __name__ == '__main__':
    unittest.main()
