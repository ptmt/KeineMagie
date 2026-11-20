import test from 'node:test';import assert from 'node:assert/strict';import {createDraftJournal} from '../dictation-journal.mjs';
test('explicit remote upgrade merges plan/settings through dirty typing without a half-v2 record',async()=>{
 const j=createDraftJournal({persist:async()=>{},send:async()=>{}});const old={id:'one',mode:'whole',step:8,replays:0,draft:'',revision:0,playback_policy_version:1,plan:[{asset:0}],playback:{revision:0}};
 j.accept(old);await j.edit('one',{draft:'Still typing'});
 const next={...old,revision:1,step:0,playback_policy_version:2,pacing:{repeats:2,gap_seconds:8},plan:[{asset:0},{asset:4}],playback:{revision:1}};
 const result=j.accept(next);assert.equal(result.draft,'Still typing');assert.deepEqual(result.pacing,next.pacing);assert.deepEqual(result.plan,next.plan);assert.equal(result.revision,1);assert.equal(result.step,0);
});
