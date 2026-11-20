"""Contextual Coach, synthetic owner-only HTTP, production web UI. No live AI."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright
import json,time,os
D={'turns':[],'observations':[],'model':'gpt-6.1-terra','actions':[{'action':'practice','turn_id':''}]};CALLS=[]
def turn(id,kind='clarification',message='Have 30 seconds?'):
 return dict(id=id,text='',state='completed',at='now',assisted=False,language='de',kind=kind,message=message,is_offer=id=='offer',message_version=id+':completed')
class Chat(Handler):
 def do_GET(self):
  if self.path=='/v1/learning/coach':return self.reply(D)
  return super().do_GET()
 def do_POST(self):
  if self.path!='/v1/learning/coach':return self.mutate()
  b=json.loads(self.rfile.read(int(self.headers['Content-Length'])));CALLS.append(b)
  if b['action']=='progress':
   time.sleep(.3);D['turns'].append(turn('summary',message='Synthetic progress: 4 saved translations; 2 Coach answers, 1 correct and 1 to repeat. Vocabulary: 3 self-reported entries. Podcast passages: 2 saved. Dictation unavailable. Activity is not mastery.'))
  return self.reply(D)
server=ThreadingHTTPServer(('127.0.0.1',0),Chat);Thread(target=server.serve_forever,daemon=True).start()
evidence=Path(os.environ['TMPDIR'])/'coach-contextual-evidence';evidence.mkdir(exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':390,'height':844},color_scheme='dark',reduced_motion='reduce');errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  D['turns']=[turn('offer')]
  page.goto(f'http://127.0.0.1:{server.server_port}/#coach');page.locator('.coach-menu-trigger').click();page.get_by_role('menuitem',name='30 seconds',exact=True).wait_for()
  assert page.get_by_role('menuitem',name='30 seconds',exact=True).count()==1
  assert page.locator('[data-turn=offer] button').count()==0
  page.screenshot(path=str(evidence/'web-offer-mobile-dark.png'))
  D['turns']=[turn('old',message='Synthetic saved feedback: repeat preposition case.')];D['actions']=[{'action':'explain','turn_id':'old'},{'action':'more','turn_id':''},{'action':'progress','turn_id':''}]
  page.reload();page.locator('.coach-menu-trigger').click();page.get_by_role('menuitem',name='Progress',exact=True).wait_for()
  page.locator('#coach-input').fill('keep my draft')
  page.screenshot(path=str(evidence/'web-after-feedback-mobile-dark.png'))
  page.evaluate("Array.from(document.querySelectorAll('.coach-command-menu button')).find(e=>e.textContent==='Progress').click();Array.from(document.querySelectorAll('.coach-command-menu button')).find(e=>e.textContent==='Progress').click()")
  page.get_by_text('Synthetic progress:',exact=False).wait_for()
  assert len([b for b in CALLS if b['action']=='progress'])==1
  assert page.locator('#coach-input').input_value()=='keep my draft'
  page.evaluate('window.scrollTo(0,0)')
  page.screenshot(path=str(evidence/'web-progress-mobile-dark.png'))
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
  page.locator('.coach-menu-trigger').click()
  assert all(x['height']>=44 for x in page.locator('.coach-command-menu button').evaluate_all('es=>es.map(e=>e.getBoundingClientRect().toJSON())'))
  assert not errors,errors
  print('PASS duplicate CTA, contextual feedback actions, one rapid-tap progress POST, draft retained, mobile dark reduced motion, 44px controls. Evidence:',evidence)
  browser.close()
finally:server.shutdown()
