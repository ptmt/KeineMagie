"""Production web UI; isolated synthetic HTTP only, never live inference."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
import json,os,time
D={'turns':[{'id':'exercise','state':'completed','kind':'cloze','prompt':'Ich warte ___ den Bus.','at':'2026-11-20T12:00:00Z'}],'observations':[],'actions':[{'action':a,'turn_id':'exercise' if a in ['reveal','explain'] else ''} for a in ['reveal','progress','more','explain','practice']]}
CALLS=[]
class Chat(Handler):
 def do_GET(self):
  if self.path=='/v1/learning/coach':return self.reply(D)
  return super().do_GET()
 def do_POST(self):
  if self.path!='/v1/learning/coach':return self.mutate()
  b=json.loads(self.rfile.read(int(self.headers['Content-Length'])));CALLS.append(b)
  if b['action']=='progress':time.sleep(.2)
  return self.reply(D)
server=ThreadingHTTPServer(('127.0.0.1',0),Chat);Thread(target=server.serve_forever,daemon=True).start()
out=Path(os.environ.get('COACH_MENU_EVIDENCE',str(Path(os.environ['TMPDIR'])/'coach-web-menu')));out.mkdir(parents=True,exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':390,'height':844});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
  trigger=page.locator('.coach-menu-trigger');expect(trigger).to_be_visible(timeout=10000)
  draft=page.locator('#coach-input');draft.fill('Exact draft ä🙂');draft.focus();page.evaluate('document.querySelector("#coach-input").setSelectionRange(2,6)')
  before=len(CALLS);trigger.click();menu=page.get_by_role('menu');expect(menu).to_be_visible();assert menu.get_by_role('menuitem').count()==5
  assert len(CALLS)==before;assert page.locator('.coach-quick').count()==0
  page.keyboard.press('Escape');expect(menu).to_be_hidden();expect(draft).to_be_focused();assert draft.input_value()=='Exact draft ä🙂'
  assert page.evaluate('document.querySelector("#coach-input").selectionStart')==2
  trigger.focus();page.keyboard.press('ArrowDown');expect(menu).to_be_visible();expect(menu.get_by_role('menuitem').first).to_be_focused();page.keyboard.press('End');expect(menu.get_by_role('menuitem').last).to_be_focused();page.keyboard.press('Escape');expect(trigger).to_be_focused()
  trigger.click();page.locator('.coach-header h1').click();expect(menu).to_be_hidden();assert len(CALLS)==before
  trigger.click();menu.get_by_role('menuitem',name='Hint',exact=True).click();page.wait_for_timeout(200)
  assert [(x['action'],x.get('text'),x.get('turn_id')) for x in CALLS if x['action']=='reveal']==[('reveal','source','exercise')]
  trigger.click();menu.get_by_role('menuitem',name='Progress',exact=True).click();page.wait_for_timeout(400)
  assert [(x['action'],x.get('text'),x.get('turn_id','')) for x in CALLS if x['action']=='progress']==[('progress','My progress','')]
  assert draft.input_value()=='Exact draft ä🙂'
  for locale in ['en','de','ru','es','fr']:
   page.locator('#interface-language-header').select_option(locale)
   for width in [390,1280]:
    page.set_viewport_size({'width':width,'height':650 if width==390 else 900});draft.focus();trigger.click();expect(menu).to_be_visible()
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    for item in [trigger,*menu.get_by_role('menuitem').all()]:
     box=item.bounding_box();assert box['height']>=44 and box['width']>=44,box
    box=menu.bounding_box();assert box['x']>=0 and box['y']>=0 and box['x']+box['width']<=width and box['y']+box['height']<=page.viewport_size['height'],box
    page.screenshot(path=str(out/f'{locale}-{width}.png'));page.keyboard.press('Escape')
  assert not errors,errors
  (out/'receipt.json').write_text(json.dumps({'locales':['en','de','ru','es','fr'],'widths':[390,1280],'actions':[{k:v for k,v in c.items() if k in ['action','text','turn_id']} for c in CALLS],'errors':errors},ensure_ascii=False,indent=2))
  print('PASS: menu, all five actions, exact payloads, preserved draft/caret, keyboard/Escape/outside click, five locales × two widths, 44px targets, no JS errors')
  browser.close()
finally:server.shutdown()
