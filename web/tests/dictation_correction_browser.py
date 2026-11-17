"""Presentation correction only; playback policy v2 is NOT implemented."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
OUT=Path(__file__).resolve().parents[2]/'docs/evidence/dictation-focused-ux/correction'
OUT.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
    browser=p.chromium.launch()
    page=browser.new_page(viewport={'width':390,'height':844})
    errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto('http://127.0.0.1:8876/tests/dictation-focused-fixture.html?locale=ru')
    page.locator('main>div>button').first.click()
    results=[]
    for locale in ['ru','en','de','es','fr']:
        page.get_by_role('combobox',name='Fixture locale').select_option(locale)
        hint=page.locator('.dictation-hint')
        expect(hint).to_be_visible()
        expect(page.locator('.dictation-disclosure')).not_to_have_attribute('open','')
        expect(page.locator('.dictation-disclosure summary')).not_to_contain_text('OpenAI')
        expect(page.locator('.dictation-answer-actions button')).to_have_count(1)
        expect(page.locator('.dictation-input-header button')).to_have_count(1)
        draft=page.locator('.dictation-work textarea')
        assert draft.get_attribute('placeholder') is None
        assert draft.get_attribute('aria-describedby')==hint.get_attribute('id')
        assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
        page.screenshot(path=str(OUT/f'hint-{locale}-mobile.png'),full_page=True)
        results.append({'locale':locale,'no_overflow':True,'hint':hint.inner_text()})
    page.get_by_role('combobox',name='Fixture locale').select_option('ru')
    page.set_viewport_size({'width':1280,'height':900})
    page.screenshot(path=str(OUT/'hint-ru-desktop.png'),full_page=True)
    page.get_by_role('button',name='По предложениям',exact=True).click()
    expect(page.locator('.dictation-hint')).to_contain_text('«Далее»')
    page.set_viewport_size({'width':390,'height':844})
    page.screenshot(path=str(OUT/'hint-ru-sentences-mobile.png'),full_page=True)
    draft=page.locator('.dictation-work textarea')
    draft.fill('Teilwörter Ω')
    page.wait_for_timeout(700)
    assert page.evaluate("calls.filter(x=>x.path.endsWith('/check')||x.path.includes('/audio/')).length")==0
    check=page.locator('.dictation-input-header button')
    draft.focus()
    page.keyboard.press('Shift+Tab')
    expect(check).to_be_focused()
    assert check.evaluate('e=>getComputedStyle(e).outlineStyle')!='none'
    page.keyboard.press('Enter')
    expect(page.locator('.dictation-input-header')).to_have_count(0)
    assert page.evaluate("calls.filter(x=>x.path.endsWith('/check')).length")==1
    assert not errors,errors
    (OUT/'presentation-result.json').write_text(json.dumps({'result':'PASS','policy_v2_implemented':False,'locales':results,'errors':errors,'explicit_keyboard_check_posts':1},ensure_ascii=False,indent=2))
    print(json.dumps({'result':'PASS','locales':len(results),'errors':errors,'policy_v2_implemented':False}))
    browser.close()
