import test from 'node:test';import assert from 'node:assert/strict';import {fixture,record,tick} from './dictation-mount-fixture.mjs';
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
test('retained audio attempt explains recovery, blocks repeated preparation, and preserves draft',async()=>{
 const value={...record(),ready:[],draft:'Keep my draft'};
 const f=fixture({request:async(path,o)=>{if(o.method==='POST'&&path.includes('/audio/'))throw Object.assign(Error('private provider prose'),{status:409,code:'speech_recovery_needed'});return path.endsWith('/one')?value:{items:[value]}}});
 await f.start();await f.click('Test one');await f.click('Prepare audio');
 assert.match(f.host.textContent,/needs recovery/);assert.doesNotMatch(f.host.textContent,/private provider prose|Resolve conflict/);
 assert.equal(f.host.querySelector('textarea').value,'Keep my draft');
 assert.equal(f.button('Prepare audio').disabled,true);await f.button('Prepare audio').onclick();assert.equal(f.requests.filter(r=>r.method==='POST').length,1);
 f.controller.identity(null);
});
test('late recovery rejection from previous owner cannot block current owner audio',async()=>{
 let rejectA;const value={...record(),ready:[],draft:'Owner draft'};
 const f=fixture({request:async(path,o)=>{
  if(o.method==='POST'&&path.includes('/audio/')){
   if(o.csrf==='synthetic')return new Promise((resolve,reject)=>{rejectA=reject});
   return {};
  }
  return path.endsWith('/one')?structuredClone(value):{items:[structuredClone(value)]};
 }});
 try{
  await f.start();await f.click('Test one');
  const pending=f.click('Prepare audio');assert.equal(typeof rejectA,'function');
  f.controller.identity({user:{id:'owner-b'},csrf_token:'owner-b'});await tick();await tick();
  rejectA(Object.assign(Error('old owner'),{status:409,code:'speech_recovery_needed'}));await pending;
  await f.click('Test one');
  assert.equal(f.button('Prepare audio').disabled,false,'owner B must remain eligible');
  assert.doesNotMatch(f.host.textContent,/needs recovery/);
  await f.click('Prepare audio');
  assert.equal(f.requests.filter(r=>r.method==='POST'&&r.csrf==='owner-b').length,1,'owner B executes its own preparation');
 }finally{f.controller.identity(null)}
});
