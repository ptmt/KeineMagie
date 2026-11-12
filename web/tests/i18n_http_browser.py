"""HTTP browser i18n regression using the episode suite's synthetic API fixture."""
from pathlib import Path
import json,time
from typing import Any
from playwright.sync_api import sync_playwright  # pyright: ignore[reportMissingImports]
fixture=Path(__file__).with_name('episode_browser.py')
ns:dict[str,Any]={'__file__':str(fixture)}
exec(compile(fixture.read_text().split('try:\n with sync_playwright()')[0],str(fixture),'exec'),ns)
server=ns['server'];origin=ns['origin'];calls=ns['CALLS'];checks=[]
def check(name,condition):
 assert condition,name
 checks.append(name)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();context=browser.new_context(locale='ru-RU');page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto(origin+ns['PATH']);page.locator('.episode-profile-link').wait_for()
  check('Russian browser initializes shell and reader',page.locator('html').get_attribute('lang')=='ru' and page.locator('#episode-summary h3').inner_text()=='Резюме')
  page.locator('.episode-quote summary').first.click();page.locator('.episode-quote input').first.fill('Guten Morgen');page.locator('.episode-quote input').first.evaluate('(el)=>el.setSelectionRange(2,7)')
  page.locator('#account').click();page.locator('#profile-cefr:enabled').wait_for();baseline=len(calls)
  for locale,label in [('en','Summary'),('es','Resumen'),('fr','Résumé'),('de','Zusammenfassung'),('ru','Резюме')]:
   page.select_option('#interface-language-account',locale)
   check(locale+' reader and open account localized without requests',page.locator('#episode-summary h3').inner_text()==label and page.locator('#account-dialog').is_visible() and page.locator('#interface-language-header').input_value()==locale and len(calls)==baseline)
   check(locale+' reader quote draft and selection retained',page.locator('.episode-quote input').first.input_value()=='Guten Morgen' and page.locator('.episode-quote input').first.evaluate('(el)=>el.selectionStart===2&&el.selectionEnd===7') and page.locator('.episode-quote').first.evaluate('(el)=>el.open'))
  page.select_option('#interface-language-account','en');page.reload();page.locator('.episode-profile-link').wait_for()
  check('explicit English survives actual page reload despite Russian browser',page.locator('html').get_attribute('lang')=='en' and page.locator('#episode-summary h3').inner_text()=='Summary')
  # History title intentionally matches built-in UI text: it must never be translated.
  page.route('**/v1/translations',lambda route:route.fulfill(json={'items':[{'id':'History_A','text':'Freundlich','translation':'Übersetzung','source_language':'ru','target_language':'de','created_at':'2026-11-11T10:30:00Z','idioms':[],'patterns':[],'vocabulary':[]}]}))
  page.goto(origin+'/#translator');page.locator('#history-list button').wait_for();page.locator('#history-list button').click();page.locator('#source-text').evaluate('(el)=>el.setSelectionRange(1,5)');page.locator('#account').click();page.locator('#profile-cefr:enabled').wait_for();baseline=len(calls)
  for locale in ['ru','de','en','es','fr']:
   page.select_option('#interface-language-account',locale)
   check(locale+' history/result text direction and draft unchanged',page.locator('#history-list .history-source').inner_text()=='Freundlich' and page.locator('#history-list .history-translation').inner_text()=='Übersetzung' and page.locator('#result').inner_text()=='Übersetzung' and page.locator('#source-text').input_value()=='Freundlich' and page.locator('#language-direction').input_value()=='ru-de' and page.locator('#source-text').evaluate('(el)=>el.selectionStart===1&&el.selectionEnd===5') and len(calls)==baseline)
  page.locator('#close-account').click();page.locator('#logout').is_hidden()
  for width in [320,390,768,1440]:
   page.set_viewport_size({'width':width,'height':900});check('no horizontal overflow '+str(width),page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
  check('all localized Apple artwork loads',all(page.request.get(origin+'/apple-sign-in-'+locale+'.png').ok for locale in ['de','en','ru','es','fr']))
  page.locator('#account').click();page.locator('#logout').click();page.wait_for_function("document.querySelector('#account-label').textContent==='Se connecter'")
  page.select_option('#interface-language-header','ru');check('guest selector works without authentication',page.locator('#account-label').inner_text()=='Войти')
  check('no page errors',not errors)
  print(json.dumps({'fixture_only':True,'checks_passed':len(checks),'checks':checks,'page_errors':errors},ensure_ascii=False))
  browser.close()
finally:server.shutdown()
