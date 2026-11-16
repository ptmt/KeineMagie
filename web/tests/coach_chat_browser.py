"""Synthetic transport exercising production Coach DOM; zero live inference."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright
import json,time
D={'turns':[],'observations':[],'model':'gpt-6.1-terra','actions':[{'action':'more','turn_id':''}]};CALLS=[];SEEN_DELAY=0
def turn(id,answered=False):
 t=dict(id=id,text='Synthetic practice',state='completed',at='now',assisted=False,language='de',message='Synthetic exercise — not live AI.',kind='cloze',prompt='Ich war einmal ___ diesem Kurs dabei.',target='verb_government',source_id='translation:synthetic',message_version=id+':completed',seen_version='',source_reveals=0,answer_reveals=0)
 if answered:t.update(attempt=dict(id='answer-'+id,answer='beim',outcome='wrong',original_outcome='wrong',assisted=False,at='now',excluded=False,assessment_state='completed',assessment=dict(verdict='incorrect',corrected_answer='bei',explanation='Synthetic: beim means bei dem.',uncertainty_reason='')),explanation='Synthetic: beim means bei dem.',quote='Ich war einmal bei diesem Kurs dabei.')
 return t
class Chat(Handler):
 def do_GET(self):
  if self.path=='/v1/learning/coach':return self.reply(D)
  return super().do_GET()
 def do_POST(self):
  if self.path!='/v1/learning/coach':return self.mutate()
  b=json.loads(self.rfile.read(int(self.headers['Content-Length'])));CALLS.append(b);assert self.headers.get('X-CSRF-Token')=='fixture-csrf'
  a=b['action'];t=next((t for t in D['turns'] if t['id']==b['turn_id']),None)
  if a=='entry':pass
  elif a=='seen':time.sleep(SEEN_DELAY);t['seen_version']=b['text']
  elif a=='reveal':t[b['text']+'_reveals']+=1
  elif a in ['message','more']:
   time.sleep(.35);D['turns'].append(turn(b['request_id']))
  return self.reply(D)
server=ThreadingHTTPServer(('127.0.0.1',0),Chat);Thread(target=server.serve_forever,daemon=True).start()
evidence=Path('/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence');evidence.mkdir(exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':1440,'height':1000});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  D['turns']=[turn('old',True),turn('latest',True)]
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  page.add_init_script("""window.historyMotion=[];const sample=()=>{for(const e of document.querySelectorAll('[data-turn]'))if(['old','latest'].includes(e.dataset.turn)){const s=getComputedStyle(e);window.historyMotion.push({id:e.dataset.turn,opacity:Number(s.opacity),animation:s.animationName});}if(window.historyMotion.length<180)requestAnimationFrame(sample);};requestAnimationFrame(sample);""")
  page.goto(f'http://127.0.0.1:{server.server_port}/#coach');page.get_by_role('button',name='More',exact=True).wait_for()
  page.wait_for_function("() => document.querySelectorAll('[data-turn]').length===2")
  old=page.locator('[data-turn="old"]');latest=page.locator('[data-turn="latest"]')
  assert old.locator('.coach-answer').count()==0 and old.locator('.coach-explanation').count()==0
  assert latest.locator('.coach-answer').inner_text()=='beim'
  page.wait_for_timeout(250)
  initial=page.evaluate('window.historyMotion')
  assert initial and all(f['animation']=='none' and f['opacity']==1 for f in initial),initial
  (evidence/'browser-initial-frames.json').write_text(json.dumps(initial,indent=2))
  old.get_by_role('button',name='Show answer & feedback').click();old.locator('.coach-answer').wait_for()
  assert any(b['action']=='reveal' and b['text']=='answer' for b in CALLS)
  page.screenshot(path=str(evidence/'desktop.png'))
  page.locator('#coach-input').fill('draft must stay')
  page.evaluate("document.querySelector('.coach-composer button').click();document.querySelector('.coach-composer button').click()")
  page.wait_for_function("() => !document.querySelector('.coach-composer button').disabled")
  assert len([b for b in CALLS if b['action'] in ['message','more']])==1
  assert page.locator('#coach-input').input_value()=='draft must stay'
  # Saved DOM bubbles retain identity through receipt refreshes.
  page.evaluate("window.savedBubble=document.querySelector('[data-turn=old]')")
  page.locator('#coach-input').press('Tab');page.wait_for_timeout(100)
  assert page.evaluate("window.savedBubble===document.querySelector('[data-turn=old]')")
  page.reload();page.locator('[data-turn=old] .coach-answer').wait_for()
  assert not page.locator('.coach-arrival').count(), 'rehydration animates history'
  # Entry now explicitly opens at bottom; manual-reading/async coverage lives
  # in coach_presentation_browser.py.
  D['turns']=[turn(str(i),True) for i in range(20)];page.reload()
  page.wait_for_timeout(400)
  assert page.locator('.coach-messages').evaluate('(e)=>e.scrollHeight-e.clientHeight-e.scrollTop')<3
  # Deterministic visibility events exercise the actual foreground handler, not a paid model.
  entries=len([b for b in CALLS if b['action']=='entry'])
  page.evaluate("Object.defineProperty(document,'visibilityState',{configurable:true,value:'hidden'});document.dispatchEvent(new Event('visibilitychange'))")
  D['turns'].append(turn('background'))
  page.get_by_role('link',name='Translator',exact=True).click();page.get_by_role('link',name='Coach',exact=True).click()
  page.wait_for_timeout(150)
  assert not any(b['action']=='seen' and b['turn_id']=='background' for b in CALLS)
  page.evaluate("Object.defineProperty(document,'visibilityState',{configurable:true,value:'visible'});document.dispatchEvent(new Event('visibilitychange'))")
  page.wait_for_timeout(250)
  assert len([b for b in CALLS if b['action']=='entry'])==entries+1,'foreground must consult server five-hour admission'
  entries+=1
  page.evaluate("Object.defineProperty(document,'visibilityState',{configurable:true,value:'hidden'});document.dispatchEvent(new Event('visibilitychange'));Object.defineProperty(document,'visibilityState',{configurable:true,value:'visible'});document.dispatchEvent(new Event('visibilitychange'))")
  page.wait_for_timeout(250)
  assert len([b for b in CALLS if b['action']=='entry'])==entries+1,'ordinary background return must consult server'
  # Both rows fit: a delayed receipt must not authorize the next row after tab hiding.
  D['turns']=[dict(turn('visible-a'),kind='clarification',message='Visible A'),dict(turn('visible-b'),kind='clarification',message='Visible B')]
  for t in D['turns']:t.pop('prompt',None)
  CALLS.clear();SEEN_DELAY=.5
  page.reload();page.wait_for_function("() => document.querySelectorAll('[data-turn]').length===2")
  deadline=time.monotonic()+3
  while not any(b['action']=='seen' and b['turn_id']=='visible-a' for b in CALLS) and time.monotonic()<deadline:
   page.locator('.coach-messages').evaluate('(e)=>{e.scrollTop=e.scrollHeight;e.dispatchEvent(new Event("scroll"))}');page.wait_for_timeout(20)
  assert any(b['action']=='seen' and b['turn_id']=='visible-a' for b in CALLS),'visibility probe must dispatch first receipt'
  page.evaluate("Object.defineProperty(document,'visibilityState',{configurable:true,value:'hidden'});document.dispatchEvent(new Event('visibilitychange'))")
  page.wait_for_timeout(700)
  assert not any(b['action']=='seen' and b['turn_id']=='visible-b' for b in CALLS),'continued receipts after background'
  SEEN_DELAY=0
  page.evaluate("Object.defineProperty(document,'visibilityState',{configurable:true,value:'visible'});document.dispatchEvent(new Event('visibilitychange'))")
  page.wait_for_timeout(200)
  page.set_viewport_size({'width':390,'height':844});page.emulate_media(color_scheme='dark',reduced_motion='reduce')
  page.locator('#coach-input').focus();page.screenshot(path=str(evidence/'mobile-dark-reduced.png'))
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
  assert page.locator('#coach-input').bounding_box()['y']<844
  assert page.locator('.coach-arrival').evaluate_all("rows=>rows.every(e=>getComputedStyle(e).animationName==='none')")
  assert not errors,errors
  print('PASS: masking/reveal persistence, one rapid-tap send, draft, keyed DOM, no rehydration motion, unread viewport, scrolled-up preservation, mobile dark reduced motion. Evidence:',evidence)
  browser.close()
finally:server.shutdown()
