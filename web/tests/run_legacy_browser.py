from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from threading import Thread
from playwright.sync_api import sync_playwright
import time,json,traceback,re
root=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(root),**kw)
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path.startswith('/v1/podcasts/subscriptions/Feed_A/artwork'):
   # Existing fixture artwork, no production content.
   import runpy
   body=runpy.run_path(str(root/'tests/podcast_fixture_server.py'))['png']();self.send_response(200);self.send_header('Content-Type','image/png');self.end_headers();self.wfile.write(body);return
  return super().do_GET()
servers=[]
for port in [8766,8769]:
 s=ThreadingHTTPServer(('127.0.0.1',port),Handler);Thread(target=s.serve_forever,daemon=True).start();servers.append(s)
results=[]
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  for name in ['browser_smoke','directions_browser','guest_browser','i18n_browser','podcasts_browser','session_browser','styles_browser']:
   context=browser.new_context(locale='de-DE');page=context.new_page();client=context.new_cdp_session(page);client.send('Page.enable')
   def nav(url):
    page.goto(url);return {}
   def js(code):
    # Old eval fixtures flattened modules. Resolve their original imports from
    # the actual shipped module sources rather than inventing dependencies.
    if 'function mountPodcasts' in code:
     if 'const {episodeLocation,episodePath,' in code:
      code=code.replace('function episodeLocation(pathname,hash) { return hash ? null : /^\\/podcasts\\/episodes\\/([a-z0-9]+(?:-[a-z0-9]+)*-[a-f0-9]{12})$/.exec(pathname)?.[1] || null; }','')
      code=code.replace("async function episodePath(job) { return (await import('./episode.mjs')).episodePath(job); }",'')
     if 'function registerStaticInterface' not in code and 'eval(window.__fixtureSource)' not in code:
      source=re.sub(r'export (?=(function|async function|const))','',(root/'i18n.mjs').read_text())
      code=code.replace('(() => {','(() => {'+source+'\n',1)
    return page.evaluate(code)
   env={'__file__':str(root/'tests'/f'{name}.py'),'new_tab':nav,'goto_url':nav,'js':js,'cdp':lambda method,**kw:client.send(method,kw),'wait_for_load':lambda:page.wait_for_load_state(),'fill_input':lambda sel,text:page.locator(sel).fill(text),'capture_screenshot':lambda:str(page.screenshot(path='/Users/tinyserve/.hermes/cache/scratch/legacy-screen.png') and '/Users/tinyserve/.hermes/cache/scratch/legacy-screen.png')}
   start=time.monotonic()
   try:exec(compile((root/'tests'/f'{name}.py').read_text(),str(root/'tests'/f'{name}.py'),'exec'),env);results.append({'suite':name,'passed':True,'seconds':round(time.monotonic()-start,2)})
   except Exception as e:results.append({'suite':name,'passed':False,'seconds':round(time.monotonic()-start,2),'error':str(e),'debug':page.evaluate('({body:document.body.innerText,calls:window.__calls,confirmCount:window.__confirmCount,buttons:[...document.querySelectorAll("#podcast-content button")].map(b=>({text:b.textContent,disabled:b.disabled,onclick:String(b.onclick)}))})')});traceback.print_exc()
   context.close()
  browser.close()
finally:
 for s in servers:s.shutdown()
print(json.dumps(results,ensure_ascii=False))
if not all(item["passed"] for item in results):raise SystemExit(1)
