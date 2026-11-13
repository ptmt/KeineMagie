"""Real Chromium, shipped HTTP assets; all identity APIs are synthetic.
Run with a Python environment containing Playwright. No account/provider replay.
"""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
import json, os
from playwright.sync_api import sync_playwright, expect  # pyright: ignore[reportMissingImports]

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = Path(os.environ.get('KM_HEADER_EVIDENCE', str(Path.home()/'.hermes/cache/scratch/km-header-evidence')))
ARTIFACTS.mkdir(parents=True, exist_ok=True)
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(ROOT), **kwargs)
    def log_message(self, format, *args): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Thread(target=server.serve_forever, daemon=True).start()
origin = f'http://127.0.0.1:{server.server_port}'
checks = []
def check(name, value):
    assert value, name
    checks.append(name)

def fixture(page):
    state = {'hold': True, 'routes': [], 'owner': 'synthetic-owner', 'status': 200, 'calls': []}
    def api(route):
        path = route.request.url.split(origin)[-1]; state['calls'].append(path)
        if path == '/v1/web/session':
            if state['hold']: state['routes'].append(route); return
            return session_reply(route)
        if path == '/v1/web/config': return route.fulfill(json={'apple_available': True, 'pairing_available': True, 'csrf_token': 'synthetic-bootstrap'})
        if path == '/v1/provider': return route.fulfill(json={'connected': False, 'status': 'disconnected'})
        if path == '/v1/web/logout':
            assert route.request.headers.get('x-csrf-token') == 'synthetic-session'
            state['status'] = 401
            return route.fulfill(json={})
        if path.startswith('/v1/learning/profiles/'): return route.fulfill(json={'cefr': 'unknown', 'self_assessments': []})
        return route.fulfill(json={'items': []})
    def session_reply(route):
        return route.fulfill(status=state['status'], json={'user': {'id': state['owner']}, 'csrf_token': 'synthetic-session'} if state['status'] == 200 else {})
    def release():
        state['hold'] = False
        for route in state['routes']: session_reply(route)
        state['routes'].clear()
    page.route('**/v1/**', api)
    return state, release

def held(page, state):
    for _ in range(100):
        if state['routes']: return
        page.wait_for_timeout(20)
    raise AssertionError('Expected delayed session request')

def geometry(page):
    return page.evaluate("""() => ['.topbar','.wordmark','.section-nav','.header-account'].map(s=>{const r=document.querySelector(s).getBoundingClientRect();return [r.x,r.y,r.width,r.height]})""")

try:
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for width in [1440, 390, 320, 768]:
            context = browser.new_context(locale='en-US', viewport={'width': width, 'height': 900})
            page = context.new_page(); state, release = fixture(page)
            page.goto(origin); held(page, state); page.wait_for_timeout(150)
            page.screenshot(path=str(ARTIFACTS/f'{width}-initial-delayed.png'))
            check(f'{width} unknown never shows signed-out account', not page.locator('#account-label').is_visible() or page.locator('#account-label').inner_text() != 'Sign in')
            check(f'{width} unknown hides language', not page.locator('.header-language').is_visible())
            check(f'{width} unknown private inputs locked', page.locator('#source-text').is_disabled())
            check(f'{width} identity gates private reads', not any(x in state['calls'] for x in ['/v1/translations','/v1/provider','/v1/learning/coach']))
            initial = geometry(page); release()
            expect(page.locator('#account-label')).to_have_text('Profile')
            expect(page.locator('.header-language')).to_be_visible()
            check(f'{width} stable initial header geometry', initial == geometry(page))
            page.screenshot(path=str(ARTIFACTS/f'{width}-signedin.png'))
            page.locator('#source-text').fill('Synthetic same-owner draft')
            before = geometry(page)
            state['hold'] = True; page.locator('#retry-session').evaluate('(el)=>el.click()'); held(page, state)
            expect(page.locator('#account-label')).to_have_text('Profile')
            check(f'{width} refresh keeps verified header and draft', before == geometry(page) and page.locator('#source-text').input_value() == 'Synthetic same-owner draft' and page.locator('.header-language').is_visible())
            page.select_option('#interface-language-header', 'fr')
            check(f'{width} locale preserves pending request', len(state['routes']) == 1 and page.locator('#source-text').input_value() == 'Synthetic same-owner draft')
            page.screenshot(path=str(ARTIFACTS/f'{width}-refresh-fr.png'))
            localized = geometry(page)
            state['status'] = 503; release()
            expect(page.locator('#connection-title')).to_contain_text('session')
            check(f'{width} transient error retains verified identity', page.locator('.header-language').is_visible() and page.locator('#source-text').input_value() == 'Synthetic same-owner draft')
            state['hold'] = True; state['status'] = 401
            page.locator('#retry-session').evaluate('(el)=>el.click()'); held(page, state); release()
            expect(page.locator('.header-language')).to_be_hidden()
            check(f'{width} 401 clears private draft', page.locator('#source-text').input_value() == '' and page.locator('#source-text').is_disabled())
            check(f'{width} guest header geometry stable', localized == geometry(page))
            page.screenshot(path=str(ARTIFACTS/f'{width}-guest-fr.png'))
            check(f'{width} no horizontal overflow', page.evaluate('document.documentElement.scrollWidth <= innerWidth'))
            # Fast guest -> authenticated -> logout transitions, no real cookies.
            state['status'] = 200
            page.locator('#retry-session').evaluate('(el)=>el.click()')
            expect(page.locator('.header-language')).to_be_visible()
            page.locator('#source-text').fill('Synthetic prior-owner draft')
            state['owner'] = 'synthetic-other-owner'
            page.locator('#retry-session').evaluate('(el)=>el.click()')
            expect(page.locator('#source-text')).to_have_value('')
            check(f'{width} owner replacement clears private draft', page.locator('#source-text').input_value() == '')
            page.locator('#account').click(); page.locator('#logout').click()
            expect(page.locator('#account-dialog')).not_to_be_visible()
            expect(page.locator('.header-language')).to_be_hidden()
            check(f'{width} logout retains stable header', localized == geometry(page))
            state['status'] = 503; page.reload()
            expect(page.locator('#account')).to_be_visible()
            check(f'{width} cold error offers neutral account not guessed sign-in', page.locator('#account-label').inner_text() == 'Ouvrir le compte' and page.locator('#source-text').is_disabled())
            state['status'] = 200
            page.locator('#connection-action').click()
            expect(page.locator('.header-language')).to_be_visible()
            check(f'{width} cold error retry recovers', page.locator('#source-text').is_enabled())
            state['hold'] = True
            page.evaluate("window.dispatchEvent(new PageTransitionEvent('pageshow', {persisted:true}))")
            held(page, state)
            check(f'{width} BFCache revalidates without guessed guest', not page.locator('#account').is_visible() and page.locator('#source-text').is_disabled())
            release(); expect(page.locator('#account')).to_be_visible()
            for locale in ['de', 'en', 'ru', 'es', 'fr']:
                page.select_option('#interface-language-header', locale)
                signed_geometry = geometry(page)
                state['status'] = 401
                page.locator('#retry-session').evaluate('(el)=>el.click()')
                expect(page.locator('.header-language')).to_be_hidden()
                check(f'{width}/{locale} auth transition geometry', signed_geometry == geometry(page))
                check(f'{width}/{locale} labels contained', page.locator('#account-label').evaluate('(el)=>el.getBoundingClientRect().right<=el.parentElement.getBoundingClientRect().right') and page.evaluate('document.documentElement.scrollWidth <= innerWidth'))
                state['status'] = 200
                page.locator('#retry-session').evaluate('(el)=>el.click()')
                expect(page.locator('.header-language')).to_be_visible()
            context.close()
        print(json.dumps({'synthetic_only': True, 'checks_passed': len(checks), 'checks': checks}))
        browser.close()
finally:
    server.shutdown()
