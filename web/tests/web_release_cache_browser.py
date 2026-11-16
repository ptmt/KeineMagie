"""Exercise old HTML/new modules and old modules/new HTML, synthetic HTTP.
No user profile, cookies, provider calls or browser cache resets.
"""
from episode_fixture import Handler, ROOT
from http.server import ThreadingHTTPServer
from threading import Thread
from playwright.sync_api import sync_playwright, expect
from pathlib import Path
import subprocess, os
OLD=os.environ.get('OLD_WEB_REVISION','64b0647')
MODE={'html':False,'modules':False}
class Mixed(Handler):
 def do_GET(self):
  path=self.path.split('?')[0]
  if path=='/v1/learning/dictations':return self.reply({'items':[]})
  if path=='/v1/learning/coach':return self.reply({'turns':[],'observations':[],'actions':[{'action':'practice','turn_id':''}]})
  name='index.html' if path=='/' else path.lstrip('/')
  if (MODE['html'] and name=='index.html') or (MODE['modules'] and name.endswith(('.mjs','.js','.css'))):
   result=subprocess.run(['git','show',f'{OLD}:web/{name}'],cwd=ROOT,capture_output=True)
   if result.returncode==0:
    self.send_response(200);self.send_header('Content-Type','text/html' if name.endswith('.html') else 'text/css' if name.endswith('.css') else 'text/javascript');self.end_headers();self.wfile.write(result.stdout);return
  return super().do_GET()
 def do_POST(self):
  if self.path=='/v1/learning/coach':return self.reply({'turns':[],'observations':[],'actions':[{'action':'practice','turn_id':''}]})
  return super().do_POST()
server=ThreadingHTTPServer(('127.0.0.1',0),Mixed);Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  for html,modules in [(True,False),(False,True),(False,False)]:
   MODE.update(html=html,modules=modules);page=browser.new_page();errors=[];page.on('pageerror',lambda e:errors.append(e.stack))
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
   page.goto(f'http://127.0.0.1:{server.server_port}/#dictation');page.wait_for_timeout(500)
   expect(page.get_by_role('button',name='Add text',exact=True)).to_be_enabled()
   expect(page.locator('#dictation [role=status]')).to_have_text('')
   # Old dictation code is expected to preserve the known bug, not a graph failure.
   empty=page.locator('#dictation').inner_text()
   assert ('No dictations yet.' in empty)==(not modules)
   page.get_by_role('link',name='Coach',exact=True).click();expect(page.locator('#coach-input')).to_be_enabled()
   assert not errors,errors
   print('PASS mixed release graph',{'old_html':html,'old_modules':modules,'known_old_empty_bug':modules,'page_errors':errors})
   page.close()
  browser.close()
finally:server.shutdown()
