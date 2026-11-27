"""Actual local UI, synthetic owner/activity; never calls a provider."""
from episode_fixture import Handler, STATE
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from datetime import date, timedelta, datetime
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import sync_playwright, expect
import json
OUT=Path(__file__).resolve().parents[2]/'docs/profile-activity-evidence'
OUT.mkdir(exist_ok=True)
CALLS=[]
SNAP=dict(turns=[dict(id='task',kind='context_translation',state='completed',target='vocabulary.word_choice',prompt='Ich muss das Paket abholen.',target_text='abholen',answer_language='en',message='Translate the highlighted word into English.',at='2026-11-27T10:00:00Z')],observations=[],actions=[dict(action=a,turn_id='task' if a in ['reveal','explain'] else '') for a in ['reveal','progress','more','explain','practice']])
class App(Handler):
 def reply(self,body,status=200):
  try:return super().reply(body,status)
  except (BrokenPipeError,ConnectionResetError):pass # Page/logout teardown can abort a read.
 def do_GET(self):
  if self.path.startswith('/v1/learning/activity?'):
   q=parse_qs(urlsplit(self.path).query);CALLS.append(q)
   start=date.fromisoformat(q['start'][0]);n=int(q.get('days',['7'])[0])
   days=[dict(date=(start+timedelta(days=i)).isoformat(),known_count=i%12,counts=dict(translator=i%12,coach=0,dictation=0,podcasts=0)) for i in range(n)]
   return self.reply(dict(days=days,time_zone=q['time_zone'][0],sources=dict(translator='retained',coach='retained',dictation='retained',podcasts='unsupported'),undated=2))
  if self.path=='/v1/learning/coach':return self.reply(SNAP)
  return super().do_GET()
 def do_POST(self):
  if self.path=='/v1/learning/coach':
   body=json.loads(self.rfile.read(int(self.headers['Content-Length'])));assert body['action'] in ['entry','seen'];STATE['calls'].append(('POST',self.path,body));return self.reply(SNAP)
  return self.mutate()
server=ThreadingHTTPServer(('127.0.0.1',0),App);Thread(target=server.serve_forever,daemon=True).start()
results=[]
try:
 with sync_playwright() as p:
  for engine in ['chromium','webkit']:
   browser=getattr(p,engine).launch()
   for width in [390,999,1000,1280]:
    for theme in ['light','dark']:
     STATE['signed']=True
     page=browser.new_page(viewport=dict(width=width,height=844),color_scheme=theme,timezone_id='Europe/Berlin')
     errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
     network=[]
     page.on('requestfailed',lambda r:network.append(dict(url=r.url,failure=r.failure)))
     page.on('console',lambda m:network.append(dict(console=m.text)) if m.type=='error' else None)
     page.on('response',lambda r:network.append(dict(url=r.url,status=r.status)) if r.status>=400 else None)
     page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en');localStorage.setItem('keinemagie:theme:v1','system')")
     page.clock.install(time=datetime(2026,11,27,12))
     page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
     week=page.locator('#coach .coach-activity-day')
     try:expect(week.first).to_be_enabled()
     except Exception:
      print(dict(engine=engine,width=width,theme=theme,errors=errors,network=network,url=page.url),flush=True);raise
     expect(week).to_have_count(7)
     assert page.locator('#coach .coach-activity-host').bounding_box()['height']==30
     expect(page.locator('#coach .activity-month-header')).to_be_hidden()
     assert week.first.evaluate("e=>getComputedStyle(e).backgroundColor")!='rgba(0, 0, 0, 0)','zero day must remain a styled square'
     page.locator('#coach-input').fill('Preserved draft 🦉')
     page.evaluate('scrollTo(0,0)')
     page.screenshot(path=str(OUT/f'{engine}-{width}-{theme}-week.png'))
     before=len(CALLS);posts=len([c for c in STATE['calls'] if c[0]=='POST'])
     page.locator('#account').click()
     expect(page.locator('#profile-cefr')).to_be_enabled()
     assert len(CALLS)==before,'opening profile must not fetch month'
     page.locator('#profile-activity-toggle').click()
     month=page.locator('#profile-activity .coach-activity-day')
     expect(month).to_have_count(30)
     expect(month.first).to_have_attribute('data-intensity','none')
     assert len(CALLS)==before+1,'one month read'
     assert page.locator('#profile-activity').bounding_box()['width']<=320
     assert month.first.bounding_box()['width']<=40
     assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
     page.locator('#account-dialog').evaluate('e=>e.scrollTop=0')
     page.screenshot(path=str(OUT/f'{engine}-{width}-{theme}-profile.png'))
     month.nth(2).click();expect(page.locator('#profile-activity .coach-activity-detail')).to_contain_text('Podcasts: Not supported')
     page.keyboard.press('Escape');expect(month.nth(2)).to_be_focused()
     page.get_by_role('button',name='Previous month',exact=True).click();expect(month).to_have_count(31)
     page.get_by_role('button',name='This month',exact=True).click();expect(month).to_have_count(30)
     before=len(CALLS)
     page.set_viewport_size(dict(width=390 if width>=1000 else 1280,height=844));page.wait_for_timeout(100)
     assert len(CALLS)==before,'resize must not fetch'
     page.locator('#profile-activity-toggle').click();page.locator('#profile-activity-toggle').click();page.wait_for_timeout(100)
     assert len(CALLS)==before,'disclosure must reuse same scope'
     page.locator('#close-account').click()
     expect(page.locator('#coach-input')).to_have_value('Preserved draft 🦉')
     assert len([c for c in STATE['calls'] if c[0]=='POST'])==posts,'profile navigation triggered AI action'
     expect(week).to_have_count(7)
     week.nth(2).click();expect(page.locator('#coach .coach-activity-detail')).to_contain_text('Translator: 2')
     page.keyboard.press('Escape');expect(week.nth(2)).to_be_focused()
     page.locator('#account').click();page.locator('#logout').click()
     expect(page.locator('#coach-input')).to_have_value('')
     expect(page.locator('#profile-activity')).to_be_hidden()
     assert not errors,errors
     results.append(dict(engine=engine,width=width,theme=theme,status='passed'));page.close()
   # A slow profile read must not steal focus from the month the user opened.
   STATE['signed']=True
   page=browser.new_page(viewport=dict(width=1280,height=844))
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
   pending=[];page.route('**/v1/learning/profiles/*',lambda route:pending.append(route))
   page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
   expect(page.locator('#coach-input')).to_be_enabled()
   page.locator('#account').click();page.locator('#profile-activity-toggle').click()
   day=page.locator('#profile-activity .coach-activity-day').nth(2)
   day.click();page.keyboard.press('Escape');expect(day).to_be_focused()
   assert len(pending)==1
   pending[0].fulfill(json=dict(language='de',cefr='B1',self_assessments=[]))
   expect(page.locator('#profile-cefr')).to_be_enabled();expect(day).to_be_focused()
   page.close();results.append(dict(engine=engine,scenario='late-profile-focus',status='passed'))
   browser.close()
 (OUT/'browser-results.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
finally:server.shutdown()
