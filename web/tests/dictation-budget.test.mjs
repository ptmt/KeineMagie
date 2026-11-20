import test from 'node:test';import assert from 'node:assert/strict';import {fixture,record} from './dictation-mount-fixture.mjs';
test('busy audio engine is not mislabeled as exhausted budget',async()=>{
 const value={...record(),ready:[]};const f=fixture({request:async(path,o)=>{if(o.method==='POST')throw Object.assign(Error('busy'),{status:429,code:'speech_engine_busy'});return path.endsWith('/one')?value:{items:[value]}}});
 await f.start();await f.click('Test one');await f.click('Prepare audio');assert.match(f.host.textContent,/Audio preparation is busy/);assert.doesNotMatch(f.host.textContent,/Audio limit reached/);f.controller.identity(null);
});
test('audio application limit is not disguised as preparation failure or auto retried',async()=>{
 const value={...record(),ready:[],draft:'Keep my draft'};
 const f=fixture({request:async(path,o)=>{if(o.method==='POST'&&path.includes('/audio/'))throw Object.assign(Error('limit'),{status:429,code:'speech_budget_exhausted'});return path.endsWith('/one')?value:{items:[value]}}});
 await f.start();await f.click('Test one');await f.click('Prepare audio');
 assert.match(f.host.textContent,/Audio limit reached/);assert.doesNotMatch(f.host.textContent,/Audio preparation failed/);
 assert.equal(f.requests.filter(r=>r.method==='POST').length,1);assert.equal(f.host.querySelector('textarea').value,'Keep my draft');f.controller.identity(null);
});
