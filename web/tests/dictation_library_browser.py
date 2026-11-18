"""Actual module/CSS in Chromium, synthetic API only; no accounts or inference.
Run against python3 -m http.server 8876 --directory web. --baseline captures RED.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / 'docs/evidence/dictation-library'
OUT.mkdir(parents=True, exist_ok=True)
BASE = 'http://127.0.0.1:8876/tests/dictation-focused-fixture.html'
source = (REPO / 'web/tests/dictation-focused-fixture.html').read_text().replace('Ein Spaziergang im Park', 'Prävention gegen Einbrecher')
# Match the real list projection: drafts/plans/results are not available there.
source = source.replace('return {items:clone(records)}', "return {items:clone(records).map(v=>({...v,draft:'',plan:[],differences:null}))}")
source = source.replace("ready:[]", "ready:[0],word_count:120,audio_duration_seconds:95")
source = source.replace("const original='Heute scheint die Sonne. Wir gehen in den Park.';", "const original=('Heute scheint die Sonne. Wir gehen gerne in den Park. ').repeat(12).trim();")
source = source.replace("if(options.method==='DELETE')", "if(!v)throw Object.assign(Error('missing'),{status:404});if(options.method==='DELETE')")
source = source.replace('window.calls=[];', "window.libraryRecords=()=>records;window.setLibraryRecords=v=>records=v;window.calls=[];")
errors, results = [], []
with sync_playwright() as p:
    browser = p.chromium.launch()
    context = browser.new_context(viewport={'width':1280,'height':900})
    context.route('**/dictation-focused-fixture.html*', lambda route: route.fulfill(body=source, content_type='text/html'))
    page = context.new_page()
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto(BASE+'?locale=ru')
    row = page.locator('main>div>button').first
    expect(row).to_contain_text('Prävention gegen Einbrecher')
    if '--baseline' in sys.argv:
        for width in [1280,390]:
            page.set_viewport_size({'width':width,'height':900 if width==1280 else 844})
            page.screenshot(path=str(OUT/f'before-ru-{width}.png'), full_page=True)
        expect(page.locator('main>header summary')).to_have_count(0)
        raise AssertionError('Baseline unexpectedly passes')
    for count in [0,1,3]:
        page.evaluate('''count=>{const initial=libraryRecords()[0]||{id:'one',title:'Prävention gegen Einbrecher',revision:0,draft:'',mode:'whole',step:0,replays:0,checked:false,plan:[{kind:'whole',asset:0}],ready:[0],word_count:120,audio_duration_seconds:95};setLibraryRecords(Array.from({length:count},(_,i)=>({...initial,id:'item-'+i,title:i?('Langer Titel '+i+' Ω ').repeat(4):initial.title,checked:i===2})));controller.route()}''',count)
        expect(page.locator('main>div>button')).to_have_count(count if count else 1)
        for locale in ['ru','en','de','es','fr']:
            page.get_by_label('Fixture locale').select_option(locale)
            labels=page.evaluate("""async locale=>{const {dt}=await import('../dictation-i18n.mjs');return Object.fromEntries(['Add text','Checked','History','More options','Delete attempt','Cancel','Title','Original text','Save text','What you heard','No dictations yet.','In progress'].map(k=>[k,dt(locale,k)]))}""",locale)
            for width in [320,390,1280]:
                page.set_viewport_size({'width':width,'height':900 if width==1280 else 844})
                expect(page.locator('main>header summary')).to_have_count(0)
                expect(page.locator('.dictation-attempt-menu')).to_have_count(0)
                expect(page.locator('main>header>button')).to_have_accessible_name(labels['Add text'])
                assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
                title=page.locator('main>header>h1').bounding_box()
                plus=page.locator('main>header>button').bounding_box()
                assert plus['x']>title['x']+title['width'] and plus['width']>=44
                if count:
                    assert row.bounding_box()['height']>=132
                    assert float(row.locator('strong').evaluate('e=>getComputedStyle(e).fontWeight'))>=600
                    expect(row.locator('small')).to_have_text({'ru':'120 слов · 1:35','en':'120 words · 1:35','de':'120 Wörter · 1:35','es':'120 palabras · 1:35','fr':'120 mots · 1:35'}[locale])
                    expect(row.locator('button')).to_have_count(0)
                    expect(row.locator('strong')).to_have_text('Prävention gegen Einbrecher')
                    assert labels['In progress'] not in page.locator('main>div').inner_text()
                    if count==3:
                        expect(page.locator('main>div>button').nth(2)).to_contain_text(labels['Checked'])
                else:
                    assert page.locator('.dictation-library').evaluate('e=>getComputedStyle(e).display')=='block', 'empty onboarding keeps its existing flow'
                    expect(page.get_by_text(labels['No dictations yet.'],exact=True)).to_be_visible()
                # Header navigation skips nonexistent overflow, goes directly to list/CTA.
                page.locator('main>header>button').focus()
                page.keyboard.press('Tab')
                expect(row).to_be_focused()
                if locale=='ru' and count in [1,3]:
                    page.locator('main>header>button').evaluate('e=>e.blur()')
                    row.evaluate('e=>e.blur()')
                    page.screenshot(path=str(OUT/f'after-ru-{count}-cards-{width}.png'),full_page=True)
                results.append({'items':count,'locale':locale,'width':width})
            # All locales keep creation and detail-only actions keyboard accessible.
            page.locator('main>header>button').focus();page.keyboard.press('Enter')
            expect(page.locator('dialog')).to_be_visible()
            page.get_by_role('button',name=labels['Cancel'],exact=True).click()
            if count:
                row.focus();page.keyboard.press('Enter')
                summary=page.locator('.dictation-attempt-menu summary')
                expect(summary).to_have_accessible_name(labels['More options'])
                summary.focus();page.keyboard.press('Enter')
                page.once('dialog',lambda dialog: dialog.dismiss())
                page.get_by_role('button',name=labels['Delete attempt'],exact=True).click()
                page.keyboard.press('Escape')
                page.get_by_role('button',name=labels['History'],exact=True).click()
                expect(page.locator('.dictation-attempt-menu')).to_have_count(0)
                assert not page.locator('main>section').evaluate("e=>[...e.querySelectorAll('button,summary,textarea')].some(x=>x.getClientRects().length)")
    # Exact second-record navigation, no generation, and checked -> list leaves no detail controls.
    page.get_by_label('Fixture locale').select_option('en')
    page.locator('main>div>button').nth(2).click()
    expect(page.locator('.dictation-heading h1')).to_contain_text('Langer Titel 2')
    expect(page.locator('.dictation-attempt-menu summary')).to_have_accessible_name('More options')
    page.get_by_role('button',name='History',exact=True).click()
    expect(page.locator('main>header')).to_be_visible()
    expect(page.locator('.dictation-attempt-menu')).to_have_count(0)
    expect(page.locator('main>section')).to_be_hidden()
    # Confirmed deletion still uses the existing owner/revision-aware detail action.
    page.locator('.dictation-card').nth(2).click()
    page.locator('.dictation-attempt-menu summary').click()
    page.once('dialog',lambda dialog: dialog.accept())
    page.get_by_role('button',name='Delete attempt',exact=True).click()
    expect(page.locator('.dictation-card')).to_have_count(2)
    assert page.evaluate("calls.filter(c=>c.method==='DELETE').length")==1
    assert page.evaluate("calls.find(c=>c.method==='DELETE').path.endsWith('/item-2')")
    # Real detail menu, keyboard, cancellation, durable draft, and owner isolation.
    row.click()
    expect(page.locator('.dictation-heading h1')).to_have_text('Prävention gegen Einbrecher')
    draft=page.get_by_role('textbox',name='What you heard',exact=True)
    draft.fill('Mein Entwurf Ω')
    page.wait_for_function("calls.some(c=>c.method==='PUT' && c.body.draft==='Mein Entwurf Ω')")
    summary=page.locator('.dictation-attempt-menu summary')
    summary.focus();page.keyboard.press('Enter')
    expect(page.get_by_role('button',name='Delete attempt',exact=True)).to_be_visible()
    page.keyboard.press('Escape');expect(summary).to_be_focused()
    expect(page.locator('.dictation-attempt-menu')).not_to_have_attribute('open','')
    summary.click()
    page.once('dialog',lambda dialog: dialog.dismiss())
    page.get_by_role('button',name='Delete attempt',exact=True).click()
    assert page.evaluate("calls.filter(c=>c.method==='DELETE').length")==1
    expect(draft).to_have_value('Mein Entwurf Ω')
    page.get_by_role('button',name='History',exact=True).click()
    expect(row.locator('strong')).to_have_text('Prävention gegen Einbrecher')
    row.click();expect(draft).to_have_value('Mein Entwurf Ω')
    page.get_by_role('button',name='History',exact=True).click()
    # Creation cancellation/resume must retain form; it is a real draft, not a job.
    page.get_by_role('button',name='Add text',exact=True).click()
    page.get_by_role('textbox',name='Title',exact=True).fill('Neuer Entwurf')
    page.get_by_role('textbox',name='Original text',exact=True).fill('Unveränderter Text Ω')
    page.get_by_role('button',name='Cancel',exact=True).click()
    page.get_by_role('button',name='Neuer Entwurf · Draft',exact=True).click()
    expect(page.get_by_role('textbox',name='Original text',exact=True)).to_have_value('Unveränderter Text Ω')
    page.get_by_role('button',name='Cancel',exact=True).click()
    # Missing stale cached attempt becomes list + recovery, never stale detail actions.
    page.evaluate("setLibraryRecords([]);fixture.fail=false")
    page.locator('.dictation-card').first.click()
    expect(page.locator('.dictation-attempt-menu')).to_have_count(0)
    expect(page.get_by_role('button',name='Export draft',exact=True).first).to_be_visible()
    assert page.evaluate("calls.every(c=>!c.path.match(/\\/(audio|check|attempts|reveal)(\\/|$)/))")
    page.evaluate('controller.identity(null)')
    expect(page.locator('main')).not_to_contain_text('Mein Entwurf Ω')
    expect(page.locator('main')).not_to_contain_text('Neuer Entwurf')
    assert not errors, errors
    result={'result':'PASS','layout_cases':len(results),'cases':results,'errors':errors,'no_inference':True,'keyboard_menu_confirmation_drafts_owner':True}
    (OUT/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result))
    browser.close()
