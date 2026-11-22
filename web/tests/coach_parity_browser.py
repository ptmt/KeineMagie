"""Actual web modules with synthetic local HTTP; no providers or production data."""
from episode_fixture import Handler, STATE
from http.server import ThreadingHTTPServer
from threading import Thread,Event
from pathlib import Path
from datetime import datetime,timezone,timedelta
from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import sync_playwright,expect
import json,os
NOW=datetime.now(timezone.utc).isoformat(); GATE=Event(); CALLS=[]; MODE='wrong'
def fresh():return {'turns':[{'id':'old','kind':'cloze','state':'completed','prompt':'Er benimmt ___ schlecht.','at':(datetime.now(timezone.utc)-timedelta(days=2)).isoformat(),'attempt':{'id':'old-a','answer':'sich','outcome':'correct','assessment_state':'completed'}},{'id':'task','kind':'context_translation','state':'completed','target':'vocabulary.word_choice','prompt':'Ich muss das Paket abholen.','target_text':'abholen','answer_language':'en','message':'Translate the highlighted word into English.','at':NOW}], 'observations':[], 'actions':[{'action':a,'turn_id':'task' if a in ['reveal','explain'] else ''} for a in ['reveal','progress','more','explain','practice']]}
D=fresh()
class Chat(Handler):
 def do_GET(self):
  if self.path=='/v1/learning/coach':return self.reply(D)
  if self.path.startswith('/v1/learning/activity?'):
   start=datetime.fromisoformat(parse_qs(urlsplit(self.path).query)['start'][0]);return self.reply({'version':1,'days':[{'date':(start+timedelta(days=i)).date().isoformat(),'known_count':i,'coverage':'partial','counts':{'translator':i,'coach':0,'dictation':0,'podcasts':0}} for i in range(7)],'sources':{'translator':'retained','coach':'retained','dictation':'retained','podcasts':'unsupported'},'undated':2})
  return super().do_GET()
 def do_POST(self):
  if self.path!='/v1/learning/coach':return self.mutate()
  b=json.loads(self.rfile.read(int(self.headers['Content-Length'])));CALLS.append(b)
  if b['action']=='answer':
   GATE.wait(15)
   if MODE=='error':return self.reply({'code':'coach_storage'},503)
   D['turns'][-1]['attempt']={'id':b['request_id'],'answer':b['text'],'outcome':'wrong' if MODE=='wrong' else 'correct','assessment_state':'completed','assessment':{'verdict':'incorrect' if MODE=='wrong' else 'correct','corrected_answer':'pick up'}}
   D['turns'][-1]['explanation']='In this sentence, abholen means collecting the parcel.'
  if b['action']=='cancel':
   D['turns'][-1]['attempt']={'id':b['turn_id'],'answer':'  gather 🙂  ','outcome':'ambiguous','assessment_state':'canceled'};GATE.set()
  if b['action']=='reveal':D['turns'][0]['answer_reveals']=1
  return self.reply(D)
server=ThreadingHTTPServer(('127.0.0.1',0),Chat);Thread(target=server.serve_forever,daemon=True).start()
out=Path(os.environ.get('COACH_PARITY_EVIDENCE',str(Path(os.environ['TMPDIR'])/'coach-web-parity-evidence')));out.mkdir(parents=True,exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();errors=[]
  for width,theme in [(1280,'light'),(390,'light'),(1280,'dark'),(390,'dark')]:
   STATE['signed']=True;D=fresh();GATE.clear();MODE='wrong';page=browser.new_page(viewport={'width':width,'height':900 if width==1280 else 844},color_scheme=theme);page.on('pageerror',lambda e:errors.append(str(e)));activity_reads=[];page.on('request',lambda r:activity_reads.append(r.url) if '/v1/learning/activity?' in r.url else None)
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
   page.goto(f'http://127.0.0.1:{server.server_port}/#coach');answer=page.locator('.coach-exercise input');expect(answer).to_be_visible()
   strip=page.locator('.coach-activity');assert strip.bounding_box()['height']==30,strip.bounding_box()
   expect(page.locator('.coach-prompt strong')).to_have_text('abholen');assert page.locator('.coach-task-status').count()==0
   answer.fill('  gather 🙂  ');page.locator('#coach-input').fill('Discussion draft ä🙂')
   task=page.locator('[data-turn="task"]');before=task.locator('.coach-prompt').bounding_box();task_height=task.bounding_box()['height'];page.screenshot(path=str(out/f'{width}-{theme}-active.png'))
   page.get_by_role('button',name='Check',exact=True).click();expect(page.locator('.coach-answer')).to_have_text('  gather 🙂  ')
   expect(page.get_by_role('button',name='Stop',exact=True)).to_be_enabled();expect(page.locator('.coach-checking')).to_have_count(1)
   page.screenshot(path=str(out/f'{width}-{theme}-pending.png'));assert task.bounding_box()['height']==task_height;GATE.set();expect(page.locator('.coach-assessment.coach-incorrect')).to_be_visible()
   assert page.locator('.coach-answer').text_content()=='  gather 🙂  ';expect(page.locator('#coach-input')).to_have_value('Discussion draft ä🙂')
   assert 'coach-incorrect' not in task.get_attribute('class');assert page.locator('.coach-assessment').bounding_box()['x']<page.locator('.coach-answer').bounding_box()['x']
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth');assert page.locator('.coach-composer').bounding_box()['y']+page.locator('.coach-composer').bounding_box()['height']<=page.viewport_size['height']
   page.screenshot(path=str(out/f'{width}-{theme}-incorrect.png'))
   trigger=page.locator('.coach-menu-trigger');trigger.focus();page.keyboard.press('ArrowDown');expect(page.get_by_role('menu')).to_be_visible();page.keyboard.press('End');expect(page.get_by_role('menuitem').last).to_be_focused();page.keyboard.press('Escape');expect(trigger).to_be_focused()
   page.locator('.coach-activity-day').first.click();expect(page.get_by_role('dialog')).to_contain_text('Podcasts: Not supported');page.screenshot(path=str(out/f'{width}-{theme}-activity.png'));page.keyboard.press('Escape')
   page.get_by_role('button',name='Earlier',exact=True).click();expect(page.get_by_role('button',name='Show answer & feedback')).to_be_visible();assert page.locator('.coach-answer').count()==1
   page.get_by_role('button',name='Show answer & feedback').click();expect(page.locator('.coach-answer')).to_have_count(2)
   before_reads=len(activity_reads);page.evaluate("location.hash='translator'");page.wait_for_timeout(100);page.evaluate("location.hash='coach'");page.wait_for_timeout(250);assert len(activity_reads)>before_reads,'return must refresh retained Translator/Dictation counts'
   page.locator('.coach-activity-day').first.click();page.evaluate("document.dispatchEvent(new Event('visibilitychange'))");page.wait_for_timeout(200);page.keyboard.press('Escape');expect(page.locator('.coach-activity-day').first).to_be_focused()
   page.close()
   # Same actual app: failed check then explicit cancellation, no invented verdict.
   D=fresh();GATE.clear();MODE='error';page=browser.new_page(viewport={'width':width,'height':900 if width==1280 else 844},color_scheme=theme)
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
   page.goto(f'http://127.0.0.1:{server.server_port}/#coach');expect(page.locator('.coach-answer-editor input')).to_be_visible()
   page.locator('.coach-answer-editor input').fill('  gather 🙂  ');page.locator('#coach-input').fill('Keep exact discussion');page.get_by_role('button',name='Check',exact=True).click()
   expect(page.get_by_role('button',name='Stop',exact=True)).to_be_enabled();page.locator('.coach-menu-trigger').click();assert all(b.is_disabled() for b in page.get_by_role('menuitem').all());page.keyboard.press('Escape');GATE.set()
   expect(page.locator('.coach-assessment')).to_contain_text('Could not save');expect(page.locator('.coach-checking')).to_have_count(0);assert page.locator('.coach-answer').text_content()=='  gather 🙂  ';assert page.locator('.coach-incorrect').count()==0
   page.screenshot(path=str(out/f'{width}-{theme}-error.png'));page.get_by_role('button',name='Stop',exact=True).click();expect(page.locator('.coach-assessment')).to_contain_text('canceled');expect(page.locator('#coach-input')).to_have_value('Keep exact discussion')
   cdp=page.context.new_cdp_session(page);cdp.send('Emulation.setEmulatedMedia',{'features':[{'name':'prefers-color-scheme','value':theme},{'name':'prefers-reduced-motion','value':'reduce'},{'name':'prefers-reduced-transparency','value':'reduce'}]})
   assert page.locator('.coach-composer-shell').evaluate("e=>getComputedStyle(e).backdropFilter")=='none'
   page.screenshot(path=str(out/f'{width}-{theme}-canceled-reduced.png'))
   page.set_viewport_size({'width':width,'height':520});page.locator('#coach-input').focus();assert page.locator('.coach-composer-shell').bounding_box()['y']+page.locator('.coach-composer-shell').bounding_box()['height']<=520
   page.locator('#account').click();page.locator('#logout').click();expect(page.locator('#coach-input')).to_be_disabled();expect(page.locator('#coach-input')).to_have_value('');assert page.locator('.coach-answer').count()==0;assert page.locator('.coach-activity-detail').is_hidden();assert all(b.is_disabled() for b in page.locator('.coach-activity-day').all());page.close()
  assert not errors,errors
  (out/'receipt.json').write_text(json.dumps({'synthetic':True,'variants':4,'errors':errors,'actions':CALLS},ensure_ascii=False,indent=2))
  print('PASS: actual app 4 viewports/themes, literal typed answers, separate verdict, pending, Stop, context target, 30px activity, source details, history reveal, menu keyboard and drafts; '+str(out));browser.close()
finally:GATE.set();server.shutdown()
