"""Offline synthetic episode only. No provider or production credentials."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit
import hashlib, json
ROOT=Path(__file__).resolve().parents[1]
JOB={'id':'Navigation_Fixture_2113','title':'The Nut Sisters · synthetic fixture','feed_id':'Fixture_Feed','source_language':'de','target_language':'ru','state':'completed','segments':[{'start':i*3,'end':i*3+3,'text':f'Guten Morgen. Wir sprechen über Sprache und Alltag. Satz {i}.','translation':f'Доброе утро. Мы говорим о языке и повседневности. Фраза {i}.'} for i in range(2113)]}
SUFFIX=hashlib.sha256(JOB['id'].encode()).hexdigest()[:12]
PATH='/podcasts/episodes/the-nut-sisters-synthetic-fixture-'+SUFFIX
CITATION={'segment_id':2012,'quote':'Guten Morgen','start':6036,'end':6039}
RESULT={'narrative':[{'text':'Synthetic summary: conversation about language and everyday life.','citations':[CITATION]}],'topics':[{'title':'Everyday language','key_points':[{'text':'A source-grounded synthetic topic.','citations':[CITATION]}]},{'title':'Learning together','key_points':[{'text':'Practice in context.','citations':[]}]}],'recommendations':[{'term':'Alltag','cefr':'B1','translation':'повседневность','reason':'Practice a useful word in context.','kind':'word','citation':{**CITATION,'quote':'Alltag'}}]}
STATE={'signed':True,'owner':'fixture-owner','cefr':'B1','history':[{'cefr':'B1','assessed_at':'2026-11-12T10:00:00Z'}],'calls':[],'profile_error':False,'items':[]}
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(ROOT),**kw)
 def log_message(self, format, *args):pass
 def reply(self,body,status=200):
  data=json.dumps(body).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(data)
 def do_GET(self):
  path=urlsplit(self.path).path
  if not path.startswith('/v1/'):
   if path.startswith('/podcasts/episodes/'):self.path='/index.html'
   return super().do_GET()
  STATE['calls'].append(('GET',self.path,None))
  if path=='/v1/web/config':return self.reply({'apple_available':True,'csrf_token':'boot'})
  if path=='/v1/web/session':return self.reply({'user':{'id':STATE['owner']},'csrf_token':'fixture-csrf','provider':{'connected':True,'selected_model':'fixture'}},200) if STATE['signed'] else self.reply({},401)
  if not STATE['signed']:return self.reply({},401)
  if path=='/v1/translations':return self.reply({'items':[]})
  if path=='/v1/provider':return self.reply({'connected':True,'status':'connected','selected_model':'fixture'})
  if path=='/v1/podcasts/subscriptions':return self.reply({'items':[{'id':'Fixture_Feed','title':'Radio fixture','episodes':[]}]})
  if path=='/v1/podcasts':return self.reply({'items':[JOB],'worker_available':True})
  if path=='/v1/podcasts/'+JOB['id'] or path.endswith(SUFFIX):return self.reply(JOB)
  if path.startswith('/v1/learning/profiles/'):
   if STATE['profile_error']:return self.reply({},503)
   return self.reply({'language':path.rsplit('/',1)[1],'cefr':STATE['cefr'],'self_assessments':STATE['history']})
  if path=='/v1/learning/vocabulary':return self.reply({'items':STATE['items']})
  if path.endswith('/analysis'):return self.reply({'state':'completed','estimate':{'remaining_requests':0,'completed_requests':3},'result':RESULT})
  return self.reply({},404)
 def mutate(self):
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))) or b'{}');STATE['calls'].append((self.command,self.path,body))
  if not STATE['signed']:return self.reply({},401)
  if self.headers.get('X-CSRF-Token')!='fixture-csrf':return self.reply({},403)
  if self.path=='/v1/web/logout':STATE['signed']=False;return self.reply({})
  if self.path.startswith('/v1/learning/profiles/'):
   if STATE['profile_error']:return self.reply({},503)
   STATE['cefr']=body['cefr'];STATE['history'].append({'cefr':body['cefr'],'assessed_at':'2026-11-12T12:00:00Z'});return self.reply({'cefr':STATE['cefr']})
  if self.path=='/v1/learning/vocabulary':
   item={**body,'id':'fixture-word'};STATE['items'].append(item);return self.reply(item)
  return self.reply({},405)
 do_PUT=mutate
 do_POST=mutate
 do_PATCH=mutate
if __name__=='__main__':
 import argparse
 parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=8767);args=parser.parse_args()
 server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler)
 print('SYNTHETIC fixture: http://127.0.0.1:'+str(server.server_port)+PATH,flush=True);server.serve_forever()
