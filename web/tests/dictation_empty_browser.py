"""Signed-in empty-list regression; synthetic HTTP only, no generation."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread
from playwright.sync_api import sync_playwright, expect
import os
from pathlib import Path

class Empty(Handler):
 malformed=False
 def do_GET(self):
  if self.path=='/v1/learning/dictations':return self.reply({'items':None} if self.malformed else {'items':[]})
  return super().do_GET()
server=ThreadingHTTPServer(('127.0.0.1',0),Empty)
Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':390,'height':844});errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  page.goto(f'http://127.0.0.1:{server.server_port}/#dictation')
  expect(page.locator('#dictation button').filter(has_text='Add text')).to_be_enabled()
  expect(page.locator('#dictation [role=status]')).to_have_text('')
  expect(page.locator('#dictation')).to_contain_text('No dictations yet.',timeout=1500)
  evidence=Path(os.environ['TMPDIR'])/'km-web-incident';evidence.mkdir(exist_ok=True)
  page.screenshot(path=str(evidence/'dictation-empty.png'),full_page=True)
  for locale,label in [('de','Noch keine Diktate.'),('ru','Диктантов пока нет.'),('es','Aún no hay dictados.'),('fr','Pas encore de dictées.'),('en','No dictations yet.')]:
   page.locator('#interface-language-header').select_option(locale)
   expect(page.locator('#dictation')).to_contain_text(label)
  page.locator('#dictation button').filter(has_text='Add text').focus();page.keyboard.press('Enter')
  expect(page.get_by_role('dialog')).to_be_visible()
  page.keyboard.press('Escape');expect(page.get_by_role('dialog')).not_to_be_visible()
  Empty.malformed=True
  page.goto(f'http://127.0.0.1:{server.server_port}/?malformed#dictation')
  expect(page.locator('#dictation [role=status]')).to_have_text('Could not save. Retry.')
  assert not errors,errors
  print('PASS signed-in completed empty list and malformed response; no page errors')
  browser.close()
finally:server.shutdown()
