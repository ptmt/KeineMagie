"""Structural safety checks only; real behavior is covered by the Swift harness/UI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class GlobalDictationOwnership(unittest.TestCase):
    def test_explicit_stop_and_actual_audio_indicator(self):
        accessory = (ROOT / 'App/DictationPracticeComponents.swift').read_text()
        self.assertIn('session.stop()', accessory)
        self.assertIn('"stop.fill"', accessory)
        self.assertIn('accessibilityReduceMotion', accessory)
        self.assertIn('session.player.playing', accessory)
        self.assertIn('session.status', accessory)

    def test_one_root_owned_transport_and_native_accessory(self):
        tabs = (ROOT / 'App/MainTabsView.swift').read_text()
        view = (ROOT / 'App/DictationView.swift').read_text()
        accessory = (ROOT / 'App/DictationPracticeComponents.swift').read_text()
        self.assertEqual(tabs.count('@State private var playback = DictationPlaybackCoordinator()'), 1)
        self.assertEqual(tabs.count('.modifier(DictationGlobalAccessory(session:playback,'), 1)
        self.assertNotIn('DictationPlayer()', view)
        self.assertNotIn('.safeAreaInset', view)
        self.assertNotIn('tabViewBottomAccessory', view)
        self.assertIn('content.tabViewBottomAccessory(isEnabled:enabled)', accessory)
        self.assertIn('content.tabViewBottomAccessory {', accessory)
        self.assertIn('@Environment(\\.tabViewBottomAccessoryPlacement)', accessory)
        self.assertNotIn('.regularMaterial', accessory)
        self.assertNotIn('.ultraThinMaterial', accessory)
        self.assertNotIn('Slider(', accessory)

    def test_minimal_single_row_without_progress_or_clocks(self):
        accessory = (ROOT / 'App/DictationPracticeComponents.swift').read_text()
        compact = accessory.split('private var compactBody:', 1)[1].split('private var expandedPlayer:', 1)[0]
        self.assertNotIn('ProgressView(', compact)
        self.assertNotIn('TimelineView(', compact)
        self.assertNotIn('clock(', compact)
        self.assertNotIn('dictation-elapsed', compact)
        self.assertNotIn('dictation-remaining', compact)
        self.assertNotIn('DictationAudioInformation()', compact)
        self.assertNotIn('padding(.leading,44)', compact)
        self.assertIn('alignment:.leading', compact)
        self.assertIn('Button(action:open)', compact)
        self.assertIn('frame(width:44,height:44)', compact)
        details = accessory.split('private var expandedPlayer:', 1)[1]
        self.assertIn('ProgressView(value:snapshot?.fraction', details)
        self.assertIn('dictation-expanded-elapsed', details)
        self.assertIn('Menu("Audio details")', (ROOT / 'App/DictationView.swift').read_text())

    def test_tab_navigation_never_interrupts_or_prepares(self):
        view = (ROOT / 'App/DictationView.swift').read_text()
        selected = view.split('.onChange(of: isSelected)', 1)[1].split('.task(', 1)[0]
        self.assertNotIn('cancelTransport', selected)
        self.assertNotIn('stop(', selected)
        self.assertNotIn('suspend(', selected)
        self.assertIn('.onDisappear { photo=nil;save() }', view)
        coordinator = (ROOT / 'App/DictationPlaybackCoordinator.swift').read_text()
        selection = coordinator.split('func select(', 1)[1].split('func loadTiming()', 1)[0]
        self.assertNotIn('prepare:true', selection)
        self.assertNotIn('await', selection)
        self.assertNotIn('isSelected', coordinator)
        self.assertNotIn('path.isEmpty', coordinator)

    def test_podcast_has_no_competing_embedded_audio_engine(self):
        # Guard the audited current scope. Adding another engine must add explicit
        # arbitration, not silently permit two sources in one AVAudioSession.
        for filename in ['PodcastLibraryView.swift', 'PodcastStore.swift', 'EpisodeReaderView.swift']:
            path = ROOT / 'App' / filename
            if path.exists():
                source = path.read_text()
                for engine in ['AVPlayer(', 'AVQueuePlayer(', 'AVAudioPlayer(', 'VideoPlayer(', 'WKWebView(']:
                    self.assertNotIn(engine, source, filename)

if __name__ == '__main__':
    unittest.main()
