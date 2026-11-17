"""Real Chromium media and Go HTTP handler, synthetic one-second silent WAVs.
No sockets or providers: Playwright routes HTTP to an isolated stdio handler.
Run with the task's Playwright Python. Requires Go and Chromium permissions.
"""
import base64,json,mimetypes,os,subprocess,tempfile,time
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
repo=Path(__file__).resolve().parents[2]
out=repo/'docs/evidence/dictation-focused-ux/policy'
out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='dictation-policy-') as tmp:
 env=dict(os.environ,DICTATION_PLAYBACK_BRIDGE=tmp)
 binary=Path(tmp)/'fixture.test'
 subprocess.run(['go','test','-c','-o',str(binary)],cwd=repo/'server',env=env,check=True,capture_output=True)
 def start():
  global bridge,identity
  bridge=subprocess.Popen([str(binary),'-test.run=^TestDictationPlaybackHTTPBridge$'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
  line=bridge.stdout.readline();assert line.startswith('PLAYBACK_BOOT '),line
  identity=json.loads(line.removeprefix('PLAYBACK_BOOT '))
 def call(method,path,body=None,headers=None):
  message=dict(method=method,path=path,body=json.dumps(body) if body is not None else '',headers=headers or {'Authorization':'Bearer '+identity['token']})
  bridge.stdin.write(json.dumps(message)+'\n');bridge.stdin.flush();response=json.loads(bridge.stdout.readline());response['bytes']=base64.b64decode(response['body'] or '');return response
 start();ranges=[];errors=[];abort_media=False
 try:
  with sync_playwright() as p:
   b=p.chromium.launch();ctx=b.new_context(viewport={'width':390,'height':844})
   ctx.add_cookies([dict(name='__Host-km-session',value=identity['browser'],url='https://dictation.test',secure=True,httpOnly=True,sameSite='Strict')])
   def route(r):
    global abort_media
    req=r.request;path=urlparse(req.url).path
    if path=='/__fixture_session':r.fulfill(content_type='application/json',body=json.dumps(dict(user=dict(id=identity['owner']),csrf_token=identity['csrf_token'])));return
    if path.startswith('/v1/'):
     if '/audio/' in path and req.method=='GET':
      ranges.append(req.headers.get('range'))
      if abort_media:abort_media=False;r.abort('connectionfailed');return
     response=call(req.method,path,json.loads(req.post_data) if req.post_data else None,req.all_headers())
     r.fulfill(status=response['status'],headers=response['headers'],body=response['bytes']);return
    file=repo/'web'/path.lstrip('/');assert file.is_relative_to(repo/'web')
    r.fulfill(path=str(file),content_type=mimetypes.guess_type(file)[0] or ('text/javascript' if file.suffix=='.mjs' else 'text/plain'))
   ctx.route('https://dictation.test/**',route)
   page=ctx.new_page();page.on('pageerror',lambda e:errors.append(e.stack))
   page.goto('https://dictation.test/tests/dictation-policy-fixture.html')
   def create(identifier):
    response=call('POST','/v1/learning/dictations',dict(id=identifier,title='Synthetic '+identifier,text='Heute scheint die Sonne. Wir gehen in den Park.',language='de',playback_policy_version=1));assert response['status']==200,response
    page.reload();page.get_by_role('button',name='Synthetic '+identifier+' · In progress',exact=True).click()
   def state(identifier):return json.loads(call('GET','/v1/learning/dictations/'+identifier)['bytes'])
   create('whole');page.get_by_role('button',name='Prepare audio',exact=True).click()
   for n in range(1,5):
    page.get_by_role('button',name='Play',exact=True).click()
    if n==1:
     page.get_by_role('textbox',name='What you heard',exact=True).fill('Words typed while listening')
    page.wait_for_function("events.filter(e=>e.event==='ended').length >= "+str(n))
    page.wait_for_timeout(100);assert state('whole')['playback']['whole_starts']==n
   expect(page.get_by_role('button',name='Play',exact=True)).to_be_disabled()
   assert state('whole')['draft']=='Words typed while listening'
   assert not state('whole')['checked']
   assert not [c for c in page.evaluate('calls') if c['path'].endswith('/check')]
   for locale in ['de','en','ru','es','fr']:
    page.get_by_label('Fixture locale').select_option(locale);page.screenshot(path=str(out/('whole-'+locale+'.png')),full_page=True)
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
   page.get_by_label('Fixture locale').select_option('en')
   first=state('whole')['playback']['listens'][0]
   assert call('POST','/v1/learning/dictations/whole/playback',dict(id=first['id'],client=first['client'],action='start',step=0,fence=0,offset=0))['status']==200
   assert state('whole')['playback']['whole_starts']==4
   assert call('POST','/v1/learning/dictations/whole/playback',dict(id='fifth',client='test',action='start',step=0,fence=0,offset=0))['status']==409
   bridge.kill();bridge.wait();start();assert state('whole')['playback']['whole_starts']==4
   create('resume');page.get_by_role('button',name='Prepare audio',exact=True).click()
   page.evaluate('rejectNextPlay=true');page.get_by_role('button',name='Play',exact=True).click();expect(page.get_by_role('button',name='Continue',exact=True)).to_be_visible();reservation=state('resume')['playback']['active']['id']
   page.get_by_role('button',name='Continue',exact=True).click();page.wait_for_function('fixtureAudio.currentTime>.1');assert state('resume')['playback']['active']['id']==reservation
   # A second controller cannot take over a currently leased reservation.
   tab=ctx.new_page();tab.goto(page.url);tab.get_by_role('button',name='Synthetic resume · In progress',exact=True).click();tab.get_by_role('button',name='Continue',exact=True).click();assert state('resume')['playback']['whole_starts']==1;tab.close()
   page.wait_for_function("events.some(e=>e.event==='ended')")
   assert len([c for c in page.evaluate('calls') if c['path'].endswith('/check')])==0
   create('network');page.get_by_role('button',name='Prepare audio',exact=True).click();abort_media=True;page.get_by_role('button',name='Play',exact=True).click();expect(page.get_by_role('button',name='Continue',exact=True)).to_be_visible();before=state('network')['playback']['active']['id'];page.get_by_role('button',name='Continue',exact=True).click();assert state('network')['playback']['active']['id']==before;page.wait_for_function("events.some(e=>e.event==='ended')");assert state('network')['playback']['whole_starts']==1
   create('paused');page.get_by_role('button',name='Prepare audio',exact=True).click()
   expect(page.get_by_role('button',name='Play',exact=True)).to_be_enabled()
   paid_before=page.evaluate("calls.filter(c=>c.method==='POST'&&c.path.includes('/audio/')).length")
   page.get_by_role('button',name='Play',exact=True).click();page.wait_for_function('fixtureAudio.currentTime>.1')
   paused_id=state('paused')['playback']['active']['id'];page.evaluate('fixtureAudio.pause()')
   paused_time=page.evaluate('fixtureAudio.currentTime');page.wait_for_timeout(200)
   assert page.evaluate('fixtureAudio.currentTime')==paused_time
   expect(page.get_by_role('button',name='Continue',exact=True)).to_be_visible()
   draft=page.get_by_role('textbox',name='What you heard',exact=True);draft.fill('Pause recovery draft')
   page.get_by_role('button',name='Continue',exact=True).click();draft.focus()
   assert state('paused')['playback']['active']['id']==paused_id
   page.wait_for_function("events.some(e=>e.event==='ended')");expect(draft).to_be_focused()
   assert state('paused')['playback']['whole_starts']==1
   page.get_by_role('button',name='History',exact=True).click()
   page.get_by_role('button',name='Synthetic paused · In progress',exact=True).click()
   expect(page.get_by_role('textbox',name='What you heard',exact=True)).to_have_value('Pause recovery draft')
   assert page.evaluate("calls.filter(c=>c.method==='POST'&&c.path.includes('/audio/')).length")==paid_before
   create('sentences');page.get_by_role('button',name='By sentences',exact=True).click();page.get_by_role('button',name='Prepare audio',exact=True).click()
   expect(page.get_by_role('button',name='Play',exact=True)).to_be_enabled()
   prepared=page.evaluate("calls.filter(c=>c.method==='POST'&&c.path.includes('/audio/')).length")
   # Clock controls timers; HTMLMediaElement ends naturally from real silent WAV.
   page.clock.install();page.get_by_role('button',name='Play',exact=True).click()
   for n in range(4):
    page.wait_for_function("events.filter(e=>e.event==='ended').length >= "+str(n+1))
    if n<3:
     expect(page.get_by_role('button',name='Writing pause · 3 seconds',exact=True)).to_be_visible();starts=page.evaluate("events.filter(e=>e.event==='play').length")
     page.clock.run_for(2999);assert page.evaluate("events.filter(e=>e.event==='play').length")==starts
     page.clock.run_for(1)
   expect(page.get_by_role('button',name='Optional final reading',exact=True)).to_be_visible();assert state('sentences')['playback']['whole_starts']==0
   page.get_by_role('button',name='Optional final reading',exact=True).click();page.wait_for_function("events.filter(e=>e.event==='ended').length===5");assert state('sentences')['playback']['whole_starts']==1
   expect(page.get_by_role('button',name='Optional final reading',exact=True)).to_be_disabled()
   assert page.evaluate("calls.filter(c=>c.method==='POST'&&c.path.includes('/audio/')).length")==prepared
   assert not page.evaluate('fixtureAudio.controls');assert not page.get_by_role('button',name='Pause',exact=True).count()
   for locale in ['de','en','ru','es','fr']:
    page.get_by_label('Fixture locale').select_option(locale);page.screenshot(path=str(out/('sentences-'+locale+'.png')),full_page=True)
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
   assert ranges and all(r is not None for r in ranges);assert not errors,errors
   (out/'browser-result.json').write_text(json.dumps(dict(result='PASS',audio='explicitly synthetic silent WAV',ranges=ranges,errors=errors),indent=2));b.close()
 finally:
  bridge.kill();bridge.wait()
