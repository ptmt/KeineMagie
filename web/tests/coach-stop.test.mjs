import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture} from './coach-mount-fixture.mjs';
test('pending answer stays visible even with later discussion, composer Stop cancels exact receipt',async()=>{
 let release;
 const snapshot={turns:[{id:'exercise',kind:'cloze',state:'completed',prompt:'Ich warte ___ den Bus.'},{id:'discussion',kind:'clarification',message:'A question.'}],observations:[]};
 const f=fixture({request:async(_,options)=>options.body.action==='answer'?await new Promise(r=>release=r):snapshot});f.controller.identity(f.session);await f.show();
 const input=f.messages.querySelector('input');input.value='  auf 🙂  ';input.oninput({currentTarget:input});
 f.messages.querySelectorAll('button').find(b=>b.textContent==='Check').onclick();await f.flush();
 assert.equal(f.messages.querySelector('.coach-answer')?.textContent,'  auf 🙂  ');
 const stop=f.host.querySelector('.coach-stop');assert.ok(stop);assert.equal(stop.disabled,false);
 await f.host.querySelector('form').onsubmit({preventDefault(){}});await f.flush();
 assert.equal(f.requests.at(-1).body.action,'cancel');assert.equal(f.requests.at(-1).body.turn_id,f.requests.find(r=>r.body.action==='answer').body.request_id);
 release(snapshot);await f.flush();
});
