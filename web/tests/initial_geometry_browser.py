"""Initial paint/async phases, not only settled controls. Synthetic APIs only."""
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from threading import Thread
import json, os
os.environ['PW_TEST_SCREENSHOT_NO_FONTS_READY'] = '1'
from playwright.sync_api import sync_playwright
ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get('KM_GEOMETRY_OUTPUT', '/Users/tinyserve/.hermes/cache/scratch/km-jump-fix/web'))
OUT.mkdir(parents=True, exist_ok=True)
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=str(ROOT), **kw)
    def log_message(self, *a): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Thread(target=server.serve_forever, daemon=True).start()
origin = f'http://127.0.0.1:{server.server_port}'
selectors = ['.topbar','.language-bar','#source-text','#style-controls','.translation-panels','#translation-form','#translate','#history','#history-list']
init = '''window.samples=[];window.phase='boot';function sample(){const boxes=Object.fromEntries(SELECTORS.map(s=>{let e=document.querySelector(s);if(!e)return [s,null];let r=e.getBoundingClientRect();return [s,[r.x,r.y+scrollY,r.width,r.height]]}));let v={phase:window.phase,scrollY,boxes};if(JSON.stringify(v)!==window.lastSample){window.samples.push(v);window.lastSample=JSON.stringify(v)}requestAnimationFrame(sample)}requestAnimationFrame(sample)'''.replace('SELECTORS',json.dumps(selectors))
cases=[]; failures=[]; checks=0
with sync_playwright() as p:
    browser=p.chromium.launch()
    for locale in os.environ.get('KM_GEOMETRY_LOCALES','de,en,ru,es,fr').split(','):
      for width in [390,1440]:
       for outcome in ['connected','disconnected','error','guest']:
        c=browser.new_context(viewport={'width':width,'height':1000},locale=locale)
        c.add_init_script(init)
        c.add_init_script(f"localStorage.setItem('keinemagie:interface-language:v1','{locale}')")
        page=c.new_page();held={};posts=[]
        def route(r):
            path=r.request.url.split(origin)[-1]
            if path.startswith('/v1/') and r.request.method!='GET': posts.append(path)
            if path in ['/app.mjs','/v1/web/session','/v1/provider','/v1/translations']: held[path]=r
            elif path=='/v1/web/config': r.fulfill(json={'apple_available':True,'pairing_available':True,'chatgpt_connect_available':True})
            elif path.startswith('/v1/'):
                r.fulfill(json={'items':[],'turns':[],'observations':[]})
            else: r.continue_()
        page.route('**/*',route)
        tag=f'{locale}-{width}-{outcome}'
        def check(ok,message):
            global checks
            checks+=1
            if not ok: failures.append(f'{tag}: {message}')
        page.goto(origin,wait_until='commit');page.wait_for_timeout(180)
        if width==390 and outcome=='error': page.screenshot(path=str(OUT/f'{tag}-initial.png'))
        check(page.locator('#history-status').inner_text()=='','no guessed guest history before identity')
        page.evaluate("window.phase='module'");held.pop('/app.mjs').continue_();page.wait_for_timeout(220)
        page.evaluate("window.phase='session'")
        held.pop('/v1/web/session').fulfill(status=401 if outcome=='guest' else 200,json={} if outcome=='guest' else {'user':{'id':'synthetic-geometry-owner'},'csrf_token':'synthetic-only'})
        page.wait_for_timeout(220)
        if outcome!='guest':
            page.locator('#source-text').fill('Synthetic draft 👩🏽‍💻 preserved')
            page.locator('#source-text').evaluate('(e)=>e.setSelectionRange(2,8)')
            page.evaluate("window.phase='provider-pending'");page.wait_for_timeout(80)
            page.evaluate("window.phase='provider-settled'");r=held.pop('/v1/provider')
            if outcome=='error':r.abort('failed')
            else:r.fulfill(json={'connected':outcome=='connected','status':outcome,'selected_model':'synthetic-only','models':['synthetic-only']})
            page.wait_for_timeout(150)
            check(page.evaluate("document.activeElement.id==='source-text' && document.activeElement.selectionStart===2 && document.activeElement.selectionEnd===8"),'provider preserves focus and selection')
            page.evaluate("window.phase='history'");held.pop('/v1/translations').fulfill(json={'items':[{'id':'synthetic-history','created_at':'2026-11-10T12:00:00Z','text':'Synthetic source','translation':'Synthetic translation','source_language':'ru','target_language':'de','idioms':[],'patterns':[],'vocabulary':[]}]})
            page.wait_for_timeout(100)
            row=page.locator('#history-list li').first
            saved_bounds=row.bounding_box()
            page.locator('#refresh-history').evaluate('(e)=>e.click()');page.wait_for_timeout(60)
            held.pop('/v1/translations').fulfill(status=503,json={});page.wait_for_timeout(80)
            check(row.bounding_box()==saved_bounds,'history failure retains existing row bounds')
            check(page.locator('#history-status').inner_text()!='' and page.locator('#refresh-history').is_enabled(),'history error stays actionable')
        else:page.evaluate("window.phase='guest'");page.wait_for_timeout(100)
        frames=page.evaluate('window.samples')
        visible=[f for f in frames if f['boxes']['#translation-form'] and f['boxes']['#translation-form'][3]>0]
        first=visible[0]
        for f in visible:
            for selector in ['.topbar','.language-bar','#source-text','.translation-panels','#translation-form','#translate','#history']:
                # History grows with actual records, but its start may not move.
                dims=range(3) if selector=='#history' else range(4)
                check(all(abs(f['boxes'][selector][i]-first['boxes'][selector][i])<.6 for i in dims),f"{f['phase']} changed {selector}: {first['boxes'][selector]} -> {f['boxes'][selector]}")
        if outcome!='guest':
            source=page.locator('#source-text')
            for language in ['de','en','ru','es','fr']:
                source.focus();source.evaluate('(e)=>e.setSelectionRange(2,8)')
                page.locator('#interface-language-header').evaluate('(e,v)=>{e.value=v;e.dispatchEvent(new Event("change",{bubbles:true}))}',language)
                check(source.input_value()=='Synthetic draft 👩🏽‍💻 preserved' and source.evaluate('(e)=>document.activeElement===e && e.selectionStart===2 && e.selectionEnd===8'),'locale preserves draft/focus/selection')
            page.locator('.section-nav a[href="#coach"]').click();page.wait_for_timeout(50)
            page.locator('.section-nav a[href="#translator"]').click();page.wait_for_timeout(100)
            check(page.evaluate('scrollY')==0,'Coach return starts at page top, not fragment offset')
            check(source.input_value()=='Synthetic draft 👩🏽‍💻 preserved','navigation retains draft')
            page.go_back();page.wait_for_timeout(60);check(page.locator('#coach').is_visible(),'Back retains section URL')
            page.go_forward();page.wait_for_timeout(60);check(page.locator('#translator').is_visible() and page.evaluate('scrollY')==0,'Forward returns without fragment jump')
            if outcome=='error':
                page.locator('#account').click();check(page.locator('#provider-detail').inner_text()!='','provider error actionable in settings')
                check(page.locator('#retry-session').is_visible(),'settings retry visible');page.locator('#close-account').click()
        check(page.evaluate('document.documentElement.scrollWidth<=innerWidth'),'no horizontal overflow')
        check(not posts,'no inference or mutation')
        if width==390 and outcome in ['error','guest']:page.screenshot(path=str(OUT/f'{tag}-settled.png'))
        cases.append({'locale':locale,'width':width,'outcome':outcome,'frames':frames})
        for r in list(held.values()):r.abort()
        c.close()
        (OUT/'frames.json').write_text(json.dumps(cases,indent=2))
    browser.close()
server.shutdown()
(OUT/'result.json').write_text(json.dumps({'cases':len(cases),'checks':checks,'failures':failures},indent=2))
print(json.dumps({'cases':len(cases),'checks':checks,'failures':failures},indent=2))
assert not failures
