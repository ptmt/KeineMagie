"""Private audio-only service. No URL, provider, account, or command RPCs."""
import hashlib
import hmac
import http.server
import json
import math
import os
import pathlib
import resource
import select
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import wave

MAX_BYTES = 40 << 20
ENV = {'PATH': '/usr/local/bin:/usr/bin:/bin', 'HOME': '/tmp', 'TMPDIR': '/tmp',
       'OMP_NUM_THREADS': '2', 'OPENBLAS_NUM_THREADS': '2', 'NUMBA_NUM_THREADS': '2',
       'PYTHONDONTWRITEBYTECODE': '1'}
READY = False
BUSY = threading.Lock()
TOKEN = b''


def media_format(data):
    # Fixed demuxers, not a broad auto-prober. Manifests never reach ffmpeg.
    if data[:4] == b'RIFF' and data[8:12] == b'WAVE': return 'wav'
    if data[:4] == b'FORM' and data[8:12] in (b'AIFF', b'AIFC'): return 'aiff'
    if data[:4] == b'fLaC': return 'flac'
    if data[:4] == b'OggS': return 'ogg'
    if data[:3] == b'ID3' or (len(data)>1 and data[0]==255 and data[1]&0xe0==0xe0): return 'mp3'
    if data[4:8] == b'ftyp': return 'mov'
    raise ValueError('unsupported audio container')


def restricted_child():
    os.setgroups([])
    os.setgid(1001)
    os.setuid(1001)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))
    resource.setrlimit(resource.RLIMIT_FSIZE, (24 << 20, 24 << 20))
    resource.setrlimit(resource.RLIMIT_CPU, (1800, 1800))


def run_stage(args, timeout, connection=None):
    with tempfile.TemporaryFile() as output:
        proc = subprocess.Popen([sys.executable, __file__, '--stage', *args], stdin=subprocess.DEVNULL, stdout=output,
                                stderr=subprocess.DEVNULL, env=ENV, close_fds=True,
                                start_new_session=True)
        deadline = time.monotonic() + timeout
        try:
            while proc.poll() is None:
                if time.monotonic() > deadline: raise ValueError('stage deadline exceeded')
                if connection and select.select([connection], [], [], 0)[0]:
                    # RPC has no pipelining; EOF or extra bytes cancels the stage.
                    raise ValueError('client disconnected')
                time.sleep(.05)
            if proc.returncode: raise ValueError('audio processing failed')
            output.seek(0)
            result = output.read((1 << 20)+1)
            if len(result)>1<<20: raise ValueError('output exceeds limit')
            return result
        finally:
            # Includes grandchildren even if the leader exited first.
            try: os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            proc.wait()


def validated_segments(data):
    result = []
    previous = 0
    total = 0
    for item in data:
        start, end, text = item['start'], item['end'], item['text'].strip()
        if not text: continue
        total += len(text)
        if not math.isfinite(start) or not math.isfinite(end) or start<previous or end<=start or end>600 or total>8000:
            raise ValueError('transcript outside limits')
        previous = end
        result.append({'start':start, 'end':end, 'text':text})
    if not 0<len(result)<=120: raise ValueError('no speech or too many segments')
    return result


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def setup(self):
        super().setup()
        self.connection.settimeout(30)
    def reply(self, code, data):
        body=json.dumps(data, allow_nan=False).encode()
        self.send_response(code)
        self.send_header('Content-Type','application/json')
        self.send_header('Cache-Control','no-store')
        self.send_header('Connection','close')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        self.close_connection=True
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
    def authorized(self):
        if not hmac.compare_digest(self.headers.get('Authorization','').encode(), b'Bearer '+TOKEN):
            self.reply(401, {'error':'authentication required'})
            return False
        if self.headers.get('X-Podcast-Version')!='1':
            self.reply(400, {'error':'protocol version required'})
            return False
        return True
    def do_GET(self):
        if not self.authorized(): return
        if self.path!='/internal/podcast/ready': self.reply(404,{}); return
        ready=READY and not BUSY.locked()
        self.reply(200 if ready else 503, {'version':1,'ready':ready,'capacity':1 if ready else 0})
    def do_POST(self):
        if not self.authorized(): return
        if self.path!='/internal/podcast/transcribe': self.reply(404,{}); return
        language=self.headers.get('X-Podcast-Language')
        try: length=int(self.headers.get('Content-Length','0'))
        except ValueError: length=0
        if self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length',[]))!=1 or not 0<length<=MAX_BYTES:
            self.reply(413,{'error':'bounded content length required'}); return
        if language not in ('de','ru') or self.headers.get('Content-Type')!='application/octet-stream':
            self.reply(400,{'error':'invalid audio request'}); return
        if not READY: self.reply(503,{}); return
        if not BUSY.acquire(False): self.reply(429,{}); return
        try:
            with tempfile.TemporaryDirectory(prefix='podcast-') as directory:
                os.chmod(directory,0o770)
                os.chown(directory,1001,0)
                source=pathlib.Path(directory)/'source.audio'
                deadline=time.monotonic()+120
                remaining=length
                with source.open('wb') as f:
                    while remaining:
                        if time.monotonic()>deadline: raise ValueError('upload timeout')
                        block=self.rfile.read(min(65536,remaining))
                        if not block: raise ValueError('truncated upload')
                        f.write(block); remaining-=len(block)
                source.chmod(0o440);os.chown(source,0,1001)
                with source.open('rb') as f: fmt=media_format(f.read(16))
                options=['-v','error','-protocol_whitelist','file,pipe','-format_whitelist',fmt,'-f',fmt]
                probe=run_stage(['/usr/bin/ffprobe',*options,'-show_entries','format=duration','-of','json',str(source)],20,self.connection)
                duration=float(json.loads(probe)['format']['duration'])
                if not math.isfinite(duration) or not 0<duration<=600: raise ValueError('audio must be at most ten minutes')
                wav=str(pathlib.Path(directory)/'speech.wav')
                run_stage(['/usr/bin/ffmpeg','-nostdin',*options,'-i',str(source),'-t','600','-vn','-sn','-dn','-ac','1','-ar','16000','-threads','2','-f','wav',wav],45,self.connection)
                with wave.open(wav) as f:
                    if f.getnframes()/f.getframerate()>600: raise ValueError('decoded audio exceeds duration')
                raw=run_stage([sys.executable,__file__,'--recognize',wav,language],1800,self.connection)
                segments=validated_segments(json.loads(raw)['segments'])
                self.reply(200,{'version':1,'segments':segments})
        except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError):
            self.reply(422,{'error':'audio processing rejected or canceled'})
        finally: BUSY.release()


class Server(http.server.ThreadingHTTPServer):
    daemon_threads=True
    request_queue_size=4
    slots=threading.BoundedSemaphore(4)
    def process_request(self, request, address):
        if not self.slots.acquire(False): request.close(); return
        try: super().process_request(request,address)
        except BaseException: self.slots.release(); raise
    def process_request_thread(self, request, address):
        try: super().process_request_thread(request,address)
        finally: self.slots.release()
    def handle_error(self, *args): pass


def recognize(path, language):
    import numpy as np
    import torch
    import whisper
    torch.set_num_threads(2)
    # Explicit local path: whisper must never download models at runtime.
    model=whisper.load_model('/models/base.pt',device='cpu')
    with wave.open(path) as f:
        audio=np.frombuffer(f.readframes(f.getnframes()),dtype=np.int16).astype(np.float32)/32768
    result=model.transcribe(audio,language=language,task='transcribe',fp16=False,verbose=None)
    print(json.dumps({'segments':result['segments']},allow_nan=False))


def main():
    global TOKEN,READY
    info=os.lstat('/run/secrets/podcast_token')
    if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode)!=0o600 or info.st_uid!=0 or info.st_size>256:
        raise ValueError('worker token requires root-owned 0600 file')
    TOKEN=pathlib.Path('/run/secrets/podcast_token').read_bytes().strip()
    if len(TOKEN)!=64 or any(c not in b'0123456789abcdef' for c in TOKEN): raise ValueError('invalid token format')
    run_stage(['/usr/bin/ffmpeg','-version'],10)
    run_stage(['/usr/bin/ffprobe','-version'],10)
    with tempfile.TemporaryDirectory() as directory:
        os.chmod(directory,0o770)
        os.chown(directory,1001,0)
        path=str(pathlib.Path(directory)/'silence.wav')
        with wave.open(path,'wb') as f:
            f.setnchannels(1);f.setsampwidth(2);f.setframerate(16000);f.writeframes(b'\0'*32000)
        run_stage([sys.executable,__file__,'--recognize',path,'de'],180)
    READY=True
    Server(('0.0.0.0',8091),Handler).serve_forever()

if __name__=='__main__':
    if len(sys.argv)>2 and sys.argv[1]=='--stage':
        restricted_child()
        os.execve(sys.argv[2],sys.argv[2:],ENV)
    elif len(sys.argv)==4 and sys.argv[1]=='--recognize': recognize(sys.argv[2],sys.argv[3])
    else: main()
