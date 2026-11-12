"""Run with browser_exec helpers. Synthetic API fixture, never live inference.
Exercises real repository HTML/CSS/JS, actual POST bodies and history reuse.
"""
from pathlib import Path
import json
import re
import time
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    def goto_url(url: str) -> Any: ...
    def cdp(method: str, **kwargs: Any) -> Any: ...
    def js(expression: str) -> Any: ...
    def fill_input(selector: str, text: str) -> Any: ...

root = Path('/Users/tinyserve/Projects/KeineMagie/web')
html = (root / 'index.html').read_text()
html = re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]+>', '', html)
html = re.sub(r'<script[^>]*>.*?</script>|<link[^>]+>', '', html)
html = html.replace('</head>', '<style>' + (root / 'styles.css').read_text() + '</style></head>')
fixture = (root / 'tests/browser_smoke.py').read_text().split('fixture = r"""')[1].split('"""')[0]
fixture = fixture.replace('reply({items:[]})', 'reply({items:window.__fixtureHistory || []})')
fixture += """
Object.defineProperty(window, 'localStorage', {configurable:true,value:{getItem:()=>null,setItem:()=>{}}});
"""
core = re.sub(r'export (?=(function|async function|const))', '', (root / 'core.mjs').read_text())
app = re.sub(r'^import .*?;\n', '', (root / 'app.mjs').read_text(), flags=re.M)
goto_url('about:blank')
cdp('Page.setDocumentContent', frameId=cdp('Page.getFrameTree')['frameTree']['frame']['id'], html=html)
js('(() => {' + fixture + '\n' + core + '\n' + app + '\nreturn true;})()')
time.sleep(.3)
checks = []

def check(name, expression):
    value = js(expression)
    assert value is True, (name, value)
    checks.append(name)

check('fresh ru-de default and matching input/output languages', "document.querySelector('#language-direction').value==='ru-de' && document.querySelector('#source-text').lang==='ru' && document.querySelector('#result').lang==='de'")
check('compact accessible three-direction menu', "JSON.stringify([...document.querySelector('#language-direction').options].map(o=>o.textContent))===JSON.stringify(['de → ru','ru → de','de → de']) && document.querySelector('option[value=de-de]').getAttribute('aria-label')==='Deutsch verbessern'")
check('direction directly above grid and tiny text styles below source only',"document.querySelector('.language-bar').nextElementSibling.matches('.translation-panels') && document.querySelector('#style-controls').closest('.input-panel')!==null && document.querySelector('#source-text').getBoundingClientRect().bottom<=document.querySelector('#style-controls').getBoundingClientRect().top && getComputedStyle(document.querySelector('.style-chip')).borderWidth==='0px' && getComputedStyle(document.querySelector('.style-chip')).backgroundColor==='rgba(0, 0, 0, 0)'")
for direction, source, target, swapped in [('de-ru', 'de', 'ru', 'ru-de'), ('ru-de', 'ru', 'de', 'de-ru'), ('de-de', 'de', 'de', 'de-de')]:
    js(f"document.querySelector('#language-direction').value='{direction}';document.querySelector('#language-direction').dispatchEvent(new Event('change'));document.querySelector('#style-chips button:nth-child(3)').click()")
    fill_input('#source-text', 'Ich habe ein frage. — test fixture')
    js("document.querySelector('#translation-form').requestSubmit()")
    time.sleep(.2)
    check(f'{direction} actual POST with style', f"(() => {{const c=window.__testCalls.findLast(c=>c.path==='/v1/translations'&&c.method==='POST');const p=JSON.parse(c.body);return p.source_language==='{source}'&&p.target_language==='{target}'&&p.instructions.includes('formal')&&c.headers['X-CSRF-Token']==='test-only-csrf';}})()")
    check(f'{direction} result accepted without opposite-language guard', f"document.querySelector('#result').textContent==='TEST FIXTURE — not a live translation' && document.querySelector('#result').lang==='{target}' && document.querySelector('#result-caption').textContent.startsWith('{source} → {target}')")
    js("document.querySelector('#swap').click()")
    check(f'{direction} swap', f"document.querySelector('#language-direction').value==='{swapped}' && document.querySelector('#source-text').value==='TEST FIXTURE — not a live translation' && !document.querySelector('#result').textContent")

js("window.__fixtureHistory=[{id:'saved-proofreading',text:'Ich habe ein frage.',source_language:'de',target_language:'de',translation:'TEST FIXTURE — corrected German',instructions:'Historical custom proofreading style.',idioms:[],patterns:[],vocabulary:[]}];document.querySelector('#refresh-history').click()")
time.sleep(.2)
check('history accepts equal-language records', "document.querySelector('#history-list .history-source').textContent==='Ich habe ein frage.' && document.querySelector('#history-list .history-translation').textContent==='TEST FIXTURE — corrected German' && document.querySelector('#history-list small').textContent.startsWith('de → de')")
js("document.querySelector('#language-direction').value='ru-de';document.querySelector('#language-direction').dispatchEvent(new Event('change'));document.querySelector('#history-list button').click()")
check('history restores proofreading direction and historical custom style', "document.querySelector('#language-direction').value==='de-de' && document.querySelector('#result').textContent==='TEST FIXTURE — corrected German' && [...document.querySelectorAll('#style-chips button')].some(b=>b.textContent==='Aus Verlauf'&&b.getAttribute('aria-pressed')==='true')")
js("document.querySelector('#translation-form').requestSubmit()")
time.sleep(.2)
check('history reuse POST retains equal languages and exact instructions', "(()=>{const p=JSON.parse(window.__testCalls.findLast(c=>c.method==='POST').body);return p.source_language==='de'&&p.target_language==='de'&&p.instructions==='Historical custom proofreading style.'})()")
for width in [320, 390, 768, 1440]:
    cdp('Emulation.setDeviceMetricsOverride', width=width, height=900, deviceScaleFactor=1, mobile=width < 700)
    check(f'no horizontal overflow {width}', 'document.documentElement.scrollWidth <= innerWidth')
print(json.dumps({'fixture_only':True,'checks_passed':len(checks),'checks':checks},ensure_ascii=False))
