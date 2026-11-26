"""Real web application, loopback-only synthetic APIs; no paid/provider calls."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread, Event
from pathlib import Path
from datetime import datetime, timezone
from playwright.sync_api import sync_playwright, expect
import json, os

CALLS=[]
GATE=Event()
def fresh():
 return {'turns':[{'id':'task','kind':'cloze','state':'completed','prompt':'Ich warte ___ den Bus.','at':datetime.now(timezone.utc).isoformat()}], 'observations':[], 'actions':[{'action':a,'turn_id':'task' if a in ['reveal','explain'] else ''} for a in ['reveal','progress','more','explain','practice']]}
D=fresh()
class Chat(Handler):
 def do_GET(self):
  if self.path=='/v1/learning/coach': return self.reply(D)
  return super().do_GET()
 def do_POST(self):
  if self.path!='/v1/learning/coach': return self.mutate()
  body=json.loads(self.rfile.read(int(self.headers['Content-Length']))); CALLS.append(body)
  if body['action']=='message': GATE.wait(10)
  if body['action']=='cancel': GATE.set()
  try: return self.reply(D)
  except (BrokenPipeError,ConnectionResetError): pass

def mutations(): return [c for c in CALLS if c['action'] not in ['entry','seen']]

out=Path(os.environ.get('COMPOSER_KEYBOARD_EVIDENCE',str(Path(os.environ['TMPDIR'])/'composer-keyboard')));out.mkdir(parents=True,exist_ok=True)
server=ThreadingHTTPServer(('127.0.0.1',0),Chat);Thread(target=server.serve_forever,daemon=True).start()
receipts=[];errors=[]
try:
 with sync_playwright() as p:
  engine=os.environ.get('BROWSER','chromium'); browser=getattr(p,engine).launch()
  for width,theme in [(1280,'light'),(390,'light'),(1280,'dark'),(390,'dark')]:
   GATE.set();page=browser.new_page(viewport={'width':width,'height':900 if width==1280 else 844},color_scheme=theme)
   page.on('pageerror',lambda e:errors.append(str(e)))
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
   page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
   draft=page.locator('#coach-input');shell=page.locator('.coach-composer-shell');plus=page.locator('.coach-menu-trigger')
   expect(draft).to_be_enabled();expect(page.get_by_role('button',name='Stop',exact=True)).to_have_count(0)
   draft.fill('Discussion draft ä🙂');draft.focus();page.wait_for_timeout(100)
   stem=f'{engine}-{width}-{theme}'
   page.screenshot(path=str(out/(stem+'-full.png')));shell.screenshot(path=str(out/(stem+'-crop.png')))
   if os.environ.get('CAPTURE_ONLY'):page.close();continue
   assert draft.evaluate("e=>getComputedStyle(e).outlineStyle")=='none','No nested textarea focus ring'
   assert shell.evaluate("e=>getComputedStyle(e).outlineStyle")=='solid','Composer retains visible keyboard focus'
   assert draft.evaluate("e=>parseFloat(getComputedStyle(e).paddingLeft)")>=8
   before=len(mutations());page.keyboard.press('Enter');page.wait_for_timeout(200)
   assert len(mutations())==before+1, 'Enter must send once via existing message action'
   assert mutations()[-1]['action']=='message' and mutations()[-1]['text']=='Discussion draft ä🙂'
   expect(draft).to_have_value('');expect(draft).to_be_focused()
   before=len(mutations());draft.fill('ab🙂cde');draft.evaluate('e=>e.setSelectionRange(2,5)')
   page.keyboard.press('Meta+Enter')
   expect(draft).to_have_value('ab\nde');assert draft.evaluate('e=>[e.selectionStart,e.selectionEnd]')==[3,3]
   page.keyboard.press('Shift+Enter');expect(draft).to_have_value('ab\n\nde');assert len(mutations())==before
   # No keyboard cancellation, repeated sends, modifier sends, or IME commits.
   draft.fill('safe draft');before=len(mutations())
   for shortcut in ['Control+Enter','Alt+Enter','Control+Meta+Enter']:
    page.keyboard.press(shortcut);assert len(mutations())==before
   for flags in [{'isComposing':True},{'keyCode':229},{'repeat':True}]:
    draft.dispatch_event('keydown',{'key':'Enter','bubbles':True,**flags});assert len(mutations())==before
   draft.dispatch_event('compositionstart',{'data':'漢'})
   draft.dispatch_event('keydown',{'key':'Enter','bubbles':True})
   page.wait_for_timeout(100);assert len(mutations())==before,'Composition lifecycle must block send even without isComposing'
   draft.dispatch_event('compositionend',{'data':'漢'})
   for text in ['', ' \n\t ']:
    draft.fill(text);expect(page.get_by_role('button',name='Send',exact=True)).to_be_disabled()
    page.keyboard.press('Enter');assert len(mutations())==before;expect(draft).to_have_value(text)
   GATE.clear();draft.fill('  exact\nmessage 🙂  ');page.keyboard.press('Enter')
   stop=page.get_by_role('button',name='Stop',exact=True);expect(stop).to_be_enabled()
   page.wait_for_timeout(100);assert len(mutations())==before+1
   assert mutations()[-1]['text']=='  exact\nmessage 🙂  '
   page.keyboard.press('Enter');draft.dispatch_event('keydown',{'key':'Enter','repeat':True,'bubbles':True})
   draft.fill('next draft');page.keyboard.press('Meta+Enter');expect(draft).to_have_value('next draft\n')
   assert len(mutations())==before+1, 'Enter while pending must not cancel or send'
   stop.click();expect(stop).to_have_count(0);expect(draft).to_have_value('next draft\n')
   assert mutations()[-1]['action']=='cancel'
   # Selection/input events, maxlength, real keyboard focus, menu restoration, growth.
   draft.fill('one');draft.focus();assert draft.bounding_box()['height']==44
   draft.evaluate("e=>{window.composerInputs=[];e.addEventListener('input',x=>window.composerInputs.push(x.inputType))}")
   page.keyboard.press('Meta+Enter');assert draft.bounding_box()['height']==68
   assert page.evaluate('window.composerInputs.includes("insertLineBreak")')
   page.keyboard.press('Shift+Enter');assert draft.bounding_box()['height']==92
   draft.fill('\n'.join(['line']*12));assert draft.bounding_box()['height']==140
   assert draft.evaluate('e=>e.scrollHeight>e.clientHeight')
   draft.fill('Draft ä🙂');assert draft.bounding_box()['height']==44
   draft.evaluate('e=>e.setSelectionRange(2,6)');plus.click();expect(page.get_by_role('menu')).to_be_visible()
   page.keyboard.press('Escape');expect(draft).to_be_focused();assert draft.evaluate('e=>[e.selectionStart,e.selectionEnd]')==[2,6]
   # macOS WebKit's default Tab policy skips buttons; Option+Tab includes them.
   page.keyboard.press('Alt+Shift+Tab' if engine=='webkit' else 'Shift+Tab');expect(plus).to_be_focused()
   page.keyboard.press('Alt+Tab' if engine=='webkit' else 'Tab');expect(draft).to_be_focused()
   assert draft.evaluate("e=>getComputedStyle(e).outlineStyle")=='none'
   assert shell.evaluate("e=>getComputedStyle(e).outlineStyle")=='solid'
   draft.fill('x'*2000);page.keyboard.press('Meta+Enter');assert len(draft.input_value())==2000
   draft.evaluate('e=>e.setSelectionRange(10,12)');page.keyboard.press('Meta+Enter');assert len(draft.input_value())==1999
   for locale in ['de','ru','es','fr','en']:
    draft.fill('Localized draft 🙂');draft.evaluate('e=>e.setSelectionRange(2,6)')
    page.locator('#interface-language-header').select_option(locale)
    expect(draft).to_have_value('Localized draft 🙂');assert draft.evaluate('e=>[e.selectionStart,e.selectionEnd]')==[2,6]
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
   receipts.append({'variant':stem,'passed':True});page.close()
  browser.close()
 assert not errors,errors
 (out/'receipt.json').write_text(json.dumps({'synthetic':True,'variants':receipts,'errors':errors},indent=2))
 print(f'PASS {engine}: {len(receipts)} variants; evidence {out}')
finally:GATE.set();server.shutdown()
