"""Run the candidate with disposable secrets, internal network, and real Mac TTS.
No production containers, routing, auth stores or provider data are accessed.
"""
import http.client
import json
import os
import pathlib
import secrets
import subprocess
import tempfile
import time

IMAGE='keinemagie-podcast-worker:candidate'
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
        audio=directory/'speech.aiff'
        cmd('/usr/bin/say','-v','Anna','-o',str(audio),'Guten Morgen. Heute lernen wir zusammen Deutsch. Das Wetter ist schön.')
        cmd('docker','network','create','--internal',NETWORK,stdout=subprocess.DEVNULL)
        cmd('docker','volume','create',VOLUME,stdout=subprocess.DEVNULL)
        try:
            cmd('docker','run','--rm','-i','--network','none','-v',VOLUME+':/secret',IMAGE,'python','-c',
                "import os,sys; p='/secret/podcast_token'; f=open(p,'wb');f.write(sys.stdin.buffer.read());f.close();os.chmod(p,0o600)",input=token.encode(),stdout=subprocess.DEVNULL)
            cmd('docker','run','-d','--name',NAME,'--network',NETWORK,'--read-only','--tmpfs','/tmp:rw,nosuid,nodev,noexec,size=160m,mode=1777',
                '--memory','1100m','--memory-swap','1100m','--cpus','2','--pids-limit','64','--cap-drop','ALL',
                '--cap-add','SETUID','--cap-add','SETGID','--cap-add','CHOWN','--cap-add','KILL',
                '--security-opt','no-new-privileges','-v',VOLUME+':/run/secrets:ro',IMAGE,stdout=subprocess.DEVNULL)
            # Client runs inside the isolated network; no host/public port needed.
            client=r'''
import http.client,json,pathlib,socket,sys,time
secret=sys.stdin.buffer.readline().strip().decode()
audio=sys.stdin.buffer.read()
def request(method,path,body=None,auth=True,extra=None):
 c=http.client.HTTPConnection('keinemagie-podcast-fixture',8091,timeout=180)
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
assert request('POST','/internal/podcast/transcribe',b'',extra={**h,'Content-Length':str((40<<20)+1)})[0]==413
s,b=request('POST','/internal/podcast/transcribe',audio,extra=h)
assert s==200,(s,b)
v=json.loads(b);text=' '.join(x['text'] for x in v['segments'])
assert 'deutsch' in text.lower(),text
print('REAL TRANSCRIPT:',text)
print('readiness/auth/oversize/manifest/real speech: PASS')
# Disconnect after the upload has been consumed; the active child group must
# disappear and capacity return without waiting for recognition's 30min limit.
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
            tokenfile=directory/'token';tokenfile.write_text(token);tokenfile.chmod(0o600)
            binary=directory/'server.test'
            cmd('go','test','-c','-o',str(binary),cwd=repo/'server',env={**os.environ,'GOOS':'linux','GOARCH':'arm64','CGO_ENABLED':'0'})
            cmd('docker','run','--rm','--network',NETWORK,'--tmpfs','/tmp:rw,size=96m',
                '-v',str(directory)+':/fixture:ro','-e','PODCAST_CONTAINER_TEST=1',
                '-e','PODCAST_WORKER_URL=http://'+NAME+':8091',
                '-e','PODCAST_WORKER_TOKEN_FILE=/fixture/token',IMAGE,
                '/fixture/server.test','-test.run','^TestPodcastRemoteRealContainer$','-test.v')
            # Verify sandbox as actual unprivileged decoder user.
            cmd('docker','exec','-u','1001:1001',NAME,'python','-c',
                "import os; p='/run/secrets/podcast_token'; assert not os.access(p,os.R_OK); assert not os.access('/app',os.W_OK); print('decoder secret isolation/read-only app: PASS')")
            config=json.loads(subprocess.check_output(['docker','inspect',NAME]))[0]
            assert not config['HostConfig']['PortBindings']
            assert config['HostConfig']['ReadonlyRootfs']
            assert list(config['NetworkSettings']['Networks'])==[NETWORK]
            print('no published ports/internal-only network: PASS')
        finally:
            subprocess.run(['docker','logs',NAME],check=False)
            subprocess.run(['docker','rm','-f',NAME],stdout=subprocess.DEVNULL,check=False)
            subprocess.run(['docker','volume','rm',VOLUME],stdout=subprocess.DEVNULL,check=False)
            subprocess.run(['docker','network','rm',NETWORK],stdout=subprocess.DEVNULL,check=False)

if __name__=='__main__': main()
