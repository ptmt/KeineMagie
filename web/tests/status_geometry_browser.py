"""Actual Chromium geometry with held synthetic APIs; no credentials/inference."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
import json, os, sys
from playwright.sync_api import sync_playwright, expect  # pyright: ignore[reportMissingImports]
ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get('KM_GEOMETRY_EVIDENCE', str(Path.home()/'.hermes/cache/scratch/km-geometry-evidence')))
OUT.mkdir(parents=True, exist_ok=True)
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs): super().__init__(*args,directory=str(ROOT),**kwargs)
    def log_message(self,format,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
checks=[]; samples=[]
def check(name, value):
    assert value,name
    checks.append(name)
def boxes(page, selectors):
    return page.evaluate('(ss)=>ss.map(s=>{const r=document.querySelector(s).getBoundingClientRect();return [r.x,r.y,r.width,r.height]})',selectors)
def wait(page, routes):
    for _ in range(100):
        if routes:return
        page.wait_for_timeout(20)
    raise AssertionError('Expected held API')
def fixture(page,guest=False):
    state={'guest':guest,'hold_session':not guest,'sessions':[],'providers':[],'starts':[],'owner':'synthetic-owner','session_status':200,'posts':0}
    def session(route):
        route.fulfill(status=401 if state['guest'] else state['session_status'],json={'user':{'id':state['owner']},'csrf_token':'synthetic-session'})
    def api(route):
        path=route.request.url.split(origin)[-1]
        if path=='/v1/web/session':
            if state['hold_session']:state['sessions'].append(route)
            else:session(route)
        elif path=='/v1/web/config':route.fulfill(json={'apple_available':True,'pairing_available':True,'csrf_token':'synthetic-bootstrap'})
        elif path=='/v1/provider':state['providers'].append(route)
        elif path=='/v1/auth/apple/start':state['starts'].append(route)
        elif path=='/v1/translations' and route.request.method=='POST':
            assert route.request.headers.get('x-csrf-token')=='synthetic-session'
            state['posts']+=1;route.fulfill(status=503,json={})
        else:route.fulfill(json={'items':[]})
    page.route('**/v1/**',api)
    def release_session():
        state['hold_session']=False
        for route in state['sessions']:session(route)
        state['sessions'].clear()
    return state,release_session
case=sys.argv[1] if len(sys.argv)>1 else 'all'
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  for locale in ['de','en','ru','es','fr']:
   for width,scale in [(320,1),(390,1),(1440,1),(320,1.5)]:
    context=browser.new_context(viewport={'width':width,'height':1000},locale='en-US',reduced_motion='reduce')
    context.add_init_script(f"localStorage.setItem('keinemagie:interface-language:v1','{locale}')")
    page=context.new_page()
    label=f'{locale}/{width}/{scale}'
    if case in ('apple','all'):
     state,release=fixture(page,True);page.goto(origin)
     page.locator('#account').click();expect(page.locator('#apple-login')).to_be_enabled()
     if scale!=1:page.evaluate('(rule)=>document.styleSheets[0].insertRule(rule,document.styleSheets[0].cssRules.length)',f'button, #apple-login-progress {{font-size:{13*scale}px}}')
     page.wait_for_timeout(200)
     selectors=['#account-dialog','#apple-login','#pair-browser','#close-account']
     before=boxes(page,selectors)
     page.locator('#apple-login').focus();page.keyboard.press('Enter');wait(page,state['starts'])
     during=boxes(page,selectors)
     samples.append({'case':label+'/apple','before':before,'during':during})
     page.screenshot(path=str(OUT/f'{locale}-{width}-{scale}-apple-pending.png'))
     (OUT/'geometry.json').write_text(json.dumps(samples,indent=2))
     check(label+' Apple pending keeps dialog/button rectangles',before==during)
     check(label+' pending accessible',page.locator('#apple-login').get_attribute('aria-busy')=='true' and page.locator('#apple-login-progress').get_attribute('role')=='status' and bool(page.locator('#apple-login-progress-label').text_content()))
     check(label+' reduced motion',page.locator('.signin-spinner').evaluate('(e)=>getComputedStyle(e).animationName')=='none')
     page.keyboard.press('Escape');state['starts'].pop().fulfill(status=503,json={})
     page.locator('#account').click();page.wait_for_timeout(200)
     check(label+' cancel restores geometry',before==boxes(page,selectors))
     page.close();page=context.new_page()
    if case in ('translator','all'):
     state,release=fixture(page);page.goto(origin);wait(page,state['sessions'])
     if scale!=1:page.evaluate('(rule)=>document.styleSheets[0].insertRule(rule,document.styleSheets[0].cssRules.length)',f'#connection-notice, button, #source-text {{font-size:{18*scale}px}}')
     selectors=['.language-bar','#source-text','.translation-panels','#translate']
     before=boxes(page,selectors);release();wait(page,state['providers'])
     during=boxes(page,selectors)
     samples.append({'case':label+'/translator','before':before,'during':during})
     (OUT/'geometry.json').write_text(json.dumps(samples,indent=2))
     check(label+' identity/provider pending stable form',before==during)
     page.locator('#source-text').fill('Synthetic draft сохранён');page.locator('#source-text').evaluate('(e)=>{e.focus();e.setSelectionRange(2,9)}')
     check(label+' held catalog does not block translation',page.locator('#translate').is_enabled())
     # Submit without moving focus; this is an intercepted synthetic 503, not inference.
     page.locator('#translation-form').evaluate('(e)=>e.requestSubmit()')
     expect(page.locator('#translate')).to_be_enabled();check(label+' POST sent while catalog held',state['posts']==1)
     page.locator('#source-text').evaluate('(e)=>{e.focus();e.setSelectionRange(2,9)}')
     state['providers'].pop().fulfill(json={'connected':True,'status':'connected'})
     page.wait_for_timeout(100)
     check(label+' connected stable form',before==boxes(page,selectors))
     for result in ['connected','disconnected','network','session-error']:
      state['hold_session']=True;page.locator('#retry-session').evaluate('(e)=>e.click()');wait(page,state['sessions'])
      check(label+'/'+result+' refresh stable',before==boxes(page,selectors))
      if result=='session-error':state['session_status']=503
      release()
      if result!='session-error':
       wait(page,state['providers']);route=state['providers'].pop()
       if result=='network':route.abort('failed')
       else:route.fulfill(json={'connected':result=='connected','status':result})
      page.wait_for_timeout(100)
      check(label+'/'+result+' settled stable',before==boxes(page,selectors))
      check(label+'/'+result+' selection retained',page.locator('#source-text').evaluate('(e)=>document.activeElement===e && e.selectionStart===2 && e.selectionEnd===9 && e.value==="Synthetic draft сохранён"'))
      check(label+'/'+result+' advisory allows attempt',page.locator('#translate').is_enabled())
     page.screenshot(path=str(OUT/f'{locale}-{width}-{scale}-translator-error.png'))
     check(label+' no overflow',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
     state['session_status']=200;state['owner']='synthetic-other-owner';page.locator('#retry-session').evaluate('(e)=>e.click()');expect(page.locator('#source-text')).to_have_value('')
     check(label+' owner change clears draft',page.locator('#source-text').input_value()=='')
    context.close()
  browser.close()
 print(json.dumps({'synthetic_only':True,'checks_passed':len(checks),'checks':checks}))
finally:server.shutdown()
