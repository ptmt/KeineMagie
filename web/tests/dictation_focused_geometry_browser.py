from playwright.sync_api import sync_playwright,expect
import json
from pathlib import Path
out=Path('/Users/tinyserve/.hermes/cache/scratch/dictation-focused-evidence')
with sync_playwright() as p:
 b=p.chromium.launch();results=[]
 for locale in ['en','de','ru','es','fr']:
  ctx=b.new_context(viewport={'width':390,'height':844},reduced_motion='reduce');page=ctx.new_page();page.goto('http://127.0.0.1:8876/tests/dictation-focused-fixture.html?locale='+locale);page.locator('main>div>button').first.click();page.evaluate('fixture.delay=1500');before=page.locator('.dictation-work textarea').bounding_box();page.locator('.dictation-player>button').first.click();expect(page.locator('.dictation-player>button').first).to_have_attribute('aria-busy','true');during=page.locator('.dictation-work textarea').bounding_box();assert before==during,(locale,before,during);assert page.evaluate('document.documentElement.scrollWidth<=innerWidth');assert page.locator('[aria-busy=true]').evaluate("e=>getComputedStyle(e,'::before').animationName")=='none';page.screenshot(path=str(out/('preparing-'+locale+'-mobile.png')),full_page=True);page.locator('.dictation-cancel').click();results.append({'locale':locale,'stable':True});ctx.close()
 (out/'geometry-result.json').write_text(json.dumps(results,indent=2));print(json.dumps(results));b.close()
