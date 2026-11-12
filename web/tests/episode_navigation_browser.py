"""Offline navigation/profile regression; explicit 2113-segment synthetic HTTP API."""
from episode_fixture import Handler, JOB, PATH, STATE
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright
import json
server=ThreadingHTTPServer(('127.0.0.1',0),Handler);Thread(target=server.serve_forever,daemon=True).start()
origin='http://127.0.0.1:'+str(server.server_port)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':1440,'height':1000});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  page.goto(origin+PATH);page.locator('.episode-citation').first.wait_for()
  assert page.locator('#episode-cefr').count()==0, 'CEFR must live in Profile, not episode'
  assert page.locator('#episode-overview').count()==0
  assert page.locator('#podcasts>.section-heading').is_hidden(), 'collection controls should not dominate episode detail'
  page.set_viewport_size({'width':320,'height':844})
  assert page.locator('.episode-nav a').last.evaluate('(e)=>e.getBoundingClientRect().right<=innerWidth'), 'Transcript visible at 320px'
  page.set_viewport_size({'width':1440,'height':1000})
  links=page.locator('.episode-nav a');assert links.count()==4
  assert page.locator('.podcast-segments>li').count()==100
  page.get_by_role('link',name='Everyday language',exact=True).click();assert page.evaluate('document.activeElement.id')=='episode-topic-0'
  page.get_by_role('link',name='Transcript',exact=True).click()
  assert page.locator('#episode-transcript').evaluate('(e)=>e.getBoundingClientRect().top')>=page.locator('.episode-nav').evaluate('(e)=>e.getBoundingClientRect().bottom')
  assert page.locator('.episode-nav [aria-current="location"]').inner_text()=='Transcript'
  page.locator('#episode-find').fill('Satz 2012.')
  assert '1' in page.locator('#episode-find-count').inner_text()
  page.get_by_role('button',name='Next match',exact=True).click()
  assert page.locator('.podcast-segments>li').count()<=200, 'distant match should load only its chunk'
  assert page.evaluate('document.activeElement.id')=='episode-segment-2012'
  assert page.locator('#episode-segment-2012 mark').inner_text()=='Satz 2012.'
  assert page.locator('.episode-find').evaluate('(e)=>e.getBoundingClientRect().top>=50&&e.getBoundingClientRect().top<60'), 'search toolbar stays reachable at match'
  assert page.locator('.episode-quote form').count()==0
  segment_url=page.url;assert 'segment=2012' in segment_url
  page.get_by_role('link',name='Summary',exact=True).click();assert page.evaluate('document.activeElement.id')=='episode-summary'
  page.go_back();page.wait_for_timeout(200);assert page.evaluate('document.activeElement.id')=='episode-segment-2012'
  page.reload();page.locator('#episode-segment-2012').wait_for();assert page.evaluate('document.activeElement.id')=='episode-segment-2012'
  page.get_by_role('link',name='Summary',exact=True).click();page.locator('.episode-citation').first.click();assert page.evaluate('document.activeElement.id')=='episode-segment-2012'
  page.get_by_role('button',name='Back to section',exact=True).click();assert page.evaluate('document.activeElement.id')=='episode-citation-0'
  page.locator('#episode-time').fill('100:36');page.locator('.episode-time-jump button').click();assert page.evaluate('document.activeElement.id')=='episode-segment-2012'
  page.get_by_role('link',name='Summary',exact=True).focus();page.keyboard.press('Enter');assert page.evaluate('document.activeElement.id')=='episode-summary'
  page.evaluate('window.scrollBy(0,400)');page.wait_for_timeout(50);assert page.evaluate('document.activeElement.id')=='episode-summary', 'scrollspy must not move focus'
  page.locator('.episode-citation').first.click();assert page.evaluate('document.activeElement.id')=='episode-segment-2012'
  page.get_by_role('button',name='B1 · Change in profile',exact=True).click()
  page.locator('#profile-cefr:enabled').wait_for();assert page.locator('#account-dialog').evaluate('(e)=>e.open')
  assert page.evaluate('document.activeElement.id')=='profile-cefr'
  page.select_option('#profile-cefr','B2');page.wait_for_function("()=>document.querySelector('#profile-cefr').value==='B2'&&!document.querySelector('#profile-cefr').disabled")
  assert STATE['cefr']=='B2' and [c for c in STATE['calls'] if c[0]=='PUT']
  assert page.locator('.profile-history').count()==1 and not page.locator('.profile-history').evaluate('(e)=>e.open')
  assert 'T10:00:00Z' not in page.locator('.profile-history').inner_text()
  page.locator('#close-account').click();page.locator('#account').click();page.locator('#profile-cefr:enabled').wait_for();assert page.locator('#profile-cefr').input_value()=='B2'
  page.locator('#close-account').click()
  STATE['profile_error']=True;page.locator('#account').click();page.get_by_text('Could not save or load profile.',exact=True).wait_for();assert page.locator('#episode-summary').count()==1
  page.locator('#close-account').click();STATE['profile_error']=False
  page.locator('#account').click();page.locator('#profile-cefr:enabled').wait_for();page.locator('#close-account').click()
  for width in [320,390,768,1440]:
   page.set_viewport_size({'width':width,'height':844});page.get_by_role('link',name='Transcript',exact=True).click();page.wait_for_timeout(100)
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),width
   assert page.locator('.episode-nav').evaluate('(e)=>Math.abs(e.getBoundingClientRect().top)<2'),width
   assert page.locator('.episode-nav [aria-current]').evaluate('(e)=>{const r=e.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth}'),width
  evidence=Path('/Users/tinyserve/.hermes/cache/scratch/episode-navigation-evidence');evidence.mkdir(exist_ok=True)
  for width in [320,1440]:
   page.set_viewport_size({'width':width,'height':1000});page.get_by_role('link',name='Summary',exact=True).click();page.screenshot(path=str(evidence/f'after-{width}.png'));page.evaluate('scrollTo(0,0)');page.screenshot(path=str(evidence/f'after-header-{width}.png'))
  page.locator('#account').click();page.locator('#logout').click();page.wait_for_function("()=>document.querySelector('#podcast-content').textContent===''")
  assert page.locator('#profile-history').inner_text()=='' and page.locator('#learning-profile').is_hidden()
  assert not [c for c in STATE['calls'] if c[0]=='POST' and c[1].endswith('/analysis')]
  assert not errors,errors
  print(json.dumps({'passed':'semantic sticky links, offsets, current section, find highlight/count, lazy segment 2012, focus/back/reload/citation, profile GET/PUT readback, collapsed dates, 4 responsive widths, zero generation','requests':len(STATE['calls']),'page_errors':errors}))
  browser.close()
finally:server.shutdown()
