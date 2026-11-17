"""Real local fixture: durable create retry, conflict, and remote deletion."""
import json
import os
import uuid
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

fixture = Path(os.environ.get('DICTATION_FIXTURE_DIR', '/Users/tinyserve/.hermes/cache/scratch/diktat-fixture'))
info = json.loads((fixture / 'fixture.json').read_text())
base = info['url'] + '/v1/learning/dictations'
headers = {'X-CSRF-Token': info['csrf'], 'Origin': info['url']}

with sync_playwright() as playwright:
    browser = playwright.chromium.launch()
    context = browser.new_context()
    context.add_cookies([{'name': '__Host-km-session', 'value': info['browser'], 'domain': 'localhost', 'path': '/', 'secure': True, 'httpOnly': True, 'sameSite': 'Strict'}])
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(info['url'] + '/#dictation')
    title = 'Create retry ' + uuid.uuid4().hex[:8]
    page.locator('#dictation header').get_by_role('button', name='Add text', exact=True).click()
    page.get_by_role('textbox', name='Title', exact=True).fill(title)
    page.get_by_role('textbox', name='Original text', exact=True).fill('   ')
    page.get_by_role('button', name='Save text', exact=True).click()
    expect(page.locator('#dictation [role="status"]')).to_contain_text('Could not save. Retry.')
    expect(page.get_by_role('textbox', name='Title', exact=True)).to_be_enabled()
    expect(page.get_by_role('textbox', name='Title', exact=True)).to_have_value(title)
    page.get_by_role('textbox', name='Original text', exact=True).fill('Heute scheint die Sonne.')
    sent = []
    def lost_ack(route):
        if route.request.method == 'POST' and route.request.url.rstrip('/') == base:
            sent.append(route.request.post_data_json)
            response = route.fetch()
            assert response.status == 200
            route.abort('failed')
        else:
            route.continue_()
    page.route('**/v1/learning/dictations', lost_ack)
    page.get_by_role('button', name='Save text', exact=True).click()
    expect(page.get_by_role('textbox', name='Title', exact=True)).to_be_disabled()
    page.wait_for_function("""() => new Promise(resolve => {const r=indexedDB.open('keinemagie-dictation',1);r.onsuccess=()=>{const q=r.result.transaction('drafts').objectStore('drafts').getAll();q.onsuccess=()=>resolve(q.result.some(v=>v.pendingCreate?.title?.startsWith('Create retry ')));};})""")
    expect(page.locator('#dictation [role="status"]')).to_contain_text('Could not save. Retry.')
    page.unroute('**/v1/learning/dictations', lost_ack)
    page.reload()
    page.locator('#dictation header').get_by_role('button', name='Add text', exact=True).click()
    expect(page.get_by_role('textbox', name='Title', exact=True)).to_have_value(title)
    expect(page.get_by_role('textbox', name='Title', exact=True)).to_be_disabled()
    page.get_by_role('button', name='Save text', exact=True).click()
    expect(page.get_by_role('textbox', name='What you heard', exact=True)).to_be_visible()
    assert len(sent) == 1
    listed = context.request.get(base).json()['items']
    matching = [item for item in listed if item['title'] == title]
    assert len(matching) == 1
    item = matching[0]
    assert sent[0] == {**{key: item[key] for key in ('id', 'title', 'language')}, 'text': 'Heute scheint die Sonne.'}

    # A second client advances the revision; the local draft remains visible for resolution.
    remote = context.request.put(base + '/' + item['id'], headers=headers, data={'mode':'whole','step':0,'replays':0,'draft':'remote version','revision':item['revision'],'mutation_id':str(uuid.uuid4())})
    assert remote.status == 200
    draft = page.get_by_role('textbox', name='What you heard', exact=True)
    draft.fill('local version')
    expect(page.get_by_text('Resolve conflict', exact=True)).to_be_visible()
    expect(draft).to_have_value('local version')
    latest = context.request.get(base + '/' + item['id']).json()
    deleted = context.request.delete(base + '/' + item['id'], headers=headers, data={'revision':latest['revision']})
    assert deleted.status == 200
    draft.fill('recover after delete')
    expect(page.get_by_role('button', name='Export draft', exact=True)).to_be_visible()
    assert not errors, errors
    print('PASS durable create, conflict, remote deletion')
    browser.close()
