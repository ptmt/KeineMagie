"""Shipped assets with local synthetic APIs only; never contacts Apple or real accounts.
Run: <playwright-python> web/tests/signin_browser.py [locale|pending|recovery|all]
"""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
import json, os, sys
from playwright.sync_api import sync_playwright, expect  # pyright: ignore[reportMissingImports]

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = Path(os.environ.get('KM_SIGNIN_EVIDENCE', str(Path.home()/'.hermes/cache/scratch/km-signin-evidence')))
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

def wait_routes(page, routes):
    for _ in range(100):
        if routes: return
        page.wait_for_timeout(50)
    raise AssertionError('Expected held request: ' + page.locator('#account-error').inner_text())

def fixture(page):
    state = {'signed': False, 'hold_config': False, 'hold_start': False, 'config_routes': [], 'start_routes': [], 'starts': 0, 'config_calls': 0}
    def api(route):
        path = route.request.url.split(origin)[-1]
        if path == '/v1/web/config':
            state['config_calls'] += 1
            if state['hold_config']: state['config_routes'].append(route); return
            return route.fulfill(json={'apple_available': True, 'pairing_available': True, 'csrf_token': 'synthetic-bootstrap'})
        if path == '/v1/web/session':
            return route.fulfill(status=200 if state['signed'] else 401, json={'user': {'id': 'synthetic-owner'}, 'csrf_token': 'synthetic-session'} if state['signed'] else {})
        if path == '/v1/auth/apple/start':
            state['starts'] += 1
            assert route.request.method == 'POST'
            assert route.request.headers.get('x-csrf-token') == 'synthetic-bootstrap'
            assert route.request.post_data_json == {}
            if state['hold_start']: state['start_routes'].append(route); return
            return route.fulfill(status=503, json={})
        if path == '/v1/provider': return route.fulfill(json={'connected': False, 'status': 'disconnected'})
        if path == '/v1/web/logout': state['signed'] = False; return route.fulfill(json={})
        if path.startswith('/v1/learning/profiles/'): return route.fulfill(json={'cefr': 'unknown', 'self_assessments': []})
        return route.fulfill(json={'items': []})
    page.route('**/v1/**', api)
    page.route('https://appleid.apple.com/**', lambda route: route.fulfill(content_type='text/html', body='<title>Synthetic Apple destination</title><p>Synthetic navigation only</p>'))
    return state

def ready(page):
    page.goto(origin)
    expect(page.locator('#connection-action')).to_be_visible()
    page.locator('#account').click()
    expect(page.locator('#apple-login')).to_be_enabled()

case = sys.argv[1] if len(sys.argv) > 1 else 'all'
try:
    with sync_playwright() as p:
        browser = p.chromium.launch()
        if case in ('locale', 'all'):
            for locale in ['de', 'en', 'ru', 'es', 'fr']:
                for width in [320, 390, 768, 1440]:
                    context = browser.new_context(locale='en-US', viewport={'width': width, 'height': 900})
                    context.add_init_script(f"localStorage.setItem('keinemagie:interface-language:v1', '{locale}')")
                    page = context.new_page(); state = fixture(page); ready(page)
                    check(f'{locale}/{width} guest language settings hidden', not page.locator('.header-language').is_visible() and not page.locator('.account-language').is_visible())
                    check(f'{locale}/{width} saved locale retained', page.locator('html').get_attribute('lang') == locale and page.evaluate("localStorage.getItem('keinemagie:interface-language:v1')") == locale)
                    check(f'{locale}/{width} no overflow', page.evaluate('document.documentElement.scrollWidth <= innerWidth') and page.locator('#account-dialog').evaluate('(el)=>el.scrollWidth<=el.clientWidth'))
                    expect(page.locator('#apple-login img')).to_have_attribute('src', f'/apple-sign-in-{locale}.png')
                    page.wait_for_function("() => document.querySelector('#apple-login img').complete && document.querySelector('#apple-login img').naturalWidth > 0")
                    check(f'{locale}/{width} touch target', page.locator('#apple-login').bounding_box()['height'] >= 44)
                    state['hold_start'] = True
                    page.locator('#apple-login').focus(); page.keyboard.press('Enter')
                    expect(page.locator('#apple-login-progress')).to_be_visible()
                    check(f'{locale}/{width} localized pending', page.locator('#apple-login-progress-label').inner_text() == {'de':'Apple-Anmeldung wird geöffnet …','en':'Opening Apple sign-in …','ru':'Открываем вход через Apple …','es':'Abriendo el inicio de sesión con Apple …','fr':'Ouverture de la connexion Apple …'}[locale])
                    check(f'{locale}/{width} animated spinner', page.locator('.signin-spinner').evaluate('(el)=>getComputedStyle(el).animationName') == 'signin-spin')
                    page.emulate_media(reduced_motion='reduce')
                    check(f'{locale}/{width} reduced motion retains text without animation', page.locator('.signin-spinner').evaluate('(el)=>getComputedStyle(el).animationName') == 'none' and page.locator('#apple-login-progress-label').is_visible())
                    page.screenshot(path=str(ARTIFACTS/f'{locale}-{width}-pending.png'))
                    if locale == 'ru' and width == 390:
                        page.emulate_media(color_scheme='dark'); page.screenshot(path=str(ARTIFACTS/'ru-390-dark-pending.png'))
                    page.keyboard.press('Escape')
                    for route in state['start_routes']: route.fulfill(status=503, json={})
                    state['start_routes'].clear()
                    state['signed'] = True; page.reload(); page.locator('#account').click()
                    expect(page.locator('.account-language')).to_be_visible(); expect(page.locator('.header-language')).to_be_visible()
                    page.select_option('#interface-language-account', 'ru')
                    check(f'{locale}/{width} authenticated language still works', page.locator('html').get_attribute('lang') == 'ru')
                    page.locator('#logout').click(); expect(page.locator('.header-language')).to_be_hidden()
                    check(f'{locale}/{width} logout retains chosen language', page.locator('html').get_attribute('lang') == 'ru')
                    context.close()
        if case in ('pending', 'all'):
            page = browser.new_page(locale='en-US'); state = fixture(page); ready(page)
            state['hold_config'] = True
            immediate = page.evaluate("""() => {
                const button = document.querySelector('#apple-login'); button.click(); button.click();
                const progress = document.querySelector('#apple-login-progress');
                return {busy: button.getAttribute('aria-busy'), disabled: button.disabled,
                    visible: !!progress && !progress.hidden, text: progress?.textContent,
                    role: progress?.getAttribute('role')};
            }""")
            check('progress synchronous before bootstrap network', immediate['busy'] == 'true' and immediate['disabled'] and immediate['visible'] and immediate['role'] == 'status' and 'Apple' in immediate['text'])
            page.wait_for_timeout(100)
            check('double click coalesces bootstrap', len(state['config_routes']) == 1)
            state['hold_config'] = False; state['hold_start'] = True
            state['config_routes'].pop().fulfill(json={'apple_available': True, 'csrf_token': 'synthetic-bootstrap'})
            page.wait_for_timeout(100)
            check('one CSRF protected attempt', state['starts'] == 1 and len(state['start_routes']) == 1)
            check('pending survives session render', page.locator('#apple-login').is_disabled())
            state['start_routes'].pop().fulfill(status=503, json={})
            expect(page.locator('#apple-login')).to_be_enabled()
            expect(page.locator('#apple-login-progress')).to_be_hidden()
            check('failure visible with retry', bool(page.locator('#account-error').inner_text()))
            page.close()
        if case in ('entry', 'all'):
            for entry in ['#connection-action', '#podcast-signin']:
                page = browser.new_page(locale='en-US'); state = fixture(page); ready(page)
                page.locator('#close-account').click()
                if entry == '#podcast-signin': page.locator('a[href="#podcasts"]').click()
                state['hold_config'] = True
                page.locator(entry).click()
                expect(page.locator('#apple-login-progress')).to_be_visible(timeout=1000)
                check(entry + ' starts Apple immediately with progress', page.locator('#apple-login').is_disabled())
                page.keyboard.press('Escape')
                for route in state['config_routes']: route.fulfill(status=503, json={})
                page.close()
        if case in ('recovery', 'all'):
            page = browser.new_page(locale='en-US'); state = fixture(page); ready(page)
            state['hold_config'] = True
            page.locator('#apple-login').click(); page.wait_for_timeout(100)
            page.keyboard.press('Escape'); page.locator('#account').click()
            expect(page.locator('#apple-login')).to_be_enabled(timeout=1000)
            check('cancel restores button immediately', page.locator('#apple-login-progress').is_hidden())
            for route in state['config_routes']: route.fulfill(json={'apple_available': True, 'csrf_token': 'synthetic-bootstrap'})
            state['config_routes'].clear(); page.wait_for_timeout(100)
            check('canceled bootstrap never starts OAuth', state['starts'] == 0)
            state['hold_config'] = False; state['hold_start'] = True
            page.locator('#apple-login').click(); page.wait_for_timeout(100)
            page.locator('#close-account').click(); page.locator('#account').click()
            expect(page.locator('#apple-login')).to_be_enabled()
            state['start_routes'].pop().fulfill(json={'authorization_url': 'https://appleid.apple.com/auth/authorize?synthetic=stale'})
            page.wait_for_timeout(100)
            check('late canceled start never redirects reopened dialog', page.url == origin + '/')
            page.locator('#apple-login').click(); page.wait_for_timeout(100)
            page.evaluate("window.dispatchEvent(new PageTransitionEvent('pageshow', {persisted:true}))")
            expect(page.locator('#apple-login')).to_be_enabled()
            check('BFCache restores retry', page.locator('#apple-login-progress').is_hidden())
            state['start_routes'].pop().fulfill(status=503, json={}); page.wait_for_timeout(100)
            check('BFCache late failure stays cleared', page.locator('#account-error').inner_text() == '')
            page.locator('#apple-login').click(); wait_routes(page, state['start_routes'])
            state['start_routes'].pop().fulfill(json={'authorization_url': 'https://appleid.apple.com/auth/authorize?synthetic=redirect'})
            page.wait_for_url('https://appleid.apple.com/**')
            check('synthetic redirect reaches expected destination', page.title() == 'Synthetic Apple destination')
            page.go_back(); page.locator('#account').click(); expect(page.locator('#apple-login')).to_be_enabled()
            check('real browser Back permits retry', page.locator('#apple-login-progress').is_hidden())
            page.close()
        if case in ('navigation-cancel', 'all'):
            page = browser.new_page(locale='en-US'); state = fixture(page); ready(page)
            state['hold_start'] = True; destinations = []
            page.route('https://appleid.apple.com/**', lambda route: destinations.append(route))
            page.evaluate("""() => setTimeout(() => document.querySelector('#close-account').click(), 1500)""")
            page.locator('#apple-login').click(); wait_routes(page, state['start_routes'])
            state['start_routes'].pop().fulfill(json={'authorization_url': 'https://appleid.apple.com/auth/authorize?synthetic=cancel'})
            page.wait_for_timeout(2000)
            check('cancel exercised a held destination', len(destinations) == 1)
            destinations.pop().fulfill(content_type='text/html', body='<title>Canceled synthetic Apple</title>')
            page.wait_for_timeout(200)
            check('explicit cancel stops delayed navigation', page.url == origin + '/')
            page.locator('#account').click(); expect(page.locator('#apple-login')).to_be_enabled()
            page.close()
        if case in ('identity', 'all'):
            page = browser.new_page(locale='en-US'); state = fixture(page); ready(page)
            state['hold_start'] = True
            page.locator('#apple-login').click(); wait_routes(page, state['start_routes'])
            state['signed'] = True
            page.locator('#retry-session').evaluate('(el)=>el.click()')
            expect(page.locator('#signed-in-account')).to_be_visible()
            check('new authenticated identity clears pending sign-in', page.locator('#apple-login').get_attribute('aria-busy') == 'false' and page.locator('#apple-login-progress').is_hidden())
            state['start_routes'].pop().fulfill(json={'authorization_url': 'https://appleid.apple.com/auth/authorize?synthetic=old-identity'})
            page.wait_for_timeout(200)
            check('new identity fences late authorization', page.url == origin + '/')
            page.close()
        if case in ('timeout', 'all'):
            page = browser.new_page(locale='en-US'); state = fixture(page); ready(page)
            state['hold_config'] = True
            page.locator('#apple-login').click()
            expect(page.locator('#apple-login')).to_be_enabled(timeout=17000)
            check('stalled bootstrap times out with recovery', 'try again' in page.locator('#account-error').inner_text())
            state['config_routes'].pop().fulfill(json={'apple_available': True, 'csrf_token': 'synthetic-bootstrap'})
            page.wait_for_timeout(100); check('timeout late bootstrap cannot start OAuth', state['starts'] == 0)
            state['hold_config'] = False; state['hold_start'] = True
            page.locator('#apple-login').click(); page.wait_for_timeout(100)
            wait_routes(page, state['start_routes'])
            state['start_routes'].pop().abort('failed')
            expect(page.locator('#apple-login')).to_be_enabled()
            check('network failure restores retry', bool(page.locator('#account-error').inner_text()))
            destinations = []
            samples = []
            page.on('console', lambda message: samples.append(json.loads(message.text[7:])) if message.text.startswith('SIGNIN:') else None)
            page.evaluate("""() => setInterval(() => console.log('SIGNIN:' + JSON.stringify({busy:document.querySelector('#apple-login')?.disabled, visible:!document.querySelector('#apple-login-progress')?.hidden, error:document.querySelector('#account-error')?.textContent})), 100)""")
            page.route('https://appleid.apple.com/**', lambda route: destinations.append(route))
            page.locator('#apple-login').click(); page.wait_for_timeout(100)
            wait_routes(page, state['start_routes'])
            state['start_routes'].pop().fulfill(json={'authorization_url': 'https://appleid.apple.com/auth/authorize?synthetic=held'})
            page.wait_for_timeout(16000)
            check('Apple destination really held', len(destinations) == 1)
            check('pending remains during delayed Apple navigation', any(s.get('busy') and s.get('visible') for s in samples))
            check('stalled navigation permits retry after deadline', any(not s.get('busy') and 'try again' in (s.get('error') or '') for s in samples))
            for route in destinations: route.fulfill(content_type='text/html', body='<title>Late synthetic Apple</title>')
            page.wait_for_timeout(200)
            check('timeout stops delayed redirect from taking user away', page.url == origin + '/')
            page.close()
        print(json.dumps({'synthetic_only': True, 'checks_passed': len(checks), 'checks': checks}, ensure_ascii=False))
        browser.close()
finally:
    server.shutdown()
