"""Real HTMLMediaElement with synthetic silent WAV, no provider/network audio."""
import io,json,wave
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
out=Path('/Users/tinyserve/.hermes/cache/scratch/dictation-focused-evidence')
buf=io.BytesIO()
with wave.open(buf,'wb') as w:
 w.setnchannels(1);w.setsampwidth(2);w.setframerate(8000);w.writeframes(b'\0\0'*24000)
audio=buf.getvalue();ranges=[]
with sync_playwright() as p:
 b=p.chromium.launch();ctx=b.new_context(viewport={'width':390,'height':844});page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.add_init_script('const ActualAudio=Audio;window.Audio=function(){const a=new ActualAudio();window.realFixtureAudio=a;return a;}')
 def media(route):
  assert route.request.method=='GET';r=route.request.headers.get('range');ranges.append(r)
  if r:
   start=int(r.split('=')[1].split('-')[0]);route.fulfill(status=206,content_type='audio/wav',headers={'Accept-Ranges':'bytes','Content-Range':f'bytes {start}-{len(audio)-1}/{len(audio)}'},body=audio[start:])
  else:route.fulfill(status=200,content_type='audio/wav',body=audio)
 page.route('**/v1/learning/dictations/*/audio/*',media)
 page.goto('http://127.0.0.1:8876/tests/dictation-focused-fixture.html?realmedia');page.get_by_role('button',name='Ein Spaziergang im Park · In progress').click();page.get_by_role('button',name='Prepare audio',exact=True).click();page.get_by_role('button',name='Play',exact=True).click();page.wait_for_function('realFixtureAudio.currentTime>.3');page.get_by_role('button',name='Pause',exact=True).click();t=page.evaluate('realFixtureAudio.currentTime');page.wait_for_timeout(150);assert page.evaluate('realFixtureAudio.currentTime')==t
 page.get_by_role('button',name='Play',exact=True).click();page.wait_for_function('realFixtureAudio.currentTime>1');expect(page.get_by_role('button',name='Replay',exact=True)).to_be_visible(timeout=10000);page.get_by_role('button',name='Replay',exact=True).click();expect(page.get_by_role('button',name='Pause',exact=True)).to_be_visible();page.get_by_role('button',name='History',exact=True).click();assert page.evaluate('realFixtureAudio.paused && !realFixtureAudio.getAttribute("src")')
 assert page.evaluate("calls.filter(x=>x.method==='POST'&&x.path.includes('/audio/')).length")==1
 assert ranges and ranges[0]=='bytes=0-';assert not errors
 result={'result':'PASS','audio':'synthetic 3-second silent WAV; real HTMLMediaElement','ranges':ranges,'errors':errors,'checks':['play gesture','pause/resume time','ended/replay','navigation cancels media src','one explicit prepare POST']};(out/'media-result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));b.close()
