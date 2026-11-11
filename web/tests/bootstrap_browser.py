"""Critical locale is ready even if the application module is delayed."""
from pathlib import Path
from typing import Any
from playwright.sync_api import sync_playwright
import json,time
fixture=Path(__file__).with_name('episode_browser.py');ns:dict[str,Any]={'__file__':str(fixture)}
exec(compile(fixture.read_text().split('try:\n with sync_playwright()')[0],str(fixture),'exec'),ns)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(locale='ru-RU',viewport={'width':390,'height':844})
  page.route('**/app.mjs',lambda route:route.abort())
  page.goto(ns['origin']);page.wait_for_timeout(200)
  assert page.locator('html').get_attribute('lang')=='ru'
  assert page.locator('#account-label').inner_text()=='Войти'
  assert page.locator('.section-nav a').first.inner_text()=='Переводчик'
  assert page.locator('#source-text').get_attribute('placeholder')=='Введите текст …'
  assert page.locator('#translate').inner_text()=='Перевести'
  assert page.locator('#main').is_visible()
  fallback=browser.new_page(locale='en-US',viewport={'width':390,'height':844})
  fallback.route('**/bootstrap.js',lambda route:route.abort())
  fallback.goto(ns['origin']);fallback.wait_for_function("document.querySelector('#connection-action').hidden===false")
  assert fallback.locator('#main').is_visible()
  assert fallback.locator('#translate').inner_text()=='Translate'
  assert fallback.locator('html').get_attribute('lang')=='en'
  assert fallback.locator('#translate').is_disabled()
  print(json.dumps({'critical_locale_before_app':True,'app_module':'intentionally blocked','bootstrap_failure_fallback':'visible localized locked guest'}));browser.close()
finally:ns['server'].shutdown()
