"""Held synthetic analysis responses prove tab navigation is not page leave."""
from episode_fixture import Handler, PATH, STATE, RESULT
from http.server import ThreadingHTTPServer
from threading import Thread, Event
from playwright.sync_api import sync_playwright
import json, time
G={'steps':0,'posts':0,'gates':[Event() for _ in range(3)]}
def analysis():
 value={'state':'completed' if G['steps']==3 else 'pending','completed_steps':G['steps'],'estimate':{'remaining_requests':3-G['steps'],'completed_requests':G['steps'],'total_requests':3}}
 if G['steps']==3:value['result']=RESULT
 return value
class LifecycleHandler(Handler):
 def do_GET(self):
  if self.path.endswith('/analysis'):return self.reply(analysis())
  return super().do_GET()
 def do_POST(self):
  if not self.path.endswith('/analysis'):return super().do_POST()
  self.rfile.read(int(self.headers.get('Content-Length','0')))
  index=G['posts'];G['posts']+=1
  if index>=3:return self.reply({},429)
  G['gates'][index].wait(10);G['steps']+=1
  try:self.reply(analysis())
  except (BrokenPipeError,ConnectionResetError):pass
server=ThreadingHTTPServer(('127.0.0.1',0),LifecycleHandler)
Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':1440,'height':1000});errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  page.goto(origin+PATH);page.get_by_role('button',name='Generate analysis',exact=True).wait_for()
  assert G['posts']==0
  page.get_by_role('button',name='Generate analysis',exact=True).click()
  page.locator('#episode-tab-transcript').click()
  page.locator('#episode-find').fill('Satz 2012.')
  page.locator('#episode-time').fill('100:36')
  page.locator('.episode-quote summary').first.click()
  draft=page.locator('.episode-quote form input').first;draft.fill('Guten Morgen');draft.evaluate('(e)=>e.setSelectionRange(2,5)')
  page.locator('#episode-tab-vocabulary').click()
  page.go_back();page.wait_for_timeout(100)
  G['gates'][0].set();page.wait_for_timeout(250)
  assert G['posts']==2, 'internal Back must not cancel the already authorized analysis pipeline'
  assert page.locator('#episode-summary').is_hidden()
  assert 'Saved steps: 1 / 3' in page.locator('#episode-summary').text_content()
  page.locator('#episode-tab-summary').click()
  assert 'Saved steps: 1 / 3' in page.locator('#episode-summary').inner_text()
  page.locator('#episode-tab-transcript').click()
  assert page.locator('#episode-find').input_value()=='Satz 2012.'
  assert page.locator('#episode-time').input_value()=='100:36'
  assert draft.input_value()=='Guten Morgen'
  assert draft.evaluate('(e)=>[e.selectionStart,e.selectionEnd]')==[2,5]
  G['gates'][1].set();page.wait_for_timeout(200);G['gates'][2].set();page.wait_for_timeout(250)
  assert G['posts']==3
  assert 'Synthetic summary:' in page.locator('#episode-summary').text_content()
  page.locator('#episode-tab-summary').click();assert page.locator('#episode-summary .episode-citation').count()>0
  for key in ['transcript','recommendations','summary']:
   page.locator('#episode-tab-'+key).click()
  assert G['posts']==3, 'tab switch cannot restart a completed pipeline'
  # A real application-route leave still cancels continuation (not internal tabs).
  G.update(steps=0,posts=0,gates=[Event() for _ in range(3)])
  page.goto(origin+PATH);page.get_by_role('button',name='Generate analysis',exact=True).click()
  page.locator('#episode-tab-transcript').click()
  page.locator('.section-nav a[href="#translator"]').click()
  G['gates'][0].set();page.wait_for_timeout(250)
  assert G['posts']==1, 'actual page leave must stop authorized continuation'
  page.go_back();page.wait_for_timeout(250)
  assert G['posts']==1, 'returning to the page must not silently resume'
  page.locator('#account').click();page.locator('#logout').click()
  page.wait_for_function("()=>document.querySelector('#podcast-content').textContent===''")
  assert page.locator('[role=tabpanel]').count()==0
  assert 'Guten Morgen' not in page.locator('body').text_content()
  assert not errors,errors
  print(json.dumps({'result':'PASS: bounded 3-step pipeline survives tabs/Back; inactive progress, drafts/selection, no restart, logout purge','completed_pipeline_posts':3,'page_leave_posts':G['posts']}))
  browser.close()
finally:
 for gate in G['gates']:gate.set()
 server.shutdown()
