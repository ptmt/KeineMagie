"""Real mounted UI + real Go handlers + synthetic media; no provider calls."""
import base64,json,mimetypes,os,subprocess,tempfile
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
repo=Path(__file__).resolve().parents[2]
out=Path(os.environ.get('OPTIONS_EVIDENCE',str(repo/'docs/evidence/dictation-options')));out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='options-',dir=os.environ['TMPDIR']) as tmp:
 env=dict(os.environ,DICTATION_PLAYBACK_BRIDGE=tmp)
 binary=Path(tmp)/'fixture.test'
 subprocess.run(['go','test','-c','-o',str(binary)],cwd=repo/'server',env=env,check=True,capture_output=True)
 bridge=subprocess.Popen([str(binary),'-test.run=^TestDictationPlaybackHTTPBridge$'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
 boot=bridge.stdout.readline();assert boot.startswith('PLAYBACK_BOOT '),boot
 identity=json.loads(boot.removeprefix('PLAYBACK_BOOT '))
 def call(method,path,body=None,headers=None):
  bridge.stdin.write(json.dumps(dict(method=method,path=path,body=json.dumps(body) if body is not None else '',headers=headers or {'Authorization':'Bearer '+identity['token']}))+'\n');bridge.stdin.flush()
  result=json.loads(bridge.stdout.readline());result['bytes']=base64.b64decode(result['body'] or '');return result
 def state():return json.loads(call('GET','/v1/learning/dictations/options')['bytes'])
 errors=[]
 try:
  with sync_playwright() as pw:
   browser=getattr(pw,os.environ.get('BROWSER','chromium')).launch();ctx=browser.new_context(viewport={'width':1100,'height':900})
   ctx.add_cookies([dict(name='__Host-km-session',value=identity['browser'],url='https://dictation.test',secure=True,httpOnly=True,sameSite='Strict')])
   def route(r):
    req=r.request;path=urlparse(req.url).path
    if path=='/__fixture_session':r.fulfill(content_type='application/json',body=json.dumps(dict(user=dict(id=identity['owner']),csrf_token=identity['csrf_token'])));return
    if path.startswith('/v1/'):
     response=call(req.method,path,json.loads(req.post_data) if req.post_data else None,req.all_headers())
     r.fulfill(status=response['status'],headers=response['headers'],body=response['bytes']);return
    file=repo/'web'/path.lstrip('/');assert file.is_relative_to(repo/'web')
    r.fulfill(path=str(file),content_type=mimetypes.guess_type(file)[0] or ('text/javascript' if file.suffix=='.mjs' else 'text/plain'))
   ctx.route('https://dictation.test/**',route);page=ctx.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
   assert call('POST','/v1/learning/dictations',dict(id='options',title='Options fixture',text='Hallo Welt. Morgen gehen wir spazieren.',language='de',playback_policy_version=2))['status']==200
   page.goto('https://dictation.test/tests/dictation-policy-fixture.html');page.get_by_role('button',name='Options fixture').click()
   draft=page.locator('.dictation-work textarea');draft.fill('Mein Entwurf.');draft.evaluate('(e)=>e.setSelectionRange(3,7)')
   page.get_by_role('button',name='Prepare audio',exact=True).click();expect(page.get_by_role('button',name='Play',exact=True)).to_be_enabled()
   page.get_by_role('button',name='Play',exact=True).click();page.wait_for_function('fixtureAudio.currentTime>.05')
   page.get_by_label('More options').click()
   page.screenshot(path=str(out/'playing-options.png'),full_page=True)
   page.get_by_label('Playback speed').select_option('0.75')
   # Exact reported failure: changing speed bubbles change to details and closes it.
   visible=page.get_by_label('Playback speed').is_visible()
   (out/'speed-result.json').write_text(json.dumps({'visible_after_speed':visible,'events':page.evaluate('events'),'calls':page.evaluate('calls')}))
   assert visible,'Options disappeared after changing playback speed during real playback'
   page.wait_for_function('events.some(e=>e.event==="ended")')
   expect(page.get_by_label('Playback speed')).to_be_visible()
   browser.close()
 finally:
  bridge.kill();bridge.wait()
