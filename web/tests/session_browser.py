"""Run with browser_exec. Shipped app, synthetic delayed APIs; no live identity claim."""
from pathlib import Path
import json, re, time
from typing import TYPE_CHECKING
if TYPE_CHECKING:
 def new_tab(url: str): ...
 def js(expression: str): ...
root=Path('/Users/tinyserve/Projects/KeineMagie/web')
html=(root/'index.html').read_text()
html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]+>|<script[^>]*>.*?</script>|<link[^>]+>', '', html)
core=re.sub(r'export (?=(function|async function|const))','',(root/'i18n.mjs').read_text())+'\n'+re.sub(r'export (?=(function|async function|const))','',(root/'core.mjs').read_text())
exports={'episode.mjs':['episodeLocation','episodePath','transcriptStats','createEpisodeClient','createAnalysisRunner'],'episode-i18n.mjs':['episodeText','relocalizeEpisodeMessage'],'episode-view.mjs':['createEpisodeView']}
for module,names in exports.items():
 source=re.sub(r'^import .*?;\n','',(root/module).read_text(),flags=re.M)
 source=re.sub(r'export (?=(function|async function|const))','',source)
 if module=='episode-view.mjs':source='const t=episodeText;\n'+source
 core+='\nconst {'+','.join(names)+'}=(()=>{'+source+'\nreturn {'+','.join(names)+'};})();\n'
app=re.sub(r'^import .*?;\n','',(root/'app.mjs').read_text(),flags=re.M)
fixture=r'''
window.__calls=[];window.__signed=true;window.__holdSession=true;window.__holdProvider=true;window.__holdHistory=true;
Object.defineProperty(document,'hidden',{configurable:true,get:()=>false});
Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:()=> 'de',setItem:()=>{}}});
window.fetch=async(path,opts={})=>{
 window.__calls.push(path);
 const reply=(v,s=200)=>new Response(JSON.stringify(v),{status:s});
 if(path==='/v1/web/config')return reply({apple_available:true,csrf_token:'fixture-boot'});
 if(path==='/v1/web/session'){
  if(window.__holdSession)await new Promise((resolve,reject)=>{window.__releaseSession=resolve;opts.signal?.addEventListener('abort',()=>reject(opts.signal.reason),{once:true});});
  return window.__signed?reply({user:{id:'fixture-owner'},csrf_token:'fixture-csrf'}):reply({},401);
 }
 if(path==='/v1/provider'){if(window.__holdProvider)await new Promise(r=>window.__releaseProvider=r);return reply({connected:true,status:'connected',selected_model:'fixture-model'});}
 if(path==='/v1/translations'){if(window.__holdHistory)await new Promise(r=>window.__releaseHistory=r);return reply({items:[]});}
 if(path==='/v1/podcasts/subscriptions')return reply({items:[{id:'Feed_A',title:'Synthetic private podcast',episodes:[]}]});
 if(path==='/v1/podcasts')return reply({items:[],worker_available:true});
 return reply({},404);
};
'''
new_tab('about:blank')
js('location.hash="#podcasts"')
js('document.open()')
for start in range(0,len(html),16000):js('document.write('+json.dumps(html[start:start+16000])+')')
js('document.close()')
script='(() => {'+fixture+'\n'+core+'\n'+app+'\nreturn true;})()'
js('window.__fixtureSource=""')
for start in range(0,len(script),12000):js('window.__fixtureSource+='+json.dumps(script[start:start+12000]))
js('eval(window.__fixtureSource)')
checks=[]
def check(name,expr):
 value=js(expr);assert value is True,(name,value);checks.append(name)
def settle():time.sleep(.25)
check('first identity gates all private podcasts',"!document.querySelector('#podcast-content').textContent && document.querySelector('#podcast-add').disabled")
js('window.__holdSession=false;window.__releaseSession()');settle()
check('podcasts visible while history remains pending',"document.querySelector('#podcast-content').textContent.includes('Synthetic private podcast')")
check('podcast route does not discover provider catalog',"!window.__calls.includes('/v1/provider')")
js("document.querySelector('#account').click()");settle()
check('account discovers catalog independently without hiding podcasts',"window.__calls.includes('/v1/provider') && document.querySelector('#podcast-content').textContent.includes('Synthetic private podcast')")
check('unverified provider stays loading not disconnected',"document.querySelector('#provider-status').textContent==='Verbindung wird geprüft …' && !document.querySelector('#connection-title').textContent.includes('verbinden') && document.querySelector('#provider-connect').disabled")
js('window.__holdProvider=false;window.__releaseProvider()');settle()
check('account provider becomes ready while history is still blocked',"document.querySelector('#provider-status').textContent==='Verbunden' && !window.__calls.includes('/v1/translations/anything') && document.querySelector('#podcast-content').textContent.includes('Synthetic private podcast')")
js("window.__holdSession=true;document.querySelector('#retry-session').click();document.querySelector('#retry-session').click()");settle()
check('same identity refresh keeps list with inline indicator',"document.querySelector('#podcast-content').textContent.includes('Synthetic private podcast') && document.querySelector('#podcast-notice').textContent.includes('Hintergrund')")
check('refresh is coalesced',"window.__calls.filter(p=>p==='/v1/web/session').length===2")
js('window.__signed=false;window.__holdSession=false;window.__releaseSession()');settle()
check('401 clears private list and draft immediately',"!document.querySelector('#podcast-content').textContent && !document.querySelector('#source-text').value")
js('window.__releaseProvider();window.__releaseHistory()');settle()
check('late discovery cannot revive private account',"document.querySelector('#provider-section').hidden && !document.querySelector('#podcast-content').textContent")
js("window.__holdSession=true;document.querySelector('#retry-session').click()")
deadline=time.monotonic()+12
while time.monotonic()<deadline:
 if js("document.querySelector('#connection-title').textContent.includes('erneut versuchen')"):break
 time.sleep(.25)
check('session timeout replaces infinite checking with retry',"document.querySelector('#connection-title').textContent.includes('erneut versuchen') && !document.querySelector('#connection-action').hidden")
js('window.__holdSession=false;window.__releaseSession()');settle()
check('late timed out identity cannot resurrect account',"document.querySelector('#provider-section').hidden")
print(json.dumps({'fixture_only':True,'checks_passed':len(checks),'checks':checks},indent=2))
