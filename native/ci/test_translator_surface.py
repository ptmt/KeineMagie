"""Native translator-first surface and honest unsupported direct-login contract."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class TranslatorSurfaceTests(unittest.TestCase):
    def test_redundant_headings_stay_hidden_but_input_and_output_keep_localized_ax_titles(self):
        view = (ROOT / 'App/TranslatorView.swift').read_text()
        self.assertIn('.accessibilityLabel("Text zum Übersetzen")', view)
        self.assertIn('.accessibilityLabel("followup.translation")', view)
        self.assertNotIn('header: { Text("Übersetzung")', view)
        catalog = json.loads((ROOT / 'App/Localizable.xcstrings').read_text())['strings']
        self.assertEqual(set(catalog['followup.translation']['localizations']), {'de', 'en', 'ru', 'es', 'fr'})

    def test_signed_in_route_is_translator_not_account_list(self):
        root = (ROOT / 'App/KeineMagieApp.swift').read_text()
        self.assertIn('MainTabsView(showSettings:', root)
        tabs = (ROOT / 'App/MainTabsView.swift').read_text()
        self.assertIn('TranslatorView(showPending:', tabs)
        self.assertLess(tabs.index('TranslatorView(showPending:'), tabs.index('feature.dictation'))
        self.assertNotIn('struct AccountView: View', root)
        view = (ROOT / 'App/TranslatorView.swift').read_text()
        self.assertIn('TextEditor(text: $model.draft)', view)
        self.assertIn('model.beginTranslation()', view)
        self.assertNotIn('model.provider?.connected != true', view.split('struct PendingTranslationsView')[0])
        self.assertIn('NavigationLink', view)
        self.assertIn('ChatGPTConnectionView()', view)
        self.assertNotIn('bootstrapToken', view)

    def test_styles_remain_available_in_contextual_sheet(self):
        view = (ROOT / 'App/TranslatorView.swift').read_text()
        styles = (ROOT / 'App/TranslationShortcutsView.swift').read_text()
        self.assertLess(view.index('TextEditor(text: $model.draft)'), view.index('TranslationShortcutsView()'))
        self.assertIn('.sheet(isPresented: $showStyles)', view)
        self.assertIn('translator-styles', view)
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
        self.assertNotIn('Task.sleep', history)
        # Auxiliary status lives in settings, not a collapsing translator row.
        self.assertNotIn('Verbindung prüfen', view)
        self.assertLess(view.index('ForEach(model.history)'), view.index('if let error = model.historyLoadError'))

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
