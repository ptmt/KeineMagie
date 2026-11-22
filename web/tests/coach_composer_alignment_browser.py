"""Real application + loopback synthetic APIs. Optical ink, not box-center regression."""
from episode_fixture import Handler
from http.server import ThreadingHTTPServer
from threading import Thread, Event
from pathlib import Path
from datetime import datetime, timezone
from playwright.sync_api import sync_playwright, expect
from PIL import Image
import json, os

GATE = Event()
CALLS = []
def fresh():
 return {'turns':[{'id':'task','kind':'cloze','state':'completed','prompt':'Ich warte ___ den Bus.','at':datetime.now(timezone.utc).isoformat()}], 'observations':[], 'actions':[{'action':a,'turn_id':'task' if a in ['reveal','explain'] else ''} for a in ['reveal','progress','more','explain','practice']]}
D = fresh()
class Chat(Handler):
 def do_GET(self):
  if self.path == '/v1/learning/coach': return self.reply(D)
  return super().do_GET()
 def do_POST(self):
  if self.path != '/v1/learning/coach': return self.mutate()
  b=json.loads(self.rfile.read(int(self.headers['Content-Length']))); CALLS.append(b)
  if b['action']=='answer': GATE.wait(10)
  if b['action']=='cancel':
   D['turns'][0]['attempt']={'id':b['turn_id'],'answer':'auf','outcome':'ambiguous','assessment_state':'canceled'}; GATE.set()
  # Stop aborts the in-flight answer fetch; WebKit closes that socket immediately.
  try: return self.reply(D)
  except (BrokenPipeError, ConnectionResetError):
   if b['action']!='answer': raise

def ink_center(image, box, theme):
 # Interior only: exclude the focus outline and rounded composer border.
 x,y,w,h=[box[k] for k in ['x','y','width','height']]
 points=[]
 for yy in range(round(y+5),round(y+h-5)):
  for xx in range(round(x+5),round(x+w-5)):
   r,g,b=image.getpixel((xx,yy))[:3]
   if (max(r,g,b)<110 if theme=='light' else min(r,g,b)>165): points.append(yy)
 assert points,box
 return (min(points)+max(points))/2

out=Path(os.environ.get('COMPOSER_EVIDENCE',str(Path(os.environ['TMPDIR'])/'composer-alignment')));out.mkdir(parents=True,exist_ok=True)
server=ThreadingHTTPServer(('127.0.0.1',0),Chat);Thread(target=server.serve_forever,daemon=True).start()
receipts=[]; failures=[]; errors=[]
try:
 with sync_playwright() as p:
  engine=os.environ.get('BROWSER','chromium'); browser=getattr(p,engine).launch()
  for width,theme in [(1280,'light'),(390,'light'),(1280,'dark'),(390,'dark')]:
   D=fresh(); GATE.clear(); page=browser.new_page(viewport={'width':width,'height':900 if width==1280 else 844},color_scheme=theme,device_scale_factor=1)
   page.on('pageerror',lambda e:errors.append(str(e)))
   # Optional released stylesheet replay for identical before/after captures.
   if os.environ.get('COMPOSER_BASELINE_CSS'):
    page.route('**/coach.css*',lambda route:route.fulfill(content_type='text/css',body=Path(os.environ['COMPOSER_BASELINE_CSS']).read_text()))
   page.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','en')")
   page.goto(f'http://127.0.0.1:{server.server_port}/#coach')
   draft=page.locator('#coach-input'); plus=page.locator('.coach-menu-trigger'); shell=page.locator('.coach-composer-shell'); send=page.get_by_role('button',name='Send',exact=True)
   expect(draft).to_be_enabled(); page.wait_for_timeout(300)
   for state,text in [('empty',''),('single','Discussion draft ä🙂'),('multiline','Discussion draft ä🙂\nSecond line\nDiscussion draft ä🙂')]:
    draft.fill(text); draft.blur(); page.evaluate('scrollTo(0,0)'); page.wait_for_timeout(60)
    stem=f'{engine}-{width}-{theme}-{state}'
    page.screenshot(path=str(out/(stem+'-full.png'))); shell.screenshot(path=str(out/(stem+'-crop.png')))
    pb=plus.bounding_box(); db=draft.bounding_box(); sb=send.bounding_box()
    styles=draft.evaluate("e=>{let s=getComputedStyle(e);return {font:s.font,lineHeight:s.lineHeight,padding:s.padding,height:s.height,scrollHeight:e.scrollHeight}}")
    # First word excludes emoji/diacritics: compare common Latin ink to plus ink.
    tb={**db,'width':87,'height':44,'y':db['y']+db['height']-44}
    image=Image.open(out/(stem+'-full.png')).convert('RGB')
    delta=ink_center(image,pb,theme)-ink_center(image,tb,theme)
    record={'variant':stem,'delta':delta,'plus':pb,'textarea':db,'send':sb,'styles':styles};receipts.append(record)
    if abs(delta)>1: failures.append(record)
    assert pb['width']==pb['height']==sb['width']==sb['height']==44
    assert abs(pb['y']+44-(db['y']+db['height']))<1
    assert db['height']==(92 if state=='multiline' else 44),record
   draft.fill('Discussion draft ä🙂'); draft.focus(); draft.evaluate('e=>e.setSelectionRange(2,6)'); before=len(CALLS)
   plus.click(); expect(page.get_by_role('menu')).to_be_visible(); page.screenshot(path=str(out/f'{engine}-{width}-{theme}-menu-full.png'))
   page.keyboard.press('Escape'); expect(draft).to_be_focused(); assert draft.evaluate('e=>[e.selectionStart,e.selectionEnd]')==[2,6]; assert len(CALLS)==before
   draft.fill('\n'.join(['Discussion draft']*12)); assert draft.bounding_box()['height']==140; assert draft.evaluate('e=>e.scrollHeight>e.clientHeight'); expect(draft).to_be_focused()
   draft.fill('Discussion draft ä🙂'); assert draft.bounding_box()['height']==44
   send_box=send.bounding_box()
   page.locator('.coach-exercise input').fill('auf'); page.get_by_role('button',name='Check',exact=True).click()
   stop=page.get_by_role('button',name='Stop',exact=True);expect(stop).to_be_enabled(); assert stop.bounding_box()==send_box
   page.screenshot(path=str(out/f'{engine}-{width}-{theme}-stop-full.png'));shell.screenshot(path=str(out/f'{engine}-{width}-{theme}-stop-crop.png'))
   stop.click();expect(stop).to_have_count(0);expect(draft).to_have_value('Discussion draft ä🙂')
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth');page.close()
  browser.close()
 (out/'receipt.json').write_text(json.dumps({'engine':engine,'synthetic':True,'measurements':receipts,'failures':failures,'errors':errors},indent=2))
 assert not errors,errors
 assert not failures, 'Optical plus/text misalignment: '+json.dumps([(r['variant'],r['delta']) for r in failures])
 print(f'PASS {engine}: optical alignment; desktop/mobile light/dark; emoji, multiline, growth/shrink/cap, 44px controls, menu focus/caret, Stop. Evidence: {out}')
finally:
 GATE.set();server.shutdown()
