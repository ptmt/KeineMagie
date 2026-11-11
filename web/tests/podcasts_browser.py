"""Run with browser_exec: synthetic API only; real shipped HTML/modules/CSS/art.
Local http.server on 8769 must serve web/. No live account/upstream is claimed.
"""
from pathlib import Path
from typing import TYPE_CHECKING, Any
if TYPE_CHECKING:
    def cdp(method: str, **kwargs: Any) -> Any: ...
    def goto_url(url: str) -> Any: ...
    def js(expression: str) -> Any: ...
    def fill_input(selector: str, text: str) -> Any: ...
    def capture_screenshot() -> str: ...
import json, time, shutil
out=Path('/Users/tinyserve/.hermes/cache/scratch/keinemagie-podcast-evidence')
out.mkdir(exist_ok=True)
fixture=r"""
Object.defineProperty(document,'hidden',{configurable:true,get:()=>false});
window.__calls=[];window.__owner='fixture-owner';window.__hold=true;window.__fail=false;
window.__feeds=[{id:'Feed_A',title:'Fixture · Deutsch im Alltag',artwork_url:'https://example.invalid/cover.png',latest_episode_title:'Fixture · Unterwegs in Berlin',episodes:[{id:'Episode_A',title:'Fixture · Unterwegs in Berlin',published:'2026-11-10'}]}];window.__jobs=[];
window.__job={id:'Job_A',feed_id:'Feed_A',episode_id:'Episode_A',title:'Fixture · Unterwegs in Berlin',state:'queued',progress:0,source_language:'de',target_language:'ru',segments:[]};
const nativeFetch=window.fetch.bind(window);
window.fetch=async(path,opts={})=>{
 if(!String(path).startsWith('/v1/'))return nativeFetch(path,opts);
 window.__calls.push({path,method:opts.method||'GET',body:opts.body?JSON.parse(opts.body):null,csrf:opts.headers?.['X-CSRF-Token'],credentials:opts.credentials});
 const reply=(v,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{'Content-Type':'application/json'}});
 if(path==='/v1/web/config')return reply({apple_available:true,csrf_token:'fixture-boot'});
 if(path==='/v1/web/session')return window.__owner?reply({user:{id:window.__owner},csrf_token:'fixture-csrf',provider:{connected:true,selected_model:'fixture-model'}}):reply({},401);
 if(path==='/v1/web/logout'){window.__owner=null;return new Response(null,{status:204});}
 if(path==='/v1/translations')return reply({items:[]});
 if(path==='/v1/podcasts/subscriptions'&&opts.method==='GET'){if(window.__hold)await new Promise(r=>window.__release=r);if(window.__fail)return reply({},503);return reply({items:window.__feeds});}
 if(path==='/v1/podcasts/subscriptions'&&opts.method==='POST')return reply(window.__feeds[0]);
 if(path.endsWith('/refresh'))return reply(window.__feeds[0]);
 if(opts.method==='DELETE'){if(path.includes('subscriptions'))window.__feeds=[];else window.__jobs=[];return new Response(null,{status:204});}
 if(path==='/v1/podcasts'&&opts.method==='POST'){if(window.__quota)return reply({},429);if(window.__prepareHold)await new Promise(r=>window.__prepareRelease=r);window.__jobs=[window.__job];return reply(window.__job,202);}
 if(path==='/v1/podcasts')return reply({items:window.__jobs,worker_available:true});
 if(path.endsWith('/cancel')){window.__job.state='canceled';return reply(window.__job);}
 if(path.endsWith('/retry')){window.__job.state='queued';return reply(window.__job);}
 if(path==='/v1/podcasts/Job_A')return reply(window.__job);
 return reply({},404);
};
window.confirm=()=>true;
"""
identifier=cdp('Page.addScriptToEvaluateOnNewDocument',source=fixture)['identifier']
goto_url('http://127.0.0.1:8769/?fixture='+str(time.time_ns())+'#podcasts')
time.sleep(.4)
checks=[]
def check(name,expression):
 value=js(expression);assert value is True,(name,value);checks.append(name)
def settle():time.sleep(.22)
def route(hash):js('location.hash='+json.dumps(hash));settle()
def clicktext(text):js('([...document.querySelectorAll("#podcast-content button")].find(b=>b.textContent==='+json.dumps(text)+')).click()');settle()
check('first load skeleton not empty flash',"document.querySelectorAll('.podcast-skeleton').length===3&&!document.querySelector('#podcast-content').textContent.includes('Noch keine')")
js('window.__hold=false;window.__release()');settle()
check('actual list title latest subtitle no subscribed heading',"document.querySelector('#podcast-content').textContent.includes('Unterwegs in Berlin')&&!document.querySelector('#podcast-content').textContent.includes('Abonniert')")
check('artwork URL is owner proxy only',"document.querySelector('.podcast-cover img').getAttribute('src')==='/v1/podcasts/subscriptions/Feed_A/artwork'")
check('artwork pixels load from same-origin fixture endpoint',"document.querySelector('.podcast-cover img').naturalWidth===128")
for width in [320,390,768,1440]:
 cdp('Emulation.setDeviceMetricsOverride',width=width,height=1000,deviceScaleFactor=1,mobile=width<700)
 check(f'library no overflow {width}','document.documentElement.scrollWidth<=innerWidth')
 if width in [320,1440]:shutil.copy(capture_screenshot(),out/f'library-{width}.png')
js("document.querySelector('#podcast-add').click()")
check('add dialog focused and defaults feed',"document.querySelector('#podcast-dialog').open&&document.querySelector('#podcast-dialog').contains(document.activeElement)&&document.querySelector('#podcast-source').value==='de'")
js("document.querySelector('#podcast-mode').value='episode';document.querySelector('#podcast-mode').dispatchEvent(new Event('change'))")
check('episode progressive disclosure',"!document.querySelector('#podcast-import-language').hidden&&document.querySelector('#podcast-submit').textContent==='Vorbereiten'")
shutil.copy(capture_screenshot(),out/'add-1440.png')
js("document.querySelector('#podcast-close').click()")
route('#translator');fill_input('#source-text','Fixture translator draft');route('#podcasts/feed/Feed_A')
check('feed route episode visible',"document.querySelector('#podcasts').checkVisibility()&&document.querySelector('.podcast-episode').textContent.includes('Vorbereiten')")
js("window.__prepareHold=true;let b=[...document.querySelectorAll('#podcast-content button')].find(b=>b.textContent==='Vorbereiten');b.click();b.dispatchEvent(new MouseEvent('click'))")
check('repeated preparation one POST',"window.__calls.filter(c=>c.path==='/v1/podcasts'&&c.method==='POST').length===1")
js('window.__prepareHold=false;window.__prepareRelease()');settle()
check('feed identity payload no audio URL',"JSON.stringify(window.__calls.find(c=>c.path==='/v1/podcasts'&&c.method==='POST').body)===JSON.stringify({feed_id:'Feed_A',episode_id:'Episode_A',source_language:'de'})")
for state,label in [('queued','In Warteschlange'),('fetching','Audio wird geladen'),('transcribing','Transkription läuft'),('translating','Übersetzung läuft'),('failed','Fehlgeschlagen'),('canceled','Abgebrochen'),('completed','Bereit')]:
 js('window.__job.state='+json.dumps(state));js("document.querySelector('#podcast-reload').click()");settle()
 check('real DOM status '+state,json.dumps(label)+"===document.querySelector('.podcast-progress').firstChild.textContent")
js("window.__job.state='queued'");route('#podcasts/job/Job_A');clicktext('Abbrechen')
check('cancel calls real API and reads exact job',"window.__calls.some(c=>c.path==='/v1/podcasts/Job_A/cancel'&&c.method==='POST')&&document.querySelector('.podcast-progress').textContent.includes('Abgebrochen')")
clicktext('Erneut versuchen')
check('retry calls real API and reads exact job',"window.__calls.some(c=>c.path==='/v1/podcasts/Job_A/retry'&&c.method==='POST')&&document.querySelector('.podcast-progress').textContent.includes('Warteschlange')")
js("window.__job.state='completed';window.__job.segments=[{start:2.5,end:8,text:'Fixture: Guten Morgen.',translation:'Пример: Доброе утро.'}]")
js("document.querySelector('#podcast-reload').click()");settle()
check('ready aligned original translation timestamps no player',"document.querySelector('.podcast-segments').textContent.includes('0:02–0:08')&&document.querySelector('.podcast-segments').textContent.includes('Доброе утро')&&!document.querySelector('audio,video')")
for width in [320,1440]:
 cdp('Emulation.setDeviceMetricsOverride',width=width,height=1000,deviceScaleFactor=1,mobile=width<700)
 check(f'reader no overflow {width}','document.documentElement.scrollWidth<=innerWidth');shutil.copy(capture_screenshot(),out/f'reader-{width}.png')
route('#translator');check('translator draft preserved',"document.querySelector('#source-text').value==='Fixture translator draft'")
route('#podcasts');check('feed job not duplicated as anonymous import',"!document.querySelector('#podcast-content').textContent.includes('Einzelne Folgen')")
js("document.querySelector('#podcast-add').click();document.querySelector('#podcast-mode').value='episode';document.querySelector('#podcast-mode').dispatchEvent(new Event('change'));document.querySelector('#podcast-url').value='https://public.example/episode.mp3';window.__quota=true;document.querySelector('#podcast-form').requestSubmit()");settle()
check('quota errors readable in add dialog',"document.querySelector('#podcast-add-error').textContent.includes('Podcast-Limit')&&document.querySelector('#podcast-dialog').open")
js("window.__quota=false;document.querySelector('#podcast-form').requestSubmit()");settle()
check('direct import submits selected source language',"window.__calls.some(c=>c.path==='/v1/podcasts'&&c.method==='POST'&&c.body.url==='https://public.example/episode.mp3'&&c.body.source_language==='de')")
route('#podcasts/feed/Feed_A');clicktext('Feed aktualisieren')
check('manual refresh mutation no implicit AI',"window.__calls.some(c=>c.path==='/v1/podcasts/subscriptions/Feed_A/refresh'&&c.method==='POST')")
route('#podcasts')
js("window.__fail=true;document.querySelector('#podcast-reload').click()");settle()
check('refresh error retains existing library',"document.querySelector('.podcast-feed')!==null&&document.querySelector('#podcast-notice').textContent.includes('nicht verfügbar')")
js("window.__fail=false;document.querySelector('#podcast-add').click();document.querySelector('#podcast-mode').value='feed';document.querySelector('#podcast-mode').dispatchEvent(new Event('change'));document.querySelector('#podcast-url').value='https://public.example/rss';document.querySelector('#podcast-form').requestSubmit()");settle()
check('subscription form calls API and reads library',"window.__calls.some(c=>c.path==='/v1/podcasts/subscriptions'&&c.method==='POST'&&c.body.url==='https://public.example/rss')&&!document.querySelector('#podcast-dialog').open")
route('#podcasts/job/Job_A');js('window.__confirmCount=0;window.confirm=()=>{window.__confirmCount++;return false;}');clicktext('Löschen')
check('delete confirmation can decline with no mutation',"window.__confirmCount===1&&!window.__calls.some(c=>c.path==='/v1/podcasts/Job_A'&&c.method==='DELETE')")
js('window.confirm=()=>{window.__confirmCount++;return true;}');clicktext('Löschen')
check('delete explicitly mutates and reads library',"window.__calls.some(c=>c.path==='/v1/podcasts/Job_A'&&c.method==='DELETE')&&location.hash==='#podcasts'")
route('#podcasts/feed/Feed_A');clicktext('Abo entfernen')
check('unsubscribe explicitly confirms deletes and reads library',"window.__confirmCount===3&&window.__calls.some(c=>c.path==='/v1/podcasts/subscriptions/Feed_A'&&c.method==='DELETE')")
check('authenticated empty distinct from error and loading',"document.querySelector('#podcast-content').textContent.includes('Noch keine Podcasts')&&!document.querySelectorAll('.podcast-skeleton').length&&!document.querySelector('#podcast-notice').textContent")
js("window.__feeds=[{id:'Feed_A',title:'Fixture private title',episodes:[]}];window.__hold=true;document.querySelector('#podcast-reload').click()");settle()
js("document.querySelector('#account').click();document.querySelector('#logout').click()");settle()
check('logout synchronously clears private podcasts',"document.querySelector('#podcast-content').children.length===0&&document.querySelector('#podcast-add').disabled&&!document.querySelector('#source-text').value")
js('window.__hold=false;window.__release()');settle()
check('late first account response ignored',"document.querySelector('#podcast-content').children.length===0")
check('guest official artwork no ChatGPT',"!document.querySelector('#podcast-signin').hidden&&document.querySelector('#podcast-signin img').naturalWidth===960&&document.querySelector('#provider-section').hidden")
cdp('Page.removeScriptToEvaluateOnNewDocument',identifier=identifier)
(out/'checks.json').write_text(json.dumps({'synthetic_api_only':True,'checks_passed':len(checks),'checks':checks},indent=2))
print((out/'checks.json').read_text());print('screenshots',list(map(str,out.glob('*.png'))))
