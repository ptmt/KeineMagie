"""Local-only browser regression: shipped UI + explicit synthetic HTTP API.
Never uses real accounts, provider requests, or production state.
Run with a Python environment containing playwright (chromium installed).
"""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
from urllib.parse import urlsplit
import hashlib, json
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
JOB={'id':'Original_User-Token_ABC','title':'The Nut Sisters','feed_id':'Feed_A','source_language':'de','target_language':'ru','state':'translating','progress':91,'segments':[{'start':i,'end':i+1,'text':'Guten Morgen '+str(i),**({'translation':'Доброе утро'} if i<954 else {})} for i in range(1000)]}
SUFFIX=hashlib.sha256(JOB['id'].encode()).hexdigest()[:12]
PATH='/podcasts/episodes/the-nut-sisters-'+SUFFIX
CALLS=[];SIGNED=True;ITEMS=[];CEFR='unknown';GENERATED=False
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*args,**kw):super().__init__(*args,directory=str(ROOT),**kw)
 def log_message(self,*args):pass
 def reply(self,body,status=200):
  data=json.dumps(body).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(data)
 def do_GET(self):
  path=urlsplit(self.path).path
  if not path.startswith('/v1/'):
   if path.startswith('/podcasts/episodes/'):self.path='/index.html'
   return super().do_GET()
  CALLS.append(('GET',self.path,None))
  if path=='/v1/web/config':return self.reply({'apple_available':True,'csrf_token':'boot'})
  if path=='/v1/web/session':return self.reply({'user':{'id':'fixture-owner'},'csrf_token':'fixture-csrf','provider':{'connected':True,'selected_model':'fixture'}},200) if SIGNED else self.reply({},401)
  if not SIGNED:return self.reply({},401)
  if path=='/v1/translations':return self.reply({'items':[]})
  if path=='/v1/podcasts/subscriptions':return self.reply({'items':[{'id':'Feed_A','title':'Nut sisters podcast','episodes':[]}]})
  if path=='/v1/podcasts':return self.reply({'items':[JOB],'worker_available':True})
  if path=='/v1/podcasts/'+JOB['id'] or (path.startswith('/v1/podcasts/episodes/') and path.endswith(SUFFIX)):return self.reply(JOB)
  if path=='/v1/learning/profiles/de':return self.reply({'language':'de','cefr':CEFR,'self_assessments':[],'progress':{'saved':len(ITEMS),'learning':0,'known':0,'favorites':len(ITEMS)}})
  if path=='/v1/learning/vocabulary':return self.reply({'items':ITEMS})
  if path.endswith('/analysis'):return self.reply({'state':'completed' if GENERATED else 'pending','estimate':{'remaining_requests':0 if GENERATED else 1,'completed_requests':int(GENERATED)},'profile_required':CEFR=='unknown','result':{'narrative':[{'text':'Fixture detailed source-grounded summary','citations':[{'segment_id':2,'quote':'Guten Morgen 2','start':2,'end':3}]}],'topics':[],'recommendations':[]} if GENERATED else None})
  return self.reply({},404)
 def mutate(self):
  global CEFR,GENERATED,SIGNED
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))) or b'{}');CALLS.append((self.command,self.path,body))
  if self.headers.get('X-CSRF-Token')!='fixture-csrf':return self.reply({},403)
  if self.path=='/v1/web/logout':SIGNED=False;return self.reply({})
  if not SIGNED:return self.reply({},401)
  if self.path=='/v1/learning/profiles/de':CEFR=body['cefr'];return self.reply({'cefr':CEFR})
  if self.path.endswith('/analysis'):
   GENERATED=True
   return self.reply({'state':'completed','estimate':{'remaining_requests':0,'completed_requests':1},'profile_required':CEFR=='unknown','result':{'narrative':[{'text':'Fixture detailed source-grounded summary','citations':[{'segment_id':2,'quote':'Guten Morgen 2','start':2,'end':3}]}],'topics':[],'recommendations':[]}})
  if self.path=='/v1/learning/vocabulary':
   assert body['job_id']==JOB['id'] and body['quote'] in JOB['segments'][body['segment_id']]['text']
   item={**body,'id':'Saved_A','start':body['segment_id'],'end':body['segment_id']+1};ITEMS.append(item);return self.reply(item)
  if self.path=='/v1/learning/vocabulary/Saved_A':ITEMS[0].update(body);return self.reply(ITEMS[0])
  return self.reply({},404)
 do_POST=mutate
 do_PUT=mutate
 do_PATCH=mutate

server=ThreadingHTTPServer(('127.0.0.1',0),Handler);Thread(target=server.serve_forever,daemon=True).start();origin='http://127.0.0.1:'+str(server.server_port)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();context=browser.new_context(locale='de-DE',permissions=['clipboard-read','clipboard-write']);page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto(origin+'/#podcasts/job/'+JOB['id']);page.wait_for_url('**'+PATH);page.locator('#episode-cefr:enabled').wait_for()
  assert page.locator('#podcasts').is_visible() and page.locator('.podcast-segments>li').count()==100
  while page.locator('[data-transcript-more]').count():page.locator('[data-transcript-more]').click()
  assert page.locator('.podcast-segments>li').count()==1000
  assert page.locator('.episode-pending').count()==46
  assert page.locator('#episode-overview').inner_text().find('954')>=0
  assert page.locator('.episode-reader progress').count()==0
  assert not [c for c in CALLS if c[0] in ['POST','PUT','PATCH']]
  before=len([c for c in CALLS if c[1].endswith('/analysis')]);page.get_by_role('button',name='Analyse erstellen',exact=True).click();page.get_by_text('Fixture detailed source-grounded summary',exact=False).first.wait_for()
  assert len([c for c in CALLS if c[0]=='POST' and c[1].endswith('/analysis')])==1
  page.locator('.episode-citation').first.click();assert page.evaluate('document.activeElement.id')=='episode-segment-2'
  page.select_option('#episode-cefr','B1');page.wait_for_function("() => document.querySelector('#episode-cefr').value==='B1' && !document.querySelector('#episode-cefr').disabled")
  page.locator('.episode-quote summary').first.click();page.locator('.episode-quote input').first.fill('Guten Morgen');page.locator('.episode-quote form button').first.click();page.get_by_role('heading',name='Guten Morgen',exact=True).wait_for()
  assert len(ITEMS)==1 and ITEMS[0]['favorite'] is True and ITEMS[0]['segment_id']==0
  page.get_by_role('button',name='Favorit entfernen',exact=True).click();page.get_by_role('button',name='Als Favorit speichern',exact=True).first.wait_for();assert ITEMS[0]['favorite'] is False
  page.get_by_role('button',name='Link kopieren',exact=True).click();page.get_by_text('Link kopiert',exact=True).wait_for();assert page.evaluate('navigator.clipboard.readText()')==origin+PATH
  for tab in ['translator','dictation','coach','podcasts']:
   page.locator('.section-nav a[href="#'+tab+'"]').click(force=True);page.wait_for_function('(id)=>!document.getElementById(id).hidden',arg=tab)
  page.go_back();page.locator('#coach').wait_for(state='visible')
  page.go_forward();page.locator('#podcasts').wait_for(state='visible')
  page.goto(origin+PATH);page.locator('#episode-cefr:enabled').wait_for();assert page.locator('.episode-header').inner_text().find('The Nut Sisters')>=0
  page.evaluate("history.pushState(null,'','/podcasts/episodes/cosmetic-title-"+SUFFIX+"');dispatchEvent(new PopStateEvent('popstate'))")
  page.locator('#episode-cefr:enabled').wait_for()
  page.go_back();page.locator('#episode-cefr:enabled').wait_for();assert page.url==origin+PATH
  page.go_forward();page.locator('#episode-cefr:enabled').wait_for();assert page.url.endswith('/cosmetic-title-'+SUFFIX)
  page.goto(origin+'/podcasts/episodes/cosmetic-title-'+SUFFIX);page.locator('#episode-cefr:enabled').wait_for()
  for width in [320,390,768,1440]:
   page.set_viewport_size({'width':width,'height':1000});assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),width
  evidence=Path('/Users/tinyserve/.hermes/cache/scratch/episode-evidence');evidence.mkdir(exist_ok=True);page.screenshot(path=str(evidence/'reader-1440.png'))
  page.locator('#account').click();page.locator('#logout').click();page.wait_for_function("() => document.querySelector('#podcast-content').textContent==='' ")
  assert not page.locator('#podcast-content').inner_text() and not errors,errors
  page.reload();page.wait_for_timeout(200);assert not page.locator('.episode-header').count()
  print(json.dumps({'checks':'legacy canonical, deep URL, cosmetic slug, all tabs, back/forward, 1000 source/954 translated/46 pending, explicit analysis only, citation focus, server vocabulary/profile readback, clipboard, owner clear, responsive','network_requests':len(CALLS),'page_errors':errors,'screenshot':str(evidence/'reader-1440.png')}))
  browser.close()
finally:server.shutdown()
