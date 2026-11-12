"""Actual shipped UI in Chromium, synthetic API only. No paid inference."""
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from threading import Thread
import json
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(root),**kw)
 def log_message(self,*a):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
origin='http://localhost:'+str(server.server_port)
checks=[]
def check(name,condition):
 assert condition,name
 checks.append(name)
original=dict(id='saved',text='лук',translation='Zwiebel',source_language='ru',target_language='de',instructions='Friendly',idioms=[],patterns=[],vocabulary=[])
revision='  Bogen 👩🏽‍💻 e\u0301\n'+('日本語 {"literal":"\\n"}\t  \n'*200)+' Ende\n '
record=dict(original)
owner=['A'];failure=[False];hold=[False];pending=[];calls=[];posts=[]
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  context=browser.new_context(locale='ru-RU',permissions=['clipboard-read','clipboard-write'])
  page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  def api(route):
   global record
   path=route.request.url.split(origin)[1];calls.append((route.request.method,path))
   if path=='/v1/translation-followups':
    body=route.request.post_data_json;posts.append(body)
    if failure[0]:route.fulfill(status=502,json={'error':'synthetic upstream failure'});return
    turn=dict(request_id=body['request_id'],question=body['question'],answer='В контексте оружия нужен Bogen, а не Zwiebel.',revised_text=revision if len(record.get('followups',[]))==0 else None)
    record={**record,'followups':[*record.get('followups',[]),turn]}
    if hold[0]:pending.append((route,dict(record)));return
    route.fulfill(status=201,json=record);return
   data={
    '/v1/web/config':dict(apple_available=False,pairing_available=True,csrf_token='fixture'),
    '/v1/web/session':dict(user=dict(id=owner[0]),csrf_token='fixture',provider=dict(connected=True,status='connected',selected_model='fixture')),
    '/v1/provider':dict(connected=True,status='connected',selected_model='fixture'),
    '/v1/translations':dict(items=[record]) if owner[0]=='A' else dict(items=[]),
    '/v1/podcasts':dict(items=[],worker_available=False),'/v1/podcasts/subscriptions':dict(items=[]),'/v1/learning/profile':dict(assessments=[])}
   route.fulfill(json=data.get(path,{}))
  page.route('**/v1/**',api);page.goto(origin)
  page.locator('#history-list button').click();page.locator('#clarify-translation').click()
  page.locator('#followup-question').fill('Я имел в виду оружие, а не овощ')
  page.locator('#send-followup').click();page.wait_for_function("() => document.querySelectorAll('#followup-thread li').length===1")
  check('question and assistant answer visible without replacing source/result',page.locator('#source-text').input_value()=='лук' and page.locator('#result').inner_text()=='Zwiebel' and 'Bogen' in page.locator('#followup-thread').inner_text())
  page.locator('[data-revision="0"]').click();check('explicit apply exact Unicode multiline output',page.locator('#result').text_content()==revision)
  page.locator('#copy').click();check('exact entire revised clipboard',page.evaluate('navigator.clipboard.readText()')==revision)
  page.locator('#history-list button').click()
  check('reopening original restores enabled explicit revision action',page.locator('#result').text_content()=='Zwiebel' and page.locator('[data-revision="0"]').is_enabled())
  page.locator('[data-revision="0"]').click()
  page.locator('#followup-question').fill('Почему?');page.locator('#followup-question').evaluate('(el)=>{el.focus();el.setSelectionRange(1,4)}')
  before=len(calls)
  for locale in ['de','en','es','fr','ru']:
   page.select_option('#interface-language-header',locale)
   check(locale+' preserves draft, open discussion and no API',page.locator('#followup-question').input_value()=='Почему?' and page.locator('#translation-discussion').is_visible() and len(calls)==before)
  page.locator('#followup-question').evaluate('(el)=>{el.focus();el.setSelectionRange(1,4)}')
  page.evaluate("document.querySelector('#interface-language-header').value='en';document.querySelector('#interface-language-header').dispatchEvent(new Event('change'))")
  check('locale retains focused textarea selection',page.evaluate("document.activeElement.id==='followup-question'&&document.activeElement.selectionStart===1&&document.activeElement.selectionEnd===4"))
  failure[0]=True;page.locator('#send-followup').click();page.wait_for_function("() => document.querySelector('#followup-status').textContent.includes('Could not')")
  check('transient error keeps draft and result',page.locator('#followup-question').input_value()=='Почему?' and page.locator('#result').text_content()==revision)
  failure[0]=False;hold[0]=True;page.locator('#send-followup').click();page.wait_for_function("() => document.querySelector('#send-followup').disabled")
  page.locator('#send-followup').evaluate('(el)=>{el.click();el.click()}')
  check('retry retains stable request ID and duplicate clicks coalesce',posts[-1]['request_id']==posts[-2]['request_id'] and len(posts)==3)
  route,value=pending.pop();route.fulfill(status=201,json=value);page.wait_for_function("() => document.querySelectorAll('#followup-thread li').length===2")
  check('multiple turns on same parent with expected version',posts[-1]['history_id']=='saved' and posts[-1]['expected_turns']==1 and len([c for c in calls if c==('POST','/v1/translations')])==0)
  record['followups'][0]['revised_text']='Bogen'
  before=len(posts);page.reload();page.locator('#history-list button').click();page.locator('#clarify-translation').click()
  check('reload reopens saved discussion with original unchanged and no inference',page.locator('#followup-thread li').count()==2 and page.locator('#result').text_content()=='Zwiebel' and len(posts)==before)
  page.locator('#followup-question').blur()
  page.evaluate('window.scrollTo(0,0)')
  for width in [1440,390]:
   page.set_viewport_size(dict(width=width,height=960));page.screenshot(path=f'/Users/tinyserve/.hermes/cache/scratch/followup-{width}.png',full_page=True)
   check(str(width)+' no horizontal overflow',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
  page.locator('#source-text').fill('другой текст');check('edited source detaches old discussion',page.locator('#translation-followup').is_hidden())
  page.locator('#history-list button').click()
  if page.locator('#translation-discussion').is_hidden():page.locator('#clarify-translation').click()
  page.locator('#followup-question').fill('private draft')
  owner[0]='B';page.locator('#account').click();page.locator('#retry-session').click();page.wait_for_function("() => document.querySelector('#translation-followup').hidden")
  check('owner change removes all private discussion and draft',page.locator('#followup-question').input_value()=='' and page.locator('#followup-thread li').count()==0)
  check('no runtime errors',not errors)
  print(json.dumps(dict(fixture_only=True,checks_passed=len(checks),checks=checks,posts=len(posts),screenshots=['/Users/tinyserve/.hermes/cache/scratch/followup-1440.png','/Users/tinyserve/.hermes/cache/scratch/followup-390.png'])))
  browser.close()
finally:server.shutdown()
