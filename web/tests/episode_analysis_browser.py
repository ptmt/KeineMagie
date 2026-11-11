"""Local-only regression of the shipped episode view against a synthetic API."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
import json
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(ROOT),**kw)
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path=='/harness':
   self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(b'<!doctype html><html lang="en"><div id="host"></div></html>');return
  super().do_GET()
server=ThreadingHTTPServer(('127.0.0.1',0),Handler);Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto('http://127.0.0.1:'+str(server.server_port)+'/harness')
  page.evaluate('''async()=>{
   const {setInterfaceLanguage}=await import('/i18n.mjs');setInterfaceLanguage('en');
   const {createEpisodeView}=await import('/episode-view.mjs');
   window.calls=0;window.steps=0;window.delay=0;
   const result={narrative:[{text:'Complete summary',citations:[{segment_id:0,quote:'Hallo'}]}],topics:[],recommendations:[]};
   const view=()=>({state:steps===3?'completed':'pending',completed_steps:steps,estimate:{total_requests:3,completed_requests:steps,remaining_requests:3-steps},result:steps===3?result:null});
   const api={request:async(path,options)=>{
    if(path.endsWith('/analysis')){
     if(options.method==='POST'){
      calls++;await new Promise((resolve,reject)=>{const timer=setTimeout(resolve,delay);options.signal.addEventListener('abort',()=>{clearTimeout(timer);reject(new DOMException('Canceled','AbortError'));},{once:true});});steps++;
     }return view();
    }
    if(path.includes('/profiles/'))return {cefr:'B1',self_assessments:[{cefr:'A2',assessed_at:'2026-01-01T12:00:00Z'},{cefr:'B1',assessed_at:'2026-02-01T12:00:00Z'}],progress:{saved:1,learning:0,known:0,favorites:1}};
    return {items:[{id:'v',term:'Hallo',quote:'Hallo',segment_id:0,status:'saved',favorite:true,history:[{status:'saved',at:'2026-02-01T12:00:00Z'}]}]};
   }};
   window.mount=()=>{window.reader?.dispose();window.reader=createEpisodeView({api});reader.identity({user:{id:'owner'},csrf_token:'csrf'});reader.render(document.getElementById('host'),{id:'job',state:'completed',source_language:'de',target_language:'ru',segments:[{text:'Hallo',start:0,end:1}]});};mount();
  }''')
  page.locator('#episode-cefr:enabled').wait_for()
  assert page.evaluate('calls')==0
  assert 'A2' in page.locator('.episode-assessment-history').inner_text()
  assert page.locator('.episode-vocabulary-history').count()==1
  page.get_by_role('button',name='Generate analysis',exact=True).click();page.wait_for_function('steps===3');page.get_by_text('Complete summary',exact=False).first.wait_for();assert page.evaluate('calls')==3, page.evaluate('({calls,steps,body:document.body.innerText})')
  page.evaluate('steps=0;calls=0;delay=1000;mount()');page.locator('#episode-cefr:enabled').wait_for();page.get_by_role('button',name='Generate analysis',exact=True).click();page.get_by_role('button',name='Cancel',exact=True).click();page.wait_for_timeout(1100)
  assert page.evaluate('calls')==1 and page.evaluate('steps')==0
  page.evaluate('mount()');page.locator('#episode-cefr:enabled').wait_for();assert page.evaluate('calls')==1
  page.evaluate('steps=1;delay=0;mount()');page.locator('#episode-cefr:enabled').wait_for();page.get_by_role('button',name='Resume analysis',exact=True).click();page.wait_for_function('steps===3');page.get_by_text('Complete summary',exact=False).first.wait_for();assert page.evaluate('calls')==3, page.evaluate('({calls,steps,body:document.body.innerText})')
  page.evaluate('steps=0;calls=0;delay=1000;mount()');page.locator('#episode-cefr:enabled').wait_for();page.get_by_role('button',name='Generate analysis',exact=True).click();page.evaluate("location.hash='#elsewhere'");page.wait_for_timeout(1100);assert page.evaluate('calls')==1 and page.evaluate('steps')==0
  assert not errors,errors
  print(json.dumps({'checks':7,'passed':['no implicit generation','dated level history','vocabulary history','single-click three-step completion','cancel aborts and stops','explicit resume only','navigation cancels'],'page_errors':errors}))
  browser.close()
finally:server.shutdown()
