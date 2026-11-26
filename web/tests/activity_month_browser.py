"""Local production app, synthetic retained counts, no external requests/inference."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
from datetime import date,timedelta
import json
from playwright.sync_api import sync_playwright
OUT=Path(__file__).resolve().parents[2]/'docs/monthly-activity-evidence'
OUT.mkdir(exist_ok=True)
MODE='ready';CALLS=[]
SNAP={'turns':[],'observations':[],'actions':[]}
class App(Handler):
 def reply(self,body,status=200):
  try:return super().reply(body,status)
  except (BrokenPipeError,ConnectionResetError):pass # Expected aborted navigation reads.
 def do_GET(self):
  global MODE
  if self.path.startswith('/v1/learning/activity?'):
   q=parse_qs(urlsplit(self.path).query);CALLS.append(q)
   if MODE=='offline':return self.reply({},503)
   if MODE=='go':return self.reply(json.loads((OUT/'go-month-wire.json').read_text()))
   start=date.fromisoformat(q['start'][0]);n=7 if MODE=='old' else int(q.get('days',['7'])[0])
   days=[]
   for i in range(n):
    d=start+timedelta(days=i);count=0 if MODE=='unknown' else [0,1,3,6,12][d.day%5]
    days.append(dict(date=d.isoformat(),known_count=count,coverage='partial',counts=dict(translator=count,coach=0,dictation=0,podcasts=0)))
   return self.reply(dict(version=1,time_zone=q['time_zone'][0],days=days,sources={s:('unavailable' if MODE=='unknown' else 'retained') for s in ['translator','coach','dictation','podcasts']},undated=2))
  if self.path=='/v1/learning/coach':return self.reply(SNAP)
  return super().do_GET()
 def do_POST(self):
  if self.path=='/v1/learning/coach':
   body=json.loads(self.rfile.read(int(self.headers['Content-Length'])));assert body['action'] in ['entry','seen'];return self.reply(SNAP)
  return self.mutate()
server=ThreadingHTTPServer(('127.0.0.1',0),App);Thread(target=server.serve_forever,daemon=True).start()
results=[]
try:
 with sync_playwright() as p:
  for engine in ['chromium','webkit']:
   browser=getattr(p,engine).launch()
   for width in [1280,390]:
    for theme in ['light','dark']:
     MODE='ready'
     page=browser.new_page(viewport={'width':width,'height':900 if width>500 else 844},color_scheme=theme,timezone_id='Europe/Berlin')
     errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
     page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en');localStorage.setItem('keinemagie:theme:v1','system')")
     page.clock.install(time=__import__('datetime').datetime(2026,11,26,12))
     page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
     page.wait_for_function("() => document.querySelectorAll('.coach-activity-day').length===30 && document.querySelector('[data-intensity=\"4\"]')")
     assert page.locator('.activity-weekday').count()==7
     colors=page.locator('.coach-activity-day').evaluate_all("es=>Object.fromEntries(es.map(e=>[e.dataset.intensity,getComputedStyle(e).backgroundColor]))")
     assert len(set(colors.values()))==5,colors
     import re
     def luminance(rgb):
      c=[int(v)/255 for v in re.findall(r'\d+',rgb)[:3]]
      return sum(w*(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4) for w,v in zip([.2126,.7152,.0722],c))
     contrasts=[]
     for bg,fg in page.locator('.coach-activity-day').evaluate_all("es=>es.map(e=>[getComputedStyle(e).backgroundColor,getComputedStyle(e).color])"):
      a,b=sorted([luminance(bg),luminance(fg)]);contrasts.append((b+.05)/(a+.05))
     assert min(contrasts)>=4.5,min(contrasts)
     assert page.locator('[aria-current=date]').count()==1
     assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
     page.screenshot(path=str(OUT/f'{engine}-{width}-{theme}.png'))
     page.locator('[data-activity-date="2026-11-04"]').click();assert '12' in page.locator('.coach-activity-detail').inner_text();assert 'Translator: 12' in page.locator('.coach-activity-detail').inner_text()
     assert page.locator('.coach-activity-detail').evaluate("e=>{const l=document.querySelector('.activity-legend').getBoundingClientRect(),r=e.getBoundingClientRect();return e.contains(document.elementFromPoint(r.left+30,Math.min(l.top+3,r.bottom-5)));}")
     page.screenshot(path=str(OUT/f'{engine}-{width}-{theme}-detail.png'))
     page.keyboard.press('Escape');assert page.locator('.coach-activity-detail').is_hidden()
     page.get_by_role('button',name='Previous month',exact=True).click();page.wait_for_function("() => document.querySelectorAll('.coach-activity-day').length===31")
     page.get_by_role('button',name='This month',exact=True).click();page.wait_for_function("() => document.querySelectorAll('.coach-activity-day').length===30")
     MODE='offline';page.get_by_role('button',name='Refresh',exact=True).click();page.wait_for_function("() => document.querySelector('.activity-month-summary').textContent.includes('failed')")
     assert page.locator('[data-intensity="4"]').count()>0
     MODE='ready';page.get_by_role('button',name='Refresh',exact=True).click();page.wait_for_function("() => document.querySelector('.activity-month-summary').textContent.includes('lower bound')")
     for year,month,count in [(2026,2,28),(2024,2,29),(2026,3,31)]:
      page.clock.set_system_time(__import__('datetime').datetime(year,month,15,12));page.get_by_role('button',name='This month',exact=True).click();page.wait_for_function(f"() => document.querySelectorAll('.coach-activity-day').length==={count}")
     # Month rollover through actual visibility lifecycle; follows current month.
     page.clock.set_system_time(__import__('datetime').datetime(2026,4,1,0,1));page.evaluate("document.dispatchEvent(new Event('visibilitychange'))")
     page.wait_for_function("() => document.querySelector('[data-activity-date=\"2026-04-30\"]')")
     MODE='old';before=len(CALLS);page.get_by_role('button',name='Refresh',exact=True).click()
     page.wait_for_function("() => document.querySelectorAll('.coach-activity-day[data-intensity=unknown]').length===0")
     page.wait_for_timeout(200)
     assert len(CALLS)-before==5,(engine,len(CALLS)-before)
     MODE='unknown';page.get_by_role('button',name='Refresh',exact=True).click()
     page.wait_for_function("() => document.querySelectorAll('.coach-activity-day[data-intensity=unknown]').length===30")
     assert page.locator('.activity-month-summary').inner_text()=='Unavailable'
     page.screenshot(path=str(OUT/f'{engine}-{width}-{theme}-unknown.png'))
     MODE='offline';page.get_by_role('button',name='Next month',exact=True).click()
     page.wait_for_function("() => document.querySelector('.activity-month-summary').textContent==='Unavailable'")
     assert page.locator('.coach-activity-day[data-intensity=unknown]').count()==31
     MODE='ready';page.get_by_role('button',name='Refresh',exact=True).click()
     page.wait_for_function("() => document.querySelectorAll('.coach-activity-day[data-intensity=unknown]').length===0")
     MODE='go';page.clock.set_system_time(__import__('datetime').datetime(2026,10,26,12));page.get_by_role('button',name='This month',exact=True).click()
     page.wait_for_function("() => document.querySelector('[data-activity-date=\"2026-10-19\"]')?.dataset.intensity==='1' && document.querySelectorAll('[data-intensity=\"1\"]').length===1")
     page.screenshot(path=str(OUT/f'{engine}-{width}-{theme}-go-wire.png'))
     assert not errors,errors
     results.append(dict(engine=engine,width=width,theme=theme,colors=colors,status='passed'))
     page.close()
   browser.close()
 (OUT/'browser-results.json').write_text(json.dumps(results,indent=2))
 print(json.dumps(results,indent=2))
finally:server.shutdown()
