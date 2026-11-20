import test from 'node:test';import assert from 'node:assert/strict';import {fixture} from './dictation-mount-fixture.mjs';
test('temporary footer shows owner-attributed reported speech cost, not reserved dollars',async()=>{
 const f=fixture({request:async()=>({items:[],speech_spend:{month:'2026-11',currency:'USD',scope:'owner_attributed_speech_receipts',reported_micro_usd:40404,reserved_micro_usd:10000000,unsettled_reservations:1}})});
 await f.start();assert.match(f.host.textContent,/Monthly audio: \$0\.040404/);assert.match(f.host.textContent,/1 unsettled/);assert.doesNotMatch(f.host.textContent,/\$10\.00/);f.controller.identity(null);assert.doesNotMatch(f.host.textContent,/0\.040404/);
});
