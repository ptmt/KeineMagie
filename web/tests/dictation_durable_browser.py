"""Real local backend; deliberate browser network/playback failures, no inference mocks."""
import json,uuid
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
root=Path('/Users/tinyserve/.hermes/cache/scratch/diktat-fixture')
out=Path('/Users/tinyserve/.hermes/cache/scratch/diktat-browser-final');out.mkdir(exist_ok=True)
info=json.loads((root/'fixture.json').read_text())
with sync_playwright() as p:
 browser=p.chromium.launch();context=browser.new_context(viewport={'width':390,'height':844})
 context.add_cookies([{'name':'__Host-km-session','value':info['browser'],'domain':'localhost','path':'/','secure':True,'httpOnly':True,'sameSite':'Strict'}])
 page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto(info['url']+'/#dictation')
 page.get_by_role('button',name='Add text',exact=True).click()
 title='Durable '+str(uuid.uuid4())[:8]
 page.get_by_role('textbox',name='Title',exact=True).fill(title)
 page.get_by_role('textbox',name='Original text',exact=True).fill('Heute scheint die Sonne.')
 page.get_by_role('button',name='Save text',exact=True).click()
 draft=page.get_by_role('textbox',name='What you heard',exact=True)
 draft.wait_for()
 # Save request reaches real server but its acknowledgement is dropped.
 dropped=[]
 def lose_ack(route):
  if route.request.method=='PUT' and not dropped:
   response=route.fetch();assert response.status==200;dropped.append(True);route.abort('failed')
  else:route.continue_()
 page.route('**/v1/learning/dictations/*',lose_ack)
 draft.fill('erste Fassung')
 for _ in range(100):
  if dropped:break
  page.wait_for_timeout(100)
 assert dropped
 draft.fill('erste Fassung plus Ω');page.wait_for_timeout(1000)
 page.unroute('**/v1/learning/dictations/*',lose_ack)
 # Local write is committed independently of the debounce/server.
 context.set_offline(True);draft.fill('Offline behalten Ω')
 page.wait_for_function("""() => new Promise(resolve=>{const r=indexedDB.open('keinemagie-dictation',1);r.onsuccess=()=>{const q=r.result.transaction('drafts').objectStore('drafts').getAll();q.onsuccess=()=>resolve(JSON.stringify(q.result).includes('Offline behalten Ω'));};})""")
 context.set_offline(False);page.reload()
 page.get_by_role('button',name=title+' · In progress',exact=True).click()
 expect(page.get_by_role('textbox',name='What you heard')).to_have_value('Offline behalten Ω')
 page.locator('.dictation-attempt-menu summary').click()
 page.get_by_role('button',name='New attempt',exact=True).click()
 expect(page.get_by_role('textbox',name='What you heard')).to_have_value('')
 page.get_by_role('textbox',name='What you heard').fill('second attempt')
 page.wait_for_timeout(700)
 page.on('dialog',lambda d:d.accept())
 page.locator('.dictation-attempt-menu summary').click()
 page.get_by_role('button',name='Delete attempt',exact=True).click()
 page.get_by_role('button',name=title+' · In progress',exact=True).click()
 expect(page.get_by_role('textbox',name='What you heard')).to_have_value('Offline behalten Ω')
 # Switch all interface languages without touching the owner or draft.
 requests=[];page.on('request',lambda r:requests.append(r.url) if '/v1/' in r.url else None)
 expected={'de':'Prüfen','ru':'Проверить','es':'Comprobar','fr':'Vérifier','en':'Check'}
 for language in ['de','ru','es','fr','en']:
  before=len(requests)
  page.locator('#interface-language-header').select_option(language)
  expect(page.get_by_role('button',name=expected[language],exact=True)).to_be_visible()
  expect(page.locator('#dictation section textarea')).to_have_value('Offline behalten Ω')
  page.wait_for_timeout(100);assert len(requests)==before
  page.screenshot(path=str(out/(language+'.png')),full_page=True)
 # Actual engine audio; deny autoplay deliberately, then restore browser playback.
 page.get_by_role('button',name='Prepare audio',exact=True).click()
 play=page.locator('.dictation-player > button').first;expect(play).to_be_enabled(timeout=60000)
 page.evaluate("() => {window.realPlay=HTMLMediaElement.prototype.play;HTMLMediaElement.prototype.play=function(){return Promise.reject(new DOMException('denied','NotAllowedError'));};}")
 play.click();expect(page.locator('#dictation [role=status]')).to_contain_text('Playback did not start')
 page.evaluate('() => {HTMLMediaElement.prototype.play=window.realPlay;}')
 play.click();page.get_by_role('button',name='Pause',exact=True).click()
 page.screenshot(path=str(out/'durable-attempt.png'),full_page=True)
 assert not errors,errors
 (out/'result.json').write_text(json.dumps({'checks':['dropped save acknowledgement retry','pending local draft survives reload','multiple attempts retain original draft','delete acknowledged attempt'],'page_errors':errors},indent=2))
 print('PASS durable browser lifecycle')
 browser.close()
