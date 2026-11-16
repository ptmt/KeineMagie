import {test} from 'node:test';
import assert from 'node:assert/strict';
import {coachRecentTurns,coachExerciseStatus,coachHistoryWindow} from '../coach-presentation.mjs';
const now=Date.parse('2026-10-25T12:00:00Z');
test('rolling 24h retains complete groups by latest learner/assessment activity, no active exception',()=>{
 const turns=[{id:'old',at:'2026-10-24T11:59:59Z'}, {id:'edge',at:'2026-10-24T14:00:00+02:00'}, {id:'feedback',at:'2026-10-20T00:00:00Z',attempt:{at:'2026-10-25T11:00:00Z'}},{id:'future',at:'2027-01-01T00:00:00Z'},{id:'unknown'},{id:'legacy',at:'now'},{id:'pending',state:'pending',at:'2026-10-20T00:00:00Z'}];
 assert.deepEqual(coachRecentTurns(turns,now).map(t=>t.id),['edge','feedback','future','unknown','legacy']);
 assert.equal(turns.length,7);
});
test('attempts including wrong/uncertain are neutral completed; checking differs from waiting and skipped',()=>{
 assert.equal(coachExerciseStatus({state:'completed'}),'awaiting');
 for(const outcome of ['correct','wrong','ambiguous'])assert.equal(coachExerciseStatus({attempt:{outcome}}),'completed');
 assert.equal(coachExerciseStatus({attempt:{assessment_state:'pending'}}),'working');
 assert.equal(coachExerciseStatus({state:'pending'}),'working');
 assert.equal(coachExerciseStatus({attempt:{outcome:'skipped'}}),'unanswered');
});
test('Earlier bounds rendering to a 50-group window without changing saved data',()=>{
 const turns=Array.from({length:1000},(_,i)=>({id:String(i),at:'2020-01-01T00:00:00Z'}));
 turns.push({id:'recent',at:new Date(now).toISOString()});
 assert.deepEqual(coachHistoryWindow(turns,now,0).map(t=>t.id),['recent']);
 const page=coachHistoryWindow(turns,now,50);
 assert.equal(page.length,51);assert.equal(page[0].id,'950');assert.equal(page.at(-1).id,'recent');
 assert.equal(coachHistoryWindow(turns,now,100).length,51);
 assert.equal(coachHistoryWindow(turns,now,100)[0].id,'900');
 assert.equal(turns.length,1001);
});
