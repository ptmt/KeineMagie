import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture} from './coach-mount-fixture.mjs';
test('context translation highlights only literal target without interpreting markup',async()=>{
 const prompt='Ich muss das Paket abholen.';
 const f=fixture({snapshot:{turns:[{id:'word',state:'completed',kind:'context_translation',prompt,target_text:'abholen',answer_language:'en',message:'Translate abholen into English.'}],observations:[]}});
 f.controller.identity(f.session);await f.show();
 assert.equal(f.messages.querySelector('.coach-prompt').textContent,prompt);
 assert.equal(f.messages.querySelector('.coach-prompt').querySelector('strong')?.textContent,'abholen');
 assert.ok(f.messages.querySelector('input'));
});
test('pending entry exposes cancellation and cancel wins over a late entry response',async()=>{
 let release;const f=fixture({request:async(_,options)=>options.body.action==='entry'?await new Promise(r=>release=r):{turns:[{id:'canceled',state:'canceled'}],observations:[]}});
 f.controller.identity(f.session);await f.show();
 const entry=f.requests[0];const cancel=f.messages.querySelectorAll('button').find(b=>b.textContent==='Cancel');
 assert.ok(cancel,'pending entry must expose Cancel');
 await cancel.onclick();await f.flush();
 assert.equal(entry.signal.aborted,true);
 assert.equal(f.requests[1].body.action,'cancel');
 assert.equal(f.requests[1].body.turn_id,entry.body.request_id);
 release({turns:[{id:'late',message:'Late entry',state:'completed'}],observations:[]});await f.flush();
 assert.doesNotMatch(f.messages.textContent,/Late entry/);
});
test('Latest in expanded history collapses and requests bottom without a snapshot change',async()=>{
 const f=fixture({snapshot:{turns:[{id:'old',message:'Old message',state:'completed',at:'2000-01-01T12:00:00Z'}],observations:[]}});
 f.controller.identity(f.session);await f.show();
 f.messages.querySelectorAll('button').find(b=>b.textContent==='Earlier').onclick();await f.flush();
 assert.equal(f.messages.scrollTop,0);
 f.controller.localize();await f.flush();assert.equal(f.messages.scrollTop,0,'manual history reading stays put');
 const latest=f.messages.querySelectorAll('button').find(b=>b.textContent==='Latest');assert.ok(latest);
 latest.onclick();await f.flush();
 assert.equal(f.messages.scrollTop,800,'explicit Latest requests bottom');
 assert.equal(f.messages.querySelectorAll('button').find(b=>b.textContent==='Earlier').getAttribute('aria-expanded'),'false');
});
test('composer menu includes every command and a detached old-owner command cannot send',async()=>{
 const actions=['reveal','progress','more','explain','practice'].map(action=>({action,turn_id:'exercise'}));
 const f=fixture({snapshot:{turns:[],observations:[],actions}});f.controller.identity(f.session);await f.show();
 const menu=f.host.querySelector('.coach-command-menu'),trigger=f.host.querySelector('.coach-menu-trigger');
 assert.equal(menu.children.length,5);const before=f.requests.length;trigger.onclick();assert.equal(f.requests.length,before);
 const old=menu.children[0];f.controller.identity({user:{id:'different'},csrf_token:'synthetic'});await f.flush();
 const switched=f.requests.length;await old.onclick();assert.equal(f.requests.length,switched);assert.equal(menu.hidden,true);
 f.controller.identity(null);assert.ok(menu.children.every(b=>b.disabled));
});
test('busy menu stays discoverable with disabled commands and opening sends nothing',async()=>{
 let release;const f=fixture({request:async()=>await new Promise(r=>release=r)});f.controller.identity(f.session);await f.show();
 const trigger=f.host.querySelector('.coach-menu-trigger'),menu=f.host.querySelector('.coach-command-menu');
 assert.equal(trigger.disabled,false);assert.ok(menu.children.every(b=>b.disabled));const before=f.requests.length;trigger.onclick();assert.equal(f.requests.length,before);
 release({turns:[],observations:[]});await f.flush();
});
const snapshot={turns:[{id:'exercise',state:'completed',kind:'cloze',prompt:'Ich warte ___ den Bus.'}],observations:[]};
test('only authenticated visible entry posts; hidden preload and background visibility do not',async()=>{
 const f=fixture({snapshot});f.controller.identity(f.session);await f.flush();assert.equal(f.requests.length,0);
 f.doc.visibilityState='hidden';await f.show();assert.equal(f.requests.length,0);
 f.doc.visibilityState='visible';f.doc.dispatch('visibilitychange');await f.flush();
 assert.deepEqual(f.requests.map(r=>r.body?.action),['entry']);
 assert.equal(f.requests[0].body.time_zone,Intl.DateTimeFormat().resolvedOptions().timeZone);
 f.host.hidden=true;f.controller.route();f.doc.dispatch('visibilitychange');await f.flush();
 assert.equal(f.requests.length,1);
 f.controller.identity(null);f.host.hidden=false;f.controller.route();await f.flush();assert.equal(f.requests.length,1);
});
test('initial data anchors once; localization, profile receipts, and older reading do not follow',async()=>{
 const f=fixture({snapshot});f.controller.identity(f.session);await f.show();
 assert.equal(f.messages.scrollTop,800);
 // A render may preserve the same offset; count actual bottom requests by changing
 // synthetic layout height before an unrelated localization render.
 f.messages.scrollHeight=1500;f.controller.localize();await f.flush();assert.equal(f.messages.scrollTop,800);
 f.messages.dispatch('wheel');f.messages.scrollTop=100;f.messages.dispatch('scroll');
 snapshot.turns.push({id:'new',state:'completed',message:'New message'});
 f.doc.dispatch('visibilitychange');await f.flush();assert.equal(f.messages.scrollTop,100);
 f.controller.localize();await f.flush();assert.equal(f.messages.scrollTop,100);
});
test('new messages follow near the bottom and own send follows from older reading',async()=>{
 let current=structuredClone(snapshot);const f=fixture({request:async()=>structuredClone(current)});
 f.controller.identity(f.session);await f.show();
 f.messages.scrollHeight=1600;
 // User is near the bottom before a new response arrives.
 f.messages.scrollTop=1200;f.messages.dispatch('scroll');
 current.turns.push({id:'another',message:'Another answer',state:'completed'});
 f.doc.dispatch('visibilitychange');await f.flush();assert.equal(f.messages.scrollTop,1200);
 f.messages.dispatch('wheel');f.messages.scrollTop=50;f.messages.dispatch('scroll');
 const form=f.host.querySelector('form'),input=f.host.querySelector('textarea');input.value='My question';
 await form.onsubmit({preventDefault(){}});await f.flush();assert.equal(f.messages.scrollTop,1200);
});
test('old greetings stay saved but never render, checking has an accessible label',async()=>{
 const data={turns:[{id:'offer',is_offer:true,message:'Legacy offer'},{id:'nudge',kind:'nudge',message:'Legacy nudge'},{id:'pending',kind:'cloze',prompt:'___',attempt:{answer:'auf',assessment_state:'pending'}}],observations:[]};
 const f=fixture({snapshot:data});f.controller.identity(f.session);await f.show();
 assert.doesNotMatch(f.messages.textContent,/Legacy/);assert.equal(data.turns.length,3);
 assert.equal(f.messages.querySelector('.coach-checking').getAttribute('aria-label'),'Checking…');
});
test('profile and seen receipt changes preserve offset, explicit answer follows from history',async()=>{
 const current=structuredClone(snapshot);const f=fixture({request:async()=>structuredClone(current)});
 f.controller.identity(f.session);await f.show();
 f.messages.scrollHeight=1800;
 current.observations=[{target:'grammar',language:'de',count:1}];current.turns[0].seen_version='seen';
 f.doc.dispatch('visibilitychange');await f.flush();assert.equal(f.messages.scrollTop,800);
 f.messages.dispatch('wheel');f.messages.scrollTop=50;f.messages.dispatch('scroll');
 const answer=f.messages.querySelector('input');answer.value='auf';answer.oninput({currentTarget:answer});
 const check=f.messages.querySelectorAll('button').find(b=>b.textContent==='Check');
 await check.onclick();await f.flush();assert.equal(f.messages.scrollTop,1400);
});
