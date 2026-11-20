// Admission and transport have their own revision, never the draft revision.
export const supportedPolicy=r=>[1,2].includes(r?.playback_policy_version);
export function pacingPhases(r){
 const phases=[];let fragment=0;
 r.plan.forEach((s,step)=>{if(s.kind==='sentence_repeat'&&phases.length){phases.at(-1).steps.push(step);return}phases.push({kind:s.kind,fragment:s.kind==='sentence'?++fragment:0,steps:[step]})});
 return phases.map(p=>({...p,complete:p.steps.every(step=>r.playback?.listens?.some(a=>a.step===step&&a.ended===true&&!a.stopped))}));
}
export const pacingNeedsNext=r=>r.playback_policy_version===2&&r.mode==='sentences'&&!r.playback?.active&&(r.playback?.cursor??0)>0&&r.plan[r.playback.cursor]?.kind==='sentence';
export const policyStep=r=>r.playback?.active?.step??(r.mode==='whole'?0:r.playback?.cursor??1);
export const policyAssets=r=>[...new Set((r.mode==='whole'?[r.plan[0]]:r.plan.slice(r.playback?.cursor??1)).map(s=>s.asset))];
export function createPolicyPlayer({audio,getRecord,request,changed,failed,getOwner=()=>null,persistStop=async()=>{throw Error('durable Stop unavailable')}}){
 const client=crypto.randomUUID();let ticket=0,owned=null,pauseTimer=null,heartbeat=null,expiry=null,queue=Promise.resolve(),working=false,waiting=false,admission=null;
 let admissionStamp=null,stopping=false;
 const serial=fn=>{const result=queue.then(fn);queue=result.catch(()=>{});return result};
 async function recoverStop(){
  const r=getRecord(),pending=r?.pending_stop;if(!pending)return true;
  if(stopping)return false;stopping=true;const owner=getOwner(),t=ticket;changed();
  try{
   if(pending.owner!==owner||pending.attempt!==r.id)throw Error('stale Stop owner');
   // Exact journal body, including original client/fence, survives cold restart.
   const ledger=await serial(()=>request('/'+r.id+'/playback',{method:'POST',body:pending.body}));
   if(t!==ticket||owner!==getOwner()||getRecord()?.id!==r.id)return false;
   r.playback=ledger;await persistStop(null);changed();return true;
  }catch(e){if(t===ticket&&owner===getOwner())failed(e);return false}
  finally{stopping=false;changed()}
 }
 async function explicitStop(){
  const r=getRecord();if(!r||r.playback_policy_version!==2||stopping)return;
  if(r.pending_stop){await recoverStop();return}
  const a=owned||admissionStamp||r.playback?.active;
  const pending={owner:getOwner(),attempt:r.id,body:{policy_version:2,id:crypto.randomUUID(),client,action:'stop',step:0,offset:0,fence:r.playback?.revision||0,...(a?{admission:a.id}:{})}};
  ticket++;admission?.abort();admission=null;admissionStamp=null;working=false;clear();owned=null;audio.pause();audio.currentTime=0;
  try{await persistStop(pending);if(pending.owner===getOwner()&&getRecord()?.id===r.id)await recoverStop()}catch(e){failed(e)}changed();
 }
 function clear(){clearTimeout(pauseTimer);clearInterval(heartbeat);clearTimeout(expiry);pauseTimer=heartbeat=expiry=null;waiting=false;}
 function apply(a,ledger){const r=getRecord();if(a.ticket===ticket&&a.owner===getOwner()&&r?.id===a.attempt){r.playback=ledger;changed();}}
 async function send(a,action,offset=audio.currentTime,reason){if(!a||a.owner!==getOwner())throw Error('stale owner');const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),8000);let ledger;try{ledger=await request('/'+a.attempt+'/playback',{method:'POST',signal:controller.signal,body:{...(reason?{reason}:{}),policy_version:getRecord()?.playback_policy_version,id:a.id,client,step:a.step,fence:a.fence,action,offset:Number.isFinite(offset)?Math.min(7200,Math.max(0,offset)):0}})}finally{clearTimeout(timeout)}if(ledger.active?.id===a.id)a.fence=ledger.active.fence;apply(a,ledger);return ledger;}
 function fail(err){clear();audio.pause();owned=null;failed(err);changed();}
 function watch(a){
  clear();const arm=()=>{clearTimeout(expiry);const until=getRecord()?.playback?.active?.lease_until||0;expiry=setTimeout(()=>{if(owned===a)fail(Error('lease expired'))},Math.max(0,until-Date.now()-250));};arm();
  heartbeat=setInterval(()=>{if(owned!==a)return;void serial(async()=>{if(owned!==a)return;try{await send(a,'progress');if(owned===a)arm();}catch(e){if(owned===a)fail(e);}})},4000);
 }
 async function playInternal(replayStep){
  if(working||waiting||(owned&&!audio.paused)||stopping)return;const r=getRecord();if(!supportedPolicy(r)||r.checked)return;
  if(r.pending_stop){await recoverStop();return}
  working=true;admissionStamp=null;const t=++ticket,controller=new AbortController();admission=controller;const timeout=setTimeout(()=>controller.abort(),8000);changed();
  try{
   // Resolve a lost start acknowledgement from the durable server ledger.
   const fresh=await request('/'+r.id,{signal:controller.signal});if(t!==ticket||getRecord()?.id!==r.id)return;
   r.playback=fresh.playback;r.plan=fresh.plan;r.pacing=fresh.pacing;r.playback_policy_version=fresh.playback_policy_version;
   const step=r.playback.active?policyStep(r):Number.isInteger(replayStep)?replayStep:policyStep(r),asset=r.plan[step]?.asset;if(asset===undefined)return;
   let a=r.playback.active;
   const body=a?{id:a.id,client,step:a.step,fence:a.fence,action:'resume',offset:0}:{id:crypto.randomUUID(),client,step,fence:0,action:'start',offset:0};
   body.policy_version=r.playback_policy_version;
   if(r.playback_policy_version===2&&!a)body.intent=Number.isInteger(replayStep)?'extra':'planned';
   admissionStamp=body;
   const ledger=await request('/'+r.id+'/playback',{method:'POST',body,signal:controller.signal});
   if(t!==ticket||getRecord()?.id!==r.id)return;
   r.playback=ledger;a=ledger.active;if(!a)return;
   const previous=owned;owned={...a,attempt:r.id,ticket:t,owner:getOwner()};
   if(!previous||previous.id!==a.id||!audio.getAttribute?.('src')||audio.ended)audio.src='/v1/learning/dictations/'+r.id+'/audio/'+asset;
   if(a.offset>0&&Math.abs(audio.currentTime-a.offset)>.5)audio.currentTime=a.offset;
   watch(owned);changed();
   try{await audio.play();if(t!==ticket)audio.pause();}catch(e){if(t===ticket){const a=owned;await serial(()=>send(a,'release',audio.currentTime,'play_failed')).catch(()=>{});if(t===ticket){clear();owned=null;failed(e);}}}
  }catch(e){if(t===ticket)fail(e)}finally{clearTimeout(timeout);if(admission===controller)admission=null;if(t===ticket){working=false;changed();}}
 }
 return {
  get working(){return working||stopping},get waiting(){return waiting},
  explicitStop,recoverStop,
  get active(){return !!owned||waiting||!!admission},get stopping(){return stopping},
  get ownsMedia(){return !!owned&&audio.getAttribute('src')==='/v1/learning/dictations/'+owned.attempt+'/audio/'+getRecord()?.plan[owned.step]?.asset},
  play:playInternal,
  stop(){ticket++;admission?.abort();admission=null;admissionStamp=null;working=false;clear();const a=owned,offset=audio.currentTime;owned=null;audio.pause();if(a)void serial(()=>send(a,'release',offset)).catch(()=>{});},
  async cancel(){ticket++;admission?.abort();admission=null;working=false;const t=ticket;clear();const a=owned;owned=null;audio.pause();const r=getRecord(),active=r?.playback?.active;if(active){const stamp=a?{...a,ticket}:{...active,attempt:r.id,ticket,owner:getOwner()};await serial(async()=>{let current=stamp;if(!a){const p=await send(stamp,'resume',0);if(t!==ticket||stamp.owner!==getOwner())throw Error('stale playback');current={...p.active,attempt:r.id,ticket:t,owner:stamp.owner}}await send(current,'cancel')});}},
  async ended(){
   const a=owned;if(!a||working||audio.ended!==true)return;const t=ticket;clear();owned=null;working=true;changed();
   try{await serial(()=>send(a,'ended'));if(t!==ticket||getRecord()?.id!==a.attempt)return;
    const r=getRecord(),next=r.plan[r.playback.cursor];
    const repeat=r.playback_policy_version===2&&a.intent!=='extra'&&next?.kind==='sentence_repeat'&&r.playback.cursor===a.step+1&&next.asset===r.plan[a.step]?.asset;
    if(repeat||(r.playback_policy_version===1&&a.step>0&&r.playback.cursor<r.plan.length-1)){waiting=true;changed();pauseTimer=setTimeout(()=>{waiting=false;if(t===ticket&&a.owner===getOwner()&&getRecord()?.id===a.attempt)void playInternal()},repeat?r.pacing.gap_seconds*1000:3000)}else changed();
   }catch(e){if(t===ticket)fail(e)}finally{if(t===ticket){working=false;changed();}}
  },
  interrupted(err){const a=owned,offset=audio.currentTime;clear();owned=null;audio.pause();if(a)void serial(()=>send(a,'release',offset)).catch(()=>{});failed(err);changed();}
 };
}
