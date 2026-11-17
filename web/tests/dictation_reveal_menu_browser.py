"""Real Chromium/module/CSS; synthetic records, no provider or production calls."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / 'docs/evidence/dictation-focused-ux/reveal-menu'
OUT.mkdir(parents=True, exist_ok=True)
fixture = (REPO / 'web/tests/dictation-focused-fixture.html').read_text()
def expect_dialog(dialog, labels):
    assert dialog.message == labels['Showing the original counts as help for this attempt. Continue?']

results, errors = [], []
with sync_playwright() as p:
    browser = p.chromium.launch()
    for checked in [False, True]:
        for locale in ['ru', 'en', 'de', 'es', 'fr']:
            context = browser.new_context(viewport={'width': 390, 'height': 844})
            source = fixture.replace('ready:[]', 'ready:[0]')
            if checked:
                source = source.replace('checked:false', 'checked:true,text:original')
            context.route('**/dictation-focused-fixture.html*', lambda r: r.fulfill(body=source, content_type='text/html'))
            page = context.new_page()
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(f'http://127.0.0.1:8876/tests/dictation-focused-fixture.html?locale={locale}')
            page.locator('main>div>button').first.click()
            labels = page.evaluate("""async locale => {const {dt}=await import('../dictation-i18n.mjs');return Object.fromEntries(['Show original','Showing the original counts as help for this attempt. Continue?'].map(k=>[k,dt(locale,k)]))}""", locale)
            menu = page.locator('.dictation-attempt-menu')
            summary = menu.locator('summary')
            reveal = menu.get_by_role('button', name=labels['Show original'], exact=True)
            draft = page.locator('.dictation-work textarea')
            if not checked:
                draft.fill('Mein Entwurf — сохранить')
                page.wait_for_timeout(650)
                page.locator('.dictation-player > button').first.click()
            before = page.evaluate('({calls:calls.length,src:fixtureAudio.src,paused:fixtureAudio.paused})')
            expect(page.locator('.dictation-original')).to_have_count(0)
            expect(reveal).not_to_be_visible()
            if locale == 'ru' and not checked:
                page.screenshot(path=str(OUT/'ru-mobile-closed-menu.png'), full_page=True)
            summary.focus()
            page.keyboard.press('Enter')
            expect(reveal).to_be_visible()
            expect(page.locator('.dictation-original')).to_have_count(0)
            assert page.evaluate('calls.length') == before['calls']
            if locale == 'ru' and not checked:
                page.screenshot(path=str(OUT/'ru-mobile-open-menu.png'), full_page=True)
            for _ in range(2 if checked else 3):
                page.keyboard.press('Tab')
            expect(reveal).to_be_focused()
            page.keyboard.press('Escape')
            expect(summary).to_be_focused()
            expect(reveal).not_to_be_visible()
            summary.click()
            if not checked:
                page.once('dialog', lambda d: d.dismiss())
                reveal.click()
                expect(reveal).to_be_focused()
                expect(page.locator('.dictation-original')).to_have_count(0)
                assert page.evaluate('calls.length') == before['calls']
                page.once('dialog', lambda d: (expect_dialog(d, labels), d.accept()))
                page.evaluate('fixture.delay=150')
            reveal.focus()
            page.keyboard.press('Enter')
            if not checked:
                expect(reveal).to_be_disabled()
            expect(page.locator('.dictation-original')).to_have_text('Heute scheint die Sonne. Wir gehen in den Park.')
            expect(summary).to_be_focused()
            expect(menu.get_by_role('button', name=labels['Show original'], exact=True)).to_have_count(0)
            expect(draft).to_have_value('' if checked else 'Mein Entwurf — сохранить')
            assert draft.is_disabled() == checked
            assert page.evaluate('({src:fixtureAudio.src,paused:fixtureAudio.paused})') == {k: before[k] for k in ['src', 'paused']}
            assert page.evaluate("calls.filter(c=>c.path.endsWith('/reveal')).length") == (0 if checked else 1)
            for width in [320, 390, 1280]:
                page.set_viewport_size({'width': width, 'height': 844})
                summary.click()
                assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
                page.keyboard.press('Escape')
            results.append({'locale': locale, 'checked': checked})
            context.close()
    assert not errors, errors
    result = {'result': 'PASS', 'cases': len(results), 'errors': errors, 'results': results}
    (OUT/'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(result))
    browser.close()
