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

class ResumeTests(unittest.TestCase):
    def test_pcm_resume_offsets_and_tail_cap(self):
        chunks=list(worker.pcm_chunks(io.BytesIO(b'\0'*64000), chunk_frames=16000, resume=600))
        self.assertEqual([offset for offset,_ in chunks], [600,601])
        with self.assertRaises(ValueError):
            list(worker.pcm_chunks(io.BytesIO(b'\0'*32002), resume=10800))

    def test_checkpoint_validation_accepts_silence_and_rejects_cross_window(self):
        event={'type':'checkpoint','chunk_index':1,'end_seconds':660.,'segments':[]}
        self.assertEqual(worker.validate_checkpoint(event,600,660), event)
        for bad in ({**event,'chunk_index':0}, {**event,'end_seconds':661},
                    {**event,'segments':[{'start':599.,'end':601.,'text':'bad'}]}):
            with self.assertRaises(ValueError): worker.validate_checkpoint(bad,600,660)

    def test_stage_stream_delivers_before_child_exit_and_bounds_lines(self):
        from unittest.mock import patch
        events=[]
        def collect(event): events.append((event,time.monotonic()))
        start=time.monotonic()
        script="import time; print('{\"type\":\"checkpoint\"}',flush=True); time.sleep(.6); print('{\"type\":\"complete\"}',flush=True)"
        # No UID dropping on the macOS test host; exercise actual subprocess pipe.
        with patch.object(worker,'restricted_child'), patch.object(worker,'stage_command', side_effect=lambda args: args):
            worker.stream_stage([sys.executable,'-c',script],3,None,collect)
        self.assertEqual([e['type'] for e,_ in events], ['checkpoint','complete'])
        self.assertLess(events[0][1]-start,.5)
        self.assertGreater(events[1][1]-events[0][1],.5)
        with patch.object(worker,'stage_command', side_effect=lambda args: args):
            with self.assertRaises(ValueError):
                worker.stream_stage([sys.executable,'-c',"print('x'*(4*1024*1024+1),flush=True)"],3,None,collect)

    def test_http_stream_is_opt_in_and_validates_offset_before_upload(self):
        import http.client, json, threading
        from unittest.mock import patch
        checkpoint={'type':'checkpoint','chunk_index':1,'end_seconds':660.,'segments':[{'start':650.,'end':655.,'text':'Bibliothek'}]}
        complete={'type':'complete','duration_seconds':660.,'language':'de'}
        def produce(args, timeout, connection, emit):
            self.assertEqual(args[-2:], ['600','660.0'])
            emit(checkpoint);emit(complete)
        server=worker.Server(('127.0.0.1',0),worker.Handler)
        thread=threading.Thread(target=server.serve_forever);thread.start()
        try:
            with patch.object(worker,'READY',True),patch.object(worker,'TOKEN',b'fixture'),patch.object(worker.os,'chown'),patch.object(worker,'run_stage',return_value=b'{"format":{"duration":"660"}}'),patch.object(worker,'stream_stage',side_effect=produce):
                headers={'Authorization':'Bearer fixture','X-Podcast-Version':'1','X-Podcast-Language':'de','Content-Type':'application/octet-stream','Accept':'application/x-ndjson','X-Resume-Offset':'600'}
                c=http.client.HTTPConnection(*server.server_address)
                c.request('POST','/internal/podcast/transcribe',b'RIFF1234WAVE0000',headers)
                response=c.getresponse()
                self.assertEqual(response.status,200)
                self.assertEqual(response.getheader('Content-Type'),'application/x-ndjson')
                self.assertEqual(response.getheader('Connection'),'close')
                self.assertIsNone(response.getheader('Content-Length'))
                self.assertEqual([json.loads(line) for line in response], [checkpoint,complete]);c.close()
                with patch.object(worker,'stream_stage',side_effect=ValueError('private exception internals')):
                    c=http.client.HTTPConnection(*server.server_address)
                    c.request('POST','/internal/podcast/transcribe',b'RIFF1234WAVE0000',headers)
                    response=c.getresponse()
                    self.assertEqual(response.status,200)
                    self.assertEqual(response.read(),b'{"type":"error","code":"recognition_failed"}\n');c.close()
                with patch.object(worker,'run_stage',return_value=b'{"format":{"duration":"600"}}'),patch.object(worker,'stream_stage',side_effect=lambda args,timeout,connection,emit:emit({'type':'complete','duration_seconds':600.,'language':'de'})):
                    c=http.client.HTTPConnection(*server.server_address)
                    c.request('POST','/internal/podcast/transcribe',b'RIFF1234WAVE0000',headers)
                    response=c.getresponse();self.assertEqual(response.status,200)
                    self.assertEqual(json.loads(response.read()),{'type':'complete','duration_seconds':600.,'language':'de'});c.close()
                for offset in ('-600','600.0','11400'):
                    c=http.client.HTTPConnection(*server.server_address)
                    c.request('POST','/internal/podcast/transcribe',headers={**headers,'Content-Length':'999','X-Resume-Offset':offset})
                    self.assertEqual(c.getresponse().status,400);c.close()
                c=http.client.HTTPConnection(*server.server_address)
                c.request('POST','/internal/podcast/transcribe',b'RIFF1234WAVE0000',{**headers,'X-Resume-Offset':'1200'})
                self.assertEqual(c.getresponse().status,422);c.close()
        finally: server.shutdown();server.server_close();thread.join()

    def test_recognizer_streams_checkpoints_with_resume_and_accurate_seek(self):
        import types, json
        from unittest.mock import patch
        class Audio(list):
            def astype(self, dtype): return self
            def __truediv__(self, value): return self
        fake_np=types.SimpleNamespace(int16='int16',float32='float32',frombuffer=lambda pcm,dtype:Audio([0,1,0]))
        calls=[]
        model=types.SimpleNamespace(transcribe=lambda *args,**kw:{'segments':[{'start':0.,'end':.0001,'text':'Ende'}]})
        fake_whisper=types.SimpleNamespace(load_model=lambda *args,**kw:model)
        decoder=types.SimpleNamespace(stdout=io.BytesIO(),wait=lambda:0,poll=lambda:0)
        def popen(args,**kw): calls.append(args);return decoder
        with patch.dict(sys.modules,{'numpy':fake_np,'torch':types.SimpleNamespace(set_num_threads=lambda n:None),'whisper':fake_whisper}),patch.object(worker.subprocess,'Popen',side_effect=popen),patch('builtins.open',return_value=io.BytesIO(b'RIFF1234WAVE0000')),patch.object(worker,'pcm_chunks',return_value=iter([(600,b'pcm')])),patch('sys.stdout',new_callable=io.StringIO) as output:
            worker.recognize('source','de',streaming=True,resume=600,duration=600.0001875)
            events=[json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([e['type'] for e in events],['checkpoint','complete'])
        self.assertEqual(events[0]['chunk_index'],1)
        self.assertGreaterEqual(events[0]['segments'][0]['start'],600)
        self.assertEqual(events[0]['end_seconds'],600.0001875)
        command=calls[0]; input_at=command.index('-i')
        self.assertIn('-ss',command[:input_at]);self.assertIn('-ss',command[input_at:])

    def test_stream_deadline_and_disconnect_kill_process_group(self):
        import os, signal, socket, tempfile
        from unittest.mock import patch
        with tempfile.TemporaryDirectory(dir='/Users/tinyserve/.hermes/cache/scratch') as directory:
            pidfile=pathlib.Path(directory)/'pids'
            script="import os,pathlib,subprocess,sys,time; c=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)']); pathlib.Path("+repr(str(pidfile))+").write_text(str(os.getpid())+' '+str(c.pid)); time.sleep(60)"
            with patch.object(worker,'stage_command',side_effect=lambda args:args):
                with self.assertRaises(ValueError):worker.stream_stage([sys.executable,'-c',script],.5,None,lambda event:None)
            pids=pidfile.read_text().split()
            for pid in pids:
                state=__import__('subprocess').run(['ps','-p',pid,'-o','stat='],capture_output=True,text=True).stdout.strip()
                self.assertTrue(not state or state.startswith('Z'),state)
            left,right=socket.socketpair();right.close()
            try:
                with patch.object(worker,'stage_command',side_effect=lambda args:args),self.assertRaisesRegex(ValueError,'disconnected'):
                    worker.stream_stage([sys.executable,'-c','import time; time.sleep(60)'],3,left,lambda event:None)
            finally:left.close()

    def test_strict_resume_header(self):
        self.assertEqual(worker.resume_offset(None), 0)
        for text, expected in [('0',0), ('600',600), ('10800',10800)]:
            self.assertEqual(worker.resume_offset(text), expected)
        for text in ('-600','600.0','nan','inf',' 600','+600','0600','1','11400','١٢٠٠',''):
            with self.subTest(text=text), self.assertRaises(ValueError): worker.resume_offset(text)

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
