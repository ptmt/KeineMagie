"""Heading-only correction: actual module/CSS, synthetic records, no audio/API inference."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / 'docs/evidence/dictation-focused-ux/headings'
OUT.mkdir(parents=True, exist_ok=True)
fixture = (REPO / 'web/tests/dictation-focused-fixture.html').read_text()
results, errors = [], []
with sync_playwright() as p:
    browser = p.chromium.launch()
    for policy in [False, True]:
        for mode in ['whole', 'sentences']:
            context = browser.new_context(viewport={'width': 390, 'height': 844})
            source = fixture.replace("mode:'whole'", f"mode:'{mode}'")
            if policy:
                source = source.replace("ready:[]", "ready:[],playback_policy_version:1,playback:{whole_starts:0,listens:[]}")
            context.route('**/dictation-focused-fixture.html*', lambda r: r.fulfill(body=source, content_type='text/html'))
            page = context.new_page()
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto('http://127.0.0.1:8876/tests/dictation-focused-fixture.html?locale=ru')
            page.locator('main>div>button').first.click()
            for locale in ['ru', 'en', 'de', 'es', 'fr']:
                page.get_by_label('Fixture locale').select_option(locale)
                strings = page.evaluate("""async ({locale,policy,mode}) => {
                    const {dt}=await import('../dictation-i18n.mjs');
                    return {hint:dt(locale,'Hint'),audio:dt(locale,'Audio details'),
                      rules:dt(locale,(policy?'dictation.policy.hint.':'dictation.hint.')+mode),
                      paid:dt(locale,'dictation.paid.notice'),budget:dt(locale,'dictation.budget.notice')};
                }""", {'locale': locale, 'policy': policy, 'mode': mode})
                hint = page.locator('.dictation-hint')
                expect(hint).to_have_text(strings['rules'])
                expect(hint).to_have_accessible_name(strings['hint'])
                expect(hint.locator('strong')).to_have_count(0)
                draft = page.locator('.dictation-work textarea')
                assert draft.get_attribute('aria-describedby') == hint.get_attribute('id')
                details = page.locator('.dictation-player > .dictation-disclosure')
                summary = details.locator('summary')
                expect(summary).to_have_text('ⓘ')
                expect(summary).to_have_accessible_name(strings['audio'])
                expect(summary.locator('span')).to_have_attribute('aria-hidden', 'true')
                for label in [strings['hint'], strings['audio']]:
                    expect(page.get_by_text(label, exact=True)).to_have_count(0)
                expect(details).not_to_have_attribute('open', '')
                expect(details.locator('p').first).not_to_be_visible()
                count = page.evaluate('calls.length')
                page.locator('.dictation-player > select').focus()
                page.keyboard.press('Tab')
                expect(summary).to_be_focused()
                assert summary.evaluate('e=>getComputedStyle(e).outlineStyle') != 'none'
                box = summary.bounding_box()
                assert box['width'] >= 44 and box['height'] >= 44
                page.keyboard.press('Enter')
                expect(details).to_have_attribute('open', '')
                expect(details.locator('p').nth(0)).to_have_text(strings['paid'])
                expect(details.locator('p').nth(0)).to_be_visible()
                expect(details.locator('p').nth(1)).to_have_text(strings['budget'])
                assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
                page.keyboard.press('Space')
                expect(details).not_to_have_attribute('open', '')
                expect(details.locator('p').first).not_to_be_visible()
                assert page.evaluate('calls.length') == count
                expect(page.locator('.dictation-input-header > button')).to_have_count(1)
                expect(page.locator('.dictation-answer-actions > button')).to_have_count(1)
                assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
                if policy and mode == 'whole' and locale == 'ru':
                    summary.evaluate('e=>e.blur()')
                    page.screenshot(path=str(OUT/'ru-whole-mobile.png'), full_page=True)
                    page.set_viewport_size({'width':1280,'height':900})
                    page.screenshot(path=str(OUT/'ru-whole-desktop.png'), full_page=True)
                    page.set_viewport_size({'width':390,'height':844})
                results.append({'policy': policy, 'mode': mode, 'locale': locale, 'rules': strings['rules'], 'keyboard_disclosure': True})
            context.close()
    assert len(results) == 20
    assert not errors, errors
    result = {'result': 'PASS', 'cases': len(results), 'errors': errors, 'results': results}
    (OUT/'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'result': 'PASS', 'cases': len(results), 'errors': errors}))
    browser.close()
