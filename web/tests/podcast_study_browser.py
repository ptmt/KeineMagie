"""Synthetic web transport; production UI assets. No provider calls."""
import json, threading, os
from pathlib import Path
from urllib.parse import urlsplit
from http.server import ThreadingHTTPServer
from playwright.sync_api import sync_playwright, expect
from episode_fixture import Handler, JOB, PATH, STATE

class StudyHandler(Handler):
 def do_GET(self):
  if urlsplit(self.path).path.endswith('/passage-groups'):
   return self.reply({'version':1,'revision':1,'job_id':JOB['id'],'groups':[],'favorite_segment_ids':[],**({'studied_at':JOB['coverage']['studied_at']} if JOB.get('coverage',{}).get('studied_at') else {})})
  return super().do_GET()
 def do_PUT(self):
  if self.path.endswith('/studied'):
   body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))) or b'{}')
   STATE['calls'].append(('PUT',self.path,body))
   assert body=={} and self.headers.get('X-CSRF-Token')=='fixture-csrf'
   JOB['coverage']={'studied_at':'2026-11-22T12:00:00Z'}
   return self.reply({'version':1,'revision':2,'job_id':JOB['id'],'groups':[],'favorite_segment_ids':[],'studied_at':JOB['coverage']['studied_at']})
  return super().do_PUT()

if __name__=='__main__':
 out=Path(os.environ['EVIDENCE_DIR']);out.mkdir(parents=True,exist_ok=True)
 server=ThreadingHTTPServer(('127.0.0.1',0),StudyHandler)
 threading.Thread(target=server.serve_forever,daemon=True).start()
 try:
  with sync_playwright() as p:
   browser=p.chromium.launch()
   for width,theme in [(1280,'light'),(1280,'dark'),(375,'light'),(375,'dark')]:
    JOB['coverage']={};STATE['calls']=[]
    page=browser.new_page(viewport={'width':width,'height':900},color_scheme=theme)
    page.goto(f'http://127.0.0.1:{server.server_port}'+PATH+'?section=transcript')
    study=page.locator('#episode-mark-studied');expect(study).to_be_visible()
    assert not [c for c in STATE['calls'] if c[0]!='GET']
    study.click()
    expect(page.locator('#episode-studied')).to_be_disabled()
    assert len([c for c in STATE['calls'] if c[0]=='PUT'])==1
    page.screenshot(path=str(out/f'web-study-{width}-{theme}.png'),full_page=False)
    page.reload();expect(page.locator('#episode-studied')).to_be_disabled()
    assert len([c for c in STATE['calls'] if c[0]=='PUT'])==1
    assert not [c for c in STATE['calls'] if c[0]=='POST']
    page.close()
   browser.close()
  print('PASS: four sizes/themes; explicit PUT once; reload persists; zero POST/provider generation')
 finally:server.shutdown()
