"""Real local Go handler + Linux Piper integration. Synthetic identity only."""
import json,os,time,urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path('/Users/tinyserve/.hermes/cache/scratch/diktat-fixture')
EVIDENCE=Path('/Users/tinyserve/.hermes/cache/scratch/diktat-browser');EVIDENCE.mkdir(exist_ok=True)
info=json.loads((ROOT/'fixture.json').read_text())
with sync_playwright() as p:
 browser=p.chromium.launch();context=browser.new_context(viewport={'width':1280,'height':950})
 context.add_cookies([{'name':'__Host-km-session','value':info['browser'],'domain':'localhost','path':'/','secure':True,'httpOnly':True,'sameSite':'Strict'}])
 page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto(info['url']+'/#dictation')
 page.get_by_role('button',name='Add text',exact=True).click()
 page.get_by_role('textbox',name='Title',exact=True).fill('German · real Piper fixture')
 source='Dr. Müller geht heute in die Stadt. Er kauft frisches Brot, weil seine Freunde am Abend zu Besuch kommen und gemeinsam mit ihm gemütlich zu Abend essen möchten. Danach geht er nach Hause.'
 page.get_by_role('textbox',name='Original text',exact=True).fill(source)
 page.get_by_role('button',name='Save text',exact=True).click()
 page.get_by_role('button',name='Prepare audio',exact=True).wait_for()
 assert source not in page.locator('#dictation').inner_text()
 started=time.monotonic();page.get_by_role('button',name='Prepare audio',exact=True).click()
 play=page.get_by_role('button',name='Play / repeat',exact=True)
 from playwright.sync_api import expect
 expect(play).to_be_enabled(timeout=60000)
 latency=time.monotonic()-started
 play.click();page.wait_for_function("() => document.querySelector('#dictation').textContent.includes('1 completed readings')",timeout=30000)
 page.get_by_role('textbox',name='What you heard').fill('Dr. Müller geht heute in die Stadt.')
 page.wait_for_timeout(1000)
 page.screenshot(path=str(EVIDENCE/'whole.png'),full_page=True)
 page.get_by_role('button',name='By sentences',exact=True).click()
 page.get_by_role('button',name='Next',exact=True).click()
 page.get_by_role('button',name='Prepare audio',exact=True).click();expect(play).to_be_enabled(timeout=60000);play.click()
 page.get_by_role('button',name='Pause',exact=True).click()
 page.screenshot(path=str(EVIDENCE/'sentences.png'),full_page=True)
 page.get_by_role('button',name='History',exact=True).click()
 page.reload();page.get_by_role('button',name='German · real Piper fixture · In progress',exact=True).first.click()
 expect(page.get_by_role('textbox',name='What you heard')).to_have_value('Dr. Müller geht heute in die Stadt.')
 page.get_by_role('button',name='Check',exact=True).click();page.locator('.dictation-original').wait_for()
 assert page.locator('.dictation-original').text_content()==source
 page.set_viewport_size({'width':390,'height':844});page.screenshot(path=str(EVIDENCE/'mobile-check.png'),full_page=True)
 assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
 assert not errors,errors
 page.get_by_role('button',name='Profile',exact=True).click()
 page.locator('#logout').click()
 expect(page.locator('#dictation')).not_to_contain_text(source)
 expect(page.locator('#dictation')).not_to_contain_text('German · real Piper fixture')
 (EVIDENCE/'result.json').write_text(json.dumps({'real_audio_prepare_seconds':latency,'checks':['real completed audio playback','whole','sentences','pause','reload draft','check original','mobile no overflow'],'page_errors':errors},indent=2))
 print('PASS real Go + Linux Piper + Chromium',round(latency,3),'seconds preparation')
 browser.close()
