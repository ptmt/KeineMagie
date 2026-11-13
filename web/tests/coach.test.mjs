import test from 'node:test';
import assert from 'node:assert/strict';
import {coachSourceLink} from '../coach.mjs';
test('source links are local, exact, and reject malformed identifiers',()=>{
 assert.equal(coachSourceLink('translation:original'),'/?translation=original#translator');
 assert.equal(coachSourceLink('passage:job_A:12'),'/?section=transcript&segment=12#podcasts/job/job_A');
 for(const id of ['translation:../foreign','passage:job:01','passage:job:-1','https://foreign','translation:'])assert.equal(coachSourceLink(id),null);
});
import {createCoachState} from '../coach-state.mjs';
test('owner reset fences delayed responses and load never posts', async()=>{
 const calls=[];let resolve;const api={request:(path,options)=>{calls.push({path,options});return new Promise(r=>resolve=r)}};
 const state=createCoachState(api,()=>{},()=>{},()=> 'en');state.identity({user:{id:'a'},csrf_token:'synthetic'});const load=state.load();
 assert.equal(calls[0].options?.method,undefined);state.identity({user:{id:'b'}});resolve({turns:[{id:'old'}],observations:[]});await load;assert.equal(state.value,null);
});
test('mutation fences older reads',async()=>{
 let resolve;const api={request:async(path,options)=>options?.method==='POST'?{turns:[{id:'new'}],observations:[]}:await new Promise(r=>resolve=r)};
 const state=createCoachState(api,()=>{},()=>{},()=> 'en');state.identity({user:{id:'a'},csrf_token:'x'});
 const load=state.load();await state.act('message','hello');resolve({turns:[],observations:[]});await load;
 assert.equal(state.value.turns[0]?.id,'new');
});
test('cancel owns mutation slot until durable acknowledgement and fences late send',async()=>{
 const releases=[];const api={request:()=>new Promise(r=>releases.push(r))};
 const state=createCoachState(api,()=>{},()=>{},()=> 'en');state.identity({user:{id:'a'},csrf_token:'x'});
 const send=state.act('message','hello');const cancel=state.act('cancel','',state.pendingID);
 assert.equal(state.busy,true);assert.equal(await state.act('message','duplicate'),false);
 releases[1]({turns:[{id:'one',state:'canceled'}]});await cancel;
 releases[0]({turns:[{id:'one',state:'completed'}]});await send;
 assert.equal(state.value.turns[0].state,'canceled');assert.equal(state.busy,false);
});
test('errors use localizable codes, never provider text',async()=>{
 const state=createCoachState({request:async()=>{throw Object.assign(new Error('private upstream detail'),{code:'coach_model_unavailable',status:503})}},()=>{},()=>{},()=> 'fr');
 state.identity({user:{id:'a'}});await state.load();assert.equal(state.error,'model_unavailable');
});
test('explicit send uses stable id; failures do not silently retry',async()=>{
 let count=0;const api={request:async()=>{count++;throw new Error('offline')}};const state=createCoachState(api,()=>{},()=>{},()=> 'en');state.identity({user:{id:'a'},csrf_token:'x'});await state.act('message','hello');assert.equal(count,1);assert.ok(state.error);assert.equal(state.busy,false);
});
