"""Real first-frame pending feedback against synthetic held HTTP only."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
import json
from playwright.sync_api import sync_playwright, expect  # pyright: ignore[reportMissingImports]
ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT.parent/'artifacts/translate-feedback-web'
EVIDENCE.mkdir(parents=True, exist_ok=True)
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw): super().__init__(*a,directory=str(ROOT),**kw)
 def log_message(self,format,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
item={'id':'synthetic','text':'Привет','translation':'Hallo 👩🏽‍💻\n<&> vollständiger Text','source_language':'ru','target_language':'de','idioms':[],'patterns':[],'vocabulary':[]}
checks=[]
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  for locale in ['en','de','ru','es','fr']:
   for mobile in [False,True]:
    context=browser.new_context(viewport={'width':390 if mobile else 1280,'height':844},color_scheme='dark' if mobile else 'light',reduced_motion='reduce' if mobile else 'no-preference')
    context.add_init_script(f"localStorage.setItem('keinemagie:interface-language:v1','{locale}')")
    page=context.new_page();held=[];posts=[]
    def api(route):
     path=route.request.url.split(origin)[-1]
     if path=='/v1/web/session': route.fulfill(json={'user':{'id':'synthetic-owner'},'csrf_token':'synthetic'})
     elif path=='/v1/web/config': route.fulfill(json={'apple_available':True})
     elif path=='/v1/provider': route.fulfill(json={'connected':True,'status':'connected','selected_model':'synthetic'})
     elif path=='/v1/translations' and route.request.method=='POST': posts.append(route.request);held.append(route)
     else: route.fulfill(json={'items':[]})
    page.route('**/v1/**',api);page.goto(origin)
    source=page.locator('#source-text');expect(source).to_be_enabled();source.fill('Привет')
    page.evaluate("""() => {window.framesSeen=[];document.querySelector('#translation-form').addEventListener('submit',()=>requestAnimationFrame(()=>{const b=document.querySelector('#translate');framesSeen.push({disabled:b.disabled,busy:document.querySelector('#result').getAttribute('aria-busy'),pending:document.querySelector('#translation-form').classList.contains('translation-pending')})}));}""")
    before=page.locator('#history').bounding_box();button_before=page.locator('#translate').bounding_box()
    page.locator('#translate').click();page.wait_for_function('() => framesSeen.length > 0')
    frame=page.evaluate('framesSeen[0]')
    assert frame=={'disabled':True,'busy':'true','pending':True},frame
    expect(page.locator('#result-skeleton')).to_be_visible()
    animation=page.locator('.output-panel').evaluate("el=>getComputedStyle(el,'::after').animationName")
    assert (animation=='none')==mobile,animation
    button_after=page.locator('#translate').bounding_box()
    assert all(abs(button_before[key]-button_after[key])<1 for key in ['width','height','x']), (button_before,button_after)
    after=page.locator('#history').bounding_box();assert abs(before['y']-after['y'])<1,(before,after)
    page.locator('#translation-form').evaluate('(el)=>el.requestSubmit()');assert len(posts)==1
    page.screenshot(path=str(EVIDENCE/f'{locale}-{mobile}-pending.png'),full_page=True)
    held.pop().fulfill(status=201,json=item);expect(page.locator('#result')).to_have_text(item['translation']);expect(page.locator('#translate')).to_be_enabled()
    page.locator('#translate').click();page.wait_for_timeout(50)
    expect(page.locator('#result')).to_have_text(item['translation']);expect(page.locator('#copy')).to_be_disabled()
    held.pop().fulfill(status=502,json={});expect(page.locator('#translate')).to_be_enabled();expect(page.locator('#result')).to_have_text(item['translation'])
    assert page.locator('#result').get_attribute('aria-busy')=='false'
    for failure in ['cancel','401']:
     page.locator('#translate').click();page.wait_for_timeout(50)
     route=held.pop()
     if failure=='cancel':
      page.locator('#cancel').click();expect(page.locator('#translate')).to_be_enabled();route.fulfill(status=201,json=item)
     else: route.fulfill(status=401,json={});expect(source).to_have_value('')
     expect(page.locator('#result-skeleton')).to_be_hidden()
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    checks.append({'locale':locale,'mobile_dark_reduced':mobile,'first_frame':frame,'history_y':before['y'],'posts':len(posts)})
    context.close()
  browser.close()
 (EVIDENCE/'checks.json').write_text(json.dumps(checks,indent=2))
 print(json.dumps({'scenarios_passed':len(checks),'evidence':str(EVIDENCE)}))
finally: server.shutdown()
