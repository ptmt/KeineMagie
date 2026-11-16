"""Synthetic owner/API fixture; executes real shipped app with browser_exec helpers."""
import json,time,shutil
from typing import TYPE_CHECKING, Any
if TYPE_CHECKING:
 def cdp(method: str, **kwargs: Any) -> Any: ...
 def goto_url(url: str) -> Any: ...
 def js(expression: str) -> Any: ...
 def capture_screenshot() -> str: ...
from pathlib import Path
out=Path('/Users/tinyserve/.hermes/cache/scratch/podcast-overview-evidence');out.mkdir(exist_ok=True)
fixture=r"""
Object.defineProperty(document,'hidden',{configurable:true,get:()=>false});
localStorage.setItem('keinemagie:interface-language:v1','ru');
window.__calls=[];window.__hold=!location.pathname.startsWith('/podcasts/episodes/');window.__fail=false;window.__owner='overview-owner';window.__sessionUnauthorized=false;
window.__feeds=[{id:'Feed_A',title:'Radio RTW · Fixture',author:'The Nut Sisters',episodes:[{id:'old',title:'Older episode',published:'2025-01-01'},{id:'shared',title:'Новый выпуск <img src=x onerror=alert(1)>',published:'2026-11-16'},{id:'partial',title:'В процессе: город и люди',published:'2026-11-15'},{id:'failed',title:'Сохранённая часть выпуска',published:'2026-11-14'}]},{id:'Feed_B',title:'Second podcast',episodes:[{id:'shared',title:'Same ID, different feed'}]},{id:'Feed_C',title:'Empty podcast',episodes:[]}];
window.__jobs=[{id:'Job_A',feed_id:'Feed_A',episode_id:'shared',title:'Ready episode',state:'completed',coverage:{recognized_segments:12,translated_segments:12,favorite_passages:3},segments:[{start:0,end:1,text:'Guten Tag',translation:'Добрый день'}]},{id:'Job_P',feed_id:'Feed_A',episode_id:'partial',title:'Partial episode',state:'translating',progress:35,coverage:{recognized_segments:20,translated_segments:7,favorite_passages:2}},{id:'Job_F',feed_id:'Feed_A',episode_id:'failed',title:'Failed episode',state:'failed',coverage:{recognized_segments:0,translated_segments:0,favorite_passages:0}}];
const nativeFetch=fetch.bind(window);window.fetch=async(path,opts={})=>{
 if(!String(path).startsWith('/v1/'))return nativeFetch(path,opts);
 window.__calls.push({path,method:opts.method||'GET'});
 const reply=(v,status=200)=>new Response(JSON.stringify(v),{status,headers:{'Content-Type':'application/json'}});
 if(path==='/v1/web/config')return reply({apple_available:true});
 if(path==='/v1/web/logout'){window.__owner=null;return new Response(null,{status:204});}
 if(path==='/v1/web/session')return window.__owner?reply({user:{id:window.__owner},csrf_token:'fixture',provider:{connected:true,selected_model:'fixture'}}):reply({},401);
 if(path==='/v1/translations')return reply({items:[]});
 if(path==='/v1/podcasts/subscriptions'){if(window.__hold)await new Promise(r=>window.__release=r);return window.__fail?reply({},503):reply({items:window.__feeds});}
 if(path==='/v1/podcasts')return reply({items:window.__jobs,worker_available:true});
 if(path.startsWith('/v1/podcasts/episodes/'))return reply(window.__jobs[0]);
 const job=window.__jobs.find(j=>path==='/v1/podcasts/'+j.id);if(job)return reply(job);
 return reply({},404);
};
"""
identifier=cdp('Page.addScriptToEvaluateOnNewDocument',source=fixture)['identifier']
goto_url('http://127.0.0.1:8773/?overview='+str(time.time_ns())+'#podcasts');time.sleep(1)
checks=[]
def check(name,expr):
 value=js(expr);assert value is True,(name,value);checks.append(name)
def settle():time.sleep(.35)
check('initial loading is not empty or ready',"document.querySelectorAll('.podcast-skeleton').length>0&&!document.querySelector('.podcast-overview')")
check('overview uses exactly two batch GETs',"window.__calls.filter(c=>c.path.startsWith('/v1/podcasts')).length===2&&window.__calls.filter(c=>c.path.startsWith('/v1/podcasts')).every(c=>c.method==='GET')")
js('window.__hold=false;window.__release()');settle()
check('three inline episodes for first feed',"document.querySelectorAll('[data-key=\"Feed_A\"] .podcast-episode').length===3")
check('not globally capped, same episode ID isolated',"document.querySelectorAll('[data-key=\"Feed_B\"] .podcast-episode').length===1&&!document.querySelector('[data-key=\"Feed_B\"] .podcast-progress')")
check('latest order and literal source title',"[...document.querySelectorAll('[data-key=\"Feed_A\"] .podcast-episode-title')].map(e=>e.textContent).join('|')==='Новый выпуск <img src=x onerror=alert(1)>|В процессе: город и люди|Сохранённая часть выпуска'&&!document.querySelector('.podcast-episode img')")
check('real coverage and separate starred count',"document.querySelector('[data-key=\"Feed_A\"]').textContent.includes('Переведено 7 / 20')&&document.querySelector('[data-key=\"Feed_A\"]').textContent.includes('Отмеченные фрагменты: 2')")
check('coverage metrics have a real layout gap',"getComputedStyle(document.querySelector('.podcast-coverage')).display==='flex'&&parseFloat(getComputedStyle(document.querySelector('.podcast-coverage')).columnGap)>=10")
check('unknown denominator omitted',"!document.querySelector('#podcast-content').textContent.includes('0 / 0')")
check('no nested links or buttons',"!document.querySelector('#podcast-content a a, #podcast-content a button')")
check('quiet all episodes and author',"document.querySelector('[data-key=\"Feed_A\"]').textContent.includes('Все эпизоды')&&document.querySelector('[data-key=\"Feed_A\"]').textContent.includes('The Nut Sisters')")
check('empty distinct',"document.querySelector('[data-key=\"Feed_C\"]').textContent.includes('нет доступных')")
check('row retry control',"document.querySelector('[data-key=\"Feed_A\"] [data-state=failed] button').textContent==='Попробовать снова'")
check('opening library never posts',"!window.__calls.some(c=>c.method==='POST')")
for locale,label in [('de','Alle Folgen'),('en','All episodes'),('ru','Все эпизоды'),('es','Todos los episodios'),('fr','Tous les épisodes')]:
 js("var s=document.querySelector('#interface-language-header');s.value="+json.dumps(locale)+";s.dispatchEvent(new Event('change'))");settle()
 check('locale '+locale,"document.querySelector('.podcast-all-episodes').textContent==="+json.dumps(label)+"&&document.querySelector('.podcast-episode-title').textContent.includes('<img src=x')")
js("var s=document.querySelector('#interface-language-header');s.value='ru';s.dispatchEvent(new Event('change'))");settle()
js("document.querySelector('[data-key=\"Feed_B\"] .podcast-episode-title a').focus()")
cdp('Input.dispatchKeyEvent',type='keyDown',key='Tab',code='Tab',windowsVirtualKeyCode=9)
cdp('Input.dispatchKeyEvent',type='keyUp',key='Tab',code='Tab',windowsVirtualKeyCode=9)
check('keyboard links reachable with visible focus',"document.activeElement.matches('a,button,summary')&&document.activeElement.matches(':focus-visible')")
# Pointer-originated focus must not inherit the keyboard-only feed outline.
js('document.activeElement.blur()')
rect=js("(()=>{const a=document.querySelector('[data-key=\"Feed_C\"] .podcast-feed');a.scrollIntoView({block:'center'});a.addEventListener('click',e=>e.preventDefault(),{once:true});const r=a.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()")
cdp('Page.bringToFront')
cdp('Input.dispatchMouseEvent',type='mouseMoved',x=rect['x'],y=rect['y'])
cdp('Input.dispatchMouseEvent',type='mousePressed',x=rect['x'],y=rect['y'],button='left',clickCount=1)
cdp('Input.dispatchMouseEvent',type='mouseReleased',x=rect['x'],y=rect['y'],button='left',clickCount=1)
check('pointer focus has no feed block ring',"!document.activeElement.matches(':focus-visible')&&getComputedStyle(document.activeElement).outlineStyle==='none'")
cdp('Input.dispatchKeyEvent',type='keyDown',key='Tab',code='Tab',windowsVirtualKeyCode=9)
cdp('Input.dispatchKeyEvent',type='keyUp',key='Tab',code='Tab',windowsVirtualKeyCode=9)
check('keyboard focus remains visible after pointer interaction',"document.activeElement.matches(':focus-visible')&&getComputedStyle(document.activeElement).outlineStyle!=='none'")
for width in [int(1440/5),320,390,768,1440]:
 cdp('Emulation.setDeviceMetricsOverride',width=width,height=1000,deviceScaleFactor=1,mobile=width<700)
 check('no overflow '+str(width),'document.documentElement.scrollWidth<=innerWidth')
 if width<=390:check('failed actions wrap below readable title '+str(width),"(()=>{const r=document.querySelector('.podcast-episode[data-state=failed]');return r.firstChild.clientWidth>=r.clientWidth*.75&&r.lastChild.getBoundingClientRect().top>=r.firstChild.getBoundingClientRect().bottom})()")
 if width in [390,1440]:shutil.copy(capture_screenshot(),out/f'overview-{width}.png')
js("document.querySelector('[data-key=\"Feed_B\"] .podcast-episode-title a').click()");settle()
check('unprepared title opens exact feed action, no generation',"location.hash==='#podcasts/feed/Feed_B?episode=shared'&&document.querySelector('.podcast-episode').textContent.includes('Подготовить')&&!window.__calls.some(c=>c.method==='POST')")
js('history.back()');settle()
check('Back restores overview',"document.querySelectorAll('[data-key=\"Feed_A\"] .podcast-episode').length===3")
js("document.querySelector('[data-key=\"Feed_A\"] .podcast-episode-title a').click()");time.sleep(.8)
check('ready opens existing persistent reader URL',"location.pathname.startsWith('/podcasts/episodes/')&&document.querySelector('[data-job=Job_A]')!==null")
cdp('Page.reload');time.sleep(1)
check('reader reload resolves same saved job without AI',"location.pathname.startsWith('/podcasts/episodes/')&&document.querySelector('[data-job=Job_A]')!==null&&!window.__calls.some(c=>c.method==='POST')")
js('history.back()');settle()
js("document.querySelector('[data-key=\"Feed_A\"] .podcast-episode-title a').focus();window.__jobs[1].coverage.translated_segments=8;document.querySelector('#podcast-reload').click()");settle()
check('progress refresh preserves exact focused title link',"document.activeElement===document.querySelector('[data-key=\"Feed_A\"] .podcast-episode-title a')&&document.querySelector('[data-key=\"Feed_A\"]').textContent.includes('8 / 20')")
js("window.__jobs[2].state='canceled';document.querySelector('#podcast-reload').click()");settle()
check('canceled row retains retry and no zero denominator',"document.querySelector('[data-state=canceled] button')!==null&&!document.querySelector('#podcast-content').textContent.includes('0 / 0')")
js("window.__hold=true;document.querySelector('#podcast-reload').click()");settle()
check('refresh keeps previous rows',"document.querySelectorAll('[data-key=\"Feed_A\"] .podcast-episode').length===3")
js('window.__fail=true;window.__hold=false;window.__release()');settle()
check('error retains rows',"document.querySelectorAll('[data-key=\"Feed_A\"] .podcast-episode').length===3&&document.querySelector('#podcast-notice').textContent.length>0")
js("window.__fail=false;window.__hold=true;document.querySelector('#podcast-reload').click()");settle()
js("document.querySelector('#account').click();document.querySelector('#logout').click()");settle()
check('logout immediately removes inline private rows',"document.querySelector('#podcast-content').children.length===0&&document.querySelector('#podcast-add').disabled")
js('window.__hold=false;window.__release()');settle()
check('old pending response cannot restore inline rows',"document.querySelector('#podcast-content').children.length===0")
cdp('Page.removeScriptToEvaluateOnNewDocument',identifier=identifier)
(out/'checks.json').write_text(json.dumps({'synthetic_only':True,'checks':checks,'passed':len(checks)},ensure_ascii=False,indent=2))
print(json.dumps({'checks':checks,'passed':len(checks),'screenshots':list(map(str,out.glob('*.png')))},ensure_ascii=False))
