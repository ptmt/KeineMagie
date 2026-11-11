"""Redesign regressions against local synthetic HTTP only; no paid calls."""
from pathlib import Path
from typing import Any
import json,time
from playwright.sync_api import sync_playwright
fixture=Path(__file__).with_name('episode_browser.py');ns:dict[str,Any]={'__file__':str(fixture)}
exec(compile(fixture.read_text().split('try:\n with sync_playwright()')[0],str(fixture),'exec'),ns)
server=ns['server'];origin=ns['origin'];calls=ns['CALLS']
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':390,'height':844},locale='en-US');errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  ns['SIGNED']=False
  page.goto(origin);page.wait_for_function("document.querySelector('#connection-action').hidden===false")
  assert page.locator('#connection-notice').bounding_box()['y'] < page.locator('#source-text').bounding_box()['y'],'guest invitation precedes input'
  assert page.locator('#translate').bounding_box()['y']+page.locator('#translate').bounding_box()['height']<844,'primary in initial mobile viewport'
  assert page.locator('#translate').inner_text()=='Translate','no decorative arrow'
  assert page.locator('.section-nav a').count()==4
  for section in ['dictation','coach']:
   assert page.locator('.section-nav a[href="#'+section+'"]').get_attribute('aria-disabled')=='true'
  assert not page.evaluate("performance.getEntriesByType('resource').some(e=>/episode.*mjs/.test(e.name))"),'episode modules lazy on translator'
  ns['SIGNED']=True
  page.goto(origin+'/#translator');page.reload();page.locator('#source-text:enabled').wait_for();page.locator('#add-prompt').click();page.locator('#prompt-name').fill('Draft');page.locator('#prompt-instructions').fill('Keep this')
  page.locator('#close-prompt').click();page.locator('.style-chip').first.focus();page.locator('.style-chip').first.evaluate('(e)=>window.styleNode=e')
  page.locator('#account').click();page.locator('#retry-session').click();page.locator('#close-account').click();page.wait_for_timeout(100)
  assert page.evaluate('window.styleNode===document.querySelector(".style-chip")'),'unchanged identity retains style controls'
  page.locator('#add-prompt').click();page.locator('#prompt-name').fill('Draft');page.locator('#prompt-instructions').fill('Keep this')
  page.route('**/v1/web/session',lambda r:(time.sleep(.4),r.fulfill(json={'user':{'id':'fixture-owner'},'csrf_token':'fixture-csrf'})))
  page.evaluate("dispatchEvent(new Event('online'));document.dispatchEvent(new Event('visibilitychange'))")
  assert page.locator('#prompt-dialog').evaluate('(e)=>e.open') and page.locator('#prompt-name').input_value()=='Draft'
  page.locator('#close-prompt').click()
  ns['JOB']['segments']=[{'start':i,'end':i+1,'text':'Guten Morgen '+str(i),'translation':'Доброе утро'} for i in range(2113)]
  page.goto(origin+ns['PATH']);page.locator('#episode-cefr:enabled').wait_for()
  assert page.locator('.podcast-segments>li').count()==100,'bounded initial transcript'
  assert page.locator('.episode-quote form').count()==0,'no unopened quote forms'
  page.evaluate("window.readerNode=document.querySelector('.episode-reader')")
  page.route('**/v1/learning/episodes/*/analysis',lambda r:r.fulfill(json={'state':'completed','estimate':{'remaining_requests':0},'result':{'narrative':[{'text':'Synthetic distant citation','citations':[{'segment_id':2112,'quote':'Guten Morgen 2112'}]}],'topics':[],'recommendations':[]}}))
  page.reload();page.locator('.episode-citation').first.wait_for();page.locator('.episode-citation').first.click()
  assert page.evaluate('document.activeElement.id')=='episode-segment-2112'
  assert page.locator('.episode-quote form').count()==0
  page.unroute('**/v1/learning/episodes/*/analysis');page.reload();page.locator('#episode-cefr:enabled').wait_for()
  page.locator('.episode-quote summary').first.click();draft=page.locator('.episode-quote input').first;draft.fill('Guten');draft.focus();draft.evaluate('(e)=>{window.savedQuote=e;e.setSelectionRange(1,4)}')
  page.evaluate("document.dispatchEvent(new Event('visibilitychange'))")
  page.wait_for_timeout(200)
  assert page.evaluate('window.savedQuote===document.querySelector(".episode-quote input")'),'same DOM input across notifications'
  before=len(calls);page.select_option('#interface-language-header','ru');assert len(calls)==before
  page.locator('#account').click();page.locator('#retry-session').click();page.locator('#close-account').click();page.wait_for_timeout(600)
  assert page.evaluate('window.savedQuote===document.querySelector(".episode-quote input")')
  assert page.locator('.episode-quote').first.evaluate('(e)=>e.open')
  page.route('**/v1/learning/profiles/de',lambda r:r.fulfill(status=503,json={}))
  page.goto(origin+ns['PATH']);page.get_by_role('button',name='Создать анализ',exact=True).wait_for()
  assert page.get_by_role('button',name='Создать анализ',exact=True).is_enabled(),'profile failure must not gate independent analysis'
  page.unroute('**/v1/learning/profiles/de');page.reload();page.locator('#episode-cefr:enabled').wait_for()
  page.locator('.episode-quote summary').first.click();page.locator('.episode-quote input').first.fill('Guten')
  assert page.locator('.episode-quote input').first.input_value()=='Guten'
  assert page.locator('.episode-quote').first.evaluate('(e)=>e.open')
  assert not errors,errors
  print(json.dumps({'fixture_only':True,'checks':'mobile invitation, primary viewport, 4 honest tabs, lazy modules, pending prompt, 2113 bounded transcript, lazy quote, stable DOM, locale no requests','errors':errors}))
  browser.close()
finally:server.shutdown()
