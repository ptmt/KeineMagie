"""Mixed old/new module graph and optional reader failure, synthetic API only."""
from episode_fixture import Handler, PATH
from http.server import ThreadingHTTPServer
from threading import Thread
from playwright.sync_api import sync_playwright
from pathlib import Path
import subprocess,json
root=Path(__file__).resolve().parents[2]
def old(file):return subprocess.check_output(['git','show','5d532e9:web/'+file],cwd=root).decode()
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();results=[]
  for stale in ['index.html','episode.mjs','episode-view.mjs','app.mjs']:
   page=browser.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   if stale=='index.html':page.route('**/podcasts/episodes/*',lambda r:r.fulfill(content_type='text/html',body=old('index.html')) if '/v1/' not in r.request.url else r.continue_())
   else:page.route('**/'+stale,lambda r:r.fulfill(content_type='text/javascript',body=old(stale)))
   page.goto(origin+PATH);page.locator('#episode-summary .episode-citation').first.wait_for()
   assert page.locator('#main').is_visible()
   if stale=='episode-view.mjs':assert page.locator('.episode-section:visible').count()==4, 'old reader remains a usable progressive fallback'
   else:assert page.locator('[role=tabpanel]:visible').count()==1
   assert not errors,(stale,errors)
   results.append(stale);page.close()
  page=browser.new_page();page.route('**/episode-view.mjs',lambda r:r.abort())
  page.goto(origin+PATH);page.wait_for_timeout(300)
  assert page.locator('#main').is_visible()
  page.locator('.section-nav a[href="#translator"]').click()
  assert page.locator('#source-text').is_visible()
  results.append('reader import failure leaves shell and translator usable')
  print(json.dumps({'passed':results}));browser.close()
finally:server.shutdown()
