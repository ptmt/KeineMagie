"""Disposable real Go/API + Node journals + actual Swift AppModels + Chromium UI.
Run with the existing Playwright Python. No real account or AI/TTS calls.
"""
from pathlib import Path
import json, os, subprocess, tempfile, time
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2]
SCRATCH=Path.home()/'.hermes/cache/scratch'
checks=[]
def check(name, value):
    assert value, name
    checks.append(name)

def browser_checks(f, folder):
    with sync_playwright() as p:
        browser=p.chromium.launch()
        contexts=[browser.new_context(locale='ru-RU') for _ in range(2)]
        pages=[]; errors=[]; inference=[]
        for i,context in enumerate(contexts):
            context.add_cookies([dict(name=f['cookie_name'],value=f['cookie'],url=f['url'].replace('http:', 'https:'),secure=True,httpOnly=True,sameSite='Strict')])
            page=context.new_page()
            page.on('pageerror',lambda e:errors.append(str(e)))
            page.on('request',lambda r:inference.append(r.url) if r.method=='POST' and ('/v1/translations' in r.url or '/tts' in r.url or '/v1/translation-followups' in r.url) else None)
            legacy=[dict(id='custom-browser-shared',name='Browser legacy '+str(i),instructions='Keep exact browser content '+str(i))]
            key='keinemagie:translation-prompts:v1:'+f['owner']
            page.add_init_script('if (!localStorage.getItem('+json.dumps(key)+')) localStorage.setItem('+json.dumps(key)+','+json.dumps(json.dumps(legacy))+');')
            page.goto(f['url']); page.locator('#add-prompt').wait_for(state='visible')
            page.wait_for_function("!document.querySelector('#add-prompt').disabled")
            page.wait_for_function("()=>Object.keys(localStorage).filter(k=>k.startsWith('keinemagie:profile-sync:')).some(k=>{const s=JSON.parse(localStorage[k]);return s.migrated && s.pending.length===0})")
            pages.append(page)
        a,b=pages
        def sync(page):
            target=page.evaluate("async()=>{const r=await fetch('/v1/translation-profiles');return (await r.json()).revision}")
            deadline=time.monotonic()+15
            while time.monotonic()<deadline:
                page.evaluate("window.dispatchEvent(new Event('online'))")
                page.wait_for_timeout(100)
                if page.evaluate("revision=>Object.keys(localStorage).filter(k=>k.startsWith('keinemagie:profile-sync:')).some(k=>{const s=JSON.parse(localStorage[k]);return s.revision>=revision && (s.pending.length===0 || s.pending[0].conflict)})",target):return
            raise AssertionError('profile sync did not settle')
        sync(a);sync(b)
        check('two actual browser contexts import same legacy ID with different contents',a.locator('#style-chips').get_by_text('Browser legacy 0',exact=True).count()==1 and a.locator('#style-chips').get_by_text('Browser legacy 1',exact=True).count()==1)
        a.locator('#source-text').fill('Unsaved composer 👩🏽‍💻 é')
        a.locator('#style-chips').get_by_text('Browser legacy 0',exact=True).click();a.locator('#edit-prompt').click()
        a.locator('#prompt-name').fill('Local editing buffer');a.locator('#prompt-name').evaluate('(el)=>{el.focus();el.setSelectionRange(2,8)}')
        b.locator('#style-chips').get_by_text('Browser legacy 0',exact=True).click();b.locator('#edit-prompt').click();b.locator('#prompt-name').fill('Remote browser title');b.locator('#save-prompt').click();sync(b);sync(a)
        check('polling does not reset profile editor draft focus or selection',a.locator('#prompt-name').input_value()=='Local editing buffer' and a.locator('#prompt-name').evaluate('(el)=>document.activeElement===el&&el.selectionStart===2&&el.selectionEnd===8'))
        a.locator('#save-prompt').click();a.locator('#profile-conflict-copy').wait_for(state='visible')
        check('stale editor save exposes explicit conflict',a.locator('#profile-conflict-remote').is_visible())
        a.locator('#profile-conflict-copy').click();sync(a);sync(b)
        check('keep both preserves full distinct records',b.locator('#style-chips').get_by_text('Remote browser title',exact=True).count()==1 and b.locator('#style-chips').get_by_text('Local editing buffer',exact=True).count()==1)
        check('profile operations preserve translator draft',a.locator('#source-text').input_value()=='Unsaved composer 👩🏽‍💻 é')
        b.locator('#style-chips').get_by_text('Remote browser title',exact=True).click()
        a.locator('#style-chips').get_by_text('Remote browser title',exact=True).click();a.locator('#edit-prompt').click();a.locator('#delete-prompt').click();sync(a);sync(b)
        check('remote deletion falls back to builtin normal',b.locator('#style-chips button[aria-pressed="true"]').count()==1 and b.locator('#style-chips button[aria-pressed="true"]').text_content()=='Обычный')
        b.route('**/v1/translation-profiles',lambda route:route.abort())
        b.locator('#add-prompt').click();b.locator('#prompt-name').fill('Offline browser profile');b.locator('#prompt-instructions').fill('  Literal offline é\nNo inference.  ');b.locator('#save-prompt').click()
        b.reload();b.locator('#style-chips').get_by_text('Offline browser profile',exact=True).wait_for()
        check('offline operation survives actual browser reload',b.locator('#style-chips').get_by_text('Offline browser profile',exact=True).count()==1)
        b.unroute('**/v1/translation-profiles');sync(b)
        b.locator('#profile-sync-status').wait_for(state='hidden')
        sync(a);a.locator('#style-chips').get_by_text('Offline browser profile',exact=True).wait_for()
        check('offline profile reaches second browser once',a.locator('#style-chips').get_by_text('Offline browser profile',exact=True).count()==1)
        check('only visible redundant labels removed; localized AX labels remain',a.locator('label[for="source-text"]').evaluate('(el)=>el.classList.contains("sr-only")') and a.get_by_role('textbox',name='Ваш текст',exact=True).count()==1 and a.get_by_role('region',name='Перевод',exact=True).count()==1)
        a.set_viewport_size(dict(width=1440,height=960));a.screenshot(path=str(folder/'profiles-desktop.png'),full_page=True)
        check('removing headings preserves trailing control placement',a.locator('#clear').evaluate('(el)=>el.getBoundingClientRect().left>el.parentElement.getBoundingClientRect().left+el.parentElement.getBoundingClientRect().width/2') and a.locator('.result-actions').evaluate('(el)=>el.getBoundingClientRect().left>el.parentElement.getBoundingClientRect().left+el.parentElement.getBoundingClientRect().width/2'))
        a.set_viewport_size(dict(width=390,height=844));a.screenshot(path=str(folder/'profiles-mobile.png'),full_page=True)
        check('mobile stays within viewport',a.evaluate('document.documentElement.scrollWidth<=innerWidth'))
        check('no JavaScript page errors',not errors)
        check('typing profile CRUD and synchronization call no inference endpoints',not inference)
        browser.close()

with tempfile.TemporaryDirectory(prefix='km-profile-sync-',dir=SCRATCH) as temporary:
    directory=Path(temporary); env=dict(os.environ,KM_PROFILE_BRIDGE_DIR=temporary)
    log=open(directory/'server.log','w')
    server=subprocess.Popen(['go','test','-run','^TestTranslationProfilesClientBridge$','-count=1','.'],cwd=ROOT/'server',env=env,stdout=log,stderr=subprocess.STDOUT)
    try:
        deadline=time.monotonic()+45
        while not (directory/'ready.json').exists():
            if server.poll() is not None or time.monotonic()>deadline: raise RuntimeError((directory/'server.log').read_text())
            time.sleep(.05)
        f=json.loads((directory/'ready.json').read_text())
        if not os.environ.get('KM_PROFILE_BROWSER_ONLY'):
            subprocess.run(['node','--test','web/tests/profile-sync-wire.test.mjs'],cwd=ROOT,env=env,check=True)
            subprocess.run(['python3','native/ci/test_connection_lifecycle.py'],cwd=ROOT,env=env,check=True)
        evidence=SCRATCH/'profile-sync-browser';evidence.mkdir(exist_ok=True)
        browser_checks(f,evidence)
        (directory/'stop').write_text('done')
        if server.wait(timeout=10)!=0: raise RuntimeError((directory/'server.log').read_text())
        print(json.dumps(dict(checks=checks,count=len(checks),screenshots=[str(evidence/'profiles-desktop.png'),str(evidence/'profiles-mobile.png')]),ensure_ascii=False,indent=2))
    finally:
        (directory/'stop').write_text('done')
        try:server.wait(timeout=10)
        except subprocess.TimeoutExpired:server.terminate();server.wait(timeout=10)
        log.close()
