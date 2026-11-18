import test from 'node:test';
import assert from 'node:assert/strict';
import {policyStep,policyAssets,createPolicyPlayer} from '../dictation-playback.mjs';
test('policy selects durable cursor, excludes final from automatic chain',()=>{
 const r={mode:'sentences',plan:[{asset:0},{asset:1},{asset:0,kind:'final'}],playback:{cursor:1}};
 assert.equal(policyStep(r),1);assert.deepEqual(policyAssets(r),[1,0]);r.playback.active={step:0};assert.equal(policyStep(r),0);
});
test('failed play resumes same reservation and never checks or prepares',async()=>{
 const r={id:'one',mode:'whole',playback_policy_version:1,plan:[{asset:0}],playback:{cursor:1,whole_starts:0}};
 const calls=[],audio={paused:true,currentTime:0,playbackRate:1,pause(){this.paused=true},removeAttribute(){},load(){},async play(){throw Error('autoplay')}};
 const p=createPolicyPlayer({audio,getRecord:()=>r,request:async(path,o)=>{calls.push([path,o]);if(!o?.method)return r;const b=o.body;r.playback={...r.playback,whole_starts:1,active:{id:b.id,client:b.client,step:0,fence:1,offset:0,lease_until:Date.now()+15000}};return r.playback},changed(){},failed(){}});
 await p.play();const id=r.playback.active.id;await p.play();assert.equal(r.playback.active.id,id);assert.deepEqual(calls.filter(c=>c[1]?.method).map(c=>c[1].body.action),['start','release','resume','release']);assert.ok(calls.every(c=>!/(check|audio\/)/.test(c[0])));p.stop();
});

function playerFixture({mode='sentences',requestGate=null}={}){
 const r={id:'one',mode,playback_policy_version:1,plan:[{asset:0,kind:'whole'},{asset:1,kind:'sentence'},{asset:1,kind:'sentence_repeat'},{asset:0,kind:'final'}],playback:{cursor:1,whole_starts:0,revision:0}};
 let owner='owner',plays=0,failures=0;const calls=[],audio={paused:true,ended:false,currentTime:0,playbackRate:1,src:'',pause(){this.paused=true},getAttribute(){return this.src},async play(){this.paused=false;this.ended=false;plays++}};
 const request=async(path,o)=>{if(requestGate)await requestGate(path,o);if(!o?.method)return structuredClone(r);const b=o.body;calls.push(b);const p=r.playback;if(b.action==='start'){p.revision++;p.active={...b,fence:p.revision,offset:0,lease_until:Date.now()+15000};if(b.step===0||b.step===3)p.whole_starts++;}else if(b.action==='resume'){p.active.fence=++p.revision;p.active.lease_until=Date.now()+15000;}else if(b.action==='ended'||b.action==='cancel'){if(b.action==='ended'&&b.step>0)p.cursor=Math.min(3,p.cursor+1);delete p.active;}else if(b.action==='release')p.active.lease_until=0;return structuredClone(p)};
 const p=createPolicyPlayer({audio,getRecord:()=>r,getOwner:()=>owner,request,changed(){},failed(){failures++}});
 return {r,p,audio,calls,get plays(){return plays},get failures(){return failures},replaceOwner(){owner='other'}};
}
test('sentence chain waits three seconds and stops before explicit final whole replay',async t=>{
 t.mock.timers.enable({apis:['setTimeout','setInterval','Date'],now:10000});
 const f=playerFixture();await f.p.play();assert.equal(f.plays,1);
 f.audio.ended=true;await f.p.ended();assert.equal(f.r.playback.cursor,2);assert.equal(f.p.waiting,true);
 t.mock.timers.tick(2999);await Promise.resolve();assert.equal(f.plays,1);
 t.mock.timers.tick(1);for(let i=0;i<10;i++)await Promise.resolve();assert.equal(f.plays,2);
 f.audio.ended=true;await f.p.ended();t.mock.timers.tick(3000);for(let i=0;i<10;i++)await Promise.resolve();assert.equal(f.plays,2);assert.equal(f.r.playback.cursor,3);assert.equal(f.r.playback.whole_starts,0);
 await f.p.play();assert.equal(f.plays,3);assert.equal(f.r.playback.whole_starts,1);f.p.stop();
 assert.ok(f.calls.every(c=>['start','resume','ended','release','progress'].includes(c.action)));
});
test('mode cancellation preserves whole quota and clears the active reservation',async()=>{
 const f=playerFixture({mode:'whole'});await f.p.play();assert.equal(f.r.playback.whole_starts,1);await f.p.cancel();assert.equal(f.r.playback.active,undefined);assert.equal(f.r.playback.whole_starts,1);f.p.stop();
});
test('late admission after navigation or owner change cannot start media',async()=>{
 let unblock;const block=new Promise(resolve=>unblock=resolve);const f=playerFixture({requestGate:async(_path,o)=>{if(o)await block}});
 const pending=f.p.play();for(let i=0;i<5;i++)await Promise.resolve();f.p.stop();f.replaceOwner();unblock();await pending;assert.equal(f.plays,0);assert.equal(f.failures,0);
});
test('synthetic stale ended events do not complete current audio',async()=>{
 const f=playerFixture();await f.p.play();await f.p.ended();assert.ok(f.r.playback.active);assert.equal(f.r.playback.cursor,1);f.p.stop();
});

test('new hints are scoped to opt-in records and legacy guidance stays unchanged',async()=>{
 const {fixture,record}=await import('./dictation-mount-fixture.mjs');
 const value={...record(),playback_policy_version:1,playback:{cursor:1,whole_starts:0},plan:[{kind:'whole',asset:0},{kind:'sentence',asset:1},{kind:'final',asset:0}]};
 const f=fixture({request:async path=>path.endsWith('/one')?value:{items:[value]}});f.media[0].paused=true;
 await f.start();await f.click('Test one');assert.match(f.host.textContent,/four times, without pauses/);assert.equal(f.button('Play').disabled,false);assert.ok(!f.host.all().some(e=>e.tagName==='BUTTON'&&e.textContent==='Pause'));assert.equal(f.requests.filter(r=>r.method==='POST').length,0);f.controller.identity(null);
});

test('checked policy attempts do not offer a nonfunctional Play action',async()=>{
 const {fixture,record}=await import('./dictation-mount-fixture.mjs');
 const value={...record(),checked:true,playback_policy_version:1,playback:{cursor:1,whole_starts:1},plan:[{kind:'whole',asset:0},{kind:'sentence',asset:1},{kind:'final',asset:0}]};
 const f=fixture({request:async path=>path.endsWith('/one')?value:{items:[value]}});f.media[0].paused=true;
 await f.start();await f.click('Test oneChecked');assert.equal(f.button('Play').disabled,true);f.controller.identity(null);
});

test('refreshing the playback ledger cannot overwrite a pending typed draft',async()=>{
 const {createDraftJournal}=await import('../dictation-journal.mjs');
 const journal=createDraftJournal({persist:async()=>{},send:async()=>{throw Error('not called')}});
 const initial={id:'one',mode:'whole',step:0,replays:0,draft:'',revision:0,playback_policy_version:1,playback:{revision:0,whole_starts:0}};
 journal.accept(initial);await journal.edit('one',{draft:'words still being typed'});
 journal.accept({...initial,playback:{revision:4,whole_starts:2}});
 assert.equal(journal.get('one').draft,'words still being typed');assert.equal(journal.get('one').playback.whole_starts,2);
 journal.accept({...initial,playback:{revision:1,whole_starts:1}});assert.equal(journal.get('one').playback.whole_starts,2);
});

test('a journaled legacy New attempt retry keeps its absent policy version',async()=>{
 const {createDraftJournal}=await import('../dictation-journal.mjs');let disk;
 const make=()=>createDraftJournal({persist:async value=>{disk=structuredClone(value)},send:async()=>{}});
 const old=make();const legacy=await old.reserveAttempt('source');const current=make();current.restore(disk);
 assert.equal(await current.reserveAttempt('source',1),legacy);assert.equal(current.attemptPolicy('source'),undefined);
 await current.clearAttempt('source');await current.reserveAttempt('source',1);assert.equal(current.attemptPolicy('source'),1);
 const restored=make();restored.restore(disk);assert.equal(restored.attemptPolicy('source'),1);
});

test('policy copy counts authorized starts and qualifies the final replay allowance',async()=>{
 const {dt}=await import('../dictation-i18n.mjs');
 for(const [locale,startWord,allowance] of [['en','starts','remaining'],['de','Starts','übrig'],['ru','Запуски','остал'],['es','Inicios','disponible'],['fr','Démarrages','restant']]){
  assert.ok(dt(locale,'dictation.listens',{n:4,total:4}).includes(startWord),locale+' must describe starts, not completed listens');
  assert.ok(dt(locale,'dictation.policy.hint.sentences').includes(allowance),locale+' must qualify final replay');
 }
});

test('navigation checkpoints the position before removing the media source',async()=>{
 const f=playerFixture({mode:'whole'});await f.p.play();f.audio.currentTime=0.7;f.p.stop();f.audio.currentTime=0;
 for(let i=0;i<10;i++)await Promise.resolve();
 assert.equal(f.calls.find(c=>c.action==='release').offset,0.7);
});
