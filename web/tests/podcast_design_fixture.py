"""Local synthetic owner/50-episode fixture. No production credentials or inference.
Run with Python; serves shipped assets on 127.0.0.1:8773 for design review.
"""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit
from typing import Any
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
JOB: dict[str, Any] = dict(id='Fixture_Ready', feed_id='Feed_A', episode_id='Episode_0', title='The Nut Sisters', source_language='de', target_language='ru', state='completed', progress=100, segments=[dict(start=0, end=4, text='Guten Morgen. Dies ist ein lokaler Test.', translation='Доброе утро. Это локальный тест.')])
SUFFIX = hashlib.sha256(JOB['id'].encode()).hexdigest()[:12]
FEED = dict(id='Feed_A', title='Radio RTW · synthetic fixture', episodes=[dict(id='Episode_'+str(i), title=['The Nut Sisters', 'Triathloten', 'Eiserne Blase', 'Ende Gelände', 'Sack in der Kette im Hodenwald'][i % 5] + ('' if i < 5 else ' '+str(i)), published='2026-10-20T12:00:00Z', **({'preparation': JOB} if i == 0 else {})) for i in range(50)])
RECORD = dict(id='Translation_A', text='Исходный текст <script>не HTML</script>\nВторая строка.', translation='Übersetzter Text <img src=x onerror=alert(1)>\nZweite Zeile.\nDer vollständige gespeicherte Text bleibt sofort lesbar.', source_language='ru', target_language='de', created_at='2026-10-20T12:00:00Z', idioms=[], patterns=[], vocabulary=[])
STATE: dict[str, Any] = dict(job=dict(JOB), subscribed=True, signed=True, calls=[])

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)
    def log_message(self, format, *args):
        pass
    def reply(self, body, status=200):
        data=json.dumps(body).encode()
        self.send_response(status); self.send_header('Content-Type', 'application/json'); self.send_header('Cache-Control', 'no-store'); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        path=urlsplit(self.path).path
        if path == '/__fixture': return self.reply(STATE)
        if not path.startswith('/v1/'):
            if path.startswith('/podcasts/episodes/'): self.path='/index.html'
            return super().do_GET()
        STATE['calls'].append(dict(method='GET', path=path))
        if path == '/v1/web/config': return self.reply(dict(apple_available=False, csrf_token='boot'))
        if path == '/v1/web/session': return self.reply(dict(user=dict(id='synthetic-owner'), csrf_token='fixture-csrf', provider=dict(connected=True, selected_model='fixture'))) if STATE['signed'] else self.reply({},401)
        if not STATE['signed']: return self.reply({},401)
        if path == '/v1/translations': return self.reply(dict(items=[RECORD]))
        if path == '/v1/podcasts/subscriptions':
            feed={**FEED, 'episodes': [{**e, **({'preparation':STATE['job']} if i==0 and STATE['job'] else {})} for i,e in enumerate(FEED['episodes'])]}
            if not STATE['job']: feed['episodes'][0].pop('preparation',None)
            return self.reply(dict(items=[feed] if STATE['subscribed'] else []))
        if path == '/v1/podcasts': return self.reply(dict(items=[STATE['job']] if STATE['job'] else [],worker_available=True))
        if path == '/v1/podcasts/Fixture_Ready' or path.endswith(SUFFIX): return self.reply(STATE['job']) if STATE['job'] else self.reply({},404)
        if path == '/v1/provider': return self.reply(dict(connected=True, selected_model='fixture'))
        if path == '/v1/learning/profiles/de': return self.reply(dict(language='de',cefr='unknown',self_assessments=[],progress=dict(saved=0,learning=0,known=0,favorites=0)))
        if path == '/v1/learning/vocabulary': return self.reply(dict(items=[]))
        if path.endswith('/analysis'): return self.reply(dict(state='pending',estimate=dict(remaining_requests=1,completed_requests=0),profile_required=True,result=None))
        return self.reply({},404)
    def mutate(self):
        path=urlsplit(self.path).path
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))) or b'{}')
        if path == '/__fixture':
            if body.get('reset'): STATE.update(job=dict(JOB),subscribed=True,signed=True,calls=[])
            if 'state' in body and STATE['job']: STATE['job']['state']=body['state']
            return self.reply(STATE)
        STATE['calls'].append(dict(method=self.command,path=path,body=body,csrf=self.headers.get('X-CSRF-Token')))
        if self.headers.get('X-CSRF-Token') != 'fixture-csrf': return self.reply({},403)
        if path == '/v1/podcasts/Fixture_Ready' and self.command == 'DELETE': STATE['job']=None; return self.reply({})
        if path == '/v1/podcasts/subscriptions/Feed_A' and self.command == 'DELETE': STATE['subscribed']=False; return self.reply({})
        if path == '/v1/podcasts/subscriptions/Feed_A/refresh': return self.reply(FEED)
        if path == '/v1/web/logout': STATE['signed']=False; return self.reply({})
        # Deliberately no preparation/analysis implementation: review cannot create AI jobs.
        return self.reply(dict(error='fixture_mutation_not_supported'),400)
    do_POST=mutate
    do_DELETE=mutate

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1',8773),Handler).serve_forever()
