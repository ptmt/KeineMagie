import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import * as core from '../core.mjs';

async function harness() {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  const nodes = new Map();
  for (const tag of html.matchAll(/<[^>]+id="([^"]+)"[^>]*>/g)) {
    const listeners = {};
    nodes.set(tag[1], { hidden: /\shidden(?:\s|>)/.test(tag[0]), value: '', textContent: '', disabled: false, open: false,
      classList: { toggle() {} }, setAttribute() {}, removeAttribute() {}, replaceChildren() {}, append() {},
      addEventListener(type, fn) { listeners[type] = fn; },
      async click() { await listeners.click?.({ preventDefault() {} }); },
      showModal() { this.open = true; }, close() { this.open = false; listeners.close?.(); }
    });
  }
  let signedIn = false;
  let deferConnect;
  const calls = [];
  const fetch = async (path, options) => {
    calls.push({path, options});
    let body = {};
    let status = 200;
    if (path === '/v1/web/config') body = {apple_available:true, pairing_available:true, chatgpt_connect_available:true, csrf_token:'boot-csrf'};
    if (path === '/v1/web/session') { if (signedIn) body = {user:{id:'synthetic-user'},csrf_token:'session-csrf',provider:{connected:false}}; else status = 401; }
    if (path === '/v1/translations') body = {items:[]};
    if (path === '/v1/provider/connect') body = await (deferConnect?.() ?? {bootstrap_token:'SYNTHETIC-ONLY',expires_in:300});
    return {ok:status===200,status,json:async()=>body};
  };
  const app = (await readFile(new URL('../app.mjs', import.meta.url), 'utf8')).replace(/^import .*?;\n/, '');
  vm.runInNewContext(app, {...core, createAPI:()=>core.createAPI(fetch), document:{ getElementById:id=>nodes.get(id), querySelectorAll:()=>[], createElement:()=>({append(){}}) }, window:{addEventListener(){}}, location:{hash:''}, setTimeout:()=>1, clearTimeout(){}, AbortController, console});
  const settle = () => new Promise(resolve=>setImmediate(resolve));
  await settle();
  return {nodes, calls, settle, signIn(value){signedIn=value;}, defer(fn){deferConnect=fn;}};
}

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

test('sign-in artwork is locally served Apple-generated German artwork without an SDK or CSP exception', async () => {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(html, /id="apple-login"[^>]*aria-label="Mit Apple anmelden"/);
  assert.match(html, /<img[^>]*src="\.\/apple-sign-in-de.png"[^>]*alt="Mit Apple anmelden"/);
  assert.match(html, /id="provider-section"[^>]*hidden/);
  assert.match(html, /id="close-account"[^>]*aria-label="[^"]+"[^>]*>.*?aria-hidden="true"/s);
  assert.doesNotMatch(html, //);
  const asset = await readFile(new URL('../apple-sign-in-de.png', import.meta.url));
  assert.equal(asset.subarray(1,4).toString(), 'PNG');
  assert.equal(asset.readUInt32BE(16), 960);
  assert.equal(asset.readUInt32BE(20), 144);
});
