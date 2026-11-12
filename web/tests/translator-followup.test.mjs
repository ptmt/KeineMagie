import test from 'node:test';
import assert from 'node:assert/strict';
import {createFollowupState, followupLabels} from '../translator-followup.mjs';
const record={id:'saved',text:'лук',translation:'Zwiebel',source_language:'ru',target_language:'de'};
test('discussion coalesces sends, retains draft and request ID on retry, ignores stale selected output',async()=>{
 let release;const sent=[];const updates=[];let failed=true;
 const state=createFollowupState({api:{request:async(path,options)=>{sent.push([path,options]);await new Promise(r=>release=r);if(failed)throw Object.assign(new Error('offline'),{status:502});return {...record,followups:[{request_id:options.body.request_id,question:options.body.question,answer:'Это оружие.',revised_text:'Bogen'}]};}},changed:()=>{},saved:r=>updates.push(r),locale:()=> 'ru',requestID:()=> 'same-retry-id'});
 state.identity({user:{id:'owner'},csrf_token:'csrf'},true);state.select(record);state.draft('Я имел в виду оружие');
 const first=state.send();const double=state.send();assert.equal(sent.length,1);assert.equal(first,double);release();await first;
 assert.equal(state.current().draft,'Я имел в виду оружие');assert.equal(state.current().error,502);
 failed=false;const retry=state.send();assert.equal(sent[1][1].body.request_id,'same-retry-id');state.select({...record,id:'new'});release();await retry;
 assert.equal(state.current().record.id,'new');assert.equal(state.current().record.followups,undefined);assert.equal(updates.length,1);
 state.select(updates[0]);assert.equal(state.current().record.followups.length,1);assert.equal(state.current().draft,'');
});
test('owner replacement erases drafts and fences late private responses',async()=>{
 let release;let saved=0;const state=createFollowupState({api:{request:()=>new Promise(r=>release=r)},changed:()=>{},saved:()=>saved++,locale:()=> 'en',requestID:()=> 'r'});
 state.identity({user:{id:'A'},csrf_token:'a'},true);state.select(record);state.draft('private');const task=state.send();state.identity({user:{id:'B'},csrf_token:'b'},true);release({...record,followups:[{answer:'private'}]});await task;
 assert.equal(state.current(),null);assert.equal(saved,0);state.select(record);assert.equal(state.current().draft,'');
});
test('reopening a saved original clears the applied selection so its revision can be used again',()=>{
 const state=createFollowupState({api:{},changed:()=>{},saved:()=>{},locale:()=> 'en'});
 state.identity({user:{id:'owner'}},true);state.select(record);state.applied(0);
 state.select(record);
 assert.equal(state.current().applied,null);
});
test('cached retry accepts its committed turn even when another client has appended a later question',async()=>{
 const turns=[{request_id:'retry',question:'context',answer:'answer',revised_text:null},{request_id:'later',question:'later',answer:'later answer',revised_text:null}];
 let saved;
 const state=createFollowupState({api:{request:async()=>({...record,followups:turns})},changed:()=>{},saved:r=>saved=r,locale:()=> 'en',requestID:()=> 'retry'});
 state.identity({user:{id:'owner'}},true);state.select(record);state.draft('context');await state.send();
 assert.equal(saved?.followups.length,2);
 assert.equal(state.current().draft,'');
});
test('retry identity includes current paired draft without replacing immutable original',async()=>{
 let id=0,draft={current_source:'paired source 😀\n',current_translation:'manual output\n'};const sent=[];
 const state=createFollowupState({api:{request:async(path,{body})=>{sent.push(body);throw Object.assign(new Error('offline'),{status:502});}},currentDraft:()=>draft,changed:()=>{},saved:()=>{},locale:()=> 'en',requestID:()=>String(++id)});
 state.identity({user:{id:'owner'}},true);state.select(record);state.draft('context');await state.send();await state.send();
 assert.equal(sent[0].current_source,draft.current_source);assert.equal(sent[0].current_translation,draft.current_translation);assert.equal(sent[0].request_id,sent[1].request_id);
 draft={...draft,current_translation:'changed after failure'};await state.send();assert.notEqual(sent[1].request_id,sent[2].request_id);assert.equal(state.current().record.translation,'Zwiebel');
});

test('oversize current pair stays local with a specific discussion limit',async()=>{
 let calls=0;const state=createFollowupState({api:{request:async()=>{calls++;}},currentDraft:()=>({current_source:'x',current_translation:'😀'.repeat(8001)}),changed:()=>{},saved:()=>{},locale:()=> 'en'});
 state.identity({user:{id:'owner'}},true);state.select(record);state.draft('question');await state.send();assert.equal(calls,0);assert.equal(state.current().error,'draft-limit');assert.equal(state.current().draft,'question');
});
test('all five dictionaries have identical keys and localized clarification',()=>{
 const keys=Object.keys(followupLabels.en).sort();assert.equal(Object.keys(followupLabels).length,5);
 for(const labels of Object.values(followupLabels))assert.deepEqual(Object.keys(labels).sort(),keys);
 assert.equal(followupLabels.ru.clarify,'Уточнить перевод');
});
