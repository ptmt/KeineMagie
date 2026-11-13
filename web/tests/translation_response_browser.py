"""Synthetic HTTP responses and injected DOM failures, never real inference."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
import json
from playwright.sync_api import sync_playwright, expect  # pyright: ignore[reportMissingImports]
ROOT=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(ROOT),**kw)
 def log_message(self,format,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler);Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
checks=[]
def check(name,value):
 assert value,name
 checks.append(name)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  for failure in ['record','history','json','schema','network','401','502','success']:
   for locale in (['de','en','ru','es','fr'] if failure in ['record','history'] else ['en']):
    context=browser.new_context(locale='en-US')
    context.add_init_script(f"localStorage.setItem('keinemagie:interface-language:v1','{locale}')")
    page=context.new_page();posts=[];logs=[]
    page.on('console',lambda message:logs.append(message.text) if message.type=='warning' else None)
    item={'id':'synthetic-accepted','text':' private source ','translation':' PRIVATE RESULT <&> ','source_language':'ru','target_language':'de','idioms':[],'patterns':[],'vocabulary':[]}
    def api(route):
     path=route.request.url.split(origin)[-1]
     if path=='/v1/web/session':route.fulfill(json={'user':{'id':'synthetic-owner'},'csrf_token':'synthetic'})
     elif path=='/v1/web/config':route.fulfill(json={'apple_available':True})
     elif path=='/v1/provider':route.fulfill(json={'connected':True,'status':'connected','selected_model':'synthetic'})
     elif path=='/v1/translations' and route.request.method=='POST':
      posts.append(route.request)
      if failure=='network':route.abort('failed')
      elif failure in ['401','502']:route.fulfill(status=int(failure),json={})
      elif failure=='json':route.fulfill(status=201,content_type='application/json',body='{')
      else:route.fulfill(status=201,json={} if failure=='schema' else item,headers={'X-Request-ID':'synthetic-request-123'})
     else:route.fulfill(json={'items':[]})
    page.route('**/v1/**',api)
    held_history=[]
    if failure=='history':
     page.route('**/v1/translations',lambda route: held_history.append(route) if route.request.method=='GET' else route.fallback())
    page.goto(origin)
    expect(page.locator('#source-text')).to_be_enabled();page.locator('#source-text').fill(' private source ')
    if failure=='record':
     page.evaluate("""() => {const el=document.querySelector('#result');const descriptor=Object.getOwnPropertyDescriptor(Node.prototype,'textContent');Object.defineProperty(el,'textContent',{configurable:true,get(){return descriptor.get.call(this)},set(value){if(value.includes('PRIVATE RESULT')){delete this.textContent;throw new TypeError('PRIVATE EXCEPTION CONTENT')}descriptor.set.call(this,value)}})}""")
    elif failure=='history':
     page.evaluate("""() => {const el=document.querySelector('#history-list');const original=el.replaceChildren;el.replaceChildren=function(...args){this.replaceChildren=original;throw new TypeError('PRIVATE EXCEPTION CONTENT')}}""")
    page.locator('#translate').click();page.wait_for_timeout(150)
    check(f'{failure}/{locale} one POST',len(posts)==1)
    if failure in ['record','history']:
     expect(page.locator('#translation-recover')).to_be_visible()
     check(f'{failure}/{locale} saved not false offline',page.locator('#translation-status').text_content() and 'No server connection' not in page.locator('#translation-status').text_content())
     expect(page.locator('#source-text')).to_have_value(' private source ')
     if failure=='history':
      assert held_history
      held_history.pop().fulfill(json={'items':[]});page.wait_for_timeout(100)
     page.locator('#translation-recover').click()
     check(f'{failure}/{locale} retained accepted result',page.locator('#result').text_content()==item['translation'])
     check(f'{failure}/{locale} retained accepted history',page.locator('.history-translation').text_content()==item['translation'])
     check(f'{failure}/{locale} recovery never repeats AI',len(posts)==1)
     check(f'{failure}/{locale} safe diagnostics',len(logs)==1 and 'render' in logs[0] and '201' in logs[0] and 'requestID' in logs[0] and 'synthetic-request-123' not in logs[0] and all(secret not in logs[0] for secret in ['PRIVATE','private source','synthetic-owner','synthetic-accepted']))
    elif failure=='success':expect(page.locator('#result')).to_have_text(item['translation'])
    else:
     message=page.locator('#translation-status').inner_text()
     expected={'json':'invalid response','schema':'invalid response','network':'connection','401':'session expired','502':'unavailable'}[failure]
     check(f'{failure} distinct error',expected.lower() in message.lower())
     check(f'{failure} not saved recovery',page.locator('#translation-recover').is_hidden())
     if failure=='401':expect(page.locator('#source-text')).to_have_value('')
     else:expect(page.locator('#source-text')).to_have_value(' private source ')
    context.close()
  browser.close()
 print(json.dumps({'synthetic_only':True,'checks_passed':len(checks),'checks':checks}))
finally:server.shutdown()
