import test from 'node:test';
import assert from 'node:assert/strict';
import {coachMasksAnswer,coachUnread,coachPracticeText} from '../coach-chat.mjs';
import {createCoachState} from '../coach-state.mjs';
test('quiet seen receipt revocation notifies the session owner',async()=>{
 const error=Object.assign(new Error('revoked'),{status:401});const revoked=[];
 const state=createCoachState({request:async()=>{throw error}},()=>{},e=>revoked.push(e),()=> 'en');
 state.identity({user:{id:'owner'},csrf_token:'synthetic'});
 await state.seen({id:'a',message_version:'a:completed'});
 assert.deepEqual(revoked,[error]);
});
test('old answered turns collapse, latest feedback and explicit reveal survive',()=>{
 const old={id:'a',attempt:{answer:'literal'}},latest={id:'b'};
 assert.equal(coachMasksAnswer(old,[old,latest]),true);
 assert.equal(coachMasksAnswer(old,[old]),false);
 assert.equal(coachMasksAnswer({...old,answer_reveals:1},[old,latest]),false);
});
test('unread matches exact message revision, not fetch',()=>{
 assert.equal(coachUnread({state:'completed',message_version:'a',seen_version:''}),true);
 assert.equal(coachUnread({state:'completed',message_version:'a',seen_version:'a'}),false);
 assert.equal(coachUnread({state:'pending',message_version:'a'}),false);
 assert.equal(coachPracticeText('ru'),'30 секунд');
});
test('hidden legacy greetings cannot mask the latest visible feedback',()=>{
 const answer={id:'answer',attempt:{answer:'auf'}};
 assert.equal(coachMasksAnswer(answer,[answer,{id:'nudge',kind:'nudge'},{id:'offer',is_offer:true}]),false);
});
