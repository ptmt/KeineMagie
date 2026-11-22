"""Actual Go handlers -> actual browser app; synthetic provider only."""
from pathlib import Path
import os,subprocess,time,json,urllib.request,tempfile
from playwright.sync_api import sync_playwright,expect
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(os.environ.get('COACH_PARITY_EVIDENCE',str(Path.home()/'.hermes/cache/scratch/coach-web-parity-evidence')));OUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='coach-web-go-',dir=str(Path.home()/'.hermes/cache/scratch')) as work:
 ready=Path(work)/'ready.json';log=open(OUT/'go-fixture.log','w');process=subprocess.Popen(['go','test','-count=1','-run','^TestCoachWebParityFixture$','-v','.'],cwd=ROOT/'server',env={**os.environ,'KM_COACH_WEB_FIXTURE':str(ready),'TMPDIR':work},stdout=log,stderr=subprocess.STDOUT)
 try:
  for _ in range(300):
   if ready.exists():break
   if process.poll() is not None:raise RuntimeError('Go fixture exited; see log')
   time.sleep(.1)
  config=json.loads(ready.read_text());url=config['url']
  with sync_playwright() as p:
   browser=p.chromium.launch();page=browser.new_page(viewport={'width':390,'height':844});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
   page.goto(url+'/#coach');expect(page.locator('.coach-clue')).to_have_text('a period of practical work experience',timeout=15000)
   expect(page.locator('.coach-prompt')).to_have_text('Ich mache ein ___ bei euch.')
   assert 'Praktikum' not in page.locator('.coach-messages').inner_text();page.screenshot(path=str(OUT/'go-clue-active-mobile.png'))
   page.locator('.coach-answer-editor input').fill('  Praktikum  ');page.get_by_role('button',name='Check',exact=True).click();expect(page.locator('.coach-assessment.coach-success')).to_be_visible(timeout=10000)
   assert page.locator('.coach-answer').text_content()=='  Praktikum  ';page.screenshot(path=str(OUT/'go-clue-correct-mobile.png'))
   page.locator('.coach-activity-day[aria-current=date]').click();expect(page.get_by_role('dialog')).to_contain_text('Coach: 1');expect(page.get_by_role('dialog')).to_contain_text('Translator: 1');expect(page.get_by_role('dialog')).to_contain_text('Podcasts: Not supported');page.screenshot(path=str(OUT/'go-activity-breakdown-mobile.png'))
   assert not errors;browser.close()
  with urllib.request.urlopen(url+'/__fixture/stop') as response:receipt=json.load(response)
  assert receipt['calls']==2,receipt
  process.wait(timeout=15);assert process.returncode==0
  (OUT/'go-browser-receipt.json').write_text(json.dumps({'synthetic_provider':True,'real_go_handlers':True,'provider_calls':receipt['calls'],'errors':errors},indent=2));print('PASS real Go → browser: new clue, exact typed answer, assessment, real retained activity 1 translator + 1 coach, podcasts unsupported; 2 synthetic calls')
 finally:
  if process.poll() is None:process.terminate();process.wait(timeout=10)
  log.close()
