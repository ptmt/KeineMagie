"""Full app + real Go list DTO, isolated local fixture account and silent WAV.
Requires TestDictationLocalFixture, DICTATION_FIXTURE_DIR. Never calls audio POST.
"""
import json
import os
import wave
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

repo=Path(__file__).resolve().parents[2]
out=repo/'docs/evidence/dictation-library'
root=Path(os.environ['DICTATION_FIXTURE_DIR'])
info=json.loads((root/'fixture.json').read_text())
errors=[]
with sync_playwright() as p:
    browser=p.chromium.launch()
    context=browser.new_context(viewport={'width':1280,'height':900})
    context.add_cookies([{'name':'__Host-km-session','value':info['browser'],'domain':'localhost','path':'/','secure':True,'httpOnly':True,'sameSite':'Strict'}])
    context.add_init_script("localStorage.setItem('keinemagie:interface-language:v1','ru')")
    page=context.new_page()
    page.on('pageerror',lambda error:errors.append(str(error)))
    calls=[]
    page.on('request',lambda request:calls.append({'method':request.method,'url':request.url}))
    page.goto(info['url']+'/#dictation')
    expect(page.get_by_text('Диктантов пока нет.',exact=True)).to_be_visible()
    page.screenshot(path=str(out/'app-empty-ru.png'),full_page=True)
    source=('Heute scheint die Sonne. Wir gehen gerne in den Park. '*12).strip()
    assert len(source.split())==120
    def create(identifier,title,text):
        response=context.request.post(info['url']+'/v1/learning/dictations',headers={'Origin':info['url'],'X-CSRF-Token':info['csrf']},data={'id':identifier,'title':title,'text':text,'language':'de','playback_policy_version':1})
        assert response.status==200,response.text()
    create('library-one','Prävention gegen Einbrecher',source)
    page.reload()
    card=page.locator('.dictation-card')
    expect(card).to_have_count(1)
    expect(card.locator('small')).to_have_text('120 слов')
    page.set_viewport_size({'width':390,'height':844})
    page.screenshot(path=str(out/'app-one-no-audio-ru-390.png'),full_page=True)
    # Seed only this disposable fixture's storage with a real 95-second silent WAV.
    # No provider config, media fetch, estimation, or paid preparation is involved.
    histories=list((root/'dictations').glob('*/history.json'))
    assert len(histories)==1
    history=histories[0];data=json.loads(history.read_text())
    assert len(data['items'])==1 and data['items'][0]['id']=='library-one'
    asset=history.parent/'library-one'/'0.wav'
    asset.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(asset),'wb') as wav:
        wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(24000)
        wav.writeframes(b'\0\0'*24000*95)
    data['items'][0]['ready']=[0]
    history.write_text(json.dumps(data))
    page.reload()
    expect(card.locator('small')).to_have_text('120 слов · 1:35')
    for count in [1,3]:
        if count==3:
            create('library-two','Ein Spaziergang im Park','Heute scheint die Sonne. Wir gehen in den Park.')
            create('library-three','Ein langes Wochenende in Berlin: Museen, Spaziergänge und neue Entdeckungen',source)
            page.reload();expect(card).to_have_count(3)
        for width in [320,390,1280]:
            page.set_viewport_size({'width':width,'height':900 if width==1280 else 844})
            assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
            expect(page.locator('#dictation>header summary')).to_have_count(0)
            page.screenshot(path=str(out/f'app-{count}-cards-ru-{width}.png'),full_page=True)
    assert not errors,errors
    assert all('/audio/' not in c['url'] for c in calls),'library must not fetch/generate media'
    (out/'app-result.json').write_text(json.dumps({'result':'PASS','real_app':True,'real_go_list_dto':True,'synthetic_words':120,'actual_silent_wav_seconds':95,'library_media_requests':0,'errors':errors},indent=2)+'\n')
    print('PASS: actual app, Go DTO, 120 source words, actual 95-second silent WAV; 0 library media requests')
    browser.close()
