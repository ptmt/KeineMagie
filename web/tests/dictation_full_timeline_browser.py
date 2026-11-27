"""Full real-app timeline with real Go ledger and synthetic WAV, no providers."""
import base64,json,mimetypes,os,subprocess,tempfile
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
repo=Path(__file__).resolve().parents[2]
out=Path(os.environ.get('DICTATION_FULL_EVIDENCE',str(repo/'docs/evidence/dictation-full-timeline')));out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='full-timeline-',dir=os.environ['TMPDIR']) as tmp:
 env=dict(os.environ,DICTATION_PLAYBACK_BRIDGE=tmp)
 binary=Path(tmp)/'fixture.test'
 subprocess.run(['go','test','-c','-o',str(binary)],cwd=repo/'server',env=env,check=True,capture_output=True)
 bridge=subprocess.Popen([str(binary),'-test.run=^TestDictationPlaybackHTTPBridge$'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
 boot=bridge.stdout.readline();assert boot.startswith('PLAYBACK_BOOT '),boot
 identity=json.loads(boot.removeprefix('PLAYBACK_BOOT '))
 def call(method,path,body=None,headers=None):
  bridge.stdin.write(json.dumps(dict(method=method,path=path,body=json.dumps(body) if body is not None else '',headers=headers or {'Authorization':'Bearer '+identity['token']}))+'\n');bridge.stdin.flush()
  result=json.loads(bridge.stdout.readline());result['bytes']=base64.b64decode(result['body'] or '');return result
 def state(identifier):return json.loads(call('GET','/v1/learning/dictations/'+identifier)['bytes'])
 captures=[];results=[]
 try:
  with sync_playwright() as pw:
   for engine in os.environ.get('TIMELINE_ENGINES','chromium,webkit').split(','):
    browser=getattr(pw,engine).launch();ctx=browser.new_context(viewport={'width':390,'height':844})
    ctx.add_cookies([dict(name='__Host-km-session',value=identity['browser'],url='https://dictation.test',secure=True,httpOnly=True,sameSite='Strict')])
    def route(r):
     req=r.request;path=urlparse(req.url).path
     if path=='/__fixture_session':r.fulfill(content_type='application/json',body=json.dumps(dict(user=dict(id=identity['owner']),csrf_token=identity['csrf_token'])));return
     if path.startswith('/v1/'):
      headers={'Authorization':'Bearer '+identity['token'],'Content-Type':'application/json'} # synthetic bridge bearer; not a browser-auth acceptance test
      if req.headers.get('range'): headers['Range']=req.headers['range']
      response=call(req.method,path,json.loads(req.post_data) if req.post_data else None,headers)
      r.fulfill(status=response['status'],headers=response['headers'],body=response['bytes']);return
     file=repo/'web'/path.lstrip('/');assert file.is_relative_to(repo/'web')
     r.fulfill(path=str(file),content_type=mimetypes.guess_type(file)[0] or ('text/javascript' if file.suffix=='.mjs' else 'text/plain'))
    ctx.route('https://dictation.test/**',route);page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
    identifier='full-'+engine
    text='Heute bleiben wir zu Hause, weil es draußen sehr stark regnet. Morgen gehen wir spazieren. Danach besuchen wir unsere Freunde. Am Abend lesen wir ein Buch. Später trinken wir Tee. Zum Schluss gehen wir schlafen.'
    assert call('POST','/v1/learning/dictations',dict(id=identifier,title=identifier,text=text,language='de',playback_policy_version=2))['status']==200
    page.goto('https://dictation.test/tests/dictation-policy-fixture.html')
    try: page.get_by_role('button',name=identifier).click(timeout=10000)
    except Exception:
     print(engine,errors,page.locator('body').inner_text(),page.evaluate('window.calls'));raise
    plan=state(identifier)['plan'];anchors=[i for i,p in enumerate(plan) if p['kind']!='sentence_repeat']
    def assert_full():
     rows=page.locator('.dictation-timeline li:not(.dictation-sentence)')
     expect(rows).to_have_count(len(anchors))
     assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
     assert page.locator('.dictation-timeline').evaluate('(e)=>e.scrollHeight<=e.clientHeight+1')
     return rows
    assert_full() # RED: old current/next slice omits later sentences.
    assert not page.evaluate('calls.some(c=>c.method==="POST")')
    page.get_by_role('button',name='Prepare audio',exact=True).click();expect(page.get_by_role('button',name='Play',exact=True)).to_be_enabled()
    page.evaluate('window.savedRows=Array.from(document.querySelectorAll(".dictation-timeline li"))')
    page.get_by_role('button',name='Play',exact=True).click()
    page.wait_for_function('events.filter(e=>e.event==="ended").length===1')
    expect(page.get_by_role('button',name='Next',exact=True)).to_be_enabled()
    # Stable row identity across admission, ended, and writing states.
    assert page.evaluate('savedRows.every((e,i)=>e===document.querySelectorAll(".dictation-timeline li")[i])')
    assert_full()
    # Reach a middle fragment using only the real manual Next and natural ended.
    for _ in range(3):
     before=page.evaluate('events.filter(e=>e.event==="ended").length')
     page.get_by_role('button',name='Next',exact=True).click()
     page.wait_for_function('(n)=>events.filter(e=>e.event==="ended").length===n',arg=before+2,timeout=20000)
     expect(page.get_by_role('button',name='Next',exact=True)).to_be_enabled();assert_full()
    before_play=page.evaluate('events.filter(e=>e.event==="play").length')
    page.get_by_role('button',name='Next',exact=True).click()
    page.wait_for_function('(n)=>events.filter(e=>e.event==="play").length===n',arg=before_play+1)
    page.wait_for_function('fixtureAudio.currentTime>0.05')
    assert_full()
    for width in [390,1100]:
     page.set_viewport_size({'width':width,'height':900})
     for theme in ['light','dark']:
      page.emulate_media(color_scheme=theme);page.wait_for_timeout(350)
      file=out/f'{engine}-midway-{width}-{theme}.png';page.screenshot(path=str(file),full_page=True);captures.append(file.name)
    # Waiting for writing does not advance or check automatically.
    expect(page.get_by_role('button',name='Next',exact=True)).to_be_enabled(timeout=20000)
    assert_full();ledger=state(identifier)['playback'];done=sum(all(any(x.get('ended') and not x.get('stopped') and x.get('intent')=='planned' and x['step']==s for x in ledger['listens']) for s in range(a,anchors[j+1] if j+1<len(anchors) else len(plan))) for j,a in enumerate(anchors))
    assert page.locator('.dictation-timeline .is-complete').count()==done
    draft=page.locator('.dictation-work textarea');draft.fill('Mein unveränderter Entwurf.');draft.focus();draft.evaluate('(e)=>e.setSelectionRange(3,8)');page.wait_for_timeout(700)
    saved=page.evaluate('scrollY');draft.press('ArrowRight')
    assert page.evaluate('savedRows.every((e,i)=>e===document.querySelectorAll(".dictation-timeline li")[i])')
    assert page.evaluate('document.activeElement.tagName')=='TEXTAREA'
    assert not state(identifier)['checked']
    page.reload();page.get_by_role('button',name=identifier).click();assert_full();expect(draft).to_have_value('Mein unveränderter Entwurf.')
    assert page.locator('.dictation-timeline .is-complete').count()==done
    assert not page.evaluate('calls.some(c=>c.method==="POST")')
    assert not errors,errors
    results.append(dict(engine=engine,phases=len(anchors),completed=done,stable_rows=True,restored=True,errors=errors));browser.close()
  (out/'result.json').write_text(json.dumps(dict(result='PASS',boundary='local real web modules + Go ledger + synthetic WAV; no paid provider',captures=captures,results=results),indent=2))
 finally:
  bridge.kill();bridge.wait()
