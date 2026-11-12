"""Real Chromium correspondence UX; synthetic owner/provider fixtures only."""
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from threading import Thread
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw):super().__init__(*a,directory=str(root),**kw)
 def log_message(self,*a):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler);Thread(target=server.serve_forever,daemon=True).start()
origin='http://localhost:'+str(server.server_port)
checks=[]
def check(name,condition):
 assert condition,name
 checks.append(name)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();context=browser.new_context(locale='en-US',permissions=['clipboard-read','clipboard-write']);page=context.new_page()
  errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  original=dict(id='saved',text='лук',translation='Zwiebel',source_language='ru',target_language='de',instructions='',idioms=[],patterns=[],vocabulary=[])
  record=dict(original);posts=[]
  def api(route):
   global record
   path=route.request.url.split(origin)[1]
   if path=='/v1/translation-followups':
    body=route.request.post_data_json;posts.append(body)
    turn=dict(request_id=body['request_id'],question=body['question'],answer='This broader sentence changes the source too.',revised_text='Wir arbeiten besser mit Grenzen.\n',revised_source_text='Мы работаем лучше с ограничениями.\n')
    turn['current_source']=body['current_source'];turn['current_translation']=body['current_translation']
    if record.get('followups'):turn['revised_source_text']=None
    record={**record,'followups':[*record.get('followups',[]),turn]};route.fulfill(status=201,json=record);return
   data={'/v1/web/config':dict(apple_available=False,pairing_available=True,csrf_token='fixture'),'/v1/web/session':dict(user=dict(id='owner'),csrf_token='fixture',provider=dict(connected=True,status='connected',selected_model='fixture')),'/v1/provider':dict(connected=True,status='connected',selected_model='fixture'),'/v1/translations':dict(items=[record]),'/v1/podcasts':dict(items=[],worker_available=False),'/v1/podcasts/subscriptions':dict(items=[]),'/v1/learning/profile':dict(assessments=[])}
   route.fulfill(json=data.get(path,{}))
  page.route('**/v1/**',api);page.goto(origin);page.locator('#history-list button').click()
  check('discussion belongs to output pane',page.locator('.output-panel #translation-followup').count()==1)
  page.locator('#edit-translation').click();editor=page.locator('#translation-editor');editor.fill('  Manuell 👩🏽‍💻 <b>literal</b>\nEnde\n ')
  page.locator('#copy').click();check('copy reads exact manual editor draft',page.evaluate('navigator.clipboard.readText()')==editor.input_value())
  page.select_option('#interface-language-header','ru');check('locale preserves editor and manual draft',editor.is_visible() and editor.input_value().endswith('\n '))
  page.locator('#finish-translation-edit').click();check('manual result plain text and local-only caption',page.locator('#result').text_content()=='  Manuell 👩🏽‍💻 <b>literal</b>\nEnde\n ' and page.locator('#result b').count()==0 and 'истор' in page.locator('#result-caption').text_content())
  page.locator('#clarify-translation').click();page.locator('#followup-question').fill('Broader context');page.locator('#send-followup').click();page.wait_for_function("() => document.querySelectorAll('#followup-thread li').length===1")
  check('manual output is next question context',posts[-1]['current_translation']=='  Manuell 👩🏽‍💻 <b>literal</b>\nEnde\n ' and posts[-1]['current_source']=='лук')
  check('paired suggestion previews both before explicit apply',page.locator('#source-text').input_value()=='лук' and page.locator('.followup-source').text_content()=='Мы работаем лучше с ограничениями.\n' and page.locator('[data-revision="0"]').text_content()=='Применить текст и перевод')
  for width in [1440,390]:
   page.set_viewport_size(dict(width=width,height=960));page.locator('#clarify-translation').focus();page.locator('#clarify-translation').blur();page.screenshot(path=f'/Users/tinyserve/.hermes/cache/scratch/correspondence-pair-{width}.png',full_page=True)
  page.locator('[data-revision="0"]').click()
  check('explicit use both updates actual source output counter and direction',page.locator('#source-text').input_value()=='Мы работаем лучше с ограничениями.\n' and page.locator('#result').text_content()=='Wir arbeiten besser mit Grenzen.\n' and page.locator('#language-direction').input_value()=='ru-de' and page.locator('#input-count').text_content().startswith(str(len('Мы работаем лучше с ограничениями.\n'))))
  page.locator('#followup-question').fill('Why?');page.locator('#send-followup').click();page.wait_for_function("() => document.querySelectorAll('#followup-thread li').length===2")
  check('next question uses explicitly applied pair',posts[-1]['current_source']=='Мы работаем лучше с ограничениями.\n' and posts[-1]['current_translation']=='Wir arbeiten besser mit Grenzen.\n')
  check('older source-sensitive proposal relabels against current pair',page.locator('[data-revision="0"]').text_content()=='Использовать перевод')
  check('immutable history preview remains original',page.locator('.history-source').text_content()=='лук' and page.locator('.history-translation').text_content()=='Zwiebel')
  for width in [1440,390]:
   page.set_viewport_size(dict(width=width,height=960));page.screenshot(path=f'/Users/tinyserve/.hermes/cache/scratch/correspondence-{width}.png',full_page=True)
   check(f'no overflow {width}',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
  page.locator('#history-list button').click();check('reopening original wipes hidden manual editor',editor.input_value()=='');check('reopen restores original but retains proposals',page.locator('#source-text').input_value()=='лук' and page.locator('#result').text_content()=='Zwiebel' and page.locator('#followup-thread li').count()==2)
  check('reopened translation-only revision retains its own source association',page.locator('[data-revision="1"]').text_content()=='Применить текст и перевод')
  page.locator('[data-revision="1"]').click();check('reopened suggestion restores contextual source too',page.locator('#source-text').input_value()=='Мы работаем лучше с ограничениями.\n')
  page.locator('#edit-translation').click();editor.fill('Edited for swap\n');page.locator('#swap').click();check('swap uses current manual editor',page.locator('#source-text').input_value()=='Edited for swap\n' and page.locator('#language-direction').input_value()=='de-ru')
  check('detaching result clears hidden private editor text',editor.input_value()=='')
  for source,target in [('ru','de'),('de','ru'),('de','de')]:
   record={**original,'source_language':source,'target_language':target}
   page.reload();page.locator('#history-list button').click();page.locator('#clarify-translation').click();page.locator('#followup-question').fill('context');page.locator('#send-followup').click();page.wait_for_function("() => document.querySelectorAll('#followup-thread li').length===1");page.locator('[data-revision="0"]').click()
   check(f'paired apply keeps actual {source}-{target} direction',page.locator('#language-direction').input_value()==source+'-'+target and page.locator('#source-text').get_attribute('lang')==source and page.locator('#result').get_attribute('lang')==target)
  check('no page errors',not errors);browser.close()
finally:server.shutdown()
print(str(len(checks))+' correspondence checks passed: '+', '.join(checks))
