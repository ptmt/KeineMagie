"""Actual local app, synthetic API only; responsive activity acceptance."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from datetime import date, timedelta
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import sync_playwright
import json
OUT=Path(__file__).resolve().parents[2]/'docs/responsive-activity-evidence'
OUT.mkdir(exist_ok=True)
CALLS=[]
class App(Handler):
 def do_GET(self):
  if self.path.startswith('/v1/learning/activity?'):
   q=parse_qs(urlsplit(self.path).query);CALLS.append(q)
   start=date.fromisoformat(q['start'][0]);n=int(q.get('days',['7'])[0])
   days=[dict(date=(start+timedelta(days=i)).isoformat(),known_count=3,counts=dict(translator=3,coach=0,dictation=0,podcasts=0)) for i in range(n)]
   return self.reply(dict(days=days,time_zone=q['time_zone'][0],sources={s:'retained' for s in ['translator','coach','dictation','podcasts']},undated=2))
  if self.path=='/v1/learning/coach':return self.reply(dict(turns=[],observations=[],actions=[]))
  return super().do_GET()
 def do_POST(self):
  if self.path=='/v1/learning/coach':
   body=json.loads(self.rfile.read(int(self.headers['Content-Length'])));assert body['action'] in ['entry','seen'];return self.reply(dict(turns=[],observations=[],actions=[]))
  return self.mutate()
server=ThreadingHTTPServer(('127.0.0.1',0),App);Thread(target=server.serve_forever,daemon=True).start()
results=[]
try:
 with sync_playwright() as p:
  for engine in ['chromium','webkit']:
   browser=getattr(p,engine).launch()
   for width in [390,999,1000,1280]:
    for theme in ['light','dark']:
     page=browser.new_page(viewport={'width':width,'height':844},color_scheme=theme,timezone_id='Europe/Berlin')
     errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
     page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en');localStorage.setItem('keinemagie:theme:v1','system')")
     page.clock.install(time=__import__('datetime').datetime(2026,11,26,12))
     page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
     page.wait_for_selector('.coach-activity-day[data-intensity="2"]')
     assert page.locator('.coach-activity-day').count()==(30 if width>=1000 else 7), (engine,width,'wrong range')
     assert page.locator('.activity-month-header button').count()==(4 if width>=1000 else 0)
     assert page.locator('.activity-weekday').count()==(7 if width>=1000 else 0)
     assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'), (engine,width,page.evaluate('({w:innerWidth,scroll:document.documentElement.scrollWidth,bad:[...document.querySelectorAll("body *")].filter(e=>e.getBoundingClientRect().right>innerWidth).map(e=>[e.tagName,e.className,e.getBoundingClientRect().right])})'))
     if width<1000:
      assert page.locator('.coach-activity-host').bounding_box()['height']==30
      assert page.locator('.coach-activity-day').first.inner_text()=='S'
     page.evaluate('scrollTo(0,0)')
     page.screenshot(path=str(OUT/f'{engine}-{width}-{theme}.png'))
     # The same real control opens details and restores focus in both layouts.
     chosen='2026-11-26'
     page.locator(f'[data-activity-date="{chosen}"]').click()
     assert 'Translator: 3' in page.locator('.coach-activity-detail').inner_text()
     page.screenshot(path=str(OUT/f'{engine}-{width}-{theme}-detail.png'))
     page.keyboard.press('Escape')
     assert page.evaluate('document.activeElement.dataset.activityDate')==chosen
     before=len(CALLS)
     page.set_viewport_size({'width':998 if width<1000 else 1001,'height':844})
     page.wait_for_timeout(200)
     assert len(CALLS)==before,'same-mode resize fetched'
     # Selected historical date survives month -> week -> month, including
     # a week straddling two months, without hidden month controls.
     page.set_viewport_size({'width':1000,'height':844})
     page.wait_for_selector('.activity-month-header button')
     page.get_by_role('button',name='Previous month',exact=True).click()
     page.wait_for_selector('[data-activity-date="2026-10-01"][data-intensity="2"]')
     page.locator('[data-activity-date="2026-10-01"]').click()
     page.set_viewport_size({'width':999,'height':844})
     page.wait_for_function("() => document.querySelectorAll('.coach-activity-day').length===7 && document.querySelector('[data-activity-date=\"2026-10-01\"]')?.dataset.intensity==='2'")
     assert page.locator('.coach-activity-day').first.get_attribute('data-activity-date')=='2026-09-27'
     assert '2026-10-01' in page.locator('.coach-activity-detail').inner_text()
     assert page.locator('.activity-month-header button').count()==0
     page.set_viewport_size({'width':1000,'height':844})
     page.wait_for_function("() => document.querySelectorAll('.coach-activity-day').length===31 && document.querySelector('[data-activity-date=\"2026-10-01\"]')?.dataset.intensity==='2'")
     assert '2026-10-01' in page.locator('.coach-activity-detail').inner_text()
     page.keyboard.press('Escape')
     page.get_by_role('button',name='This month',exact=True).click()
     page.wait_for_selector('[data-activity-date="2026-11-26"][data-intensity="2"]')
     page.get_by_role('link',name='Translator',exact=True).click()
     page.wait_for_timeout(200)
     before=len(CALLS)
     page.set_viewport_size({'width':390,'height':844});page.wait_for_timeout(300)
     assert len(CALLS)==before,'hidden Coach resize fetched activity'
     page.get_by_role('link',name='Coach',exact=True).click()
     page.wait_for_selector('.coach-activity-day[data-intensity="2"]')
     assert page.locator('.coach-activity-day').count()==7
     assert not errors,errors
     results.append(dict(engine=engine,width=width,theme=theme,status='passed'))
     page.close()
   # Controlled promises deliberately ignore abort: exercise the production
   # mount's epoch fence, not just transport cancellation, in each browser.
   probe=browser.new_page(viewport={'width':1000,'height':844})
   probe.goto(f'http://127.0.0.1:{server.server_port}/coach.css')
   probe.evaluate("""async () => {
    const {mountCoachActivity}=await import('/coach-activity.mjs');
    document.body.replaceChildren();const host=document.createElement('div');document.body.append(host);
    window.calls=[];window.probe=mountCoachActivity({host,document,locale:()=> 'en',now:()=>new Date(2026,10,26,12),api:{request:(url,options)=>new Promise((resolve,reject)=>calls.push({url,options,resolve,reject}))}});
    window.finish=(i,n)=>{const q=new URL(calls[i].url,location.href).searchParams,start=new Date(q.get('start')+'T12:00:00');calls[i].resolve({time_zone:q.get('time_zone'),sources:{translator:'retained'},days:Array.from({length:+q.get('days')},(_,j)=>{const d=new Date(start);d.setDate(d.getDate()+j);return {date:[d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-'),known_count:n,counts:{translator:n}}})});};
    probe.sync('owner-a');
   }""")
   assert probe.evaluate('calls.length')==1
   probe.bring_to_front()
   probe.set_viewport_size({'width':999,'height':844})
   probe.wait_for_function('() => calls.length===2')
   assert probe.evaluate('calls.length')==2
   assert probe.evaluate('calls[0].options.signal.aborted')
   assert probe.evaluate("new URL(calls[1].url,location.href).searchParams.get('days')")=='7'
   probe.evaluate('finish(1,3);finish(0,99)')
   probe.wait_for_timeout(30)
   assert probe.locator('.coach-activity-day[data-intensity="2"]').count()==7
   # Rapid threshold oscillation is coalesced, same-mode changes do nothing.
   before=probe.evaluate('calls.length')
   probe.clock.install(time=__import__('datetime').datetime(2026,11,26,12))
   probe.clock.pause_at(__import__('datetime').datetime(2026,11,26,12))
   for w in [1000,999,1000,999,1000]:
    probe.set_viewport_size({'width':w,'height':844});probe.wait_for_timeout(50)
   assert probe.evaluate('calls.length')==before,'debounce issued a read before settling'
   probe.clock.run_for(151);probe.clock.resume()
   assert probe.evaluate('calls.length')==before+1, (engine,before,probe.evaluate('calls.length'))
   probe.evaluate('finish(calls.length-1,6)');probe.wait_for_timeout(20)
   assert probe.locator('.coach-activity-day[data-intensity="3"]').count()==30
   # Navigate while pending, then switch owner before either response settles.
   probe.get_by_role('button',name='Previous month',exact=True).click()
   old=probe.evaluate('calls.length-1')
   probe.set_viewport_size({'width':390,'height':844});probe.wait_for_timeout(250)
   pending=probe.evaluate('calls.length-1')
   assert probe.evaluate(f'calls[{old}].options.signal.aborted')
   probe.evaluate("probe.sync('owner-b')")
   assert probe.evaluate(f'calls[{pending}].options.signal.aborted')
   probe.evaluate(f'finish({old},99);finish({pending},99);finish(calls.length-1,1)');probe.wait_for_timeout(30)
   assert probe.locator('.coach-activity-day[data-intensity="1"]').count()==7
   before=probe.evaluate('calls.length')
   probe.evaluate('probe.destroy()');probe.set_viewport_size({'width':1280,'height':844});probe.wait_for_timeout(250)
   assert probe.evaluate('calls.length')==before
   results.append(dict(engine=engine,scenario='pending-resize-navigation-owner-destroy',status='passed'))
   probe.close();browser.close()
 (OUT/'browser-results.json').write_text(json.dumps(results,indent=2))
 print(json.dumps(results,indent=2))
finally:server.shutdown()
