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
     headers=req.all_headers()
     # WebKit routed __Host cookie omission: synthetic bearer bridge only.
     if os.environ.get('BROWSER')=='webkit':
      headers={'Authorization':'Bearer '+identity['token'],'Content-Type':'application/json'}
      if req.headers.get('range'):headers['Range']=req.headers['range']
     response=call(req.method,path,json.loads(req.post_data) if req.post_data else None,headers)
     r.fulfill(status=response['status'],headers=response['headers'],body=response['bytes']);return
    file=repo/'web'/path.lstrip('/');assert file.is_relative_to(repo/'web')
    r.fulfill(path=str(file),content_type=mimetypes.guess_type(file)[0] or ('text/javascript' if file.suffix=='.mjs' else 'text/plain'))
   ctx.route('https://dictation.test/**',route);page=ctx.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
   assert call('POST','/v1/learning/dictations',dict(id='options',title='Options fixture',text='Hallo Welt. Morgen gehen wir spazieren.',language='de',playback_policy_version=2))['status']==200
   page.goto('https://dictation.test/tests/dictation-policy-fixture.html');page.get_by_role('button',name='Options fixture').click()
   page.get_by_role('button',name='More options',exact=True).click()
   expect(page.get_by_label('Plays per fragment')).to_have_value('3')
   with page.expect_response(lambda r:r.url.endswith('/pacing') and r.request.method=='POST'):
    page.get_by_label('Plays per fragment').select_option('2')
   expect(page.get_by_label('Plays per fragment')).to_be_enabled()
   with page.expect_response(lambda r:r.url.endswith('/pacing') and r.request.method=='POST'):
    page.get_by_label('Longer gaps (8 s)').check()
   expect(page.get_by_label('Plays per fragment')).to_be_enabled()
   assert state()['pacing']=={'repeats':2,'gap_seconds':8}
   page.get_by_role('button',name='Close',exact=True).click()
   page.reload();page.get_by_role('button',name='Options fixture').click()
   page.get_by_role('button',name='More options',exact=True).click()
   expect(page.get_by_label('Plays per fragment')).to_have_value('2');expect(page.get_by_label('Longer gaps (8 s)')).to_be_checked()
   page.get_by_role('button',name='Close',exact=True).click()
   draft=page.locator('.dictation-work textarea');draft.fill('Mein Entwurf.');draft.evaluate('(e)=>e.setSelectionRange(3,7)')
   page.get_by_role('button',name='Prepare audio',exact=True).click();expect(page.get_by_role('button',name='Play',exact=True)).to_be_enabled()
   page.get_by_role('button',name='Play',exact=True).click();page.wait_for_function('fixtureAudio.currentTime>.05')
   page.get_by_role('button',name='More options',exact=True).click()
   page.locator('dialog[open]').evaluate('(e)=>Promise.all(e.getAnimations().map(a=>a.finished))')
   page.screenshot(path=str(out/'playing-options.png'),full_page=True)
   modal=page.locator('.dictation-options');expect(modal).to_be_visible()
   modal.evaluate('(e)=>e.dataset.identity="persistent"')
   opening_calls=len(page.evaluate('calls'))
   page.mouse.click(2,2);expect(modal).to_be_visible()
   assert len(page.evaluate('calls'))==opening_calls,'Opening/outside click issued requests'
   page.get_by_label('Playback speed').select_option('0.75')
   # Exact reported failure: changing speed bubbles change to details and closes it.
   visible=page.get_by_label('Playback speed').is_visible()
   (out/'speed-result.json').write_text(json.dumps({'visible_after_speed':visible,'events':page.evaluate('events'),'calls':page.evaluate('calls')}))
   assert visible,'Options disappeared after changing playback speed during real playback'
   page.wait_for_function('events.some(e=>e.event==="ended")')
   expect(page.get_by_label('Playback speed')).to_be_visible()
   assert modal.get_attribute('data-identity')=='persistent'
   assert page.evaluate('fixtureAudio.playbackRate')==0.75
   expect(draft).to_have_value('Mein Entwurf.')
   for locale in ['de','ru','es','fr','en']:
    page.locator('[aria-label="Fixture locale"]').evaluate('(e,v)=>{e.value=v;e.dispatchEvent(new Event("change"))}',locale)
    expect(modal).to_be_visible();assert modal.get_attribute('data-identity')=='persistent'
    for width in [390,1100]:
     page.set_viewport_size({'width':width,'height':900})
     for theme in ['light','dark']:
      page.emulate_media(color_scheme=theme)
      modal.evaluate('(e)=>{e.scrollTop=0}')
      box=modal.bounding_box();assert box['x']>=0 and box['x']+box['width']<=width and box['height']<=900
      if theme=='dark':
       colors=modal.evaluate('(e)=>[getComputedStyle(e).backgroundColor,getComputedStyle(e.querySelector(".dictation-disclosure")).color]')
       def luminance(color):
        import re
        rgb=[int(n)/255 for n in re.findall(r'\d+',color)[:3]]
        c=[v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in rgb]
        return sum(v*w for v,w in zip(c,[0.2126,0.7152,0.0722]))
       a,b=sorted(map(luminance,colors));assert (b+.05)/(a+.05)>=4.5,colors
      page.screenshot(path=str(out/f'{locale}-{width}-{theme}.png'))
   page.get_by_role('button',name='Close',exact=True).focus()
   for _ in range(18):
    page.keyboard.press('Tab');assert modal.evaluate('(e)=>e.contains(document.activeElement)'),'Focus escaped modal'
   before_cancel=len(page.evaluate('calls'))
   page.once('dialog',lambda d:d.dismiss());page.get_by_role('button',name='Show original',exact=True).click()
   page.once('dialog',lambda d:d.dismiss());page.get_by_role('button',name='Delete attempt',exact=True).click()
   assert len(page.evaluate('calls'))==before_cancel,'Canceled confirmation mutated server'
   page.keyboard.press('Escape');expect(modal).not_to_be_visible()
   expect(page.get_by_role('button',name='More options',exact=True)).to_be_focused()
   page.get_by_role('button',name='More options',exact=True).click()
   page.get_by_role('button',name='Close',exact=True).click();expect(modal).not_to_be_visible()
   expect(draft).to_have_value('Mein Entwurf.')
   assert not errors,errors
   (out/'verified.json').write_text(json.dumps({'browser':os.environ.get('BROWSER','chromium'),'media_ended':True,'persistent_dialog':True,'locales':5,'widths':[390,1100],'themes':['light','dark'],'keyboard':True,'cancel_confirmations':True,'errors':errors}))
   browser.close()
 finally:
  bridge.kill();bridge.wait()
