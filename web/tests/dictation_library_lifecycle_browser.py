"""Real app + Go store lifecycle; isolated fixture only, zero AI/media requests."""
import json
import os
import wave
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

repo = Path(__file__).resolve().parents[2]
out = repo/'docs/evidence/dictation-card-lifecycle'
out.mkdir(parents=True, exist_ok=True)
root = Path(os.environ['DICTATION_FIXTURE_DIR'])
info = json.loads((root/'fixture.json').read_text())
stages = ['added', 'ready', 'started', 'completed']
titles = ['Ein Spaziergang im Park', 'Prävention gegen Einbrecher', 'Ein Wochenende in Berlin', 'Neue Wörter im Alltag']
errors, calls, results = [], [], []
with sync_playwright() as p:
    browser = p.chromium.launch()
    context = browser.new_context(viewport={'width':1280,'height':1000}, reduced_motion='reduce')
    context.add_cookies([{'name':'__Host-km-session','value':info['browser'],'domain':'localhost','path':'/','secure':True,'httpOnly':True,'sameSite':'Strict'}])
    headers = {'Origin':info['url'], 'X-CSRF-Token':info['csrf']}
    def api(method, path='', data=None):
        response = context.request.fetch(info['url']+'/v1/learning/dictations'+path,method=method,headers=headers,data=data)
        assert response.status == 200, response.text()
        return response.json()
    # A rerun uses the same disposable IDs. Create/read is idempotent.
    for stage, title in zip(stages, titles):
        api('POST',data={'id':'lifecycle-'+stage,'title':title,'text':'Heute scheint die Sonne. Wir gehen in den Park.','language':'de','playback_policy_version':1})
    history = next((root/'dictations').glob('*/history.json'))
    data = json.loads(history.read_text())
    for item in data['items']:
        if item['id']=='lifecycle-ready':
            asset=history.parent/item['id']/'0.wav'
            asset.parent.mkdir(exist_ok=True)
            with wave.open(str(asset),'wb') as wav:
                wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(24000);wav.writeframes(b'\0\0'*24000*8)
            item['ready']=[0]
    history.write_text(json.dumps(data))
    for stage in ['started','completed']:
        item=api('GET','/lifecycle-'+stage)
        if not item['checked']:
            item=api('PUT','/lifecycle-'+stage,{'revision':item['revision'],'mode':'whole','step':0,'replays':0,'draft':'Eine falsche Antwort Ω'})
            if stage=='completed':api('POST','/lifecycle-'+stage+'/check',{'revision':item['revision']})
    snapshot=history.read_bytes()
    listed=api('GET')['items']
    assert {v['id']:v['lifecycle_stage'] for v in listed}=={'lifecycle-'+s:s for s in stages}
    assert all(not v.get('text') and not v.get('draft') and not v.get('differences') for v in listed)
    page=context.new_page()
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('request',lambda r:calls.append({'method':r.method,'url':r.url}))
    page.goto(info['url']+'/#dictation')
    for locale in ['ru','en','de','es','fr']:
        page.evaluate("locale=>localStorage.setItem('keinemagie:interface-language:v1',locale)",locale)
        page.reload()
        cards=page.locator('.dictation-card')
        expect(cards).to_have_count(4)
        labels=page.evaluate("async locale=>{const {dt}=await import('/dictation-i18n.mjs');return ['added','ready','started','completed'].map(s=>dt(locale,'dictation.lifecycle.'+s))}",locale)
        for scheme in ['light','dark']:
            page.emulate_media(color_scheme=scheme)
            for width in [320,390,1280]:
                page.set_viewport_size({'width':width,'height':1000 if width==1280 else 844})
                assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
                for card in cards.all():
                    expect(card.locator('.dictation-milestone')).to_have_text(labels)
                    expect(card.locator('[aria-current=step]')).to_have_count(1)
                    expect(card.locator('button,a,input')).to_have_count(0)
                metrics=page.locator('.dictation-milestone').evaluate_all('''elements=>elements.map(e=>{
                    const s=getComputedStyle(e),card=e.closest('.dictation-card'), cs=getComputedStyle(card);
                    const rgb=x=>(x.match(/[\\d.]+/g)||[]).slice(0,3).map(Number);
                    const lum=c=>rgb(c).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4}).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0);
                    const bg=s.backgroundColor==='rgba(0, 0, 0, 0)'?cs.backgroundColor:s.backgroundColor;
                    const a=lum(s.color),b=lum(bg),r=e.getBoundingClientRect(),cr=card.getBoundingClientRect();
                    return {color:s.color,contrast:(Math.max(a,b)+.05)/(Math.min(a,b)+.05),size:parseFloat(s.fontSize),weight:parseFloat(s.fontWeight),active:e.hasAttribute('aria-current'),inside:r.left>=cr.left&&r.right<=cr.right};
                })''')
                assert all(m['size']>=14 and m['contrast']>=4.5 and m['inside'] for m in metrics),metrics
                active=[m for m in metrics if m['active']]
                assert all(m['weight']>=600 for m in active),active
                assert len({m['color'] for m in active})==4,active
                # Lifecycle adds no keyboard stops; whole card remains the action.
                cards.first.focus();page.keyboard.press('Tab');expect(cards.nth(1)).to_be_focused()
                cards.nth(1).evaluate('e=>e.blur()')
                if locale=='ru':page.screenshot(path=str(out/f'app-ru-{scheme}-{width}.png'),full_page=True)
                results.append({'locale':locale,'scheme':scheme,'width':width,'minimum_contrast':min(m['contrast'] for m in metrics)})
    assert snapshot==history.read_bytes(),'presentation wrote attempt/ledger state'
    # A new attempt retains cached audio, not its parent's progress. Then remote
    # edits/check/deletion become visible on a real library refresh.
    extra='lifecycle-refresh-'+os.urandom(6).hex()
    api('POST','/lifecycle-ready/attempts',{'id':extra,'playback_policy_version':1})
    def refreshed(stage):
        listed=api('GET')['items']
        assert next(v for v in listed if v['id']==extra)['lifecycle_stage']==stage
        page.reload();expect(cards).to_have_count(5)
        expect(cards.first.locator('[aria-current=step]')).to_have_class('dictation-milestone is-current stage-'+stage)
    refreshed('ready')
    api('PUT','/'+extra,{'revision':0,'mode':'sentences','step':1,'replays':0,'draft':' '})
    refreshed('added')
    api('PUT','/'+extra,{'revision':1,'mode':'sentences','step':1,'replays':0,'draft':'Remote draft'})
    refreshed('started')
    api('POST','/'+extra+'/check',{'revision':2})
    refreshed('completed')
    api('DELETE','/'+extra,{'revision':3})
    assert not any(v['id']==extra for v in api('GET')['items'])
    page.reload();expect(cards).to_have_count(4)
    assert not errors,errors
    assert not any('/audio/' in c['url'] or c['method']!='GET' and '/v1/' in c['url'] for c in calls),calls
    result={'result':'PASS','real_app':True,'real_go_dto':True,'cases':results,'library_media_requests':0,'library_mutations':0,'errors':errors}
    (out/'browser-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result))
    browser.close()
