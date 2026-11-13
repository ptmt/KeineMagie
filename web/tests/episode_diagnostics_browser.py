"""Synthetic analysis diagnostics, exercising the real DOM/client error boundary."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
import json
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(ROOT),**kw)
 def log_message(self,format,*a):pass
 def do_GET(self):
  if self.path=='/harness':
   self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(b'<!doctype html><html lang="en"><link rel="stylesheet" href="/styles.css"><link rel="stylesheet" href="/episode.css"><div id="host"></div></html>');return
  super().do_GET()
server=ThreadingHTTPServer(('127.0.0.1',0),Handler);Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':900,'height':1000});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto('http://127.0.0.1:'+str(server.server_port)+'/harness')
  page.evaluate('''async()=>{
   const {setInterfaceLanguage}=await import('/i18n.mjs');setInterfaceLanguage('en');
   const {createEpisodeView}=await import('/episode-view.mjs');
   window.calls=0;window.steps=0;window.release=null;
   const api={request:async(path,options)=>{
    if(path.endsWith('/analysis')){
     if(options.method==='POST'){calls++;await new Promise(resolve=>release=resolve);throw Object.assign(new Error('private provider payload must not appear'),{status:502,code:'analysis_invalid_output'});}
     return {state:'pending',completed_steps:steps,estimate:{total_requests:51,completed_requests:steps,remaining_requests:51-steps},result:null};
    }
    if(path.includes('/profiles/'))return {cefr:'B1'};
    return {items:[]};
   }};
   window.reader=createEpisodeView({api});reader.identity({user:{id:'owner'},csrf_token:'csrf'});reader.render(document.getElementById('host'),{id:'job',state:'completed',source_language:'de',target_language:'ru',segments:[{text:'Hallo',start:0,end:1}]});
  }''')
  page.get_by_role('button',name='Generate analysis',exact=True).wait_for()
  assert page.evaluate('calls')==0
  page.get_by_role('button',name='Generate analysis',exact=True).click()
  page.get_by_text('Generating analysis…',exact=True).wait_for(timeout=1500)
  assert page.locator('#episode-summary').get_by_text('Not generated',exact=True).count()==0
  page.screenshot(path='/Users/tinyserve/.hermes/cache/scratch/summary-running-synthetic.png')
  page.evaluate('release()')
  page.get_by_text('The analysis response could not be verified. Saved steps are retained. Try again to resume.',exact=True).wait_for(timeout=1500)
  assert page.evaluate('calls')==1 and 'private provider payload' not in page.locator('body').inner_text()
  assert page.get_by_role('button',name='Cancel',exact=True).count()==0
  page.screenshot(path='/Users/tinyserve/.hermes/cache/scratch/summary-error-synthetic.png')
  for locale in ['de','ru','es','fr','en']:
   page.evaluate("async locale=>{const {setInterfaceLanguage}=await import('/i18n.mjs');setInterfaceLanguage(locale);reader.localize()}",locale)
   assert page.locator('#episode-summary [role=alert]').inner_text()
   assert page.evaluate('calls')==1
  page.evaluate('steps=1;reader.dispose();reader.render(document.getElementById("host"),{id:"job",state:"completed",source_language:"de",target_language:"ru",segments:[{text:"Hallo",start:0,end:1}]})')
  page.get_by_text('Saved steps: 1 / 51',exact=True).wait_for()
  page.get_by_role('button',name='Resume analysis',exact=True).wait_for()
  assert page.evaluate('calls')==1
  # A failed checkpoint GET must keep the same safe, actionable diagnostic.
  page.evaluate('''async()=>{reader.dispose();const {createEpisodeView}=await import('/episode-view.mjs');reader=createEpisodeView({api:{request:async path=>{if(path.endsWith('/analysis'))throw Object.assign(new Error('private storage path'),{status:503,code:'analysis_checkpoint_unavailable'});return {items:[]};}}});reader.identity({user:{id:'owner'}});reader.render(document.getElementById('host'),{id:'other',state:'completed',source_language:'de',target_language:'ru',segments:[]});}''')
  page.get_by_text('Could not save or read analysis. Try again; saved steps are retained.',exact=True).wait_for(timeout=1500)
  assert 'private storage path' not in page.locator('body').inner_text()
  out=Path('/Users/tinyserve/.hermes/cache/scratch/summary-diagnostics-synthetic.png');page.screenshot(path=str(out))
  assert not errors,errors
  print(json.dumps({'passed':['no implicit inference','immediate running state','safe actionable failure','no automatic retry','cancel removed','saved step denominator and explicit resume'],'screenshot':str(out)}))
  browser.close()
finally:server.shutdown()
