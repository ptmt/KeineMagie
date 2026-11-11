"""HTTP guest layout/contrast snapshots and measured local critical path."""
from pathlib import Path
from typing import Any
from playwright.sync_api import sync_playwright
import json,time
fixture=Path(__file__).with_name('episode_browser.py');ns:dict[str,Any]={'__file__':str(fixture)}
exec(compile(fixture.read_text().split('try:\n with sync_playwright()')[0],str(fixture),'exec'),ns)
ns['SIGNED']=False
out=Path('/Users/tinyserve/.hermes/cache/scratch/keinemagie-redesign');out.mkdir(exist_ok=True);results=[]
try:
 with sync_playwright() as p:
  browser=p.chromium.launch()
  for mode in ['light','dark']:
   for width in [320,390,768,1440]:
    page=browser.new_page(locale='ru-RU',viewport={'width':width,'height':844},color_scheme=mode)
    start=time.monotonic();page.goto(ns['origin']);page.wait_for_function("!document.querySelector('#connection-action').hidden")
    ready=round((time.monotonic()-start)*1000,1)
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    assert page.locator('#translate').bounding_box()['y']+44<844
    assert page.locator('#connection-action').bounding_box()['y']<page.locator('#source-text').bounding_box()['y']
    metrics=page.evaluate('''() => {
     const rgb=s=>s.match(/[\\d.]+/g).slice(0,3).map(Number);
     const lum=s=>rgb(s).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4}).reduce((n,v,i)=>n+v*[.2126,.7152,.0722][i],0);
     const ratio=(a,b)=>(Math.max(lum(a),lum(b))+.05)/(Math.min(lum(a),lum(b))+.05);
     const root=getComputedStyle(document.documentElement),button=getComputedStyle(document.querySelector('#translate'));
     return {disabledContrast:ratio(button.color,button.backgroundColor),textContrast:ratio(root.color,root.backgroundColor),buttonHeight:document.querySelector('#translate').getBoundingClientRect().height,sessionStart:performance.getEntriesByType('resource').find(e=>e.name.endsWith('/v1/web/session')).startTime,firstPaint:performance.getEntriesByType('paint').map(e=>({name:e.name,start:e.startTime}))};
    }''')
    assert metrics['disabledContrast']>=4.5,metrics
    assert metrics['textContrast']>=4.5 and metrics['buttonHeight']>=44
    path=out/f'guest-{mode}-{width}.png';page.screenshot(path=str(path));results.append({'mode':mode,'width':width,'ready_ms':ready,**metrics,'screenshot':str(path)});page.close()
  browser.close()
 (out/'measurements.json').write_text(json.dumps(results,indent=2));print(json.dumps(results))
finally:ns['server'].shutdown()
