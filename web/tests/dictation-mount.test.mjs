import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture,record,tick} from './dictation-mount-fixture.mjs';

for(const [label,change] of [['title',{form:{title:'Saved title'}}],['text',{form:{text:'Saved text Ω'}}],['pending create',{pendingCreate:{id:'pending',title:'Pending title',text:'Pending text Ω',language:'de'}}]]){
 test(`saved creation ${label} has a visible resume row opening the exact saved form`,async()=>{
  const f=fixture({request:async()=>({items:[]})});
  const saved={entries:{},form:{id:'saved',title:'',text:'',language:'de',...change.form},pendingCreate:change.pendingCreate??null,recoveries:{},revision:1};
  f.disk.set('dictation:synthetic',structuredClone(saved));await f.start();
  assert.doesNotMatch(f.host.textContent,/No dictations yet|Listen → type → check/);
  const resumeLabel=(saved.form.title?saved.form.title+' · ':'')+'Draft';
  await f.click(resumeLabel);
  assert.equal(f.host.all().find(e=>e.tagName==='DIALOG').open,true);
  const field=label=>f.host.all().find(e=>e.getAttribute('aria-label')===label);
  assert.equal(field('Title').value,saved.form.title);assert.equal(field('Original text').value,saved.form.text);
  assert.equal(field('Text language').value,saved.form.language);
  assert.equal(field('Title').disabled,!!saved.pendingCreate);
  assert.deepEqual(f.disk.get('dictation:synthetic'),saved,'opening existing form must not overwrite saved creation');
  assert.equal(f.requests.length,1);f.controller.identity(null);
 });
}
test('refresh removes stale empty onboarding immediately while history is loading',async()=>{
 let release,count=0;const f=fixture({request:async()=>++count===1?{items:[]}:await new Promise(r=>release=r)});
 await f.start();assert.match(f.host.textContent,/Listen → type → check/);
 f.controller.route();
 assert.match(f.host.textContent,/Loading…/);
 assert.doesNotMatch(f.host.textContent,/No dictations yet|Listen → type → check/);
 release({items:[]});await tick();await tick();
 assert.match(f.host.textContent,/Listen → type → check/);f.controller.identity(null);
});

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
 await f.start();await f.click('Test one');
 await f.click('Play');
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
 await f.start();await f.click('Test one');
 f.media[0].playError=Error('media load failed');
 await f.click('Play');
 assert.equal(f.unauthorized,0,'play rejection alone does not prove an expired session');
 await f.media[0].onerror();await tick();
 assert.equal(f.unauthorized,1);
 assert.equal(f.media[0].plays,1);
});

test('onboarding only follows an authenticated successful empty read; header stays focused on creation',async()=>{
 let release;const f=fixture({request:async()=>await new Promise(r=>release=r)});
 assert.doesNotMatch(f.host.textContent,/Listen → type → check/);
 await f.start();assert.doesNotMatch(f.host.textContent,/Listen → type → check/);
 release({items:[]});await tick();await tick();
 assert.match(f.host.textContent,/Listen → type → check/);
 assert.equal(f.requests.length,1,'empty onboarding never generates content');
 assert.equal(f.host.all().filter(e=>e.tagName==='SUMMARY').length,0);
 f.controller.identity(null);assert.doesNotMatch(f.host.textContent,/Listen → type → check/);
});
test('failed history never renders onboarding',async()=>{
 const f=fixture({request:async()=>{throw Error('offline')}});await f.start();
 assert.doesNotMatch(f.host.textContent,/No dictations yet|Listen → type → check/);
 f.controller.identity(null);
});

test('loaded empty onboarding has a visible Add text CTA opening the existing dialog',async()=>{
 const f=fixture({request:async()=>({items:[]})});await f.start();
 const list=f.host.children[2];
 const cta=list.all().find(e=>e.tagName==='BUTTON'&&e.textContent==='Add text');
 assert.ok(cta,'onboarding must include a text button in the history list');
 await cta.onclick();
 assert.equal(f.host.all().find(e=>e.tagName==='DIALOG').open,true);
 assert.equal(f.requests.length,1);assert.equal(f.writes.length,0);
 f.controller.identity(null);
});

test('editing then cancelling Add text exposes a resume row beside practice and recovery rows',async()=>{
 const f=fixture({request:async()=>({items:[record()]})});
 const saved={entries:{},form:{id:'saved',title:'',text:'',language:'de'},recoveries:{deleted:{title:'Removed',draft:'Recovery Ω'}},revision:1};
 f.disk.set('dictation:synthetic',saved);await f.start();await f.click('Add text');
 const field=label=>f.host.all().find(e=>e.getAttribute('aria-label')===label);
 field('Title').value='New title Ω';field('Title').listeners.input();await tick();
 field('Original text').value='Exact text\nΩ ';field('Original text').listeners.input();await tick();
 await f.click('Cancel');
 assert.ok(f.button('Test one'));assert.ok(f.button('Export draft'));
 await f.click('New title Ω · Draft');
 assert.equal(field('Original text').value,'Exact text\nΩ ');
 assert.equal(f.requests.length,1);
 f.controller.identity(null);
 assert.doesNotMatch(f.host.children[2].textContent,/New title Ω|In progress|Removed/);
});
