"""Real Chromium system clipboard, synthetic API only; never calls a provider."""
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from threading import Thread
import json
from playwright.sync_api import sync_playwright  # pyright: ignore[reportMissingImports]

root = Path(__file__).resolve().parents[1]
TEXT = '  Übersetzung 👩🏽‍💻 Привет e\u0301\n\n' + ('Zeile 日本語\t  {"nested":{"literal":"\\n","items":[1,2]}}\n' * 1200) + '  Ende\n '
record = dict(id='copy-fixture', text='SOURCE NOT OUTPUT', translation=TEXT, source_language='ru', target_language='de', idioms=[], patterns=[], vocabulary=[])
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=str(root), **kw)
    def log_message(self, format, *args): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Thread(target=server.serve_forever, daemon=True).start()
origin = 'http://localhost:' + str(server.server_port)
checks = []
def check(name, condition):
    assert condition, name
    checks.append(name)
try:
    with sync_playwright() as p:
        browser = p.chromium.launch()
        context = browser.new_context(permissions=['clipboard-read', 'clipboard-write'], locale='en-US')
        page = context.new_page()
        errors = []; calls = []; owner = ['owner-A']
        page.on('pageerror', lambda e: errors.append(str(e)))
        def api(route):
            path = route.request.url.split(origin)[1]; calls.append(path)
            bodies = {
                '/v1/web/config': dict(apple_available=False, pairing_available=True, csrf_token='fixture'),
                '/v1/web/session': dict(user=dict(id=owner[0]), csrf_token='fixture', provider=dict(connected=True, status='connected', selected_model='fixture')),
                '/v1/provider': dict(connected=True, status='connected', selected_model='fixture'),
                '/v1/translations': dict(items=[record]) if owner[0] == 'owner-A' else dict(items=[]),
                '/v1/podcasts': dict(items=[], worker_available=False), '/v1/podcasts/subscriptions': dict(items=[])}
            route.fulfill(json=bodies.get(path, {}))
        page.route('**/v1/**', api)
        page.goto(origin)
        page.locator('#history-list button').click()
        page.locator('#copy:enabled').wait_for()
        page.locator('#copy').click()
        page.wait_for_function("() => document.querySelector('#copy').textContent === 'Copied'")
        check('modern clipboard exact full Unicode multiline whitespace and JSON literal', page.evaluate('navigator.clipboard.readText()') == TEXT)
        check('brief visible copied confirmation', page.locator('#copy').inner_text() == 'Copied')
        page.wait_for_function("() => document.querySelector('#copy').textContent === 'Copy'")
        for locale, label, copied in [('de','Kopieren','Kopiert'),('en','Copy','Copied'),('ru','Копировать','Скопировано'),('es','Copiar','Copiado'),('fr','Copier','Copié')]:
            page.select_option('#interface-language-header', locale)
            before = len(calls)
            page.locator('#copy').click()
            page.wait_for_function('(copied) => document.querySelector("#copy").textContent === copied', arg=copied)
            check(locale + ' localized confirmation', page.locator('#copy').inner_text() == copied)
            check(locale + ' copy adds no API work', len(calls) == before)
            page.wait_for_function('(label) => document.querySelector("#copy").textContent === label', arg=label)
        page.select_option('#interface-language-header','en')
        for width in [390, 1440]:
            page.set_viewport_size(dict(width=width,height=844))
            page.locator('#copy').scroll_into_view_if_needed()
            check(str(width) + ' reachable 44px target without overlay', page.locator('#copy').bounding_box()['height'] >= 44 and page.locator('#copy').is_visible())
            page.locator('#copy').click()
            check(str(width) + ' exact clipboard', page.evaluate('navigator.clipboard.readText()') == TEXT)
        # Denial of modern API must use the actual browser execCommand, not a mock clipboard.
        page.wait_for_function("() => document.querySelector('#copy').textContent === 'Copy'")
        page.evaluate("navigator.clipboard.writeText('fallback sentinel')")
        page.evaluate("""() => { window.realClipboard=navigator.clipboard; Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:()=>Promise.reject(new DOMException('Denied','NotAllowedError'))}}); const el=document.querySelector('#source-text');el.focus();el.setSelectionRange(2,7);window.scrollTo(0,0); }""")
        page.locator('#copy').evaluate('(el) => el.click()')
        page.wait_for_function("() => document.querySelector('#copy').textContent === 'Copied'")
        check('fallback exact actual clipboard', page.evaluate('window.realClipboard.readText()') == TEXT)
        check('fallback restores editor focus selection and removes private textarea', page.evaluate("document.activeElement.id==='source-text' && document.activeElement.selectionStart===2 && document.activeElement.selectionEnd===7 && !document.querySelector('textarea[aria-hidden=true]')"))
        # Both APIs failing must never claim success.
        page.evaluate("""() => { document.execCommand=()=>false; }""")
        page.locator('#copy').click()
        page.wait_for_function("() => document.querySelector('#translation-status').textContent.includes('failed')")
        check('failure is honest inline', 'failed' in page.locator('#translation-status').inner_text().lower())
        owner[0] = 'owner-B'
        page.locator('#account').click();page.locator('#retry-session').click()
        page.wait_for_function("() => document.querySelector('#copy').disabled")
        check('owner change removes output and copy availability', page.locator('#result').text_content() == '' and page.locator('#copy').is_disabled())
        check('owner change does not clear system clipboard', page.evaluate('window.realClipboard.readText()') == TEXT)
        check('no page errors', not errors)
        print(json.dumps(dict(fixture_only=True, checks_passed=len(checks), checks=checks, characters=len(TEXT))))
        browser.close()
finally:
    server.shutdown()
