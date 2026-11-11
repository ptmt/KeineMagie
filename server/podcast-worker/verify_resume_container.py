"""Disposable real-Whisper resume/crash verification; never touches production.
The opt-in fixture launcher adds a test-only sitecustomize pause before second
Whisper inference. Neither the hook nor its control path is in the image.
"""
import hashlib
import json
import os
import pathlib
import secrets
import subprocess
import tempfile
import time

IMAGE=os.environ.get('PODCAST_WORKER_TEST_IMAGE','keinemagie-podcast-worker:resume-candidate')
NAME='keinemagie-resume-fixture'
NETWORK=NAME
VOLUME=NAME+'-secret'

def cmd(*args, **kwargs):
    return subprocess.run(args,check=True,**kwargs)

CLIENT=r'''
import http.client,json,pathlib,sys,time
secret=sys.stdin.buffer.read().strip().decode()
mode=sys.argv[1]
path=pathlib.Path('/fixture/long.wav')
headers={'Authorization':'Bearer '+secret,'X-Podcast-Version':'1','X-Podcast-Language':'de','Content-Type':'application/octet-stream','Content-Length':str(path.stat().st_size),'Accept':'application/x-ndjson'}
def connect(offset):
 c=http.client.HTTPConnection('keinemagie-resume-fixture',8091,timeout=5400)
 with path.open('rb') as f:c.request('POST','/internal/podcast/transcribe',body=f,headers={**headers,'X-Resume-Offset':str(offset)})
 r=c.getresponse();assert r.status==200,(r.status,r.read())
 assert r.getheader('Content-Type')=='application/x-ndjson'
 assert r.getheader('Connection')=='close' and r.getheader('Content-Length') is None
 return c,r
if mode=='drop':
 c,r=connect(0);first=json.loads(r.readline());assert first['type']=='checkpoint' and first['chunk_index']==0 and first['end_seconds']==600,first
 assert any('deutsch' in s['text'].lower() for s in first['segments']),first
 # Persist the exact observed checkpoint independently of the worker.
 with open('/result/checkpoint.json','w') as f:json.dump(first,f);f.flush();__import__('os').fsync(f.fileno())
 print('FIRST CHECKPOINT (before second inference release):',json.dumps(first,ensure_ascii=False),flush=True)
 time.sleep(1)
 c.close();r.close()
elif mode=='resume':
 c,r=connect(600);events=[json.loads(line) for line in r];c.close()
 assert [e['type'] for e in events]==['checkpoint','complete'],events
 cp,complete=events
 assert cp['chunk_index']==1 and cp['end_seconds']==660,events
 assert all(600<=s['start']<s['end']<=660 for s in cp['segments']),events
 assert any(s['start']>649 and 'bibliothek' in s['text'].lower() for s in cp['segments']),events
 assert not any('guten morgen' in s['text'].lower() for s in cp['segments']),events
 assert complete=={'type':'complete','duration_seconds':660.,'language':'de'},events
 print('RESUMED REAL TRANSCRIPT:',json.dumps(events,ensure_ascii=False),flush=True)
 with open('/result/resumed.json','w') as f:json.dump(events,f)
elif mode=='full':
 c,r=connect(0);events=[];times=[]
 for line in r:events.append(json.loads(line));times.append(time.monotonic())
 c.close()
 assert [e['type'] for e in events]==['checkpoint','checkpoint','complete'],events
 assert [e['chunk_index'] for e in events[:2]]==[0,1]
 assert events[0]['end_seconds']==600 and events[1]['end_seconds']==660
 assert any(s['start']>649 and 'bibliothek' in s['text'].lower() for s in events[1]['segments']),events
 print('UNINSTRUMENTED FLUSHED EVENTS:',json.dumps(events,ensure_ascii=False),'checkpoint arrival delta=%.3fs'%(times[1]-times[0]),flush=True)
else:raise AssertionError(mode)
'''

HOOK='''import sys
if '--stream' in sys.argv:
 import os,pathlib,time,whisper
 original=whisper.load_model
 def load(*args,**kwargs):
  model=original(*args,**kwargs);transcribe=model.transcribe;calls=0
  def wrapped(*a,**kw):
   nonlocal calls
   calls+=1
   if calls==2:
    pathlib.Path('/tmp/fixture-paused').write_text(str(os.getpid()))
    while not pathlib.Path('/tmp/fixture-release').exists():time.sleep(.05)
   return transcribe(*a,**kw)
  model.transcribe=wrapped
  return model
 whisper.load_model=load
'''

def main():
    image_id=subprocess.check_output(['docker','image','inspect','--format','{{.Id}}',IMAGE],text=True).strip()
    token=secrets.token_hex(32)
    root=pathlib.Path('/Users/tinyserve/.hermes/cache/scratch')
    with tempfile.TemporaryDirectory(prefix='podcast-resume-',dir=root) as directory:
        directory=pathlib.Path(directory)
        directory.chmod(0o755)
        start=directory/'start.aiff';end=directory/'end.aiff'
        cmd('/usr/bin/say','-v','Anna','-o',str(start),'Guten Morgen. Heute lernen wir zusammen Deutsch. Das Wetter ist schön.')
        cmd('/usr/bin/say','-v','Anna','-o',str(end),'Zum Abschluss sprechen wir über die Bibliothek. In der Bibliothek lesen wir deutsche Bücher. Auf Wiedersehen.')
        audio=directory/'long.wav'
        cmd('ffmpeg','-v','error','-i',str(start),'-i',str(end),'-filter_complex','[0:a]aresample=16000,apad,atrim=duration=650[a];[1:a]aresample=16000,apad,atrim=duration=10[b];[a][b]concat=n=2:v=0:a=1[out]','-map','[out]','-ac','1','-c:a','pcm_s16le',str(audio))
        (directory/'sitecustomize.py').write_text(HOOK)
        result=directory/'result';result.mkdir()
        cmd('docker','network','create','--internal',NETWORK,stdout=subprocess.DEVNULL)
        cmd('docker','volume','create',VOLUME,stdout=subprocess.DEVNULL)
        try:
            cmd('docker','run','--rm','-i','--network','none','-v',VOLUME+':/secret',image_id,'python','-c',"import os,sys; p='/secret/podcast_token'; open(p,'wb').write(sys.stdin.buffer.read());os.chmod(p,0o600)",input=token.encode())
            def launch(pause=False):
                args=['docker','run','-d','--name',NAME,'--network',NETWORK,'--read-only','--tmpfs','/tmp:rw,nosuid,nodev,noexec,size=512m,mode=1777','--memory','2g','--memory-swap','2g','--cpus','2','--pids-limit','64','--cap-drop','ALL','--cap-add','SETUID','--cap-add','SETGID','--cap-add','CHOWN','--cap-add','KILL','--security-opt','no-new-privileges','-v',VOLUME+':/run/secrets:ro']
                if pause:args+=['-v',str(directory)+':/fixture:ro']
                args+=[image_id]
                if pause:args+=['python','-c',"import worker,sys; worker.stage_command=lambda a:[sys.executable,worker.__file__,'--stage',sys.executable,'-c',\"import sys,runpy;sys.argv=\"+repr(a[1:])+\";exec(open('/fixture/sitecustomize.py').read());runpy.run_path('/app/worker.py',run_name='__main__')\"]; worker.main()"]
                cmd(*args,stdout=subprocess.DEVNULL)
                probe="import http.client,sys,time; token=sys.stdin.read().strip();\nfor _ in range(120):\n try:\n  c=http.client.HTTPConnection('localhost',8091,timeout=2);c.request('GET','/internal/podcast/ready',headers={'Authorization':'Bearer '+token,'X-Podcast-Version':'1'});r=c.getresponse();r.read();c.close();\n  if r.status==200:break\n except OSError:pass\n time.sleep(1)\nelse:raise RuntimeError('not ready')"
                cmd('docker','exec','-i',NAME,'python','-c',probe,input=token.encode())
            def client(mode):
                return cmd('docker','run','--rm','-i','--network',NETWORK,'-v',str(directory)+':/fixture:ro','-v',str(result)+':/result',image_id,'python','-c',CLIENT,mode,input=token.encode())
            launch();client('full')
            cmd('docker','rm','-f',NAME,stdout=subprocess.DEVNULL)
            launch(pause=True);client('drop')
            assert (result/'checkpoint.json').is_file()
            # The second real model call must be paused, not already completed.
            paused=cmd('docker','exec',NAME,'python','-c',"import pathlib,time; p=pathlib.Path('/tmp/fixture-paused');\nfor _ in range(100):\n if p.exists():print(p.read_text());break\n time.sleep(.05)\nelse:raise AssertionError('second chunk never paused')",capture_output=True,text=True).stdout.strip()
            cmd('docker','exec',NAME,'python','-c',"import pathlib,time; pid="+repr(paused)+";\nfor _ in range(100):\n p=pathlib.Path('/proc')/pid/'stat'\n if not p.exists() or p.read_text().split()[2]=='Z':break\n time.sleep(.05)\nelse:raise AssertionError('disconnected recognition survived')")
            print('FIRST CHECKPOINT DURABLE; SECOND INFERENCE PAUSED; DISCONNECT KILLED RECOGNIZER PID:',paused,flush=True)
            # Actual deployment replacement: destroy whole ephemeral worker and
            # tmpfs, then resume on a new normal container with no worker cache.
            cmd('docker','rm','-f',NAME,stdout=subprocess.DEVNULL)
            launch();client('resume')
            config=json.loads(subprocess.check_output(['docker','inspect',NAME]))[0]
            assert config['Image']==image_id and config['HostConfig']['ReadonlyRootfs']
            assert config['HostConfig']['Memory']==2*1024**3 and config['HostConfig']['MemorySwap']==2*1024**3
            assert not config['HostConfig']['PortBindings'] and list(config['NetworkSettings']['Networks'])==[NETWORK]
            assert not subprocess.check_output(['docker','logs',NAME],stderr=subprocess.STDOUT)
            stats=cmd('docker','exec',NAME,'python','-c',"import pathlib,json; p=pathlib.Path('/sys/fs/cgroup');print(json.dumps({n:(p/n).read_text() for n in ('memory.peak','memory.events')}))",capture_output=True,text=True).stdout.strip()
            assert 'oom_kill 0' in stats
            artifact={'image':image_id,'source_sha256':hashlib.sha256(pathlib.Path(__file__).with_name('worker.py').read_bytes()).hexdigest(),'fixture_sha256':hashlib.sha256(audio.read_bytes()).hexdigest(),'checkpoint':json.loads((result/'checkpoint.json').read_text()),'resumed':json.loads((result/'resumed.json').read_text()),'resources':json.loads(stats)}
            target=pathlib.Path(__file__).with_name('resume-verification.json')
            target.write_text(json.dumps(artifact,ensure_ascii=False,indent=2)+'\n')
            print('REPLACEMENT RESUME / ISOLATION / NO WORKER PERSISTENT AUDIO VOLUME: PASS',flush=True)
            print('ARTIFACT:',target,'IMAGE:',image_id,'RESOURCES:',stats,flush=True)
        finally:
            subprocess.run(['docker','rm','-f',NAME],stdout=subprocess.DEVNULL,check=False)
            subprocess.run(['docker','volume','rm',VOLUME],stdout=subprocess.DEVNULL,check=False)
            subprocess.run(['docker','network','rm',NETWORK],stdout=subprocess.DEVNULL,check=False)

if __name__=='__main__':main()
