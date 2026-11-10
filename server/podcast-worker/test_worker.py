import importlib.util
import pathlib
import unittest
import sys
import time

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
