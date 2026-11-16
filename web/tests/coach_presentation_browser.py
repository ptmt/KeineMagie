"""Production UI + synthetic HTTP only; no private data or AI."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright
import json, os, time
NOW='2026-10-25T12:00:00Z'
def row(id,at=NOW,**extra):return dict(id=id,text='',state='completed',at=at,assisted=False,language='de',kind='clarification',message='Synthetic saved conversation '+id+'. '+('Context for manual reading. '*12),**extra)
def exercise(id,outcome=None,at=NOW):
 r=row(id,at);r.update(kind='cloze',prompt='Ich warte ___ den Bus.',source_id='translation:internal-only',quote='Never show source metadata',source_reveals=1,explanation='warten auf + Akkusativ',answer_reveals=1)
 if outcome:r['attempt']=dict(id='a'+id,answer='literal answer',outcome=outcome,at=at,assessment_state='completed')
 return r
D={'turns':[exercise('archived','wrong','2026-10-20T00:00:00Z')]+[row(str(i)) for i in range(18)]+[exercise('correct','correct'),exercise('wrong','wrong'),exercise('waiting')],'observations':[],'model':'fixture','actions':[{'action':'reveal','turn_id':'waiting'}]};CALLS=[]
class Chat(Handler):
 def do_GET(self):
  if self.path=='/v1/learning/coach':return self.reply(D)
  return super().do_GET()
 def do_POST(self):
  if self.path!='/v1/learning/coach':return self.mutate()
  b=json.loads(self.rfile.read(int(self.headers['Content-Length'])));CALLS.append(b)
  if b['action']=='message':
   time.sleep(.15);D['turns'].append(row('arrival'+str(len(CALLS))))
  return self.reply(D)
server=ThreadingHTTPServer(('127.0.0.1',0),Chat);Thread(target=server.serve_forever,daemon=True).start()
evidence=Path(os.environ['TMPDIR'])/'coach-history-evidence';evidence.mkdir(exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  for locale,earlier,waiting in [('en','Earlier','Awaiting answer'),('de','Früher','Antwort ausstehend'),('ru','Ранее','Ожидает ответа'),('es','Anteriores','Esperando respuesta'),('fr','Plus tôt','En attente de réponse')]:
   page=browser.new_page(viewport={'width':390,'height':844},color_scheme='dark',reduced_motion='reduce');errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   from datetime import datetime, timezone
   page.clock.install(time=datetime(2026,10,25,12,tzinfo=timezone.utc))
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1',"+json.dumps(locale)+")")
   page.goto(f'http://127.0.0.1:{server.server_port}/#coach');page.get_by_text(waiting,exact=True).wait_for();page.wait_for_timeout(300)
   gap=lambda:page.locator('.coach-messages').evaluate('(e)=>e.scrollHeight-e.clientHeight-e.scrollTop')
   assert gap()<3,('initial bottom',locale,gap())
   assert page.locator('[data-turn=archived]').count()==0
   assert page.locator('[data-turn=correct].coach-completed').count()==1
   assert page.locator('[data-turn=wrong].coach-completed').count()==1
   assert page.locator('[data-coach-source],.coach-bubble blockquote').count()==0
   assert 'internal-only' not in page.locator('.coach-messages').inner_text()
   hint=page.locator('.coach-quick button');assert hint.count()==1,'Contextual Hint must remain'
   page.locator('#coach-input').fill('hint preserves draft');hint.click();page.wait_for_timeout(200)
   assert any(c.get('action')=='reveal' and c.get('text')=='source' and c.get('turn_id')=='waiting' for c in CALLS)
   assert page.locator('[data-turn=waiting] .coach-hint').is_visible()
   assert page.locator('#coach-input').input_value()=='hint preserves draft'
   page.locator('#coach-input').fill('')
   page.screenshot(path=str(evidence/f'web-{locale}-dark.png'))
   page.locator('.coach-messages').evaluate('(e)=>e.scrollTop=0');page.wait_for_timeout(100)
   page.get_by_role('button',name=earlier,exact=True).click();assert page.locator('[data-turn=archived]').count()==1
   page.locator('#coach-input').fill('keep draft while reading');before=page.locator('.coach-messages').evaluate('(e)=>e.scrollTop')
   page.set_viewport_size({'width':390,'height':600});page.wait_for_timeout(100)
   assert abs(page.locator('.coach-messages').evaluate('(e)=>e.scrollTop')-before)<3
   # A refresh arriving while reading must not follow or erase the exact draft.
   D['turns'].append(row('background-'+locale))
   page.evaluate("Object.defineProperty(document,'visibilityState',{configurable:true,value:'hidden'});document.dispatchEvent(new Event('visibilitychange'));Object.defineProperty(document,'visibilityState',{configurable:true,value:'visible'});document.dispatchEvent(new Event('visibilitychange'))")
   page.wait_for_timeout(300)
   assert abs(page.locator('.coach-messages').evaluate('(e)=>e.scrollTop')-before)<3
   assert page.locator('#coach-input').input_value()=='keep draft while reading'
   page.locator('.coach-jump').click();page.wait_for_timeout(100);assert gap()<3
   # Asynchronous spoiler/explanation height follows only at bottom.
   page.locator('[data-turn=waiting]').evaluate("e=>{const p=document.createElement('p');p.textContent='asynchronous layout '.repeat(200);e.append(p)}")
   page.wait_for_timeout(500);assert gap()<3,('async',gap(),page.locator('.coach-messages').evaluate('(e)=>[e.scrollTop,e.scrollHeight,e.clientHeight]'));page.wait_for_timeout(100)
   page.locator('.coach-messages').dispatch_event('wheel',{'deltaY':-900});page.locator('.coach-messages').evaluate('(e)=>e.scrollTop=0');page.wait_for_timeout(100)
   page.locator('.coach-composer button[type=submit]').click();page.wait_for_timeout(400);assert gap()<3,('own send',gap())
   page.reload();page.wait_for_timeout(300);assert page.locator('[data-turn=archived]').count()==0;assert gap()<3
   assert not errors,errors
   page.close()
  browser.close()
 print('PASS five locales: history/reload, neutral correct+wrong, source absent, initial/own send bottom, manual reading+draft, resize, asynchronous layout. Evidence:',evidence)
finally:server.shutdown()
