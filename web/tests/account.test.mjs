import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import * as core from '../core.mjs';
import * as episode from '../episode.mjs';
import * as i18n from '../i18n.mjs';
import { createEpisodeView } from '../episode-view.mjs';
import { mountTranslatorFollowup } from '../translator-followup.mjs';
import { mountCoach } from '../coach.mjs';

export async function harness({deferSession, deferHistory, deferProvider, config: configOverride, leanSession = false, deferTranslation} = {}) {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  const nodes = new Map();
  for (const tag of html.matchAll(/<[^>]+id="([^"]+)"[^>]*>/g)) {
    const listeners = {};
    nodes.set(tag[1], { dataset:{}, hidden: /\shidden(?:\s|>)/.test(tag[0]), value: '', textContent: '', disabled: false, open: false, children: [],
      classList: { toggle() {} }, getAttribute(){return null;}, setAttribute() {}, removeAttribute() {}, replaceChildren() { this.children = []; }, append(...children) { this.children.push(...children); }, focus() {},
      addEventListener(type, fn) { listeners[type] = fn; },
      async dispatch(type) { await listeners[type]?.({ preventDefault() {} }); },
      async click() { await listeners.click?.({ preventDefault() {} }); },
      showModal() { this.open = true; }, close() { this.open = false; listeners.close?.(); }
    });
  }
  let signedIn = false;
  let userID = 'synthetic-user';
  const data = new Map();
  const storage = {getItem:key=>data.get(key) ?? null, setItem:(key,value)=>data.set(key,value)};
  let provider = {connected:false,status:'not_connected'};
  let items = [];
  let deferConnect;
  let providerHTTPStatus = 200;
  const calls = [];
  const fetch = async (path, options) => {
    calls.push({path, options});
    let body = {};
    let status = 200;
    if (path === '/v1/web/config') body = configOverride ?? {apple_available:true, pairing_available:true, chatgpt_connect_available:true, csrf_token:'boot-csrf'};
    if (path === '/v1/web/session') { await deferSession?.(); if (signedIn) body = {user:{id:userID},csrf_token:'session-csrf',...(leanSession ? {} : {provider})}; else status = 401; }
    if (path === '/v1/web/logout') { signedIn = false; status = 204; }
    if (path === '/v1/translations') { await deferHistory?.(); body = {items}; }
    if (path === '/v1/translations' && options.method === 'POST' && deferTranslation) body = await deferTranslation();
    if (path === '/v1/provider') { await deferProvider?.(); body = provider; status = providerHTTPStatus; }
    if (path === '/v1/podcasts/subscriptions') body = {items:[{id:'Feed_A',title:'Private podcast',episodes:[]}]};
    if (path === '/v1/podcasts') body = {items:[],worker_available:true};
    if (path === '/v1/provider/connect') body = await (deferConnect?.() ?? {bootstrap_token:'SYNTHETIC-ONLY',expires_in:300});
    return {ok:status===200,status,json:async()=>body};
  };
  const app = (await readFile(new URL('../app.mjs', import.meta.url), 'utf8')).replace(/^import .*?;\n/gm, '');
  const links = [...html.matchAll(/<a href="#(translator|dictation|podcasts|coach)"[^>]*>([^<]+)<\/a>/g)].map(([,id,textContent]) => ({hash:`#${id}`,textContent,setAttribute(){},removeAttribute(){}}));
  const createElement = () => {
    const listeners = {};
    return { querySelectorAll(){return [];}, hasAttribute(){return false;}, classList:{toggle(){}}, dataset:{}, attributes:[], childNodes:[], children: [], replaceChildren(){this.children=[];},getAttribute(){return null;},removeAttribute(){},append(...children) { this.children.push(...children); }, setAttribute() {}, addEventListener(type, fn) { listeners[type] = fn; }, async click() { await listeners.click?.(); } };
  };
  const events = {}, location = {hash:'#podcasts'};
  const document = {hidden:false, addEventListener(type,fn){events[type]=fn;}, getElementById:id=>nodes.get(id), querySelectorAll:selector=>selector==='.section-nav a'?links:[], createElement};
  i18n.setInterfaceLanguage('de');
  vm.runInNewContext(app, {...core, ...episode, ...i18n, reconcileDOM(target,next){target.children=next.children;}, registerStaticInterface(){}, createEpisodeView:options=>createEpisodeView({...options,document}), mountCoach:options=>mountCoach({...options,document}), mountTranslatorFollowup:options=>mountTranslatorFollowup({...options,document}), createAPI:()=>core.createAPI(fetch), document, window:{addEventListener(type,fn){events[type]=fn;}, localStorage:storage}, crypto:{randomUUID:()=> 'fixture-id'}, location, setTimeout:()=>1, clearTimeout(){}, AbortController, AbortSignal, console});
  const settle = () => new Promise(resolve=>setImmediate(resolve));
  await settle();
  return {nodes, calls, settle, storage, events, document, location, signIn(value, id=userID){signedIn=value;userID=id;}, provider(value, status=200){provider=value;providerHTTPStatus=status;}, history(value){items=value;}, defer(fn){deferConnect=fn;}};
}

test('validated identity opens podcasts while history and provider discovery remain pending', async () => {
 let hold=false, releaseHistory, releaseProvider;
 const h=await harness({leanSession:true,deferHistory:()=>hold?new Promise(r=>releaseHistory=r):undefined,deferProvider:()=>hold?new Promise(r=>releaseProvider=r):undefined});
 h.signIn(true);hold=true;
 const pending=h.nodes.get('retry-session').click();await h.settle();
 assert.ok(h.calls.some(c=>c.path==='/v1/podcasts/subscriptions'));
 assert.notEqual(h.nodes.get('podcast-notice').textContent,'Sitzung wird geprüft …');
 assert.ok(h.nodes.get('podcast-content').children.length);
 assert.equal(h.calls.some(c=>c.path==='/v1/provider'),true); // explicit recheck, unlike passive library opening
 await h.nodes.get('account').click();await h.settle();
 assert.ok(h.calls.some(c=>c.path==='/v1/provider'));
 assert.notEqual(h.nodes.get('podcast-notice').textContent,'Sitzung wird geprüft …');
 hold=false;releaseHistory?.();releaseProvider?.();await pending;
});

test('lean identity keeps unknown provider loading and explicit recheck fetches provider on podcasts', async () => {
 const h=await harness({leanSession:true});const el=id=>h.nodes.get(id);
 h.signIn(true);h.provider({connected:true,status:'connected',selected_model:'fixture-model'});
 await el('retry-session').click();await h.settle();
 assert.ok(h.calls.some(c=>c.path==='/v1/provider'));
 assert.equal(el('provider-status').textContent,'Verbunden');
 h.provider({connected:false,status:'reauthorization_required'});
 await el('retry-session').click();await h.settle();
 assert.equal(el('provider-status').textContent,'Nicht verbunden');
});

test('delayed real provider contract never presents unverified identity as disconnected', async () => {
 let release;const h=await harness({leanSession:true,deferProvider:()=>new Promise(r=>release=r)});const el=id=>h.nodes.get(id);
 h.signIn(true);h.provider({connected:true,status:'connected',selected_model:'fixture-model'});
 const pending=el('retry-session').click();await h.settle();await el('account').click();await h.settle();
 assert.equal(el('provider-status').textContent,'Verbindung wird geprüft …');
 assert.doesNotMatch(el('connection-title').textContent,/verbinden/);
 assert.equal(el('provider-connect').disabled,true);
 release();await pending;await h.settle();assert.equal(el('provider-status').textContent,'Verbunden');
});

test('provider transport failure is unknown, retry recovers, and true HTTP 401 clears identity', async () => {
 const h=await harness({leanSession:true});const el=id=>h.nodes.get(id);
 h.signIn(true);h.provider({},503);await el('retry-session').click();
 assert.equal(el('provider-status').textContent,'Verbindung konnte nicht geprüft werden');
 assert.equal(el('provider-section').hidden,false);assert.equal(el('provider-connect').disabled,true);
 assert.match(el('connection-title').textContent,/konnte nicht geprüft/);
 h.provider({connected:true,status:'connected',selected_model:'offered-model'});await el('connection-action').click();
 assert.equal(el('provider-status').textContent,'Verbunden');
 h.provider({},401);await el('retry-session').click();assert.equal(el('provider-section').hidden,true);
 assert.equal(el('podcast-content').children.length,0);
});

test('fresh focus and hash navigation reuse validated identity; concurrent refresh keeps podcasts visible', async () => {
 let hold=false,release;
 const h=await harness({deferSession:()=>hold?new Promise(r=>release=r):undefined});
 h.signIn(true);await h.nodes.get('retry-session').click();await h.settle();
 const before=h.calls.filter(c=>c.path==='/v1/web/session').length;
 h.location.hash='#translator';h.events.hashchange();h.location.hash='#podcasts';h.events.hashchange();
 h.document.hidden=true;h.events.visibilitychange();h.document.hidden=false;h.events.visibilitychange();h.events.online();await h.settle();
 assert.equal(h.calls.filter(c=>c.path==='/v1/web/session').length,before);
 hold=true;const pending=h.nodes.get('retry-session').click();const joined=h.nodes.get('retry-session').click();await h.settle();
 assert.equal(h.calls.filter(c=>c.path==='/v1/web/session').length,before+1);
 assert.ok(h.nodes.get('podcast-content').children.length);
 assert.match(h.nodes.get('podcast-notice').textContent,/Hintergrund/);
 h.signIn(false);hold=false;release();await Promise.all([pending,joined]);await h.settle();
 assert.equal(h.nodes.get('podcast-content').children.length,0);
 assert.equal(h.nodes.get('source-text').value,'');
});

test('guest and unresolved sessions disable translator controls and reject synthetic events', async () => {
 let release;const h=await harness({deferSession:()=>new Promise(resolve=>{release=resolve;})});const el=id=>h.nodes.get(id);
 for(const id of ['source-text','language-direction','swap','translate','add-prompt','clear']) assert.equal(el(id).disabled,true,id);
 assert.equal(el('connection-title').textContent,'Sitzung wird geprüft …');
 await el('add-prompt').click();assert.equal(el('prompt-dialog').open,false);
 release();await h.settle();
 assert.equal(el('connection-title').textContent,'Melde dich an, um zu übersetzen.');
 assert.equal(el('style-controls').hidden,false);
 assert.ok(el('style-chips').children.length>=3);
 for(const chip of el('style-chips').children) assert.equal(chip.disabled,true);
 el('source-text').value='Synthetic guest draft';el('language-direction').value='de-ru';
 await el('swap').click();assert.equal(el('language-direction').value,'de-ru');
 await el('clear').click();assert.equal(el('source-text').value,'Synthetic guest draft');
 await el('style-chips').children[1].click();await el('add-prompt').click();
 assert.equal(el('prompt-dialog').open,false);
 el('prompt-name').value='Guest';el('prompt-instructions').value='Do not save';await el('prompt-form').dispatch('submit');
 assert.equal(h.storage.getItem('keinemagie:translation-prompts:v1:synthetic-user'),null);
 await el('translation-form').dispatch('submit');
 assert.equal(h.calls.some(c=>c.path==='/v1/translations'&&c.options.method==='POST'),false);
 assert.equal(el('provider-section').hidden,true);
 await el('connection-action').click();assert.equal(el('account-dialog').open,true);
});

test('rechecking preserves only same-account drafts, blocks stale handlers and logout clears private text', async () => {
 let wait=false,release;const h=await harness({deferSession:()=>wait ? new Promise(resolve=>{release=resolve;}) : undefined});const el=id=>h.nodes.get(id);
 h.signIn(true,'owner-A');h.provider({connected:true,status:'connected',selected_model:'fixture-model'});await el('retry-session').click();
 el('source-text').value='Private draft';await el('source-text').dispatch('input');
 const oldChip=el('style-chips').children[1];await oldChip.click();
 await el('add-prompt').click();el('prompt-name').value='Unsaved';
 wait=true;const pending=el('retry-session').click();await h.settle();
 assert.equal(el('source-text').disabled,false);assert.equal(el('translate').disabled,false);assert.equal(el('prompt-dialog').open,true);
 assert.equal(el('prompt-name').value,'Unsaved');
 wait=false;release();await pending;
 assert.equal(el('source-text').value,'Private draft');assert.equal(el('source-text').disabled,false);assert.equal(el('translate').disabled,false);
 h.signIn(true,'owner-B');await el('retry-session').click();assert.equal(el('source-text').value,'');
 await oldChip.click();assert.equal(el('style-chips').children[0].textContent,'Standard');
 el('source-text').value='Account B private';await el('source-text').dispatch('input');await el('logout').click();
 assert.equal(el('source-text').value,'');assert.equal(el('source-text').disabled,true);assert.equal(el('history-list').children.length,0);
 h.signIn(true,'owner-B');await el('retry-session').click();assert.equal(el('source-text').value,'');
});

test('late history cannot erase accepted results after the draft is edited', async () => {
  let hold=false,release;const h=await harness({deferHistory:()=>hold?new Promise(resolve=>{release=resolve;}):undefined,deferTranslation:()=>({id:'accepted',text:'saved',translation:'result',source_language:'ru',target_language:'de',idioms:[],patterns:[],vocabulary:[]})});const el=id=>h.nodes.get(id);
  h.signIn(true);await el('retry-session').click();hold=true;const pending=el('refresh-history').click();await h.settle();hold=false;
  el('language-direction').value='ru-de';el('source-text').value='saved';await el('translation-form').dispatch('submit');
  el('source-text').value='new draft';await el('source-text').dispatch('input');
  release();await pending;assert.equal(el('history-list').children.length,1);assert.equal(el('source-text').value,'new draft');
});

test('late old-owner POST cannot unlock or cancel the new owner attempt', async () => {
  const held=[];const h=await harness({deferTranslation:()=>new Promise(resolve=>held.push(resolve))});const el=id=>h.nodes.get(id);
  const result=text=>({id:text,text,translation:text,source_language:'ru',target_language:'de',idioms:[],patterns:[],vocabulary:[]});
  h.signIn(true,'owner-A');await el('retry-session').click();el('language-direction').value='ru-de';el('source-text').value='A';
  const first=el('translation-form').dispatch('submit');await h.settle();
  await el('logout').click();h.signIn(true,'owner-B');await el('retry-session').click();el('source-text').value='B';
  const second=el('translation-form').dispatch('submit');await h.settle();
  held[0](result('A'));await first;
  assert.equal(el('translate').disabled,true);assert.equal(el('cancel').hidden,false);assert.equal(el('source-text').value,'B');
  await el('translation-form').dispatch('submit');assert.equal(held.length,2);
  const call=h.calls.filter(c=>c.path==='/v1/translations'&&c.options.method==='POST').at(-1);
  await el('cancel').click();assert.equal(call.options.signal.aborted,true);
  held[1](result('B'));await second;assert.equal(el('result').textContent,'B');
});

test('detached history handlers cannot restore another account’s private text', async () => {
 const h=await harness();const el=id=>h.nodes.get(id);
 h.signIn(true,'owner-A');h.history([{id:'a',text:'Private A',translation:'Private result A',source_language:'de',target_language:'ru',idioms:[],patterns:[],vocabulary:[]}]);
 await el('retry-session').click();await h.settle();const stale=el('history-list').children[0].children[0];
 h.signIn(true,'owner-B');h.history([]);await el('retry-session').click();
 await stale.click();assert.equal(el('source-text').value,'');assert.equal(el('copy').disabled,true);
});

test('history restores the exact style snapshot even after a shortcut was edited or removed', async () => {
 const h=await harness();const el=id=>h.nodes.get(id);
 h.signIn(true);h.history([{id:'old',text:'Hallo',translation:'Привет',source_language:'de',target_language:'ru',instructions:'A historical style.',idioms:[],patterns:[],vocabulary:[]}]);
 await el('retry-session').click();await h.settle();await el('history-list').children[0].children[0].click();
 assert.ok(el('style-chips').children.some(x=>x.textContent==='Aus Verlauf'));
});

test('shortcut UI persists edits, clears private account UI and restores only matching owner', async () => {
 const h=await harness();const el=id=>h.nodes.get(id);
 h.signIn(true,'owner-A');await el('retry-session').click();
 assert.equal(el('style-controls').hidden,false);
 await el('add-prompt').click();
 el('prompt-name').value='Brief';el('prompt-instructions').value='Kurz und freundlich.';
 await el('prompt-form').dispatch('submit');
 assert.equal(el('prompt-dialog').open,false);
 assert.equal(el('style-chips').children.at(-1).textContent,'Brief');
 await el('edit-prompt').click();assert.equal(el('prompt-instructions').value,'Kurz und freundlich.');
 el('prompt-name').value='E-Mail';await el('prompt-form').dispatch('submit');
 assert.equal(el('style-chips').children.at(-1).textContent,'E-Mail');
 await el('edit-prompt').click();
 h.signIn(true,'owner-B');await el('retry-session').click();
 assert.equal(el('prompt-dialog').open,false);assert.equal(el('prompt-instructions').value,'');
 assert.equal(el('style-chips').children.some(x=>x.textContent==='E-Mail'),false);
 h.signIn(true,'owner-A');await el('retry-session').click();
 const restored=el('style-chips').children.find(x=>x.textContent==='E-Mail');assert.ok(restored);await restored.click();
 await el('edit-prompt').click();await el('delete-prompt').click();
 assert.deepEqual(core.promptStore(h.storage,'owner-A').list(),[]);
 h.signIn(false);await el('retry-session').click();assert.equal(el('style-controls').hidden,false);assert.ok(el('style-chips').children.every(chip=>chip.disabled));
});

test('guest dialog exposes only sign-in and secondary pairing; authenticated account resets on expiry', async () => {
  const h = await harness(); const el = id => h.nodes.get(id);
  assert.equal(el('account-title').textContent, 'Anmelden');
  assert.equal(el('provider-section').hidden, true);
  assert.equal(el('signed-in-account').hidden, true);
  assert.equal(el('retry-session').hidden, true);
  assert.equal(el('sign-in-options').hidden, false);
  assert.equal(el('apple-login').hidden, false);
  assert.equal(el('provider-detail').textContent, '');
  assert.doesNotMatch(el('connection-detail').textContent, /ChatGPT/);
  h.signIn(true); await el('retry-session').click();
  assert.equal(el('account-title').textContent, 'Dein Konto');
  assert.equal(el('provider-section').hidden, false);
  assert.equal(el('sign-in-options').hidden, true);
  await el('account').click(); await el('provider-connect').click();
  assert.equal(el('bootstrap-code').value, 'SYNTHETIC-ONLY');
  assert.equal(el('provider-bootstrap').hidden, false);
  h.signIn(false); await el('retry-session').click();
  assert.equal(el('provider-section').hidden, true);
  assert.equal(el('bootstrap-code').value, '');
  assert.equal(el('provider-detail').textContent, '');
  assert.equal(el('provider-bootstrap').hidden, true);
});

test('late provider bootstrap cannot repopulate a closed and reopened dialog', async () => {
  const h = await harness(); const el = id => h.nodes.get(id);
  h.signIn(true); await el('retry-session').click(); await el('account').click();
  let resolve; h.defer(()=>new Promise(done=>{resolve=done;}));
  const pending = el('provider-connect').click(); await h.settle();
  await el('close-account').click(); await el('account').click();
  resolve({bootstrap_token:'STALE-SYNTHETIC',expires_in:300}); await pending;
  assert.equal(el('bootstrap-code').value, '');
  assert.equal(el('provider-bootstrap').hidden, true);
});

test('catalog unavailable stays advisory, permits server-authorized submits and preserves history', async () => {
  const h = await harness(); const el = id => h.nodes.get(id);
  const provider = { connected: true, status: 'catalog_unavailable', message: 'ChatGPT connection saved; model catalog unavailable. Check the connection again.', models: [], selected_model: '' };
  const saved = { id: 'saved-fixture', created_at: '2026-01-01T12:00:00Z', text: 'Hallo', source_language: 'de', target_language: 'ru', translation: 'Test-only saved translation', idioms: [], patterns: [], vocabulary: [] };
  h.signIn(true); h.provider(provider); h.history([saved]);
  await el('retry-session').click();
  el('language-direction').value = 'ru-de';
  el('source-text').value = 'New draft'; await el('source-text').dispatch('input');
  assert.equal(el('translate').disabled, false);
  await el('translation-form').dispatch('submit');
  assert.equal(h.calls.some(c => c.path === '/v1/translations' && c.options.method === 'POST'), true);
  assert.equal(el('provider-status').textContent, 'Verbunden · Modell nicht verfügbar');
  assert.match(el('provider-detail').textContent, /verbunden.*Modellkatalog.*nicht verfügbar/s);
  assert.equal(el('connection-notice').hidden, false);
  assert.equal(el('connection-title').textContent, 'ChatGPT verbunden · Modell nicht verfügbar.');
  assert.match(el('connection-detail').textContent, /erneut prüfen/i);
  assert.doesNotMatch(el('connection-title').textContent + el('connection-detail').textContent, /neu verbinden|trennen/i);
  assert.equal(el('connection-action-label').textContent, 'Erneut prüfen');
  assert.equal(el('provider-connect').disabled, true);
  assert.equal(el('provider-bootstrap').hidden, true);
  assert.equal(el('refresh-history').disabled, false);
  assert.equal(el('history-list').children.length, 1);
  await el('history-list').children[0].children[0].click();
  assert.equal(el('result').textContent, saved.translation);
  assert.equal(el('copy').disabled, false);
  assert.equal(el('translate').disabled, false);
  await el('refresh-history').click();
  assert.equal(el('history-list').children.length, 1);
  h.provider({ connected: true, status: 'connected', message: 'ChatGPT connected', models: [{ slug: 'offered-model', display_name: 'Offered model' }], selected_model: 'offered-model' });
  await el('connection-action').click();
  assert.equal(el('connection-notice').hidden, true);
  assert.equal(el('translate').disabled, false);
  assert.equal(el('result').textContent, saved.translation);
  assert.equal(el('history-list').children.length, 1);
  assert.equal(h.calls.some(c => /\/v1\/provider\/(connect|disconnect)$/.test(c.path)), false);
});

test('sign-in artwork is locally served Apple-generated German artwork without an SDK or CSP exception', async () => {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(html, /id="apple-login"[^>]*aria-label="Mit Apple anmelden"/);
  assert.match(html, /<img[^>]*src="(?:\.\/|\/)apple-sign-in-de.png"[^>]*alt="Mit Apple anmelden"/);
  assert.match(html, /id="provider-section"[^>]*hidden/);
  assert.match(html, /id="close-account"[^>]*aria-label="[^"]+"[^>]*>.*?aria-hidden="true"/s);
  assert.doesNotMatch(html, //);
  const asset = await readFile(new URL('../apple-sign-in-de.png', import.meta.url));
  assert.equal(asset.subarray(1,4).toString(), 'PNG');
  assert.equal(asset.readUInt32BE(16), 960);
  assert.equal(asset.readUInt32BE(20), 144);
});
