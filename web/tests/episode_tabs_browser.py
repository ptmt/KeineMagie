"""Real Chromium, synthetic owner/API; never contacts a provider."""
from episode_fixture import Handler, PATH, STATE
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright
import json
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
evidence=Path('/Users/tinyserve/.hermes/cache/scratch/episode-true-tabs-evidence')
evidence.mkdir(exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  page=browser.new_page(viewport={'width':1440,'height':1000})
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  page.goto(origin+PATH)
  page.locator('.episode-citation').first.wait_for()
  page.screenshot(path=str(evidence/'baseline-or-after-1440.png'))
  assert page.locator('[role=tab]').count()==4, 'four real tabs, not section anchors'
  assert page.locator('[role=tabpanel]:visible').count()==1
  def tab(key): return page.locator(f'#episode-tab-{key}')
  def selected(key):
   assert tab(key).get_attribute('aria-selected')=='true'
   assert page.locator('[role=tabpanel]:visible').count()==1
   assert page.locator('[role=tab][tabindex="0"]').count()==1
   assert page.locator('[role=tabpanel][hidden]').evaluate_all('(els)=>els.length===3&&els.every(e=>e.inert&&e.getAttribute("aria-hidden")==="true"&&getComputedStyle(e).display==="none")')
  selected('summary')
  y=page.evaluate('scrollY')
  for key in ['vocabulary','recommendations','transcript','summary']:
   tab(key).click();selected(key)
   assert page.evaluate('scrollY')==y, 'ordinary tabs must not scroll to headings'
  tab('summary').focus()
  for key,target in [('ArrowRight','vocabulary'),('End','transcript'),('ArrowRight','summary'),('ArrowLeft','transcript'),('Home','summary'),('Enter','summary'),('Space','summary')]:
   page.keyboard.press(key);selected(target)
   assert page.evaluate('document.activeElement.id')=='episode-tab-'+target
  page.keyboard.press('Tab')
  assert page.evaluate('document.activeElement.id')=='episode-summary'
  assert page.locator('#episode-summary').evaluate('(e)=>e.matches(":focus-visible")&&getComputedStyle(e).outlineStyle!=="none"')
  tab('transcript').click()
  assert page.locator('[role=tabpanel]:focus').count()==0, 'pointer tabs do not focus/outline a whole panel'
  page.locator('#episode-find').fill('Satz 2012.')
  page.get_by_role('button',name='Next match',exact=True).click()
  assert page.locator('.podcast-segments>li').count()<=200
  assert page.evaluate('document.activeElement.id')=='episode-segment-2012'
  page.wait_for_timeout(100)
  match_y=page.evaluate('scrollY')
  tab('summary').click()
  page.go_back();page.wait_for_timeout(150);selected('transcript')
  assert abs(page.evaluate('scrollY')-match_y)<3
  assert page.locator('#episode-find').input_value()=='Satz 2012.'
  assert page.locator('#episode-find-count').inner_text().startswith('1 / 1')
  page.go_forward();page.wait_for_timeout(150);selected('summary')
  page.go_back();page.wait_for_timeout(150)
  page.locator('#episode-find').fill('no matching phrase')
  page.go_back();page.wait_for_timeout(150)
  assert page.locator('#episode-find').input_value()=='Satz 2012.', 'Back restores entry search state'
  page.goto(origin+PATH+'#episode-transcript')
  page.wait_for_timeout(500)
  assert page.locator('#episode-tab-transcript[aria-selected=true]').count()==1, 'legacy section fragment must route to episode and activate Transcript'
  assert '#' not in page.url, 'canonical section query must not collide with router'
  page.goto(origin+PATH+'?section=transcript&segment=2012')
  page.locator('#episode-segment-2012').wait_for()
  selected('transcript')
  page.reload();page.locator('#episode-segment-2012').wait_for();selected('transcript')
  tab('summary').click()
  page.locator('#episode-summary .episode-citation').nth(1).click();selected('transcript')
  page.go_back();page.wait_for_timeout(150);selected('summary')
  assert page.evaluate('document.activeElement.id')=='episode-citation-1', 'browser Back restores the originating citation control'
  page.locator('#episode-summary .episode-citation').nth(1).click();selected('transcript')
  page.get_by_role('button',name='Back to section',exact=True).click();selected('summary')
  assert page.evaluate('document.activeElement.id')=='episode-citation-1'
  tab('recommendations').click()
  citation_id=page.locator('#episode-recommendations .episode-citation').get_attribute('id')
  page.locator('#episode-recommendations .episode-citation').click();selected('transcript')
  page.get_by_role('button',name='Back to section',exact=True).click();selected('recommendations')
  assert page.evaluate('document.activeElement.id')==citation_id
  tab('transcript').click()
  page.locator('#episode-time').fill('100:36');page.locator('.episode-time-jump button').click()
  assert page.evaluate('document.activeElement.id')=='episode-segment-2012'
  page.goto(origin+PATH+'?section=transcript&segment=99999999999999999999')
  page.locator('#episode-tab-transcript').wait_for()
  page.wait_for_timeout(100);selected('transcript')
  assert page.locator('.podcast-segments>li').count()==100, 'invalid segment must not load extra chunks or hide selected panel'
  page.locator('#episode-find').fill('Guten Morgen')
  page.locator('#episode-find').press('Enter');page.locator('#episode-find').press('Enter')
  assert page.locator('#episode-find-count').inner_text().startswith('2 / 2113')
  page.go_back();page.wait_for_timeout(150)
  assert page.locator('#episode-find-count').inner_text().startswith('1 / 2113'), 'Back restores the previous match index, not the next one'
  page.go_forward();page.wait_for_timeout(150)
  assert page.locator('#episode-find-count').inner_text().startswith('2 / 2113')
  for locale in ['de','en','ru','es','fr']:
   for width in [390,1440]:
    page.set_viewport_size({'width':width,'height':844 if width==390 else 1000})
    page.locator('[data-interface-language]').first.select_option(locale)
    page.evaluate('scrollTo(0,0)')
    tab('transcript').click();selected('transcript')
    page.locator('#episode-find').fill('Guten Morgen')
    assert '/ 2113 ' in page.locator('#episode-find-count').inner_text()
    page.locator('#episode-find').press('Enter')
    assert page.locator('#episode-segment-0').evaluate('(e)=>e.getBoundingClientRect().top')>=page.locator('.episode-find').evaluate('(e)=>e.getBoundingClientRect().bottom')-1
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),(locale,width)
    page.locator('#episode-find').fill('')
    page.evaluate('scrollTo(0,0)')
    page.screenshot(path=str(evidence/f'after-transcript-{locale}-{width}.png'))
    tab('summary').click();selected('summary')
    page.evaluate('scrollTo(0,0)')
    page.screenshot(path=str(evidence/f'after-summary-{locale}-{width}.png'))
    ax=page.context.new_cdp_session(page).send('Accessibility.getFullAXTree')['nodes']
    assert len([n for n in ax if not n.get('ignored') and n.get('role',{}).get('value')=='tabpanel'])==1
    page.locator('#episode-find').evaluate('(e)=>e.focus()')
    assert page.evaluate('document.activeElement.id')!='episode-find', 'inert descendants cannot be focused'
  assert not [c for c in STATE['calls'] if c[0]=='POST' and c[1].endswith('/analysis')]
  print(json.dumps({'result':'PASS: tabs, keyboard, history/search, legacy links/citations; 10 locale/width cases; AX single panel; 2113 full search; zero AI POSTs','evidence':str(evidence)}))
  browser.close()
finally: server.shutdown()
