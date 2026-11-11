import importlib.util
import pathlib
import unittest
import sys
import time
import io

spec = importlib.util.spec_from_file_location('worker', pathlib.Path(__file__).with_name('worker.py'))
assert spec is not None and spec.loader is not None
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)

class LongAudioTests(unittest.TestCase):
    def test_pcm_chunks_are_bounded_contiguous_and_preserve_tail(self):
        audio = bytes(range(256)) * 300
        chunks = list(worker.pcm_chunks(io.BytesIO(audio), chunk_frames=16000))
        self.assertEqual(b''.join(chunk for _, chunk in chunks), audio)
        self.assertEqual([offset for offset, _ in chunks], [0, 1, 2])
        self.assertTrue(all(len(chunk) <= 32000 for _, chunk in chunks))

    def test_long_global_timestamps_and_bounds(self):
        segments = [{'start': 601., 'end': 660., 'text': ' Ende ' }]
        self.assertEqual(worker.validated_segments(segments)[0]['end'], 660.)
        for end in (10800.01, float('inf')):
            with self.assertRaises(ValueError):
                worker.validated_segments([{'start': 0, 'end': end, 'text': 'invalid'}])

    def test_chunk_offsets_do_not_duplicate_or_overlap(self):
        target = [{'start': 590., 'end': 600., 'text': 'Anfang'}]
        worker.append_chunk(target, [{'start': 0., 'end': 4., 'text': 'Ende'},
                                     {'start': 3.9, 'end': 6., 'text': 'Buch'}], 600., 6.)
        self.assertEqual(target, [{'start': 590., 'end': 600., 'text': 'Anfang'},
                                  {'start': 600., 'end': 604., 'text': 'Ende'},
                                  {'start': 604., 'end': 606., 'text': 'Buch'}])

    def test_exact_silence_trim_preserves_absolute_speech_position(self):
        self.assertEqual(worker.speech_bounds([0, 0, 4, -2, 0]), (2, 4))
        self.assertIsNone(worker.speech_bounds([0, 0, 0]))

    def test_decoder_limits_samples_even_when_metadata_lies(self):
        original=worker.MAX_DURATION
        setattr(worker, 'MAX_DURATION', 1)
        try:
            with self.assertRaises(ValueError):
                list(worker.pcm_chunks(io.BytesIO(b'\0' * 32002), chunk_frames=16000))
            with self.assertRaises(ValueError):
                list(worker.pcm_chunks(io.BytesIO(b'\0' * 3)))
        finally: setattr(worker, 'MAX_DURATION', original)

    def test_silent_chunks_do_not_end_transcript(self):
        target=[]
        worker.append_chunk(target, [], 0, 600)
        worker.append_chunk(target, [{'start': 50, 'end': 55, 'text': 'Bibliothek'}], 600, 60)
        self.assertEqual(target, [{'start': 650, 'end': 655, 'text': 'Bibliothek'}])

    def test_limits_can_only_be_lowered(self):
        self.assertEqual(worker.bounded_limit('300', 300), 300)
        self.assertEqual(worker.bounded_limit('20', 300), 20)
        for invalid in ('301', '0', '-1', 'abc'):
            with self.assertRaises(ValueError): worker.bounded_limit(invalid, 300)

    def test_configured_deadline_can_only_reduce_ninety_minutes(self):
        self.assertEqual(worker.timeout_seconds('5400'), 5400)
        self.assertEqual(worker.timeout_seconds('60'), 60)
        for invalid in ('5401', '0', '-1', 'nan', 'anything'):
            with self.assertRaises(ValueError): worker.timeout_seconds(invalid)

class WorkerTests(unittest.TestCase):
    def test_manifest_cannot_select_a_decoder(self):
        spec = importlib.util.spec_from_file_location('worker', pathlib.Path(__file__).with_name('worker.py'))
        assert spec is not None and spec.loader is not None
        worker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(worker)
        self.assertEqual(worker.media_format(b'RIFF1234WAVE'), 'wav')
        for data in (b'#EXTM3U\nfile:///run/secrets/token', b'ffconcat version 1.0', b'[playlist]', b'<MPD>'):
            with self.assertRaises(ValueError):
                worker.media_format(data)

    def test_supervisor_does_not_use_thread_unsafe_preexec(self):
        source=pathlib.Path(__file__).with_name('worker.py').read_text()
        self.assertNotIn('preexec_fn=',source)

if __name__ == '__main__': unittest.main()
