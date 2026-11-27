"""Real mounted UI; explicitly synthetic malformed/legacy/long/restored ledgers."""
import json,mimetypes,os
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
repo=Path(__file__).resolve().parents[2]
out=repo/'docs/evidence/dictation-full-timeline';out.mkdir(parents=True,exist_ok=True)
results=[]
with sync_playwright() as pw:
 for engine in ['chromium','webkit']:
  browser=getattr(pw,engine).launch()
  for variant in ['mapped','flat','mixed']:
   plan=[dict(kind='whole',asset=0)]
   for f in range(24):
    meta=dict(sentence=f//8+1,fragment=f%8+1) if variant=='mapped' or variant=='mixed' and f%3 else {}
    for repeat in range(3):plan.append(dict(kind='sentence' if not repeat else 'sentence_repeat',asset=f+1,**meta))
   plan.append(dict(kind='final',asset=0))
   for phase in ['ready','unprepared','middle','repeat-ready','writing','stopped','pending-stop','checked','final','final-ended']:
    cursor={'ready':0,'unprepared':0,'middle':38,'repeat-ready':38,'writing':40,'stopped':0,'pending-stop':0,'checked':40,'final':73,'final-ended':73}[phase]
    # Skipped first fragment, extra replay, admission-only second repeat: never complete.
    listens=[dict(step=s,ended=True,intent='planned') for s in range(37) if s not in [1,2,3,5]]
    listens += [dict(step=5,ended=True,intent='extra'),dict(step=5,done=True,intent='planned')]
    if phase in ['ready','unprepared']:listens=[]
    if phase=='final-ended':listens += [dict(step=73,ended=True,intent='planned')]
    record=dict(id='timeline-'+variant+'-'+phase,title='Whole ordered plan',language='de',created='2026-11-27T00:00:00Z',mode='sentences',step=0,replays=0,draft='Unveränderter Entwurf.',revision=1,checked=phase=='checked',assisted=False,plan=plan,ready=list(range(25)) if phase!='unprepared' else [],playback_policy_version=2,pacing=dict(repeats=3,gap_seconds=3),playback=dict(revision=1,cursor=cursor,whole_starts=1,listens=listens))
    if phase=='middle':record['playback']['active']=dict(step=38,id='synthetic',intent='planned')
    if phase=='pending-stop':record['pending_stop']=dict(owner='timeline-owner',attempt=record['id'],body={})
    ctx=browser.new_context(viewport=dict(width=390,height=844));ctx.add_init_script('window.fixtureRecord='+json.dumps(record))
    def route(r):
     file=repo/'web'/urlparse(r.request.url).path.lstrip('/');assert file.is_relative_to(repo/'web')
     r.fulfill(path=str(file),content_type=mimetypes.guess_type(file)[0] or ('text/javascript' if file.suffix=='.mjs' else 'text/plain'))
    ctx.route('https://timeline.test/**',route);page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto('https://timeline.test/tests/dictation-timeline-fixture.html');page.get_by_role('button',name='Whole ordered plan').click()
    rows=page.locator('.dictation-timeline li:not(.dictation-sentence)');expect(rows).to_have_count(26)
    if variant=='flat':expect(page.locator('.dictation-sentence')).to_have_count(0)
    assert page.locator('.dictation-timeline').evaluate('(e)=>e.clientHeight>=e.scrollHeight')
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    if listens:
     assert 'is-complete' not in rows.nth(1).get_attribute('class')
     assert 'is-complete' not in rows.nth(2).get_attribute('class')
    assert page.locator('[aria-current=step]').count()==1
    if phase=='middle':expect(page.locator('.dictation-timeline [aria-current]')).to_contain_text('Play 2 of 3')
    if phase=='final-ended':assert 'is-complete' in rows.last.get_attribute('class')
    draft=page.locator('.dictation-work textarea')
    if phase=='middle' and variant=='mapped':
     draft.focus();draft.evaluate('(e)=>e.setSelectionRange(3,8)');page.evaluate('window.savedRows=Array.from(document.querySelectorAll(".dictation-timeline li"));window.beforeY=scrollY;fixtureController.localize()')
     assert page.evaluate('savedRows.every((e,i)=>e===document.querySelectorAll(".dictation-timeline li")[i])')
     assert page.evaluate('document.activeElement.selectionStart===3&&document.activeElement.selectionEnd===8')
     assert page.evaluate('Math.abs(scrollY-beforeY)<1')
     for width in [390,1100]:
      page.set_viewport_size(dict(width=width,height=900))
      for theme in ['light','dark']:
       page.emulate_media(color_scheme=theme);page.wait_for_timeout(350)
       if theme=='dark':
        colors=page.evaluate('({fg:getComputedStyle(document.querySelector(".dictation-heading h1")).color,bg:getComputedStyle(document.documentElement).backgroundColor})')
        import re
        def luminance(color):
         values=[int(x)/255 for x in re.findall(r'\d+',color)[:3]]
         return sum(w*(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4) for w,c in zip([.2126,.7152,.0722],values))
        a,b=sorted([luminance(colors['fg']),luminance(colors['bg'])]);assert (b+.05)/(a+.05)>=4.5,colors
       page.screenshot(path=str(out/f'{engine}-long-{width}-{theme}.png'),full_page=True)
     page.get_by_role('button',name='More options',exact=True).click();page.get_by_role('button',name='New attempt',exact=True).click()
     expect(page.locator('.dictation-timeline .is-complete')).to_have_count(0);expect(rows).to_have_count(26)
     expect(draft).to_have_value('');assert page.evaluate('savedRows.every(e=>!e.isConnected)')
     page.evaluate('window.savedRows=Array.from(document.querySelectorAll(".dictation-timeline li"))')
     page.evaluate('fixtureController.identity(null)');expect(rows).to_have_count(0)
     page.evaluate('fixtureRecord={...fixtureRecord,id:"fresh-attempt",playback:{revision:0,cursor:0,whole_starts:0,listens:[]}};fixtureController.identity({user:{id:"new-owner"},csrf_token:"new"})')
     page.get_by_role('button',name='Whole ordered plan').click();expect(rows).to_have_count(26);expect(page.locator('.dictation-timeline .is-complete')).to_have_count(0)
     assert page.evaluate('savedRows.every(e=>!e.isConnected)')
    assert not page.evaluate('calls.some(c=>c.method==="POST"&&!c.path.endsWith("/attempts"))')
    assert not errors,errors
    results.append(dict(engine=engine,variant=variant,state=phase,rows=26));ctx.close()
  browser.close()
(out/'state-matrix.json').write_text(json.dumps(dict(result='PASS',boundary='synthetic ledgers rendered by actual mounted UI, gap timing covered separately by natural-media suite',cases=results),indent=2))
print('PASS',len(results),'mounted cases')
