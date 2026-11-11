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

def bounded_limit(value, ceiling):
    result = int(value)
    if not 0 < result <= ceiling: raise ValueError('invalid worker limit')
    return result


MAX_BYTES = bounded_limit(os.environ.get('PODCAST_MAX_BYTES', str(300 << 20)), 300 << 20)
MAX_DURATION = bounded_limit(os.environ.get('PODCAST_MAX_DURATION_SECONDS', '10800'), 10800)
MAX_SEGMENTS = 3600
MAX_TEXT = 216000
CHUNK_SECONDS = 600
ENV = {'PATH': '/usr/local/bin:/usr/bin:/bin', 'HOME': '/tmp', 'TMPDIR': '/tmp',
       'OMP_NUM_THREADS': '2', 'OPENBLAS_NUM_THREADS': '2', 'NUMBA_NUM_THREADS': '2',
       'PYTHONDONTWRITEBYTECODE': '1',
       'PODCAST_MAX_DURATION_SECONDS': str(MAX_DURATION), 'PODCAST_MAX_BYTES': str(MAX_BYTES)}
READY = False
BUSY = threading.Lock()
TOKEN = b''


def resume_offset(value):
    if value is None: return 0
    if value not in {str(i) for i in range(0, MAX_DURATION+1, CHUNK_SECONDS)}:
        raise ValueError('invalid resume offset')
    return int(value)


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
    resource.setrlimit(resource.RLIMIT_CPU, (5400, 5400))


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
            result = output.read((4 << 20)+1)
            if len(result)>4<<20: raise ValueError('output exceeds limit')
            return result
        finally:
            # Includes grandchildren even if the leader exited first.
            try: os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            proc.wait()


def stage_command(args):
    return [sys.executable, __file__, '--stage', *args]


def stream_stage(args, timeout, connection, emit):
    proc = subprocess.Popen(stage_command(args), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, env=ENV, close_fds=True, start_new_session=True)
    deadline = time.monotonic()+timeout
    pending=bytearray()
    try:
        while True:
            if time.monotonic()>=deadline: raise ValueError('stage deadline exceeded')
            if connection and select.select([connection],[],[],0)[0]:
                raise ValueError('client disconnected')
            if not select.select([proc.stdout],[],[],min(.05,max(0,deadline-time.monotonic())))[0]: continue
            block=os.read(proc.stdout.fileno(),65536)
            if not block: break
            pending.extend(block)
            while b'\n' in pending:
                line,_,tail=pending.partition(b'\n'); pending=bytearray(tail)
                if len(line)>4<<20: raise ValueError('output exceeds limit')
                emit(json.loads(line))
            if len(pending)>4<<20: raise ValueError('output exceeds limit')
        if pending or proc.wait(timeout=max(.001,deadline-time.monotonic())):
            raise ValueError('audio processing failed')
    finally:
        try: os.killpg(proc.pid,signal.SIGKILL)
        except ProcessLookupError: pass
        proc.wait()
        proc.stdout.close()


def validate_checkpoint(event, cursor, duration):
    end=min(cursor+CHUNK_SECONDS,duration)
    if event.get('type')!='checkpoint' or event.get('chunk_index')!=int(cursor//CHUNK_SECONDS) or event.get('end_seconds')!=end or end<=cursor:
        raise ValueError('invalid checkpoint')
    items=event['segments']
    if not isinstance(items,list): raise ValueError('invalid segments')
    if items:
        checked=validated_segments(items)
        if checked!=items or checked[0]['start']<cursor or checked[-1]['end']>end:
            raise ValueError('invalid checkpoint bounds')
    return event


def validated_segments(data):
    result = []
    previous = 0
    total = 0
    for item in data:
        start, end, text = item['start'], item['end'], item['text'].strip()
        if not text: continue
        total += len(text)
        if not math.isfinite(start) or not math.isfinite(end) or start<previous or end<=start or end>MAX_DURATION or len(text)>8000 or total>MAX_TEXT:
            raise ValueError('transcript outside limits')
        previous = end
        result.append({'start':start, 'end':end, 'text':text})
    if not 0<len(result)<=MAX_SEGMENTS: raise ValueError('no speech or too many segments')
    return result


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def setup(self):
        super().setup()
        self.connection.settimeout(30)
    def reply(self, code, data):
        body=json.dumps(data, allow_nan=False, ensure_ascii=False).encode()
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
        streaming='application/x-ndjson' in [part.strip() for part in self.headers.get('Accept','').split(',')]
        try:
            if len(self.headers.get_all('X-Resume-Offset',[]))>1: raise ValueError('duplicate offset')
            resume=resume_offset(self.headers.get('X-Resume-Offset'))
            if resume and not streaming: raise ValueError('resume requires streaming')
        except ValueError:
            self.reply(400,{'error':'invalid resume offset'}); return
        language=self.headers.get('X-Podcast-Language')
        try: length=int(self.headers.get('Content-Length','0'))
        except ValueError: length=0
        if self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length',[]))!=1 or not 0<length<=MAX_BYTES:
            self.reply(413,{'error':'bounded content length required'}); return
        if language not in ('de','ru') or self.headers.get('Content-Type')!='application/octet-stream':
            self.reply(400,{'error':'invalid audio request'}); return
        if not READY: self.reply(503,{}); return
        if not BUSY.acquire(False): self.reply(429,{}); return
        started=False
        try:
            with tempfile.TemporaryDirectory(prefix='podcast-') as directory:
                os.chmod(directory,0o770)
                os.chown(directory,1001,0)
                source=pathlib.Path(directory)/'source.audio'
                deadline=time.monotonic()+TIMEOUT
                upload_deadline=min(deadline,time.monotonic()+600)
                remaining=length
                with source.open('wb') as f:
                    while remaining:
                        if time.monotonic()>upload_deadline: raise ValueError('upload timeout')
                        self.connection.settimeout(min(30, max(.001, upload_deadline-time.monotonic())))
                        block=self.rfile.read(min(65536,remaining))
                        if not block: raise ValueError('truncated upload')
                        f.write(block); remaining-=len(block)
                source.chmod(0o440);os.chown(source,0,1001)
                with source.open('rb') as f: fmt=media_format(f.read(16))
                options=decoder_options(fmt)
                probe=run_stage(['/usr/bin/ffprobe',*options,'-show_entries','format=duration','-of','json',str(source)],min(20,deadline-time.monotonic()),self.connection)
                duration=float(json.loads(probe)['format']['duration'])
                if not math.isfinite(duration) or not 0<duration<=MAX_DURATION: raise ValueError('audio exceeds duration')
                if resume>duration: raise ValueError('resume beyond duration')
                if streaming:
                    self.send_response(200)
                    self.send_header('Content-Type','application/x-ndjson')
                    self.send_header('Cache-Control','no-store')
                    self.send_header('Connection','close')
                    self.end_headers();self.close_connection=True;started=True
                    cursor=resume
                    complete=False
                    total_segments=total_text=total_bytes=0
                    def emit(event):
                        nonlocal cursor,complete,total_segments,total_text,total_bytes
                        if complete: raise ValueError('event after complete')
                        if event.get('type')=='checkpoint':
                            validate_checkpoint(event,cursor,duration)
                            total_segments+=len(event['segments'])
                            total_text+=sum(len(item['text']) for item in event['segments'])
                            if total_segments>MAX_SEGMENTS or total_text>MAX_TEXT: raise ValueError('transcript exceeds limits')
                            cursor=event['end_seconds']
                        elif event.get('type')=='complete':
                            if cursor!=duration or event.get('duration_seconds')!=duration or event.get('language')!=language:
                                raise ValueError('invalid completion')
                            complete=True
                            # Do not publish completion until the producer exits cleanly.
                            return
                        else: raise ValueError('invalid event')
                        line=(json.dumps(event,allow_nan=False,ensure_ascii=False)+'\n').encode()
                        total_bytes+=len(line)
                        if total_bytes>4<<20: raise ValueError('transcript exceeds limits')
                        self.connection.settimeout(max(.001,min(30,deadline-time.monotonic())))
                        self.wfile.write(line);self.wfile.flush()
                    stream_stage([sys.executable,__file__,'--stream',str(source),language,str(resume),str(duration)],deadline-time.monotonic(),self.connection,emit)
                    if not complete: raise ValueError('missing completion')
                    self.wfile.write((json.dumps({'type':'complete','duration_seconds':duration,'language':language})+'\n').encode());self.wfile.flush()
                else:
                    raw=run_stage([sys.executable,__file__,'--recognize',str(source),language],deadline-time.monotonic(),self.connection)
                    segments=validated_segments(json.loads(raw)['segments'])
                    self.reply(200,{'version':1,'language':language,'segments':segments})
        except (ValueError, OSError, KeyError, TypeError, AttributeError, subprocess.TimeoutExpired):
            if started:
                try:
                    self.wfile.write(b'{"type":"error","code":"recognition_failed"}\n');self.wfile.flush()
                except OSError: pass
            else: self.reply(422,{'error':'audio processing rejected or canceled'})
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


def timeout_seconds(value):
    seconds = int(value)
    if not 0 < seconds <= 5400: raise ValueError('invalid worker deadline')
    return seconds


TIMEOUT = timeout_seconds(os.environ.get('PODCAST_WORKER_TIMEOUT_SECONDS', '5400'))


def decoder_options(fmt):
    return ['-v','error','-protocol_whitelist','file,pipe','-format_whitelist',fmt,'-f',fmt]


def pcm_chunks(stream, chunk_frames=16000*CHUNK_SECONDS, resume=0):
    # Continuous bounded decode of the remaining input after exact seek.
    frames = resume*16000
    while True:
        block = bytearray()
        while len(block) < chunk_frames*2:
            part = stream.read(min(65536, chunk_frames*2-len(block)))
            if not part: break
            block.extend(part)
        if not block: return
        if len(block) % 2: raise ValueError('partial PCM sample')
        count = len(block)//2
        if frames+count > MAX_DURATION*16000: raise ValueError('decoded audio exceeds duration')
        yield frames/16000, block
        frames += count


def append_chunk(target, items, offset, duration):
    for item in items:
        start, end, text = item['start'], item['end'], item['text'].strip()
        if not math.isfinite(start) or not math.isfinite(end) or start < 0 or end <= start:
            raise ValueError('invalid chunk timestamp')
        # Whisper can extend a final token beyond available samples and can
        # overlap adjacent inferred segments. Keep each token once, clipped to
        # this disjoint PCM window and to the previous emitted segment's end.
        start = max(offset+min(start,duration), target[-1]['end'] if target else 0)
        end = offset+min(end,duration)
        if text and end > start: target.append({'start':start,'end':end,'text':text})
    if len(target)>MAX_SEGMENTS or sum(len(x['text']) for x in target)>MAX_TEXT:
        raise ValueError('transcript exceeds limits')


def speech_bounds(samples):
    # Trim only exact digital silence; no VAD threshold that can erase quiet
    # speech. Retain the original sample offset when restoring timestamps.
    first = next((i for i, sample in enumerate(samples) if sample != 0), None)
    if first is None: return None
    last = len(samples)
    while samples[last-1] == 0: last -= 1
    return first, last


def recognize(path, language, smoke=False, streaming=False, resume=0, duration=None):
    import numpy as np
    import torch
    import whisper
    torch.set_num_threads(2)
    def emit(event):
        print(json.dumps(event,allow_nan=False,ensure_ascii=False),flush=True)
    if streaming and resume==duration:
        emit({'type':'complete','duration_seconds':duration,'language':language});return
    # Explicit local path: whisper must never download models at runtime.
    model=whisper.load_model('/models/base.pt',device='cpu')
    with open(path,'rb') as source: fmt=media_format(source.read(16))
    # Input accurate seek avoids decoding prior windows; ffmpeg discards to the
    # sample-exact target after demuxer/keyframe seek. Output -ss 0 explicitly
    # resets the remaining timeline (not a second resume-length trim).
    seek=['-ss',str(resume),'-accurate_seek'] if resume else []
    args=['/usr/bin/ffmpeg','-nostdin',*decoder_options(fmt),'-threads','2',*seek,'-i',path,
          '-ss','0','-map','0:a:0','-vn','-sn','-dn','-ac','1','-ar','16000','-threads','2','-f','s16le','pipe:1']
    # Same supervisor-created process group and restricted UID/environment.
    # Pipe backpressure keeps decoder memory/output bounded during inference.
    decoder=subprocess.Popen(args,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL,close_fds=True,env=ENV)
    assert decoder.stdout is not None
    segments=[]
    consumed=resume
    total_segments=total_text=0
    try:
        for offset, pcm in pcm_chunks(decoder.stdout,resume=resume):
            if streaming: segments=[]
            consumed=offset+len(pcm)/32000
            audio=np.frombuffer(pcm,dtype=np.int16).astype(np.float32)/32768
            # Exact digital silence carries no speech. Do not submit silence
            # to Whisper (hallucinations); still decode/count every sample.
            bounds = speech_bounds(audio)
            if bounds is not None or smoke:
                first, last = bounds if bounds is not None else (0, len(audio))
                # Small real-context padding, still inside this PCM window.
                first=max(0,first-3200);last=min(len(audio),last+3200)
                result=model.transcribe(audio[first:last],language=language,task='transcribe',fp16=False,
                                        verbose=None,condition_on_previous_text=False)
                append_chunk(segments,result['segments'],offset+first/16000,(last-first)/16000)
            if streaming:
                end=min(offset+CHUNK_SECONDS,duration)
                if abs(consumed-end)>.25: raise ValueError('decoded duration mismatch')
                # Clip inferred final tokens to the probed original endpoint.
                segments=[{**item,'end':min(item['end'],end)} for item in segments if item['start']<end]
                total_segments+=len(segments);total_text+=sum(len(item['text']) for item in segments)
                if total_segments>MAX_SEGMENTS or total_text>MAX_TEXT: raise ValueError('transcript exceeds limits')
                emit({'type':'checkpoint','chunk_index':int(offset//CHUNK_SECONDS),'end_seconds':end,'segments':segments})
            del audio, pcm
        if decoder.wait(): raise ValueError('decoder failed')
        if streaming and abs(consumed-duration)>.25: raise ValueError('decoded duration mismatch')
    finally:
        decoder.stdout.close()
        if decoder.poll() is None: decoder.kill()
        decoder.wait()
    if streaming: emit({'type':'complete','duration_seconds':duration,'language':language})
    else: print(json.dumps({'segments':segments},allow_nan=False,ensure_ascii=False))


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
        run_stage([sys.executable,__file__,'--smoke',path,'de'],180)
    READY=True
    Server(('0.0.0.0',8091),Handler).serve_forever()

if __name__=='__main__':
    if len(sys.argv)>2 and sys.argv[1]=='--stage':
        restricted_child()
        os.execve(sys.argv[2],sys.argv[2:],ENV)
    elif len(sys.argv)==6 and sys.argv[1]=='--stream':
        recognize(sys.argv[2],sys.argv[3],streaming=True,resume=resume_offset(sys.argv[4]),duration=float(sys.argv[5]))
    elif len(sys.argv)==4 and sys.argv[1] in ('--recognize','--smoke'):
        recognize(sys.argv[2],sys.argv[3],smoke=sys.argv[1]=='--smoke')
    else: main()
