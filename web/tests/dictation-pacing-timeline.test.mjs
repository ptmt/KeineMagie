import test from 'node:test';
import assert from 'node:assert/strict';
import {pacingPhases,pacingNeedsNext} from '../dictation-playback.mjs';
const record=()=>({mode:'sentences',playback_policy_version:2,plan:[{kind:'whole',asset:0},{kind:'sentence',asset:1},{kind:'sentence_repeat',asset:1},{kind:'sentence',asset:2},{kind:'sentence_repeat',asset:2},{kind:'final',asset:0}],playback:{cursor:0,listens:[]}});
test('timeline completion requires ended receipts for every repetition, never starts or canceled reservations',()=>{
 const r=record();r.playback.listens=[{step:0,done:true},{step:1,ended:true,done:true},{step:2,done:true,stopped:true}];
 assert.deepEqual(pacingPhases(r).map(p=>p.complete),[false,false,false,false]);
 r.playback.listens.push({step:0,done:true,ended:true},{step:2,done:true,ended:true});
 assert.deepEqual(pacingPhases(r).map(p=>p.complete),[true,true,false,false]);
 r.playback.cursor=3;assert.equal(pacingNeedsNext(r),true);r.playback.active={step:3};assert.equal(pacingNeedsNext(r),false);
});
