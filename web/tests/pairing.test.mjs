import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createAPI, startBrowserPairing } from '../core.mjs';
test('pairing is CSRF bound and never exposes a native session', async () => {
 const seen=[];const api=createAPI(async(path,options)=>{seen.push({path,options});return {ok:true,status:200,json:async()=>({user_code:'ABCD-EFGH',expires_in:300,interval:3})};});
 const p=await startBrowserPairing(api,'csrf');assert.equal(p.user_code,'ABCD-EFGH');assert.equal(seen[0].path,'/v1/web/pairing/start');assert.equal(seen[0].options.headers['X-CSRF-Token'],'csrf');assert.equal(seen[0].options.credentials,'same-origin');
 const html=await readFile(new URL('../index.html',import.meta.url),'utf8');assert.match(html,/id="pair-browser"/);assert.match(html,/id="pairing-code"/);
});
