"""Independent combined-tree regression using local synthetic data only."""
from episode_fixture import Handler, JOB, PATH, STATE
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
from playwright.sync_api import sync_playwright
import json
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
evidence=Path('/Users/tinyserve/.hermes/cache/scratch/episode-independent-review');evidence.mkdir(exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(viewport={'width':320,'height':844});errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
  page.goto(origin+PATH);page.locator('.episode-citation').first.wait_for()
  page.screenshot(path=str(evidence/'before-320.png'))
  assert page.locator('.section-nav a').count()==4
  assert page.locator('.section-nav a').last.evaluate('(e)=>{const r=e.getBoundingClientRect(),p=e.parentElement.getBoundingClientRect();return r.left>=p.left&&r.right<=p.right}'), 'Coach must not be clipped at 320px'
  page.set_viewport_size({'width':1440,'height':1000})
  page.locator('.episode-topics a').first.click()
  source=page.locator('#episode-topic-0 + p .episode-citation')
  source.click();page.get_by_role('button',name='Back to section',exact=True).click()
  assert source.evaluate('(e)=>e===document.activeElement'), 'citation return must restore the stable source control, not the section heading'
  for locale in ['de','en','ru','es','fr']:
   for width in [320,390,768,1440]:
    page.set_viewport_size({'width':width,'height':844})
    page.locator('[data-interface-language]').first.select_option(locale)
    page.evaluate('scrollTo(0,0)')
    assert page.locator('.section-nav a').count()==4
    assert page.locator('.section-nav a').evaluate_all('(es)=>es.every(e=>{const r=e.getBoundingClientRect(),p=e.parentElement.getBoundingClientRect();return r.left>=p.left&&r.right<=p.right+.5})'), (locale,width)
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),(locale,width)
    page.locator('.episode-nav a').last.focus();page.keyboard.press('Enter')
    page.locator('#episode-find').fill('Guten Morgen')
    assert '/ 2113 ' in page.locator('#episode-find-count').inner_text()
    page.locator('#episode-find').press('Enter')
    assert page.locator('.podcast-segments>li').count()<=200
    assert page.locator('.episode-quote form').count()==0
    assert page.locator('#episode-segment-0').evaluate('(e)=>e.getBoundingClientRect().top')>=page.locator('.episode-find').evaluate('(e)=>e.getBoundingClientRect().bottom')-1,(locale,width,'sticky target overlap')
    assert page.locator('.episode-find').evaluate('(e)=>Math.abs(e.getBoundingClientRect().top-document.querySelector(".episode-nav").getBoundingClientRect().bottom)<2'),(locale,width,'toolbar must follow effective nav height')
    page.locator('#episode-find').fill('absent-string');assert page.locator('[data-match-direction]:enabled').count()==0
    page.locator('#episode-find').fill('')
    if width in [320,1440]:
     page.evaluate('scrollTo(0,0)');page.screenshot(path=str(evidence/f'after-{locale}-{width}.png'))
  page.locator('[data-interface-language]').first.select_option('en');page.set_viewport_size({'width':1440,'height':1000})
  page.locator('.episode-nav a').last.click();page.locator('#episode-find').fill('Guten Morgen')
  page.evaluate("document.styleSheets[0].insertRule('.episode-reader .episode-nav{flex-wrap:wrap!important;width:160px!important}',0)")
  page.wait_for_timeout(50);page.locator('#episode-find').press('Enter')
  page.wait_for_timeout(100)
  assert page.locator('.episode-find').evaluate('(e)=>Math.abs(e.getBoundingClientRect().top-document.querySelector(".episode-nav").getBoundingClientRect().bottom)<2'), ('wrapped nav height must drive sticky toolbar offset',page.evaluate("({nav:document.querySelector('.episode-nav').getBoundingClientRect().toJSON(),toolbar:document.querySelector('.episode-find').getBoundingClientRect().toJSON(),style:document.querySelector('.episode-reader').getAttribute('style')})"))
  page.evaluate('document.styleSheets[0].deleteRule(0)');page.locator('#episode-find').fill('')
  page.locator('.episode-nav a').first.click();page.locator('.episode-citation').first.click()
  page.evaluate('window.reviewScrollCalls=0;window.reviewScrollStacks=[];window.reviewOriginalScroll=window.scrollTo;window.scrollTo=(...args)=>{window.reviewScrollCalls++;window.reviewScrollStacks.push(new Error().stack);return window.reviewOriginalScroll(...args)};void 0')
  page.locator('#episode-segment-2012 .episode-quote summary').click()
  draft=page.locator('#episode-segment-2012 .episode-quote input');draft.fill('Guten')
  draft.evaluate('(e)=>{e.focus();e.setSelectionRange(1,3)}')
  for locale in ['fr','ru','en']:
   page.locator('[data-interface-language]').first.select_option(locale)
   assert draft.input_value()=='Guten' and draft.evaluate('(e)=>e.selectionStart===1&&e.selectionEnd===3')
  page.wait_for_timeout(100);assert page.evaluate('window.reviewScrollCalls')==0,('locale redraw must not replay permalink scroll',page.evaluate('window.reviewScrollStacks'))
  page.evaluate('window.scrollTo=window.reviewOriginalScroll')
  page.locator('.episode-nav a').last.click()
  page.locator('#episode-time').fill('0:00');page.locator('.episode-time-jump button').click()
  assert page.evaluate('document.activeElement.id')=='episode-segment-0'
  original=page.url;page.locator('#episode-time').fill('0:60');page.locator('.episode-time-jump button').click();assert page.url==original
  page.locator('#account').click();page.locator('#profile-cefr:enabled').wait_for()
  languages=[]
  page.route('**/v1/learning/profiles/ru',lambda route:languages.append(route))
  page.locator('#profile-language').select_option('ru');page.wait_for_timeout(100);assert languages
  page.locator('#profile-language').evaluate("(e)=>{e.value='de';e.dispatchEvent(new Event('change'))}")
  page.locator('#profile-cefr:enabled').wait_for()
  languages.pop().fulfill(json={'language':'ru','cefr':'C2','self_assessments':[]});page.wait_for_timeout(100)
  assert page.locator('#profile-language').input_value()=='de' and page.locator('#profile-cefr').input_value()=='B1','late language response must not replace selected profile'
  page.unroute('**/v1/learning/profiles/ru')
  assert not [c for c in STATE['calls'] if c[0]=='PUT'], 'opening and locale changes never auto-save CEFR'
  page.locator('#close-account').click()
  pending=[];hold={'next':True}
  def delay_profile(route):
   if hold['next']:
    hold['next']=False;pending.append(route)
   else:route.continue_()
  page.route('**/v1/learning/profiles/de',delay_profile)
  page.locator('#account').click();page.wait_for_function("()=>document.querySelector('#profile-cefr').disabled")
  page.wait_for_timeout(100);assert pending
  STATE['owner']='second-owner';STATE['cefr']='C1';STATE['history']=[{'cefr':'C1','assessed_at':'2026-11-12T12:00:00Z'}]
  page.locator('#retry-session').click();page.wait_for_timeout(200)
  assert page.locator('#profile-cefr').input_value()=='unknown' and page.locator('#profile-history').inner_text()==''
  pending.pop(0).fulfill(json={'language':'de','cefr':'A1','self_assessments':[{'cefr':'A1','assessed_at':'2026-01-01T00:00:00Z'}]})
  page.wait_for_timeout(100)
  assert page.locator('#profile-cefr').input_value()=='unknown' and 'A1' not in page.locator('#profile-history').inner_text(), 'late prior-owner GET must never revive history'
  hold['next']=True
  page.locator('#close-account').click();page.locator('#account').click();page.wait_for_timeout(100);assert pending
  page.locator('#logout').click()
  pending.pop(0).fulfill(json={'language':'de','cefr':'C2','self_assessments':[{'cefr':'C2','assessed_at':'2026-01-01T00:00:00Z'}]})
  page.wait_for_timeout(100)
  assert page.locator('#learning-profile').is_hidden() and page.locator('#profile-history').inner_text()==''
  assert not [c for c in STATE['calls'] if c[0]=='POST' and c[1].endswith('/analysis')]
  page.unroute_all(behavior='ignoreErrors')
  STATE['signed']=True;STATE['owner']='review-final'
  for query in ['?section=transcript&segment=2012','?section=%3Cimg%20src=x%20onerror=alert(1)%3E&segment=0','?section=transcript&segment=99999999999999999999','?section=summary&topic=%22%5D%3Cscript%3E&next=https%3A%2F%2Fevil.invalid']:
   page.goto(origin+PATH+query);page.locator('.episode-reader').wait_for();page.wait_for_timeout(100)
   assert page.url.startswith(origin+PATH) and page.locator('.episode-nav a').count()==4
   assert page.locator('.episode-reader script,.episode-reader img[src="x"]').count()==0
   if 'segment=2012' in query:page.wait_for_function("() => document.activeElement.id==='episode-segment-2012'")
  page.locator('.episode-breadcrumb a').first.click();page.wait_for_timeout(100)
  assert page.locator('#podcasts').is_visible() and page.locator('.podcast-feed').count()==1,'query cannot break legacy podcasts hash routing'
  def empty_analysis(route):route.fulfill(status=409,json={'error':'not_ready'})
  page.route('**/analysis',empty_analysis)
  page.route('**/v1/learning/vocabulary?*',lambda route:route.fulfill(status=503,json={}))
  JOB['segments']=[]
  page.goto(origin+PATH);page.locator('.episode-reader').wait_for();page.wait_for_timeout(100)
  assert page.locator('.episode-citation').count()==0 and page.locator('.podcast-segments>li').count()==0
  assert 'Synthetic summary:' not in page.locator('#episode-summary').inner_text()
  assert page.locator('#episode-summary button:enabled').count()==1,'missing analysis offers explicit generation, never generated text'
  JOB['segments']=[{'start':0,'end':3,'text':'Literal <script>alert(1)</script> & Unicode Ж','translation':''}]
  page.reload();page.locator('.podcast-segments>li').wait_for()
  assert page.locator('[data-transcript-text="text"]').inner_text()==JOB['segments'][0]['text']
  assert page.locator('.episode-pending').count()==1 and page.locator('.episode-reader script').count()==0
  assert not [c for c in STATE['calls'] if c[0]=='POST' and c[1].endswith('/analysis')]
  assert not errors,errors
  print(json.dumps({'passed':'20 locale/width keyboard sticky-search combinations; global navigation; citation return; timestamp zero/invalid; owner replacement and logout delayed GET; no automatic PUT/analysis','page_errors':errors,'requests':len(STATE['calls'])}))
  browser.close()
finally:server.shutdown()
