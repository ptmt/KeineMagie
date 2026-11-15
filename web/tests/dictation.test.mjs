import test from 'node:test';
import assert from 'node:assert/strict';
import {practiceTransition} from '../dictation-state.mjs';
test('writing pauses, replay, mode switches and interruptions never imply autoplay',()=>{
 const r={mode:'whole',step:0,replays:0,checked:false,plan:[{kind:'whole',asset:0},{kind:'sentence',asset:1},{kind:'chunk',asset:2},{kind:'sentence_repeat',asset:1},{kind:'final',asset:0}]};
 let s=practiceTransition(r,'ended');assert.equal(s.replays,1);assert.equal(s.playing,false);
 s=practiceTransition(s,'sentences');assert.equal(s.step,0);assert.equal(s.replays,0);
 s=practiceTransition(s,'next');assert.equal(s.step,1);assert.equal(s.playing,false);
 s=practiceTransition(s,'replay');assert.equal(s.step,1);assert.equal(s.playing,false);
 for(const event of ['pause','background','logout','reload','denied'])assert.equal(practiceTransition({...s,playing:true},event).playing,false);
 s=practiceTransition({...s,step:4},'next');assert.equal(s.step,4);
 assert.equal(practiceTransition({...s,checked:true},'whole').mode,'sentences');
});
test('rapid mode and step changes retain only the final deliberate state',()=>{
 const base={mode:'whole',step:0,replays:2,checked:false,playing:true,plan:[{asset:0},{asset:1},{asset:2}]};
 let state=base;
 for(const event of ['sentences','next','whole','sentences','next','next','whole'])state=practiceTransition(state,event);
 assert.equal(state.mode,'whole');assert.equal(state.step,0);assert.equal(state.replays,0);assert.equal(state.playing,false);
});
