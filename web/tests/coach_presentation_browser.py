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
   scheme=os.environ.get('KM_COACH_COLOR_SCHEME','dark')
   page=browser.new_page(viewport={'width':390,'height':844},color_scheme=scheme,reduced_motion='reduce');errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   from datetime import datetime, timezone
   page.clock.install(time=datetime(2026,10,25,12,tzinfo=timezone.utc))
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1',"+json.dumps(locale)+")")
   page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
   try: page.get_by_text(waiting,exact=True).wait_for()
   except Exception:
    page.screenshot(path=str(evidence/f'failure-{locale}-{scheme}.png'))
    print('LOAD_FAILURE',locale,page.evaluate('document.visibilityState'),errors,page.locator('body').inner_text())
    raise
   page.wait_for_timeout(300)
   gap=lambda:page.locator('.coach-messages').evaluate('(e)=>e.scrollHeight-e.clientHeight-e.scrollTop')
   assert gap()<3,('initial bottom',locale,gap())
   assert page.locator('[data-turn=archived]').count()==0
   assert page.locator('[data-turn=correct].coach-success').count()==1
   assert page.locator('[data-turn=wrong].coach-incorrect').count()==1
   assert page.locator('[data-coach-source],.coach-bubble blockquote').count()==0
   assert 'internal-only' not in page.locator('.coach-messages').inner_text()
   hint=page.locator('.coach-command-menu button');assert hint.count()==1,'Contextual Hint must remain'
   page.locator('#coach-input').fill('hint preserves draft');page.locator('.coach-menu-trigger').click();hint.click();page.wait_for_timeout(200)
   assert any(c.get('action')=='reveal' and c.get('text')=='source' and c.get('turn_id')=='waiting' for c in CALLS)
   assert page.locator('[data-turn=waiting] .coach-hint').is_visible()
   assert page.locator('#coach-input').input_value()=='hint preserves draft'
   page.locator('#coach-input').fill('')
   page.screenshot(path=str(evidence/f'web-{locale}-{scheme}.png'))
   # Read actual computed foreground/backgrounds, including placeholder rules.
   samples=page.evaluate('''() => {
    const rgba=s=>{const m=s.match(/[\\d.]+/g).map(Number);return [m[0]/255,m[1]/255,m[2]/255,m[3]??1]};
    const over=(a,b)=>[0,1,2].map(i=>a[i]*a[3]+b[i]*(1-a[3])).concat(1);
    const bg=e=>{if(!e)return [1,1,1,1];const c=rgba(getComputedStyle(e).backgroundColor);return over(c,e.parentElement?bg(e.parentElement):(matchMedia('(prefers-color-scheme: dark)').matches?[.07,.07,.07,1]:[1,1,1,1]))};
    const lum=c=>c.slice(0,3).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((v,x,i)=>v+x*[.2126,.7152,.0722][i],0);
    return ['.coach-task-status','.coach-prompt','.coach-answer','.coach-exercise input','#coach-input'].map(s=>{const e=document.querySelector(s);const p=e.matches('input,textarea')?'::placeholder':null;const style=getComputedStyle(e,p),back=bg(e),fore=over(rgba(style.color),back),a=lum(fore),b=lum(back);return {selector:s,color:style.color,background:back,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)}});
   }''')
   assert all(s['ratio']>=4.5 for s in samples),samples
   (evidence/f'contrast-{locale}-{scheme}.json').write_text(json.dumps(samples,indent=2))
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
  # Large archives use a replacement page, not an ever-growing native/web stack.
  for count in [200,1000]:
   D['turns']=[exercise('old-'+str(i),at='2020-01-01T00:00:00Z') for i in range(count)]+[row('new')]
   D['actions']=[{'action':'reveal','turn_id':'old-'+str(count-1)}]
   page=browser.new_page(viewport={'width':390,'height':844},color_scheme='light');page.clock.install(time=datetime(2026,10,25,12,tzinfo=timezone.utc))
   start=time.perf_counter();page.goto(f'http://127.0.0.1:{server.server_port}/#coach');page.locator('.coach-active-earlier').wait_for();initial=time.perf_counter()-start
   assert page.locator('[data-turn]').count()==1
   start=time.perf_counter();page.locator('.coach-active-earlier').click();page.locator(f'[data-turn="old-{count-50}"]').wait_for();reveal=time.perf_counter()-start
   assert page.locator('[data-turn]').count()==51
   assert page.locator('[data-turn="old-0"]').count()==0
   page.get_by_role('button',name='Earlier',exact=True).click();assert page.locator('[data-turn]').count()==51
   assert page.locator(f'[data-turn="old-{count-100}"]').count()==1
   print('WEB_BENCH',json.dumps({'archive':count,'initial_s':initial,'reveal_s':reveal,'rendered':51}))
   page.close()
  browser.close()
 print('PASS five locales: history/reload, green correct + muted-red wrong, source absent, initial/own send bottom, manual reading+draft, resize, asynchronous layout. Evidence:',evidence)
finally:server.shutdown()
