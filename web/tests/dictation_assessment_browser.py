"""Actual Go/auth/persistence/app assets; synthetic provider only, no paid calls."""
import json, os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
ART=Path(os.environ['DICTATION_ASSESSMENT_BROWSER'])
info=json.loads((ART/'fixture.json').read_text())
with sync_playwright() as p:
 browser=p.chromium.launch()
 context=browser.new_context(viewport={'width':1280,'height':1000})
 context.add_cookies([{'name':'__Host-km-session','value':info['browser'],'domain':'localhost','path':'/','secure':True,'httpOnly':True,'sameSite':'Strict'}])
 page=context.new_page();errors=[];posts=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.on('response',lambda r:print('HTTP',r.status,r.url,r.text()[:200]) if r.status>=400 else None)
 page.on('request',lambda r:posts.append(r.url) if r.method=='POST' and r.url.endswith('/check') else None)
 page.goto(info['url']+'/#dictation')
 page.get_by_role('button',name='Synthetic',exact=False).first.click()
 expect(page.get_by_role('textbox',name='What you heard')).to_have_value('Die Katze schläft.')
 assert 'kleine' not in page.locator('#dictation').inner_text()
 assert len(posts)==0
 page.get_by_role('button',name='Check',exact=True).click()
 expect(page.locator('.dictation-assessment')).to_contain_text('Preparing explanation',timeout=10000)
 expect(page.get_by_role('textbox',name='What you heard')).to_be_disabled()
 page.screenshot(path=str(ART/'pending-desktop.png'),full_page=True)
 expect(page.locator('.dictation-assessment')).to_contain_text('Synthetic provider explanation',timeout=15000)
 assert page.locator('.dictation-assessment img').count()==0
 assert page.locator('.dictation-unattempted').get_attribute('open') is None
 expect(page.locator('.dictation-unattempted summary')).to_have_text('Not yet attempted · 54 words')
 assert page.locator('.dictation-inline-diff').count()==2
 assert len(posts)==1
 page.screenshot(path=str(ART/'partial-desktop.png'),full_page=True)
 page.set_viewport_size({'width':390,'height':844})
 page.screenshot(path=str(ART/'partial-mobile.png'),full_page=True)
 page.get_by_role('combobox',name='Language',exact=True).select_option('ru')
 expect(page.locator('.dictation-unattempted summary')).to_have_text('Ещё не написано · 54 слова')
 page.screenshot(path=str(ART/'partial-mobile-ru.png'),full_page=True)
 for locale in ['de','en','ru','es','fr']:
  page.locator('#interface-language-header').select_option(locale)
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
  page.screenshot(path=str(ART/f'partial-mobile-{locale}.png'),full_page=True)
 page.get_by_role('combobox').first.select_option('en')
 assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
 page.get_by_role('button',name='History',exact=True).click();page.reload()
 page.get_by_role('button',name='Synthetic',exact=False).first.click()
 expect(page.locator('.dictation-assessment')).to_contain_text('Synthetic provider explanation')
 assert len(posts)==1
 # A distinct attempt retains original history, and provider failure retains diff.
 page.get_by_role('button',name='New attempt',exact=True).click()
 page.get_by_role('textbox',name='What you heard').fill('Die Katze schläft. Fehler')
 page.get_by_role('button',name='Check',exact=True).click()
 expect(page.locator('.dictation-assessment')).to_contain_text('Explanation unavailable.',timeout=15000)
 page.screenshot(path=str(ART/'failed-mobile.png'),full_page=True)
 before=len(posts);page.get_by_role('button',name='Get saved result').click()
 expect(page.locator('.dictation-assessment')).to_contain_text('Explanation unavailable.')
 assert len(posts)==before
 # Complete declaration grades the whole source, without an unattempted suffix.
 page.get_by_role('button',name='New attempt',exact=True).click()
 page.get_by_role('textbox',name='What you heard').fill('Die kleine Katze schläft. '+'Danach gehen die Kinder zusammen in die große Schule. '*6)
 page.get_by_label('More options').click()
 page.get_by_role('checkbox',name='I finished the whole text').check()
 page.get_by_role('button',name='Check',exact=True).click()
 expect(page.locator('.dictation-assessment')).to_contain_text('AI explanation of the saved comparison',timeout=15000)
 expect(page.locator('.dictation-assessment')).to_contain_text('Submitted as complete.')
 assert page.locator('.dictation-unattempted').count()==0
 page.screenshot(path=str(ART/'whole-mobile.png'),full_page=True)
 page.get_by_role('button',name='New attempt',exact=True).click()
 page.get_by_role('textbox',name='What you heard').fill('Die Katze schläft.')
 page.get_by_role('button',name='Check',exact=True).click()
 expect(page.locator('.dictation-assessment')).to_contain_text('Preparing explanation',timeout=10000)
 page.locator('.dictation-assessment').get_by_role('button',name='Cancel',exact=True).click()
 expect(page.locator('.dictation-assessment')).to_contain_text('Explanation canceled.')
 page.wait_for_timeout(3500)
 expect(page.locator('.dictation-assessment')).to_contain_text('Explanation canceled.')
 page.screenshot(path=str(ART/'canceled-mobile.png'),full_page=True)
 assert not errors,errors
 (ART/'browser-result.json').write_text(json.dumps({'provider':'synthetic, no live LLM','check_posts':len(posts),'checks':['source hidden before check','actual handler receipt pending','literal markup inert','inline compact diff','closed unattempted suffix','390px no overflow','reload GET-only recovery','failure preserves answer/diff','complete declaration'],'page_errors':errors},indent=2))
 (ART/'done').write_text('done')
 print('PASS actual Go + Chromium synthetic LLM',len(posts),'explicit checks')
 browser.close()
