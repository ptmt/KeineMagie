"""Run the candidate with disposable secrets, internal network, and real Mac TTS.
No production containers, routing, auth stores or provider data are accessed.
"""
import hashlib
import struct
import threading
import wave
import http.client
import json
import os
import pathlib
import secrets
import subprocess
import tempfile
import time

IMAGE=os.environ.get('PODCAST_WORKER_TEST_IMAGE','keinemagie-podcast-worker:candidate')
NAME='keinemagie-podcast-fixture'
NETWORK=NAME
VOLUME=NAME+'-secret'

def cmd(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def main():
    token=secrets.token_hex(32)
    root=pathlib.Path('/Users/tinyserve/.hermes/cache/scratch')
    repo=pathlib.Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='podcast-fixture-', dir=root) as directory:
        directory=pathlib.Path(directory)
        started=time.monotonic()
        audio=directory/'speech.aiff'
        cmd('/usr/bin/say','-v','Anna','-o',str(audio),'Guten Morgen. Heute lernen wir zusammen Deutsch. Das Wetter ist schön.')
        ending=directory/'ending.aiff'
        cmd('/usr/bin/say','-v','Anna','-o',str(ending),'Zum Abschluss sprechen wir über die Bibliothek. In der Bibliothek lesen wir deutsche Bücher. Auf Wiedersehen.')
        long_audio=directory/'long.wav'
        # Actual 11-minute decoded media, not forged duration metadata. German
        # bookends straddle 600 seconds; final marker starts at 650 seconds.
        cmd('ffmpeg','-v','error','-i',str(audio),'-i',str(ending),
            '-filter_complex','[0:a]aresample=16000,apad,atrim=duration=650[a];[1:a]aresample=16000,apad,atrim=duration=10[b];[a][b]concat=n=2:v=0:a=1[out]',
            '-map','[out]','-ac','1','-c:a','pcm_s16le',str(long_audio))
        with wave.open(str(long_audio)) as media:
            assert media.getnframes()/media.getframerate()==660
        # Valid RIFF JUNK padding exercises the full 300 MiB streamed upload
        # and tmpfs+cgroup budget without changing its real decoded duration.
        size=300<<20
        with long_audio.open('r+b') as media:
            media.seek(0,2);current=media.tell()
            media.write(b'JUNK'+struct.pack('<I',size-current-8))
            media.truncate(size)
            media.seek(4);media.write(struct.pack('<I',size-8))
        digest=hashlib.sha256()
        with long_audio.open('rb') as media:
            for block in iter(lambda:media.read(65536),b''):digest.update(block)
        print('LONG FIXTURE:',long_audio.stat().st_size,'bytes SHA256:',digest.hexdigest(),flush=True)
        cmd('docker','network','create','--internal',NETWORK,stdout=subprocess.DEVNULL)
        cmd('docker','volume','create',VOLUME,stdout=subprocess.DEVNULL)
        try:
            cmd('docker','run','--rm','-i','--network','none','-v',VOLUME+':/secret',IMAGE,'python','-c',
                "import os,sys; p='/secret/podcast_token'; f=open(p,'wb');f.write(sys.stdin.buffer.read());f.close();os.chmod(p,0o600)",input=token.encode(),stdout=subprocess.DEVNULL)
            cmd('docker','run','-d','--name',NAME,'--network',NETWORK,'--read-only','--tmpfs','/tmp:rw,nosuid,nodev,noexec,size=512m,mode=1777',
                '--memory','2g','--memory-swap','2g','--cpus','2','--pids-limit','64','--cap-drop','ALL',
                '--cap-add','SETUID','--cap-add','SETGID','--cap-add','CHOWN','--cap-add','KILL',
                '--security-opt','no-new-privileges','-v',VOLUME+':/run/secrets:ro',IMAGE,stdout=subprocess.DEVNULL)
            # Client runs inside the isolated network; no host/public port needed.
            client=r'''
import hashlib
import struct
import threading
import wave
import http.client,json,pathlib,socket,sys,time
secret=sys.stdin.buffer.readline().strip().decode()
audio=sys.stdin.buffer.read()
def request(method,path,body=None,auth=True,extra=None):
 c=http.client.HTTPConnection('keinemagie-podcast-fixture',8091,timeout=5400)
 h={'X-Podcast-Version':'1'}
 if auth:h['Authorization']='Bearer '+secret
 if extra:h.update(extra)
 c.request(method,path,body=body,headers=h);r=c.getresponse();s=r.status;b=r.read();c.close();return s,b
for n in range(120):
 try:
  s,b=request('GET','/internal/podcast/ready')
  if s==200:break
 except OSError:pass
 time.sleep(1)
else:raise RuntimeError('worker never became ready')
assert request('GET','/internal/podcast/ready',auth=False)[0]==401
h={'Content-Type':'application/octet-stream','X-Podcast-Language':'de'}
assert request('POST','/internal/podcast/transcribe',b'#EXTM3U\nfile:///run/secrets/podcast_token',extra=h)[0]==422
assert request('POST','/internal/podcast/transcribe',b'',extra={**h,'Content-Length':str((300<<20)+1)})[0]==413
s,b=request('POST','/internal/podcast/transcribe',audio,extra=h)
assert s==200,(s,b)
v=json.loads(b);text=' '.join(x['text'] for x in v['segments'])
assert 'deutsch' in text.lower(),text
print('REAL TRANSCRIPT:',text)
print('readiness/auth/oversize/manifest/real speech: PASS')
# Disconnect after the upload has been consumed; the active child group must
# disappear and capacity return without waiting for the overall deadline.
c=http.client.HTTPConnection('keinemagie-podcast-fixture',8091,timeout=10)
c.request('POST','/internal/podcast/transcribe',body=audio,headers={**h,'X-Podcast-Version':'1','Authorization':'Bearer '+secret})
for n in range(100):
 if request('GET','/internal/podcast/ready')[0]==503:break
 time.sleep(.02)
else:raise RuntimeError('request did not become active')
assert request('POST','/internal/podcast/transcribe',audio,extra=h)[0]==429
c.close()
for n in range(100):
 if request('GET','/internal/podcast/ready')[0]==200:break
 time.sleep(.05)
else:raise RuntimeError('disconnect did not release worker capacity')
print('contention/disconnect cancellation: PASS')
try:socket.create_connection(('1.1.1.1',443),timeout=2)
except OSError:print('internet egress blocked: PASS')
else:raise RuntimeError('internet egress reachable')
'''
            cmd('docker','run','--rm','-i','--network',NETWORK,IMAGE,'python','-c',client,input=token.encode()+b'\n'+audio.read_bytes())
            long_client=r'''
import http.client,json,pathlib,sys,time
secret=sys.stdin.buffer.read().strip().decode()
path=pathlib.Path('/fixture/long.wav')
c=http.client.HTTPConnection('keinemagie-podcast-fixture',8091,timeout=5400)
h={'Authorization':'Bearer '+secret,'X-Podcast-Version':'1','X-Podcast-Language':'de','Content-Type':'application/octet-stream','Content-Length':str(path.stat().st_size)}
t=time.monotonic()
with path.open('rb') as audio:c.request('POST','/internal/podcast/transcribe',body=audio,headers=h)
r=c.getresponse();b=r.read();assert r.status==200,(r.status,b)
v=json.loads(b);assert v['version']==1 and v['language']=='de'
previous=0
for segment in v['segments']:
 assert previous<=segment['start']<segment['end']<=660,segment
 previous=segment['end']
text=' '.join(x['text'] for x in v['segments'])
assert 'deutsch' in text.lower(),text
assert any(x['start']>=600 and 'bibliothek' in x['text'].lower() for x in v['segments']),v
print('LONG TRANSCRIPT:',json.dumps(v,ensure_ascii=False),flush=True)
print('real 660-second chunk boundary/final marker/monotonic schema: PASS; elapsed=%.2fs'%(time.monotonic()-t),flush=True)
'''
            stop=threading.Event()
            samples=[]
            def monitor():
                while not stop.is_set():
                    sample=subprocess.run(['docker','exec',NAME,'python','-c',
                        "import json,pathlib; r=pathlib.Path('/sys/fs/cgroup'); print(json.dumps({n:(r/n).read_text() for n in ('memory.current','memory.peak','memory.events','cpu.stat')}))"],capture_output=True,text=True)
                    if sample.returncode==0:samples.append(json.loads(sample.stdout))
                    stop.wait(2)
            thread=threading.Thread(target=monitor);thread.start()
            try:
                cmd('docker','run','--rm','-i','--network',NETWORK,'-v',str(directory)+':/fixture:ro',IMAGE,'python','-c',long_client,input=token.encode())
            finally:
                stop.set();thread.join()
            assert samples
            assert all('oom_kill 0' in x['memory.events'] for x in samples),samples[-1]
            print('RESOURCE SAMPLES:',len(samples),'PEAK:',max(int(x['memory.peak']) for x in samples),'LAST:',json.dumps(samples[-1]),flush=True)
            tokenfile=directory/'token';tokenfile.write_text(token);tokenfile.chmod(0o600)
            binary=directory/'server.test'
            cmd('go','test','-c','-o',str(binary),cwd=repo/'server',env={**os.environ,'GOOS':'linux','GOARCH':'arm64','CGO_ENABLED':'0'})
            go_result=subprocess.run(['docker','run','--rm','--network',NETWORK,'--tmpfs','/tmp:rw,size=96m',
                '-v',str(directory)+':/fixture:ro','-e','PODCAST_CONTAINER_TEST=1',
                '-e','PODCAST_WORKER_URL=http://'+NAME+':8091',
                '-e','PODCAST_WORKER_TOKEN_FILE=/fixture/token',IMAGE,
                '/fixture/server.test','-test.run','^TestPodcastRemoteRealContainer$','-test.v'])
            # Exercise supervisor deadlines and killpg against actual child +
            # grandchild processes, not source-text assertions or fake Popen.
            cmd('docker','exec',NAME,'python','-c',r'''
import pathlib,sys,time,worker
p=pathlib.Path('/tmp/worker-cancel-pids')
child="import os,pathlib,subprocess,sys,time; c=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); pathlib.Path('/tmp/worker-cancel-pids').write_text(str(os.getpid())+' '+str(c.pid)); time.sleep(60)"
t=time.monotonic()
try:worker.run_stage([sys.executable,'-c',child],1)
except ValueError:pass
else:raise AssertionError('deadline did not cancel')
assert time.monotonic()-t<3
pids=p.read_text().split();assert len(pids)==2
for pid in pids:
 path=pathlib.Path('/proc')/pid/'stat'
 assert not path.exists() or path.read_text().split()[2]=='Z',pid
p.unlink()
print('real supervisor deadline/process-group grandchildren cancellation: PASS')
''')
            # Verify sandbox as actual unprivileged decoder user.
            cmd('docker','exec','-u','1001:1001',NAME,'python','-c',
                "import os; p='/run/secrets/podcast_token'; assert not os.access(p,os.R_OK); assert not os.access('/app',os.W_OK); print('decoder secret isolation/read-only app: PASS')")
            config=json.loads(subprocess.check_output(['docker','inspect',NAME]))[0]
            assert not config['HostConfig']['PortBindings']
            assert config['HostConfig']['ReadonlyRootfs']
            assert config['HostConfig']['Memory']==2*1024**3
            assert config['HostConfig']['MemorySwap']==2*1024**3
            assert config['HostConfig']['NanoCpus']==2*10**9
            assert 'size=512m' in config['HostConfig']['Tmpfs']['/tmp']
            print('IMAGE:',config['Image'],'TOTAL ELAPSED: %.2fs'%(time.monotonic()-started),flush=True)
            assert list(config['NetworkSettings']['Networks'])==[NETWORK]
            print('no published ports/internal-only network: PASS')
            logs=subprocess.check_output(['docker','logs',NAME],stderr=subprocess.STDOUT)
            assert token.encode() not in logs
            assert not logs, 'worker must not log auth or transcripts'
            print('no auth/transcript logs: PASS')
            go_result.check_returncode()
        finally:
            subprocess.run(['docker','logs',NAME],check=False)
            subprocess.run(['docker','rm','-f',NAME],stdout=subprocess.DEVNULL,check=False)
            subprocess.run(['docker','volume','rm',VOLUME],stdout=subprocess.DEVNULL,check=False)
            subprocess.run(['docker','network','rm',NETWORK],stdout=subprocess.DEVNULL,check=False)

if __name__=='__main__': main()
