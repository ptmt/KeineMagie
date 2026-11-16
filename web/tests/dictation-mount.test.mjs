import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture,record,tick} from './dictation-mount-fixture.mjs';

test('malformed history reports an error without poisoning subsequent rendering',async()=>{
 const f=fixture({request:async()=>({items:null})});
 await f.start();
 assert.match(f.host.textContent,/Could not save\. Retry\./);
 assert.doesNotThrow(()=>f.controller.localize());
 f.controller.identity(null);
});

test('local draft hydration is visibly loading before history can start',async()=>{
 const f=fixture({request:async()=>({items:[]})});f.controller.identity(f.session);
 assert.match(f.host.textContent,/Loading…/);await tick();await tick();f.controller.identity(null);
});

test('empty history renders after loading settles',async()=>{
 const f=fixture({request:async()=>({items:[]})});await f.start();
 assert.match(f.host.textContent,/No dictations yet\./);f.controller.identity(null);
});

test('failed hydration stays closed and cannot overwrite an unread durable journal',async()=>{
 const f=fixture({readError:true,request:async(path,options)=>options.method==='POST'?record('new'):{items:[]}});
 const old={revision:8,entries:{valuable:{local:{draft:'unread Ω'}}}};
 f.disk.set('dictation:synthetic',structuredClone(old));
 await f.start();
 // Even a submitted form must fail durability before it reaches the network.
 await f.create();
 assert.equal(f.requests.length,0,'failed hydration must block history and create requests');
 assert.equal(f.button('Add text').disabled,true);
 assert.equal(f.writes.length,0);
 assert.deepEqual(f.disk.get('dictation:synthetic'),old);
 f.controller.identity(null);
});

test('history started before creation cannot archive the new durable draft',async()=>{
 let release;
 const f=fixture({request:async(path,options)=>{
  if(!options.method)return await new Promise(resolve=>{release=resolve;});
  if(options.method==='POST')return record('new');
  throw Error('unexpected request');
 }});
 await f.start();assert.ok(release);
 await f.create();
 const draft=f.host.all().find(e=>e.getAttribute('aria-label')==='What you heard');
 draft.value='created after history read Ω';draft.oninput();await tick();
 release({items:[]});await tick();await tick();
 const disk=f.disk.get('dictation:synthetic');
 assert.equal(disk.entries.new?.local.draft,'created after history read Ω');
 assert.deepEqual(disk.recoveries,{});
 assert.ok(f.host.all().some(e=>e.getAttribute('aria-label')==='What you heard'));
 f.controller.identity(null);
});

test('media error probes 401 and clears identity while playback keeps its click gesture',async()=>{
 const f=fixture({request:async(path,options)=>{
  if(options.method==='HEAD')throw Object.assign(Error('expired'),{status:401});
  assert.equal(options.method,undefined,'never synthesize or mutate during playback');
  return path.endsWith('/one')?record():{items:[record()]};
 }});
 await f.start();await f.click('Test one · In progress');
 await f.click('Play / repeat');
 const audio=f.media[0];
 assert.equal(audio.src,'/v1/learning/dictations/one/audio/0');
 assert.equal(audio.plays,1);
 assert.equal(f.requests.length,2,'successful playback must not wait for a status probe');
 await audio.onerror();await tick();await tick();
 assert.equal(f.unauthorized,1,'real media authorization failure must reject identity');
 assert.equal(f.requests.at(-1).method,'HEAD');
 assert.equal(f.requests.at(-1).path,'/v1/learning/dictations/one/audio/0');
 assert.equal(audio.src,null);
 assert.equal(audio.plays,1,'never automatically replay');
 assert.ok(!f.host.textContent.includes('Test one'));
 assert.equal(f.disk.has('dictation:synthetic'),false);
});

test('media 401 is detected even when play rejects before the media error event',async()=>{
 const f=fixture({request:async(path,options)=>{
  if(options.method==='HEAD')throw Object.assign(Error('expired'),{status:401});
  return path.endsWith('/one')?record():{items:[record()]};
 }});
 await f.start();await f.click('Test one · In progress');
 f.media[0].playError=Error('media load failed');
 await f.click('Play / repeat');
 assert.equal(f.unauthorized,0,'play rejection alone does not prove an expired session');
 await f.media[0].onerror();await tick();
 assert.equal(f.unauthorized,1);
 assert.equal(f.media[0].plays,1);
});
