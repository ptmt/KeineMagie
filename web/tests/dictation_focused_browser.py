"""Real production module/CSS, synthetic owner, deterministic media/API only."""
import json,os
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('DICTATION_FOCUSED_URL','http://127.0.0.1:8876/tests/dictation-focused-fixture.html')
OUT=Path(os.environ.get('DICTATION_EVIDENCE','/Users/tinyserve/.hermes/cache/scratch/dictation-focused-evidence'));OUT.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
 b=p.chromium.launch();ctx=b.new_context(viewport={'width':1280,'height':900},reduced_motion='reduce');page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 ctx.route('**/*',lambda route:route.continue_() if route.request.url.startswith('http://127.0.0.1:8876/') else route.abort())
 def shot(name):page.screenshot(path=str(OUT/(name+'.png')),full_page=True)
 def click(name):page.get_by_role('button',name=name,exact=True).click()
 page.goto(BASE+'?empty');expect(page.get_by_text('Listen → type → check.',exact=False)).to_be_visible();shot('after-empty')
 page.get_by_role('button',name='Add text',exact=True).last.click();page.get_by_role('textbox',name='Title',exact=True).fill('Ein Spaziergang im Park');page.get_by_role('textbox',name='Original text',exact=True).fill('Heute scheint die Sonne. Wir gehen in den Park.');click('Save text')
 expect(page.get_by_role('button',name='Prepare audio',exact=True)).to_be_visible();expect(page.get_by_text('Audio details',exact=True)).to_be_visible();expect(page.get_by_text('Via OpenAI API · paid',exact=True)).to_have_count(0)
 assert page.evaluate("calls.filter(x=>x.path.includes('/audio/')).length")==0
 shot('after-unprepared-desktop');page.set_viewport_size({'width':390,'height':844});shot('after-unprepared-mobile')
 original_rect=page.locator('.dictation-work textarea').bounding_box();page.evaluate('fixture.delay=800');click('Prepare audio');expect(page.get_by_role('button',name='Preparing audio…')).to_be_disabled()
 assert page.locator('.dictation-work textarea').bounding_box()==original_rect
 shot('after-preparing-mobile');expect(page.get_by_role('button',name='Play',exact=True)).to_be_visible();page.evaluate('fixture.delay=0')
 assert page.evaluate("calls.filter(x=>x.path.includes('/audio/')&&x.method==='POST').length")==1
 click('Play');expect(page.get_by_role('button',name='Pause',exact=True)).to_be_visible();page.evaluate('fixtureAudio.currentTime=4');click('Pause');click('Play');assert page.evaluate('fixtureAudio.currentTime')==4
 page.evaluate('fixtureAudio.finish()');expect(page.get_by_role('button',name='Replay',exact=True)).to_be_visible();shot('after-replay-mobile')
 draft=page.get_by_role('textbox',name='What you heard');draft.fill('Heute scheintt die Sonne. Ω');page.wait_for_timeout(700)
 click('By sentences');expect(draft).to_have_value('Heute scheintt die Sonne. Ω');expect(page.get_by_role('button',name='By sentences')).to_have_attribute('aria-pressed','true');click('Next');shot('after-sentence-mobile')
 click('Whole text');expect(draft).to_have_value('Heute scheintt die Sonne. Ω')
 for locale in ['ru','de','es','fr','en']:
  page.get_by_role('combobox',name='Fixture locale').select_option(locale);assert page.evaluate('document.documentElement.scrollWidth<=innerWidth');assert page.locator('.dictation-work textarea').input_value()=='Heute scheintt die Sonne. Ω';shot('after-'+locale+'-mobile')
 click('Check');expect(page.get_by_role('button',name='New attempt',exact=True)).to_be_visible();expect(page.locator('.dictation-original')).to_have_count(0);shot('after-checked-mobile');click('Show original');expect(page.locator('.dictation-original')).to_have_text('Heute scheint die Sonne. Wir gehen in den Park.');shot('after-revealed-mobile')
 click('New attempt');expect(draft).to_have_value('');expect(page.locator('.dictation-original')).to_have_count(0);expect(page.get_by_role('button',name='Play',exact=True)).to_be_visible()
 draft.fill('Saved retry draft Ω');page.wait_for_timeout(700);click('History');page.get_by_role('button',name='Ein Spaziergang im Park · In progress',exact=True).last.click();expect(draft).to_have_value('Saved retry draft Ω')
 page.once('dialog',lambda d:d.accept());click('Show original');expect(page.get_by_text('With hint · assisted',exact=True)).to_be_visible()
 page.set_viewport_size({'width':1280,'height':900});page.get_by_role('combobox',name='Fixture locale').select_option('ru');shot('after-assisted-desktop')
 # Isolated error / cancellation exercise, no cached audio.
 ctx2=b.new_context(viewport={'width':390,'height':844});page=ctx2.new_page();page.on('pageerror',lambda e:errors.append(str(e)));page.goto(BASE);click('Ein Spaziergang im Park · In progress');page.evaluate('fixture.fail=true');click('Prepare audio');expect(page.get_by_role('button',name='Prepare audio',exact=True)).to_be_visible();shot('after-error-mobile');assert page.evaluate("calls.filter(x=>x.path.includes('/audio/')).length")==1
 page.evaluate('fixture.fail=false;fixture.delay=10000');click('Prepare audio');click('Cancel preparation');expect(page.get_by_role('button',name='Prepare audio',exact=True)).to_be_visible();page.evaluate('fixture.delay=0');click('Prepare audio');expect(page.get_by_role('button',name='Play',exact=True)).to_be_visible()
 summary=page.locator('.dictation-attempt-menu summary');summary.focus();page.keyboard.press('Enter');expect(page.get_by_role('button',name='Delete attempt',exact=True)).to_be_visible();page.keyboard.press('Escape');expect(summary).to_be_focused();expect(page.get_by_role('button',name='Delete attempt',exact=True)).not_to_be_visible()
 assert not errors,errors
 (OUT/'result.json').write_text(json.dumps({'result':'PASS','synthetic':True,'errors':errors,'checks':['empty onboarding','create','explicit paid prepare only once','stable preparing geometry','pause/resume currentTime','ended replay','mode draft preservation','five locales mobile overflow','check then explicit original reveal','new attempt cache reuse','history draft','assistance confirmation','prepare error retry cancel','keyboard menu Escape']},indent=2));print((OUT/'result.json').read_text());b.close()
