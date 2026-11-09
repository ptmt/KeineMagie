"""Browser-harness smoke test. Fixtures are test-only, NOT live provider output.
Run through browser_exec with this file's code (browser helpers pre-imported).
Requires the web/ static server at http://127.0.0.1:8766.
"""
import json
import time
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    def cdp(method: str, **kwargs: Any) -> Any: ...
    def js(expression: str) -> Any: ...
    def goto_url(url: str) -> Any: ...
    def wait_for_load() -> Any: ...
    def fill_input(selector: str, text: str) -> Any: ...

fixture = r"""
window.__testCalls = [];
window.__testSignedIn = true;
window.__testMode = 'ok';
window.__testConnected = true;
const item = {id:'fixture-record',created_at:'2026-01-01T12:00:00Z',text:'Browser test input',source_language:'de',target_language:'ru',translation:'TEST FIXTURE — not a live translation',idioms:[{expression:'<script>fixture</script>',meaning:'Test-only meaning',example:'Test-only example'}],patterns:[],vocabulary:[]};
window.fetch = async (path, options = {}) => {
  window.__testCalls.push({path,method:options.method,headers:options.headers,credentials:options.credentials,body:options.body});
  const reply = (body,status=200) => new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
  if(path === '/v1/web/config') return reply({apple_available:true,pairing_available:true,chatgpt_connect_available:true,csrf_token:'test-only-bootstrap-csrf'});
  if(path === '/v1/web/session') return window.__testSignedIn ? reply({user:{id:'test-only-user'},csrf_token:'test-only-csrf',provider:{connected:window.__testConnected}}) : reply({error:'expired'},401);
  if(path === '/v1/provider/connect') return reply({bootstrap_token:'TEST-ONLY-ONE-TIME-CODE',expires_in:300});
  if(path === '/v1/web/logout') { window.__testSignedIn=false; return new Response(null,{status:204}); }
  if(path === '/v1/translations' && options.method === 'GET') return reply({items:[]});
  if(path === '/v1/translations' && options.method === 'POST') {
    if(window.__testMode === 'slow') return new Promise((resolve,reject)=>options.signal.addEventListener('abort',()=>reject(new DOMException('Canceled','AbortError')),{once:true}));
    if(window.__testMode === 'expired') { window.__testSignedIn=false; return reply({error:'expired'},401); }
    if(window.__testMode === 'upstream') return reply({error:'test-only upstream failure'},502);
    return reply({...item,...JSON.parse(options.body)},201);
  }
  return reply({error:'unknown test endpoint'},404);
};
"""
script_id = cdp('Page.addScriptToEvaluateOnNewDocument', source=fixture)['identifier']
checks = []

def check(name, expression):
    result = js(expression)
    assert result is True, f'{name}: {result}'
    checks.append(name)

try:
    goto_url('http://127.0.0.1:8766')
    wait_for_load()
    time.sleep(.3)
    check('confirmed session enables translator only after input', "document.querySelector('#translate').disabled && document.querySelector('#connection-title').textContent.includes('Bereit')")
    fill_input('#source-text', 'Browser test input')
    check('typing enables primary action', "!document.querySelector('#translate').disabled")
    js("window.__testMode='slow';document.querySelector('#translation-form').requestSubmit()")
    time.sleep(.1)
    check('busy translation locks input and exposes cancel', "document.querySelector('#source-text').readOnly && document.querySelector('#translate').disabled && document.querySelector('#cancel').checkVisibility()")
    js("document.querySelector('#cancel').click()")
    time.sleep(.1)
    check('cancel restores editing without a successful result', "!document.querySelector('#source-text').readOnly && document.querySelector('#cancel').hidden && document.querySelector('#translation-status').textContent.includes('abgebrochen') && !document.querySelector('#result').textContent")
    js("window.__testMode='ok'")
    js("document.querySelector('#translation-form').requestSubmit()")
    time.sleep(.2)
    check('renders completed result and history', "document.querySelector('#result').textContent === 'TEST FIXTURE — not a live translation' && document.querySelectorAll('#history-list li').length === 1")
    check('enrichment panels and marketing chrome are removed from markup', "!document.querySelector('#idioms,#patterns,#vocabulary,.page-heading,.page-footer')")
    for route, label in [('dictation', 'Diktat'), ('podcasts', 'Podcasts'), ('coach', 'Coach')]:
        js(f"document.querySelector('.section-nav a[href=\"#{route}\"]').click()")
        time.sleep(.1)
        check(f'{label} route is active and honest', f"location.hash === '#{route}' && document.querySelector('#translator').hidden && document.querySelector('#{route}').checkVisibility() && document.querySelector('#{route}').innerText.includes('Noch nicht verfügbar') && document.querySelector('.section-nav [aria-current=page]').hash === '#{route}'")
    js("document.querySelector('.section-nav a[href=\"#translator\"]').click()")
    time.sleep(.1)
    check('switching preserves input result and history without requests', "document.querySelector('#source-text').value === 'Browser test input' && document.querySelector('#result').textContent === 'TEST FIXTURE — not a live translation' && document.querySelectorAll('#history-list li').length === 1 && window.__testCalls.filter(c=>c.path === '/v1/translations' && c.method === 'POST').length === 2")
    js("window.__testMode='slow';document.querySelector('#translation-form').requestSubmit();location.hash='#podcasts'")
    time.sleep(.1)
    check('switching during translation does not cancel request', "document.querySelector('#source-text').readOnly && !document.querySelector('#cancel').hidden")
    js("location.hash='#translator'")
    time.sleep(.1)
    js("document.querySelector('#cancel').click();window.__testMode='ok'")
    time.sleep(.1)
    js("document.querySelector('#history-list button').click()")
    check('post has cookie credentials and CSRF without bearer', "window.__testCalls.some(c => c.path === '/v1/translations' && c.method === 'POST' && c.credentials === 'same-origin' && c.headers['X-CSRF-Token'] === 'test-only-csrf' && !c.headers.Authorization)")
    js("document.querySelector('#swap').click()")
    check('swap reuses result as next input and clears stale result', "document.querySelector('#source-language').value === 'ru' && document.querySelector('#source-text').value === 'TEST FIXTURE — not a live translation' && document.querySelector('#copy').disabled")
    js("document.querySelector('#history-list button').click()")
    check('history reopens record', "document.querySelector('#source-language').value === 'de' && document.querySelector('#result').textContent === 'TEST FIXTURE — not a live translation'")
    js("window.__copied='';Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{window.__copied=text}}});document.querySelector('#copy').click()")
    time.sleep(.1)
    check('copy uses actual result text', "window.__copied === 'TEST FIXTURE — not a live translation'")
    js("document.querySelector('#clear').click()")
    check('clear removes draft and result without deleting history', "!document.querySelector('#source-text').value && !document.querySelector('#result').textContent && document.querySelector('#copy').disabled && document.querySelectorAll('#history-list li').length===1")
    js("document.querySelector('#history-list button').click()")
    js("window.__testMode='upstream';document.querySelector('#translation-form').requestSubmit()")
    time.sleep(.2)
    check('upstream error never renders a successful result', "document.querySelector('#translation-status').textContent.includes('nicht verfügbar') && document.querySelector('#copy').disabled && document.querySelectorAll('#history-list li').length === 1")
    js("window.__testMode='expired';document.querySelector('#translation-form').requestSubmit()")
    time.sleep(.2)
    check('401 clears private input result history and locks translation', "document.querySelector('#translate').disabled && !document.querySelector('#source-text').value && document.querySelectorAll('#history-list li').length === 0 && document.querySelector('#copy').disabled")
    for width in [320,390,768,1440]:
        cdp('Emulation.setDeviceMetricsOverride', width=width, height=900, deviceScaleFactor=1, mobile=width<700)
        check(f'no horizontal overflow at {width}px', 'document.documentElement.scrollWidth <= innerWidth')
    js("document.querySelector('#account').click()")
    check('guest account offers Apple without ChatGPT, status or retry', "document.querySelector('#account-title').textContent === 'Anmelden' && !document.querySelector('#provider-section').checkVisibility() && !document.querySelector('#retry-session').checkVisibility() && document.querySelector('#apple-login').checkVisibility() && !document.querySelector('#account-dialog').innerText.includes('ChatGPT')")
    js("document.querySelector('#close-account').click()")
    js("document.querySelector('#account').click();location.hash='#coach'")
    time.sleep(.1)
    check('hash navigation retains account dialog and modal focus', "document.querySelector('#account-dialog').open && document.querySelector('#account-dialog').contains(document.activeElement)")
    js("document.querySelector('#close-account').click();location.hash='#translator'")
    time.sleep(.1)
    js("window.__testSignedIn=true;window.__testConnected=false;document.querySelector('#retry-session').click()")
    time.sleep(.2)
    js("document.querySelector('#account').click();document.querySelector('#provider-connect').click()")
    time.sleep(.2)
    check('disconnected account offers actual desktop bootstrap instructions', "!document.querySelector('#provider-bootstrap').hidden && document.querySelector('#bootstrap-code').value === 'TEST-ONLY-ONE-TIME-CODE' && document.querySelector('#provider-bootstrap').textContent.includes('go run . connect')")
    js("document.querySelector('#close-account').click()")
    check('closing account clears one-time code from DOM', "!document.querySelector('#bootstrap-code').value && document.querySelector('#provider-bootstrap').hidden")
    js("document.querySelector('#account').click();document.querySelector('#logout').click()")
    time.sleep(.2)
    check('logout is verified by reading exact session back', "document.querySelector('#translation-status').textContent === 'Abgemeldet.' && window.__testCalls.slice(-1)[0].path === '/v1/web/session' && !window.__testSignedIn")
    print(json.dumps({'fixture_only':True,'checks_passed':len(checks),'checks':checks},ensure_ascii=False))
finally:
    cdp('Page.removeScriptToEvaluateOnNewDocument', identifier=script_id)
    goto_url('http://127.0.0.1:8766')
    wait_for_load()
