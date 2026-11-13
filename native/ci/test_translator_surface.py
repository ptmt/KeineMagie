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

    def test_compact_form_keeps_styles_below_input_without_duplicate_heading(self):
        view = (ROOT / 'App/TranslatorView.swift').read_text()
        styles = (ROOT / 'App/TranslationShortcutsView.swift').read_text()
        self.assertLess(view.index('TextEditor(text: $model.draft)'), view.index('TranslationShortcutsView()'))
        self.assertLess(view.index('TranslationShortcutsView()'), view.index('await model.translate()'))
        self.assertNotIn('Label("feature.translator"', view)
        self.assertNotIn('frame(minHeight: 160)', view)
        self.assertIn('.scrollDismissesKeyboard(.interactively)', view)
        self.assertIn('@FocusState', view)
        self.assertIn('translator-input', view)
        self.assertIn('translator-submit', view)
        inline_styles = styles.split('private struct ShortcutManager')[0]
        self.assertNotIn('Text("shortcut.heading")', inline_styles)
        self.assertNotIn('Text(verbatim: instruction)', inline_styles)
        self.assertIn('shortcut-manage', inline_styles)
        self.assertIn('.contextMenu', inline_styles)
        self.assertIn('.accessibilityLabel("shortcut.add")', inline_styles)

    def test_initial_history_loading_is_quiet_without_false_empty_or_delayed_work(self):
        view = (ROOT / 'App/TranslatorView.swift').read_text()
        history = view.split('Section {', 1)[1].split('ForEach(model.history)', 1)[0]
        self.assertNotIn('ProgressView', history)
        self.assertIn('model.historyPhase == .loaded', history)
        self.assertIn('model.history.isEmpty', history)
        self.assertNotIn('Task.sleep', view.split('private struct TranslationResultView')[0])
        # A provider spinner also appeared above cached rows, and waited for history.
        provider = view.split('if model.session.canWrite && model.provider == nil {', 1)[1].split('if model.busy', 1)[0]
        self.assertNotIn('ProgressView', provider)
        self.assertIn('Verbindung prüfen', provider)

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
