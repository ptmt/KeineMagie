import test from 'node:test';
import assert from 'node:assert/strict';
import {createPolicyPlayer} from '../dictation-playback.mjs';

test('explicit Stop journals the exact body and recovers lost ACK after restart without refund',async()=>{
 let disk, fail=true;
 const r={id:'one',mode:'sentences',playback_policy_version:2,pacing:{repeats:2,gap_seconds:3},plan:[{kind:'whole',asset:0},{kind:'sentence',asset:1},{kind:'sentence_repeat',asset:1},{kind:'final',asset:0}],playback:{revision:4,cursor:1,whole_starts:1}};
 const audio={currentTime:0,paused:false,pause(){this.paused=true}};const bodies=[];
 const request=async(_path,o)=>{bodies.push(structuredClone(o.body));if(fail){fail=false;throw Error('lost ACK')}return {...r.playback,revision:5,cursor:0}};
 const options={audio,getRecord:()=>r,getOwner:()=> 'owner',request,changed(){},failed(){},persistStop:async value=>{disk=structuredClone(value);r.pending_stop=value}};
 const p=createPolicyPlayer(options);await p.explicitStop();assert.equal(audio.paused,true);assert.ok(disk);assert.equal(disk.body.action,'stop');
 const original=structuredClone(disk.body);const restored=createPolicyPlayer(options);assert.equal(await restored.recoverStop(),true);
 assert.deepEqual(bodies,[original,original]);assert.equal(r.playback.whole_starts,1);assert.equal(r.playback.cursor,0);assert.equal(disk,null);
});
