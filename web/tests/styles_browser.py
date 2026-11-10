"""Run with browser_exec helpers. Explicit synthetic UI fixture, no live inference.
Loads repository assets into an isolated about:blank document because some browser
backends cannot reach the host loopback server. Storage below is a test-only Map;
real localStorage persistence is covered by Node tests. Screenshots go to scratch.
"""
from pathlib import Path
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
out = Path('/Users/tinyserve/.hermes/cache/scratch/keinemagie-style-evidence')
out.mkdir(exist_ok=True)
html = (root / 'index.html').read_text()
html = re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]+>', '', html)
html = re.sub(r'<script[^>]*>.*?</script>', '', html)
html = re.sub(r'<link[^>]+>', '', html)
html = html.replace('</head>', '<style>' + (root / 'styles.css').read_text() + '</style></head>')
fixture = (root / 'tests/browser_smoke.py').read_text().split('fixture = r"""')[1].split('"""')[0]
fixture += """
// about:blank lacks the secure-context randomUUID available on production HTTPS.
Object.defineProperty(crypto, 'randomUUID', {configurable:true,value:()=> 'fixture-only-id'});
window.__styleStorage = new Map();
Object.defineProperty(window, 'localStorage', {configurable:true, value:{
 getItem:key=>window.__styleStorage.get(key)??null,
 setItem:(key,value)=>window.__styleStorage.set(key,value)
}});
"""
core = re.sub(r'export (?=(function|async function|const))', '', (root / 'core.mjs').read_text())
app = re.sub(r'^import .*?;\n', '', (root / 'app.mjs').read_text())
goto_url('about:blank')
cdp('Page.setDocumentContent', frameId=cdp('Page.getFrameTree')['frameTree']['frame']['id'], html=html)
js('(() => {' + fixture + '\n' + core + '\n' + app + '\nreturn true;})()')
time.sleep(.3)
checks = []

def check(name, expression):
    value = js(expression)
    assert value is True, (name, value)
    checks.append(name)

js("document.querySelector('#style-chips button:nth-child(2)').click()")
fill_input('#source-text', 'Browser test input')
js("document.querySelector('#translation-form').requestSubmit()")
time.sleep(.2)
check('friendly style POST payload', "JSON.parse(window.__testCalls.findLast(c=>c.method==='POST').body).instructions.includes('friendly')")
check('plain structured translation', "document.querySelector('#result').textContent==='TEST FIXTURE — not a live translation'")
cdp('Emulation.setDeviceMetricsOverride', width=1280, height=900, deviceScaleFactor=1, mobile=False)
shutil.copy(capture_screenshot(), out / 'desktop-translator.png')
js("document.querySelector('#add-prompt').click()")
fill_input('#prompt-name', 'E-Mail')
fill_input('#prompt-instructions', 'Bitte kurz und freundlich übersetzen. Die Bedeutung beibehalten.')
check('editor focus', "document.querySelector('#prompt-dialog').contains(document.activeElement)")
check('Unicode count and privacy', "document.querySelector('#prompt-count').textContent.includes('/ 1.000') && document.querySelector('#prompt-privacy').textContent.includes('nicht mit der App synchronisiert')")
for width in [320, 390, 768, 1280]:
    cdp('Emulation.setDeviceMetricsOverride', width=width, height=900, deviceScaleFactor=1, mobile=width < 700)
    check(f'no editor overflow {width}', 'document.documentElement.scrollWidth <= innerWidth')
    if width == 390:
        shutil.copy(capture_screenshot(), out / 'mobile-editor.png')
js("document.querySelector('#prompt-form').requestSubmit()")
check('saved named chip', "!document.querySelector('#prompt-dialog').open && [...document.querySelectorAll('#style-chips button')].some(x=>x.textContent==='E-Mail' && x.getAttribute('aria-pressed')==='true')")
check('storage excludes session secrets', "[...window.__styleStorage.keys()].every(k=>k.endsWith(':test-only-user')) && ![...window.__styleStorage.values()].join('').includes('test-only-csrf')")
js("document.querySelector('#edit-prompt').click()")
fill_input('#prompt-name', 'Brief')
js("document.querySelector('#prompt-form').requestSubmit()")
check('edited named chip', "[...document.querySelectorAll('#style-chips button')].some(x=>x.textContent==='Brief')")
js("document.querySelector('#edit-prompt').click();document.querySelector('#delete-prompt').click()")
check('delete updates storage', "[...window.__styleStorage.values()].every(x=>x==='[]')")
js("document.querySelector('#add-prompt').click()")
fill_input('#prompt-name', 'Private draft')
js("window.__testMode='expired';document.querySelector('#translation-form').requestSubmit()")
time.sleep(.2)
check('expiry clears editor and chips', "!document.querySelector('#prompt-dialog').open && !document.querySelector('#prompt-name').value && document.querySelectorAll('#style-chips button').length===3 && [...document.querySelectorAll('#style-chips button')].every(b=>b.disabled) && !document.querySelector('#style-controls').hidden")
print(json.dumps({'fixture_only': True, 'checks_passed': len(checks), 'checks': checks, 'screenshots': [str(out / 'desktop-translator.png'), str(out / 'mobile-editor.png')]}))
