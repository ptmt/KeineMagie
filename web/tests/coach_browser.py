"""Synthetic browser transport only; production module and full shell, no live AI."""
from episode_fixture import Handler, STATE, JOB
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright
import json

DATA={'turns':[],'observations':[],'model':'gpt-6.1-terra'}
CALLS=[]
class CoachHandler(Handler):
 def do_GET(self):
  if self.path=='/v1/learning/coach': return self.reply(DATA)
  if self.path=='/v1/translations': return self.reply({'items':[{'id':'synthetic','created_at':'2026-11-13T00:00:00Z','text':'Synthetic source','translation':'Ich warte auf den Bus.','source_language':'ru','target_language':'de','idioms':[],'patterns':[],'vocabulary':[]}]})
  return super().do_GET()
 def do_POST(self):
  if self.path!='/v1/learning/coach': return self.mutate()
  body=json.loads(self.rfile.read(int(self.headers['Content-Length'])));CALLS.append(body)
  assert self.headers.get('X-CSRF-Token')=='fixture-csrf'
  action=body['action']
  if action=='message':
   DATA['turns'].append({'id':body['request_id'],'text':body['text'],'state':'pending' if body['text']=='pending' else 'completed','message':'Synthetic exercise — not live AI.','kind':'cloze','prompt':'Ich warte ___ den Bus.','target':'verb_government','source_id':'translation:synthetic','at':'2026-11-13T00:00:00Z','assisted':False,'language':'de'})
  else:
   turn=next((t for t in DATA['turns'] if t['id']==body['turn_id']),None)
   assert turn is not None
   if action=='cancel':turn['state']='canceled';turn.pop('kind',None)
   elif action in ['answer','skip']:
    outcome='skipped' if action=='skip' else {'auf':'correct','für':'wrong'}.get(body['text'],'ambiguous')
    turn['attempt']={'id':body['request_id'],'answer':body['text'],'outcome':outcome,'original_outcome':outcome,'assisted':turn['assisted'],'at':'2026-11-13T00:00:00Z','excluded':False}
    turn['quote']='Ich warte auf den Bus.';turn['explanation']='warten auf + Akkusativ'
   elif action=='reveal':turn.update(assisted=True,quote='Ich warte auf den Bus.',explanation='warten auf + Akkusativ')
   elif action=='review':
    turn['attempt']['excluded']=body['text']=='excluded'
    if body['text']!='excluded':turn['attempt']['outcome']=body['text']
  return self.reply(DATA)

server=ThreadingHTTPServer(('127.0.0.1',0),CoachHandler);Thread(target=server.serve_forever,daemon=True).start()
evidence=Path('/Users/tinyserve/.hermes/cache/scratch/coach-browser');evidence.mkdir(exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':1440,'height':1000});errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
  page.get_by_role('button',name='Practice · ~30 sec',exact=True).wait_for(state='visible')
  page.wait_for_function("!document.querySelector('.coach-actions button').disabled")
  assert not CALLS
  assert page.locator('.coach-page > .coach-profile').count()==0, 'observations belong in Profile'
  for text,expected in [('für','Needs practice'),('auf','Correct'),('perhaps','I can’t check this confidently')]:
   # Compact bubbles retain evidence in Profile, not technical exercise chrome.
   page.get_by_role('button',name='Practice · ~30 sec',exact=True).click()
   card=page.locator('.coach-exercise').last;card.get_by_role('textbox',name='Answer',exact=True).fill(text)
   card.get_by_role('button',name='Check',exact=True).click();card.get_by_text(expected,exact=True).wait_for()
   assert card.locator('details').count()==0, 'technical Skills disclosure remains in exercise'
   assert card.locator('.coach-answer').inner_text()==text
   assert page.locator('[data-turn]').last.get_by_text('warten auf + Akkusativ',exact=True).is_visible(), 'explanation hidden after answer'
   assert 'translation:synthetic' not in page.locator('.coach-messages').inner_text()
  page.screenshot(path=str(evidence/'desktop-feedback.png'),full_page=True)
  source=page.locator('[data-turn]').last.locator('details').last
  source.locator('summary').click();source.get_by_role('link',name='Saved translation').click()
  page.wait_for_function("document.activeElement.closest('[data-translation-i-d]')?.dataset.translationID==='synthetic'")
  page.reload();page.wait_for_function("document.activeElement.closest('[data-translation-i-d]')?.dataset.translationID==='synthetic'")
  page.go_back();page.locator('.coach-exercise').last.wait_for()
  # A reloaded page has no in-memory focus receipt, but Back still restores Coach.
  DATA['turns'][-1]['source_id']='passage:'+JOB['id']+':2012'
  DATA['turns'][-1]['quote']=JOB['segments'][2012]['text']
  page.get_by_role('button',name='Refresh',exact=True).click()
  source=page.locator('[data-turn]').last.locator('details').last
  page.wait_for_function("() => document.querySelector('[data-turn]:last-of-type a')?.href.includes('segment=2012')")
  if source.get_attribute('open') is None: source.locator('summary').click()
  source.get_by_role('link',name='Saved podcast passage').click()
  page.wait_for_function("() => document.activeElement.id==='episode-segment-2012'")
  page.go_back();page.wait_for_function("!!document.activeElement.dataset.coachSource")
  page.screenshot(path=str(evidence/'citation-return.png'))
  # Exact reported sentence: keep the literal attempt, abstain, show the rule.
  page.get_by_role('button',name='Practice · ~30 sec',exact=True).click()
  turn=DATA['turns'][-1]
  turn.update(message='Fill in the missing preposition.',prompt='Ich war einmal ___ diesem Kurs dabei.')
  page.get_by_role('button',name='Refresh',exact=True).click()
  page.locator('.coach-prompt').last.get_by_text('Ich war einmal ___ diesem Kurs dabei.',exact=True).wait_for()
  assert 'Fill in the missing preposition.' not in page.locator('.coach-messages').inner_text()
  card=page.locator('.coach-exercise').last
  card.get_by_role('textbox',name='Answer',exact=True).fill('beim')
  page.locator('[data-turn]').last.get_by_role('button',name='Hint',exact=True).click()
  assert turn['assisted']
  assert card.get_by_role('textbox',name='Answer',exact=True).input_value()=='beim'
  card.get_by_role('button',name='Check',exact=True).click()
  card.get_by_text('I can’t check this confidently',exact=True).wait_for()
  turn.update(quote='Ich war einmal bei diesem Kurs dabei.',explanation='Bei takes the dative. Beim means bei dem; diesem already supplies the determiner.')
  page.get_by_role('button',name='Refresh',exact=True).click()
  page.locator('.coach-explanation').last.get_by_text(turn['explanation'],exact=True).wait_for()
  assert card.locator('.coach-answer').inner_text()=='beim'
  page.locator('[data-turn]').last.scroll_into_view_if_needed()
  page.screenshot(path=str(evidence/'exact-course-desktop.png'))
  page.set_viewport_size({'width':390,'height':600})
  page.locator('.coach-explanation').last.scroll_into_view_if_needed()
  assert page.locator('#coach-input').bounding_box()['y']+page.locator('#coach-input').bounding_box()['height']<=600
  page.screenshot(path=str(evidence/'exact-course-mobile.png'))
  page.set_viewport_size({'width':1440,'height':1000})
  before_node=page.locator('[data-turn]').first.element_handle()
  page.get_by_role('button',name='Practice · ~30 sec',exact=True).click()
  assert before_node.evaluate('e=>e.isConnected'), 'existing chat nodes replaced during send'
  page.locator('.coach-exercise').last.get_by_role('button',name='Skip',exact=True).click()
  page.locator('.coach-exercise').last.get_by_text('Skipped',exact=True).wait_for()
  before=len(CALLS);page.reload();page.locator('.coach-exercise').last.get_by_text('Skipped',exact=True).wait_for();assert len(CALLS)==before
  page.set_viewport_size({'width':390,'height':600});page.emulate_media(reduced_motion='reduce')
  composer=page.locator('#coach-input');composer.fill('pending');page.locator('.coach-composer button').click()
  page.get_by_text('Pending · reload never retries. Cancel to continue.',exact=True).wait_for()
  page.get_by_role('button',name='Cancel',exact=True).click();page.get_by_text('Canceled',exact=True).wait_for()
  for locale in ['de','en','ru','es','fr']:
   page.locator('[data-interface-language]').first.select_option(locale)
   composer.fill('Retained draft');composer.focus()
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
   assert composer.input_value()=='Retained draft'
   composer.scroll_into_view_if_needed()
   assert composer.bounding_box()['y']+composer.bounding_box()['height']<=600
   assert page.locator('.coach-bubble').first.evaluate("e=>getComputedStyle(e).animationName")=='none'
  page.screenshot(path=str(evidence/'mobile-reduced-motion.png'))
  page.locator('[data-interface-language]').first.select_option('en')
  page.locator('#account').click()
  profile=page.locator('#learning-profile .coach-profile');profile.locator(':scope > summary').click()
  review=profile.locator('details').filter(has=page.locator('summary',has_text='Ich war einmal ___ diesem Kurs dabei.'))
  review.locator('summary').click();review.get_by_role('button',name='Count as correct',exact=True).click()
  page.wait_for_function("() => document.querySelector('.coach-answer') !== null")
  assert CALLS[-1]['action']=='review' and CALLS[-1]['text']=='correct'
  review.locator('summary').click();review.get_by_role('button',name='Exclude',exact=True).click()
  assert CALLS[-1]['action']=='review' and CALLS[-1]['text']=='excluded'
  assert turn['attempt']['answer']=='beim' and turn['attempt']['original_outcome']=='ambiguous'
  page.locator('#logout').click()
  page.wait_for_function("document.querySelector('#coach-input').disabled")
  assert page.locator('.coach-exercise').count()==0 and composer.input_value()==''
  assert not errors,errors
  print('PASS: correct/wrong/ambiguous/skip/reload/cancel, five locales, mobile composer, reduced motion, logout; synthetic HTTP only')
  browser.close()
finally:server.shutdown()
