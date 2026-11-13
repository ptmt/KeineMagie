"""Synthetic row coverage, honest denominators, localization and passage marks."""
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
import json
from playwright.sync_api import sync_playwright
from podcast_design_fixture import Handler,STATE
STATE['job']['coverage']={'recognized_segments':1,'translated_segments':1,'favorite_passages':0}
class CoverageHandler(Handler):
 def mutate(self):
  if '/passages/' in self.path:
   body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))));STATE['calls'].append({'method':self.command,'path':self.path,'body':body})
   if self.headers.get('X-CSRF-Token')!='fixture-csrf':return self.reply({},403)
   c=STATE['job']['coverage'];c['favorite_passages']=int(body['favorite']);c['favorite_segment_ids']=[0] if body['favorite'] else []
   return self.reply({'favorite':body['favorite'],'segment_id':0})
  return super().mutate()
 do_PUT=mutate
server=ThreadingHTTPServer(('127.0.0.1',0),CoverageHandler);Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(locale='en-US',viewport={'width':900,'height':900});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto('http://127.0.0.1:'+str(server.server_port)+'/#podcasts/feed/Feed_A')
  row=page.locator('.podcast-episode').first
  row.get_by_text('Translated 1 / 1 segments',exact=True).wait_for(timeout=2000)
  row.get_by_text('Starred 0 / 1 passages',exact=True).wait_for()
  assert page.locator('.podcast-episode').nth(1).locator('[data-coverage]').count()==0
  assert len([c for c in STATE['calls'] if c['path'].startswith('/v1/learning/')])==0
  for locale in ['de','ru','es','fr','en']:
   page.select_option('[data-interface-language]',locale)
   assert '1 / 1' in row.locator('[data-coverage]').inner_text()
  row.locator('.podcast-episode-title a').click();page.locator('#episode-segment-0').wait_for()
  mark=page.get_by_role('button',name='Star passage',exact=True);mark.click()
  page.get_by_role('button',name='Unstar passage',exact=True).wait_for()
  page.get_by_role('link',name='Radio RTW · synthetic fixture',exact=True).click()
  row.get_by_text('Starred 1 / 1 passages',exact=True).wait_for()
  out=Path('/Users/tinyserve/.hermes/cache/scratch/podcast-coverage-synthetic.png');page.screenshot(path=str(out))
  page.set_viewport_size({'width':320,'height':900});assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
  assert len([c for c in STATE['calls'] if '/passages/' in c['path']])==1
  assert not [c for c in STATE['calls'] if c['method']=='POST']
  assert not errors,errors
  print(json.dumps({'passed':['real counts','unprepared denominator unknown','no learning N+1','five locales','explicit passage mark and feed readback','no inference','320px no overflow'],'screenshot':str(out)}))
  browser.close()
finally:server.shutdown()
