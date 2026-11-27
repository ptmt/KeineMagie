"""Production activity mounts, controlled promises ignoring AbortSignal."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
import json
OUT=Path(__file__).resolve().parents[2]/'docs/profile-activity-evidence'
server=ThreadingHTTPServer(('127.0.0.1',0),Handler);Thread(target=server.serve_forever,daemon=True).start()
results=[]
try:
 with sync_playwright() as p:
  for engine in ['chromium','webkit']:
   browser=getattr(p,engine).launch();page=browser.new_page(viewport=dict(width=1280,height=844))
   page.goto(f'http://127.0.0.1:{server.server_port}/coach.css')
   page.evaluate("""async()=>{
    const {mountCoachActivity}=await import('/coach-activity.mjs');document.body.replaceChildren();
    window.calls=[];window.shown=true;window.language='en';
    window.make=(mode)=>{const host=document.createElement('div');host.id=mode;document.body.append(host);return mountCoachActivity({host,mode,document,active:()=>shown,locale:()=>language,now:()=>new Date(2026,10,27,12),api:{request:(url,options)=>new Promise((resolve,reject)=>calls.push({url,options,resolve,reject}))}});};
    window.finish=(i,n)=>{const q=new URL(calls[i].url,location.href).searchParams,start=new Date(q.get('start')+'T12:00:00');calls[i].resolve({time_zone:q.get('time_zone'),sources:{translator:'retained'},days:Array.from({length:+q.get('days')},(_,j)=>{const d=new Date(start);d.setDate(d.getDate()+j);return {date:[d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-'),known_count:n,counts:{translator:n}}})});};
    window.week=make('week');window.month=make('month');week.sync('a');month.sync('a');
   }""")
   assert page.evaluate('calls.length')==2
   page.evaluate('finish(0,1);finish(1,3)')
   expect(page.locator('#week [data-intensity="1"]')).to_have_count(7)
   expect(page.locator('#month [data-intensity="2"]')).to_have_count(30)
   page.set_viewport_size(dict(width=390,height=844));page.wait_for_timeout(200)
   assert page.evaluate('calls.length')==2
   for locale in ['de','ru','es','fr','en']:
    before=page.evaluate('calls.length');page.evaluate('(l)=>{language=l;month.sync("a")}',locale)
    assert page.evaluate('calls.length')==before,'month locale changed read scope'
   page.get_by_role('button',name='Previous month',exact=True).click()
   page.get_by_role('button',name='Next month',exact=True).click()
   assert page.evaluate('calls[2].options.signal.aborted')
   page.evaluate('finish(3,6);finish(2,99)')
   expect(page.locator('#month [data-intensity="3"]')).to_have_count(30)
   expect(page.locator('#week [data-intensity="1"]')).to_have_count(7)
   # Closing/logout fences even a transport that ignores abort.
   page.get_by_role('button',name='Previous month',exact=True).click()
   page.evaluate('shown=false;month.clear();finish(4,99)')
   expect(page.locator('#month [data-intensity="4"]')).to_have_count(0)
   assert page.evaluate('calls[4].options.signal.aborted')
   before=page.evaluate('calls.length');page.evaluate('month.refresh();document.dispatchEvent(new Event("visibilitychange"))')
   assert page.evaluate('calls.length')==before
   # Owner replacement with late success and late error.
   page.evaluate('shown=true;month.sync("a");month.sync("b")')
   assert page.evaluate('calls[5].options.signal.aborted')
   page.evaluate('finish(6,1);finish(5,99)')
   expect(page.locator('#month [data-intensity="1"]')).to_have_count(30)
   page.evaluate('month.refresh();month.sync("c");finish(8,3);calls[7].reject(new Error("late failure"))')
   expect(page.locator('#month [data-intensity="2"]')).to_have_count(30)
   assert 'failed' not in page.locator('#month .activity-month-summary').inner_text()
   page.evaluate('month.refresh();month.destroy();week.destroy();finish(9,99)')
   expect(page.locator('[data-intensity="4"]')).to_have_count(0)
   before=page.evaluate('calls.length');page.set_viewport_size(dict(width=1000,height=844));page.wait_for_timeout(200)
   assert page.evaluate('calls.length')==before
   results.append(dict(engine=engine,status='passed',scenario='range-owner-close-destroy-late-success-error-locale-resize'))
   browser.close()
 (OUT/'lifecycle-results.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
finally:server.shutdown()
