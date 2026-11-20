"""Policy 2: actual Chromium media events + real Go HTTP/state, synthetic WAV only."""
import base64,json,mimetypes,os,subprocess,tempfile
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
repo=Path(__file__).resolve().parents[2]
out=Path(os.environ.get('DICTATION_MANUAL_EVIDENCE',str(repo/'docs/evidence/dictation-manual-pacing')));out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='manual-pacing-',dir=os.environ['TMPDIR']) as tmp:
 env=dict(os.environ,DICTATION_PLAYBACK_BRIDGE=tmp)
 binary=Path(tmp)/'fixture.test'
 subprocess.run(['go','test','-c','-o',str(binary)],cwd=repo/'server',env=env,check=True,capture_output=True)
 bridge=subprocess.Popen([str(binary),'-test.run=^TestDictationPlaybackHTTPBridge$'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
 boot=bridge.stdout.readline();assert boot.startswith('PLAYBACK_BOOT '),boot
 identity=json.loads(boot.removeprefix('PLAYBACK_BOOT '))
 def call(method,path,body=None,headers=None):
  bridge.stdin.write(json.dumps(dict(method=method,path=path,body=json.dumps(body) if body is not None else '',headers=headers or {'Authorization':'Bearer '+identity['token']}))+'\n');bridge.stdin.flush()
  result=json.loads(bridge.stdout.readline());result['bytes']=base64.b64decode(result['body'] or '');return result
 def state(identifier='manual'):return json.loads(call('GET','/v1/learning/dictations/'+identifier)['bytes'])
 errors=[];ranges=[];dropped=[];drop_stop=False
 try:
  with sync_playwright() as pw:
   browser=pw.chromium.launch();ctx=browser.new_context(viewport={'width':390,'height':844})
   ctx.add_cookies([dict(name='__Host-km-session',value=identity['browser'],url='https://dictation.test',secure=True,httpOnly=True,sameSite='Strict')])
   def route(r):
    global drop_stop
    req=r.request;path=urlparse(req.url).path
    if path=='/__fixture_session':r.fulfill(content_type='application/json',body=json.dumps(dict(user=dict(id=identity['owner']),csrf_token=identity['csrf_token'])));return
    if path.startswith('/v1/'):
     body=json.loads(req.post_data) if req.post_data else None
     if '/audio/' in path and req.method=='GET':ranges.append(req.headers.get('range'))
     response=call(req.method,path,body,req.all_headers())
     if drop_stop and body and body.get('action')=='stop':
      drop_stop=False;dropped.append(body);r.abort('connectionfailed');return
     r.fulfill(status=response['status'],headers=response['headers'],body=response['bytes']);return
    file=repo/'web'/path.lstrip('/');assert file.is_relative_to(repo/'web')
    r.fulfill(path=str(file),content_type=mimetypes.guess_type(file)[0] or ('text/javascript' if file.suffix=='.mjs' else 'text/plain'))
   ctx.route('https://dictation.test/**',route);page=ctx.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
   assert call('POST','/v1/learning/dictations',dict(id='manual',title='Manual pacing fixture',text='Heute bleiben wir zu Hause, weil es draußen sehr stark regnet. Morgen gehen wir spazieren.',language='de',playback_policy_version=2))['status']==200
   page.goto('https://dictation.test/tests/dictation-policy-fixture.html');page.get_by_role('button',name='Manual pacing fixture').click()
   assert state()['mode']=='sentences';assert state()['playback']['cursor']==0
   assert not page.evaluate('calls.some(c=>c.method==="POST")')
   page.get_by_label('Longer gaps (8 s)').check();expect(page.get_by_label('Longer gaps (8 s)')).to_be_checked()
   page.wait_for_function('calls.some(c=>c.path.endsWith("/pacing"))');page.wait_for_timeout(200);assert state()['pacing']=={'repeats':2,'gap_seconds':8}
   page.screenshot(path=str(out/'setup-390-en.png'),full_page=True)
   page.get_by_role('button',name='Prepare audio',exact=True).click();expect(page.get_by_role('button',name='Play',exact=True)).to_be_enabled()
   paid=page.evaluate('calls.filter(c=>c.method==="POST"&&c.path.includes("/audio/")).length')
   page.get_by_role('button',name='Play',exact=True).click();expect(page.get_by_role('button',name='Stop',exact=True)).to_be_visible()
   draft=page.locator('.dictation-work textarea');draft.fill('Mein unveränderter Entwurf.');draft.focus()
   page.wait_for_function('events.filter(e=>e.event==="ended").length===1');expect(page.get_by_role('button',name='Next',exact=True)).to_be_enabled()
   assert state()['playback']['cursor']==1;assert state()['playback']['whole_starts']==1
   page.wait_for_timeout(3500);assert page.evaluate('events.filter(e=>e.event==="play").length')==1
   page.get_by_role('button',name='Next',exact=True).dblclick()
   page.wait_for_function('events.filter(e=>e.event==="play").length===2')
   playing_slot=page.get_by_role('button',name='Stop',exact=True).bounding_box()
   page.wait_for_function('events.filter(e=>e.event==="ended").length===2')
   expect(page.locator('.dictation-now')).to_contain_text('Gap before repeat · 8 s')
   page.screenshot(path=str(out/'gap-390-en.png'),full_page=True)
   page.wait_for_timeout(3000);assert page.evaluate('events.filter(e=>e.event==="play").length')==2
   page.wait_for_function('events.filter(e=>e.event==="ended").length===3',timeout=15000)
   expect(page.get_by_role('button',name='Next',exact=True)).to_be_enabled()
   played=page.evaluate('events.filter(e=>e.event==="play").map(e=>e.src)');assert played[1]==played[2]
   assert state()['playback']['cursor']==3
   next_slot=page.get_by_role('button',name='Next',exact=True).bounding_box()
   assert all(abs(playing_slot[k]-next_slot[k])<1 for k in ['x','y','width','height']),(playing_slot,next_slot)
   page.wait_for_timeout(3500);assert page.evaluate('events.filter(e=>e.event==="play").length')==3
   assert page.locator('.dictation-timeline .is-complete').count()==2
   page.get_by_role('button',name='Replay fragment once',exact=True).click()
   page.wait_for_function('events.filter(e=>e.event==="ended").length===4')
   expect(page.get_by_role('button',name='Next',exact=True)).to_be_enabled()
   assert state()['playback']['cursor']==3
   assert state()['playback']['listens'][-1]['intent']=='extra'
   assert state()['playback']['listens'][-1]['ended'] is True
   assert state()['playback']['whole_starts']==1
   page.wait_for_timeout(3500);assert page.evaluate('events.filter(e=>e.event==="play").length')==4
   captures=['setup-390-en.png','gap-390-en.png']
   for width in [390,1100]:
    page.set_viewport_size({'width':width,'height':900})
    for locale in ['de','en','ru','es','fr']:
     page.get_by_label('Fixture locale').select_option(locale)
     assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
     slot=page.locator('.dictation-player > button').first.bounding_box();assert slot['height']>=44 and slot['width']>=150
     expect(draft).to_have_value('Mein unveränderter Entwurf.')
     path=out/f'next-{width}-{locale}.png';page.screenshot(path=str(path),full_page=True);captures.append(path.name)
   page.get_by_label('Fixture locale').select_option('en');page.reload();page.get_by_role('button',name='Manual pacing fixture').click()
   expect(page.get_by_role('button',name='Next',exact=True)).to_be_enabled();expect(draft).to_have_value('Mein unveränderter Entwurf.')
   page.get_by_role('button',name='Next',exact=True).click();page.wait_for_function('fixtureAudio.currentTime>.1')
   drop_stop=True;page.get_by_role('button',name='Stop',exact=True).click();expect(page.get_by_role('button',name='Confirm Stop',exact=True)).to_be_enabled()
   assert state()['playback']['cursor']==0;assert state()['playback']['whole_starts']==1;assert not state()['playback'].get('active')
   page.reload();page.get_by_role('button',name='Manual pacing fixture').click();expect(page.get_by_role('button',name='Confirm Stop',exact=True)).to_be_enabled()
   page.get_by_role('button',name='Confirm Stop',exact=True).click();expect(page.get_by_role('button',name='Play',exact=True)).to_be_enabled()
   retries=page.evaluate('calls.filter(c=>c.body?.action==="stop").map(c=>c.body)');assert retries==dropped
   expect(draft).to_have_value('Mein unveränderter Entwurf.')
   assert not state()['checked'];assert state()['playback']['whole_starts']==1
   assert not page.evaluate('calls.some(c=>c.path.endsWith("/check")||c.method==="POST"&&c.path.includes("/audio/"))')
   # Integrated actual policy-2 replay ledger -> immutable assessment snapshot.
   page.get_by_role('button',name='Check',exact=True).click()
   expect(page.locator('.dictation-assessment')).to_be_visible()
   assessment=state()['assessment'];summary=assessment['assistance_summary']
   assert summary['tracking']=='partial' and summary['unreported']=='unknown'
   fragment=next(s for s in summary['segments'] if s['step']==1)
   assert fragment['planned_started']==2 and fragment['extra_requested']==1 and fragment['completed']==3,fragment
   checks=page.evaluate('calls.filter(c=>c.path.endsWith("/check")).length')
   page.reload();page.get_by_role('button',name='Manual pacing fixture').click()
   expect(page.locator('.dictation-assessment')).to_be_visible()
   assert not page.evaluate('calls.some(c=>c.path.endsWith("/check"))')
   assert state()['assessment']==assessment
   page.screenshot(path=str(out/'integrated-assistance-390-en.png'),full_page=True)
   assert call('POST','/v1/learning/dictations',dict(id='triples',title='Three-repeat fixture',text='Hallo Welt.',language='de',playback_policy_version=2))['status']==200
   page.reload();page.get_by_role('button',name='Three-repeat fixture').click()
   page.get_by_label('Plays per fragment').select_option('3');page.wait_for_timeout(250);assert state('triples')['pacing']['repeats']==3
   page.get_by_role('button',name='Prepare audio',exact=True).click();expect(page.get_by_role('button',name='Play',exact=True)).to_be_enabled()
   page.get_by_role('button',name='Play',exact=True).click();page.wait_for_function('events.filter(e=>e.event==="ended").length===1')
   expect(page.get_by_role('button',name='Next',exact=True)).to_be_enabled();page.get_by_role('button',name='Next',exact=True).click()
   page.wait_for_function('events.filter(e=>e.event==="ended").length===4',timeout=20000)
   expect(page.get_by_role('button',name='Optional final reading',exact=True)).to_be_enabled()
   page.wait_for_timeout(3500);assert page.evaluate('events.filter(e=>e.event==="play").length')==4
   assert state('triples')['playback']['whole_starts']==1
   page.get_by_role('button',name='Optional final reading',exact=True).click();page.wait_for_function('events.filter(e=>e.event==="ended").length===5')
   expect(page.get_by_role('button',name='Optional final reading',exact=True)).to_be_disabled();assert state('triples')['playback']['whole_starts']==2
   assert state('triples')['playback']['final_used'] is True
   assert ranges and all(ranges);assert not errors,errors
   (out/'browser-result.json').write_text(json.dumps(dict(result='PASS',audio='synthetic silent WAV; natural play/ended',captures=captures,initial_prepared_assets=paid,repeat_counts_verified=[2,3],primary_slot_verified=True,ranges=ranges,lost_stop_ack_recovered=True,errors=errors),indent=2));browser.close()
 finally:
  bridge.kill();bridge.wait()
