"""Structural safety checks only; real behavior is covered by the Swift harness/UI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class GlobalDictationOwnership(unittest.TestCase):
    def test_one_root_owned_transport_and_native_accessory(self):
        tabs = (ROOT / 'App/MainTabsView.swift').read_text()
        view = (ROOT / 'App/DictationView.swift').read_text()
        accessory = (ROOT / 'App/DictationPracticeComponents.swift').read_text()
        self.assertEqual(tabs.count('@State private var playback = DictationPlaybackCoordinator()'), 1)
        self.assertEqual(tabs.count('.modifier(DictationGlobalAccessory(session:playback)'), 1)
        self.assertNotIn('DictationPlayer()', view)
        self.assertNotIn('.safeAreaInset', view)
        self.assertNotIn('tabViewBottomAccessory', view)
        self.assertIn('content.tabViewBottomAccessory(isEnabled:session.visible)', accessory)
        self.assertIn('content.tabViewBottomAccessory {', accessory)
        self.assertIn('@Environment(\\.tabViewBottomAccessoryPlacement)', accessory)
        self.assertNotIn('.regularMaterial', accessory)
        self.assertNotIn('.ultraThinMaterial', accessory)
        self.assertNotIn('Slider(', accessory)

    def test_compact_full_width_timeline_and_no_mini_player_info(self):
        accessory = (ROOT / 'App/DictationPracticeComponents.swift').read_text()
        toolbar = accessory.split('struct DictationAudioToolbar:', 1)[1].split('struct DictationAudioInformation:', 1)[0]
        timeline = toolbar.split('TimelineView(', 1)[1]
        self.assertNotIn('DictationAudioInformation()', toolbar)
        self.assertIn('ZStack(alignment:.bottom)', toolbar)
        self.assertIn('.multilineTextAlignment(.center)', toolbar)
        self.assertIn('}.frame(height:44).buttonStyle(.plain)', toolbar)
        self.assertIn('ProgressView(value:snapshot?.fraction', timeline)
        self.assertIn('}.frame(maxWidth:.infinity)', timeline)
        self.assertNotIn('.frame(width:', timeline)
        self.assertIn('.allowsHitTesting(false)', timeline)
        self.assertIn('DictationAudioInformation()', (ROOT / 'App/DictationView.swift').read_text())

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
