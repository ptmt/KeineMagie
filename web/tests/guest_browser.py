"""Run via browser_exec. Real repo HTML/CSS/JS/art, synthetic auth only.
Uses a document harness when the browser cannot reach host loopback.
No live Apple login, provider connection, or translation is claimed.
"""
from pathlib import Path
import base64
import json
import re
import shutil
import time
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    def goto_url(url: str) -> Any: ...
    def cdp(method: str, **kwargs: Any) -> Any: ...
    def js(expression: str) -> Any: ...
    def fill_input(selector: str, text: str) -> Any: ...
    def capture_screenshot() -> str: ...

root = Path('/Users/tinyserve/Projects/KeineMagie/web')
out = Path('/Users/tinyserve/.hermes/cache/scratch/keinemagie-guest-evidence')
out.mkdir(exist_ok=True)
html = (root / 'index.html').read_text()
html = re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]+>', '', html)
html = re.sub(r'<script[^>]*>.*?</script>|<link[^>]+>', '', html)
html = html.replace('./apple-sign-in-de.png', 'data:image/png;base64,' + base64.b64encode((root / 'apple-sign-in-de.png').read_bytes()).decode())
html = html.replace('</head>', '<style>' + (root / 'styles.css').read_text() + '</style></head>')
fixture = r"""
window.__calls=[];window.__signed=false;window.__connected=true;window.__hold=true;
Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:()=>null,setItem:()=>{}}});
window.fetch=async(path,opts={})=>{
 window.__calls.push({path,method:opts.method});
 const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
 if(path==='/v1/web/config')return reply({apple_available:true,pairing_available:true,chatgpt_connect_available:true,csrf_token:'fixture-bootstrap'});
 if(path==='/v1/web/session'){
  if(window.__hold)await new Promise(r=>window.__release=r);
  return window.__signed?reply({user:{id:window.__owner||'fixture-owner'},csrf_token:'fixture-csrf',provider:{connected:window.__connected,selected_model:window.__catalog===false?'':window.__connected?'fixture-model':''}}):reply({},401);
 }
 if(path==='/v1/web/logout'){window.__signed=false;return new Response(null,{status:204});}
 if(path==='/v1/translations'&&opts.method==='POST'){window.__signed=false;return reply({},401);}
 if(path==='/v1/translations')return reply({items:[]});
 return reply({},404);
};
"""
core = re.sub(r'export (?=(function|async function|const))', '', (root / 'core.mjs').read_text())
app = re.sub(r'^import .*?;\n', '', (root / 'app.mjs').read_text())
goto_url('about:blank')
cdp('Page.setDocumentContent', frameId=cdp('Page.getFrameTree')['frameTree']['frame']['id'], html=html)
js('(() => {' + fixture + '\n' + core + '\n' + app + '\nreturn true;})()')
checks = []
def check(name, expression):
    value = js(expression)
    assert value is True, (name, value)
    checks.append(name)

locked = "['source-text','source-language','target-language','swap','translate','clear','add-prompt'].every(id=>document.getElementById(id).disabled)"
check('loading controls truly disabled', locked)
check('loading has no premature sign-in action', "document.querySelector('#connection-action').hidden && document.querySelector('#connection-title').textContent==='Sitzung wird geprüft …'")
js('window.__hold=false;window.__release()')
time.sleep(.2)
check('guest controls truly disabled', locked)
check('guest clear in-place message', "document.querySelector('#connection-title').textContent==='Melde dich an, um zu übersetzen.'")
check('guest preset and add controls disabled', "!document.querySelector('#style-controls').hidden && [...document.querySelectorAll('#style-chips button')].every(b=>b.disabled)")
check('official Apple image loaded in place', "document.querySelector('#connection-action-art').checkVisibility() && document.querySelector('#connection-action-art').naturalWidth===960")
js("document.querySelector('#add-prompt').dispatchEvent(new MouseEvent('click'));document.querySelector('#translation-form').dispatchEvent(new Event('submit',{cancelable:true}));document.querySelector('#style-chips button:nth-child(2)').dispatchEvent(new MouseEvent('click'))")
check('synthetic guest events rejected', "!document.querySelector('#prompt-dialog').open && !window.__calls.some(c=>c.path==='/v1/translations'&&c.method==='POST') && document.querySelector('#style-chips button').getAttribute('aria-pressed')==='true'")
for width in [320, 390, 768, 1440]:
    cdp('Emulation.setDeviceMetricsOverride', width=width, height=1100, deviceScaleFactor=1, mobile=width < 700)
    check(f'guest no overflow {width}', 'document.documentElement.scrollWidth <= innerWidth')
    if width in [320,1440]:
        shutil.copy(capture_screenshot(), out / f'guest-{width}.png')
js("document.querySelector('#connection-action').click()")
check('Apple in-place action opens guest dialog without ChatGPT', "document.querySelector('#account-dialog').open && document.querySelector('#account-dialog').contains(document.activeElement) && !document.querySelector('#account-dialog').innerText.includes('ChatGPT') && document.querySelector('#apple-login img').naturalWidth===960")
cdp('Emulation.setDeviceMetricsOverride', width=320, height=900, deviceScaleFactor=1, mobile=True)
check('guest dialog no overflow', 'document.documentElement.scrollWidth <= innerWidth')
shutil.copy(capture_screenshot(), out / 'guest-dialog-320.png')
js("document.querySelector('#close-account').click();window.__signed=true;document.querySelector('#retry-session').dispatchEvent(new MouseEvent('click'))")
time.sleep(.2)
check('signed in and connected permits editing', "!document.querySelector('#source-text').disabled && document.querySelector('#connection-notice').hidden")
fill_input('#source-text', 'Synthetic private draft')
check('signed in connected ready only with draft', "!document.querySelector('#translate').disabled")
js("window.__hold=true;document.querySelector('#retry-session').click()")
check('rechecking locks controls without clearing same-owner draft', locked + " && document.querySelector('#source-text').value==='Synthetic private draft'")
js("document.querySelector('#add-prompt').dispatchEvent(new MouseEvent('click'))")
check('rechecking rejects synthetic modal click', "!document.querySelector('#prompt-dialog').open")
js('window.__hold=false;window.__release()')
time.sleep(.2)
check('same-owner draft survives confirmed session', "document.querySelector('#source-text').value==='Synthetic private draft' && !document.querySelector('#translate').disabled")
js("window.__connected=false;document.querySelector('#retry-session').click()")
time.sleep(.2)
check('unconnected requires ChatGPT only after identity sign-in', "document.querySelector('#translate').disabled && !document.querySelector('#source-text').disabled && document.querySelector('#connection-title').textContent==='ChatGPT im Konto verbinden.'")
js("window.__connected=true;window.__catalog=false;document.querySelector('#retry-session').click()")
time.sleep(.2)
check('catalog unavailable stays distinct from reconnect', "document.querySelector('#translate').disabled && document.querySelector('#connection-title').textContent.includes('Modell nicht verfügbar') && document.querySelector('#provider-connect').disabled && document.querySelector('#connection-action-label').textContent==='Erneut prüfen'")
js("window.__catalog=true;document.querySelector('#retry-session').click()")
time.sleep(.2)
js("document.querySelector('#translation-form').requestSubmit()")
time.sleep(.2)
check('expired translation clears private text and disables controls', locked + " && !document.querySelector('#source-text').value && !document.querySelector('#result').textContent && !document.querySelector('#history-list').children.length")
check('expiry leaves disabled public presets only', "!document.querySelector('#prompt-dialog').open && document.querySelectorAll('#style-chips button').length===3 && [...document.querySelectorAll('#style-chips button')].every(b=>b.disabled)")
js("window.__signed=true;document.querySelector('#retry-session').dispatchEvent(new MouseEvent('click'))")
time.sleep(.2)
fill_input('#source-text', 'Synthetic logout draft')
js("document.querySelector('#account').click();document.querySelector('#logout').click()")
time.sleep(.2)
check('logout clears and verifies session revocation', locked + " && !document.querySelector('#source-text').value && window.__calls.at(-1).path==='/v1/web/session'")
(out / 'checks.json').write_text(json.dumps({'fixture_only':True,'checks_passed':len(checks),'checks':checks},indent=2))
print((out / 'checks.json').read_text())
print('screenshots:', [str(p) for p in out.glob('*.png')])
