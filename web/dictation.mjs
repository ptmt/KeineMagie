import {renderAssessment} from './dictation-assessment.mjs';
import {createPolicyPlayer,policyStep,policyAssets,supportedPolicy,pacingPhases,pacingNeedsNext} from './dictation-playback.mjs';
import {practiceTransition} from './dictation-state.mjs';
import {dt} from './dictation-i18n.mjs';
import {createDraftJournal} from './dictation-journal.mjs';
import {createOwnerDraftCache,indexedDraftStorage} from './dictation-cache.mjs';
const root='/v1/learning/dictations';
export function mountDictation({host,api,unauthorized,locale=()=>'en'}){
 let session=null,epoch=0,items=[],record=null,busy=false,loading=false,loaded=false,error='',timer=null,flight=null,playback=null,mediaAttempt=null,mediaEpoch=0,conflict=null,dirty=0;
 const l=(key,values)=>dt(locale(),key,values);
 const cache=createOwnerDraftCache(indexedDraftStorage());let lease=null,hydrating=false;
 const journal=createDraftJournal({persist:value=>lease?.save(value),send:(id,body)=>request('/'+id,{method:'PUT',body})});
 function accept(value){const e=epoch;record=journal.accept(value);void journal.persist().catch(()=>{if(e===epoch){error=l('Could not save. Retry.');renderStatus();}});}
 let speechSpend=null,selectedManualStep=null;
 let updatePlayer=()=>{},originalVisible=null,activeAttemptMenu=null,policyView='';
 const completeAttempts=new Map();let checking=false;
 async function recoverAssessment(id,e=epoch){
  try{const value=await request('/'+id);if(e!==epoch||record?.id!==id||!value.assessment)return;
   const old=record.assessment;if(old&&old.id===value.assessment.id&&old.state!=='pending'&&value.assessment.state==='pending')return;
   accept(value);render();
  }catch(err){if(e===epoch&&err.status===401)unauthorized(err);}
 }
 document.addEventListener('pointerdown',e=>{if(activeAttemptMenu?.open&&!activeAttemptMenu.contains(e.target))activeAttemptMenu.open=false;});
 const audio=new Audio();audio.preload='none';
 audio.onplay=()=>updatePlayer();audio.onpause=()=>updatePlayer();
 const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;};
 const button=(label,fn)=>{const b=el('button',label);b.type='button';b.onclick=fn;return b;};
 const notice=el('p');notice.setAttribute('role','status');
 const header=el('header'),title=el('h1',l('Diktat')),add=button('+',openAdd);add.setAttribute('aria-label',l('Add text'));const refresh=button(l('Refresh'),()=>load());header.append(title,add);
 const list=el('div'),practice=el('section'),dialog=el('dialog'),form=el('form'),name=el('input'),text=el('textarea'),language=el('select'),option=el('option','Deutsch');option.value='de';language.append(option);language.setAttribute('aria-label',l('Text language'));name.placeholder=l('Title');name.setAttribute('aria-label',l('Title'));name.maxLength=80;text.placeholder=l('Original text');text.setAttribute('aria-label',l('Original text'));text.maxLength=1800;text.rows=8;
 const create=el('button',l('Save text'));create.type='submit';const cancel=button(l('Cancel'),()=>dialog.close());form.append(el('h2',l('Add text')),name,language,text,el('small',l('German · up to 1800 characters / 300 words. Computer-generated voice.')),create,cancel);dialog.append(form);
 function localizeStatic(){refresh.textContent=l('Refresh');title.textContent=l('Diktat');add.setAttribute('aria-label',l('Add text'));name.placeholder=l('Title');name.setAttribute('aria-label',l('Title'));text.placeholder=l('Original text');text.setAttribute('aria-label',l('Original text'));language.setAttribute('aria-label',l('Text language'));create.textContent=l('Save text');cancel.textContent=l('Cancel');form.querySelector('h2').textContent=l('Add text');form.querySelector('small').textContent=l('German · up to 1800 characters / 300 words. Computer-generated voice.');}
 const spendFooter=el('footer');spendFooter.className='dictation-spend';
 list.className='dictation-library';host.className='dictation-page';host.replaceChildren(header,notice,list,practice,dialog,spendFooter);
 function renderSpend(){spendFooter.hidden=!session;spendFooter.textContent='';if(!session)return;const s=speechSpend,known=s?.scope==='owner_attributed_speech_receipts'&&Number.isSafeInteger(s.reported_micro_usd)&&s.reported_micro_usd>=0;const amount=known?new Intl.NumberFormat(locale(),{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:6}).format(s.reported_micro_usd/1000000):l('spend.unknown');spendFooter.textContent=l('spend.monthly',{amount})+(s?.month?' · '+s.month+' UTC':'');if(s?.unsettled_reservations>0)spendFooter.textContent+=' · '+l('spend.unsettled',{n:s.unsettled_reservations});spendFooter.title=l('spend.scope');}
 async function refreshSpend(){const e=epoch;try{const v=await request();if(e===epoch){speechSpend=v.speech_spend;renderSpend()}}catch{if(e===epoch){speechSpend=null;renderSpend()}}}
 function openAdd(){syncForm();dialog.showModal();}
 function syncForm(){const value=journal.form();name.value=value.title;text.value=value.text;language.value=value.language;renderStatus();}
 for(const control of [name,text,language])control.addEventListener(control===language?'change':'input',()=>{const e=epoch;void journal.editForm({title:name.value,text:text.value,language:language.value}).then(()=>{if(e===epoch)render();}).catch(()=>{if(e===epoch){error=l('Could not save. Retry.');renderStatus();}});});
 form.onsubmit=async e=>{e.preventDefault();const ownerEpoch=epoch;let body;try{if(!journal.createBody())await journal.editForm({title:name.value,text:text.value,language:language.value});if(ownerEpoch!==epoch)return;body=await journal.pendingCreate(2);}catch{if(ownerEpoch===epoch){error=l('Could not save. Retry.');renderStatus();}return}if(ownerEpoch!==epoch)return;renderStatus();const value=await run(async()=>{try{return await request('',{method:'POST',body})}catch(err){if(err.status===400&&ownerEpoch===epoch)await journal.rejectCreate(body.id);throw err}});if(ownerEpoch!==epoch)return;if(value){accept(value);await journal.finishCreate(body.id);if(ownerEpoch!==epoch)return;syncForm();dialog.close();render();}else renderStatus();};
 const request=(path='',options={})=>api.request(root+path,{...options,csrf:session?.csrf_token});
 const policy=createPolicyPlayer({audio,getRecord:()=>record,getOwner:()=>session?.user?.id,persistStop:async pending=>{if(!record)return;record.pending_stop=pending;await journal.edit(record.id,{pending_stop:pending,playback:record.playback});},request,changed:()=>{if(!supportedPolicy(record))return;const key=JSON.stringify([record.id,record.mode,policyStep(record),record.playback?.whole_starts,!!record.playback?.active,record.playback?.final_used,record.playback?.revision,policy.waiting,policy.working]);if(key!==policyView){policyView=key;render()}else renderStatus();},failed:err=>{error=l(err?.status===409?'dictation.playback.conflict':'dictation.continue');if(err?.status===404&&record){const asset=record.plan[policyStep(record)]?.asset;record.ready=record.ready.filter(n=>n!==asset);error=l('Saved audio unavailable. Prepare it again.');}if(err?.status===401)unauthorized(err);renderStatus();}});
 function stop(){policy.stop();mediaEpoch++;playback=null;mediaAttempt=null;audio.pause();audio.removeAttribute('src');audio.load();flight?.abort();flight=null;}
 async function run(fn,sourceID=null,failureKey='Could not save. Retry.'){if(busy||!session)return null;const e=epoch;busy=true;error='';renderStatus();try{const v=await fn();return e===epoch?v:null;}catch(err){if(e===epoch&&err.name!=='AbortError'){error=l(err.status===429&&failureKey==='Audio preparation failed. Try again.'?(err.code==='speech_budget_exhausted'?'dictation.audio.limit':'dictation.audio.busy'):err.status===409?'conflict':failureKey);if(err.status===401)unauthorized(err);if(sourceID&&(err.status===404||err.status===409))await inspectConflict(sourceID);}return null;}finally{if(e===epoch){busy=false;flight=null;render();}}}
 function renderStatus(){renderSpend();header.hidden=!!record;updatePlayer();refresh.disabled=!session||busy||loading||hydrating;const draft=practice.querySelector('textarea');if(draft)draft.disabled=checking||(busy&&!record?.playback_policy_version)||!!record?.checked;notice.textContent=error||(busy?(flight?'':l('Working…')):loading||hydrating?l('Loading…'):!session?l('Sign in to use Diktat.'):'');add.disabled=!session||busy||hydrating;create.disabled=busy||hydrating;for(const control of [name,text,language])control.disabled=busy||hydrating||!!journal.createBody();}
 async function load(){if(!session||loading||record||hydrating)return;const e=epoch,readIDs=Object.keys(journal.entries());loading=true;render();try{const v=await request();if(e!==epoch)return;if(!Array.isArray(v?.items)||v.items.some(item=>!item||typeof item.id!=='string'||typeof item.title!=='string'))throw Error('invalid dictation history');items=v.items;speechSpend=v.speech_spend;loaded=true;error='';for(const id of readIDs){if(e!==epoch)return;if(!items.some(item=>item.id===id))await journal.recoverDeleted(id);}if(e!==epoch)return;if(record&&!journal.get(record.id)){record=null;conflict=null;}render();}catch(err){if(e===epoch){error=l('Could not save. Retry.');if(err.status===401)unauthorized(err);}}finally{if(e===epoch){loading=false;render();}}}
 async function save(){clearTimeout(timer);if(!record||record.checked||!session)return;const e=epoch,id=record.id;
  try{await journal.edit(id,record);if(e!==epoch)return;await journal.flush(id);if(e===epoch&&record?.id===id){record=journal.get(id);error='';renderStatus();}}
  catch(err){if(e===epoch){if(err.status===409||err.status===404)await inspectConflict(id);if(e!==epoch)throw err;if(err.status!==409&&err.status!==404)error=l('Not saved. Retry before leaving.');renderStatus();if(err.status===401)unauthorized(err);}throw err;}
 }
 async function inspectConflict(id){
  const e=epoch;try{const remote=await request('/'+id);if(e!==epoch||record?.id!==id)return;conflict={id,remote};error=l('conflict');render();}
  catch(err){if(e!==epoch)return;if(err.status===404){await journal.recoverDeleted(id);if(e!==epoch)return;if(record?.id===id)record=null;conflict=null;error=l('Deleted on another device. Your draft is available to export.');items=items.filter(item=>item.id!==id);render();}else if(err.status===401)unauthorized(err);}
 }
 function exportDraft(title,draft){const blob=new Blob([draft],{type:'text/plain;charset=utf-8'}),url=URL.createObjectURL(blob),link=el('a');link.href=url;link.download=(title||'dictation').replace(/[\\/:*?"<>|]/g,'_')+'.txt';document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
 async function transition(event){
  if(record?.pending_stop||record?.pending_pacing)return;
  if(supportedPolicy(record)&&event===record.mode)return;
  const e=epoch;
  if(supportedPolicy(record)){
   try{await policy.cancel()}catch(err){if(e===epoch){error=l('dictation.playback.conflict');renderStatus();}return;}
   if(e!==epoch||!record)return;
  }
  stop();record=practiceTransition(record,event);await journal.edit(record.id,record);
  if(e!==epoch)return;dirty++;render();try{await save();}catch{}
 }

 // The list DTO deliberately excludes drafts/source. Unchecked is not a job,
 // nor evidence that the learner has written anything. Omit that generic state.
 // Only the list summary knows the redacted draft. Missing/future fields stay
 // unknown; checked is the one authoritative legacy completion fallback.
 function libraryLifecycle(v){
  const stages=['added','ready','started','completed'];
  const current=v.checked?'completed':v.lifecycle_stage,index=stages.indexOf(current);
  if(index<0)return null;
  const track=el('span');track.className='dictation-lifecycle';
  stages.forEach((stage,i)=>{const step=el('span',l('dictation.lifecycle.'+stage));
   step.className='dictation-milestone '+(i===index?'is-current stage-'+stage:i<index?'is-earlier':'is-later');
   if(i===index)step.setAttribute('aria-current','step');
   track.append(step);
  });
  return track;
 }
 function libraryMetadata(v){
  const parts=[],lang=['de','en','ru','es','fr'].includes(locale())?locale():'en';
  if(Number.isSafeInteger(v.word_count)&&v.word_count>0)parts.push(l('dictation.words.'+new Intl.PluralRules(lang).select(v.word_count),{n:new Intl.NumberFormat(lang).format(v.word_count)}));
  if(Number.isFinite(v.audio_duration_seconds)&&v.audio_duration_seconds>0){const seconds=Math.max(1,Math.round(v.audio_duration_seconds));parts.push(`${Math.floor(seconds/60)}:${String(seconds%60).padStart(2,'0')}`);}

  return parts.join(' · ');
 }
 async function configurePacing(repeats=2,gap=3){
  if(busy||!record||policy.working||record.pending_stop)return;const e=epoch,id=record.id;
  stop();try{await save()}catch{return}if(e!==epoch||record?.id!==id)return;
  const body=record.pending_pacing||{revision:record.revision,playback_revision:record.playback?.revision||0,mutation_id:crypto.randomUUID(),repeats,gap_seconds:gap};
  try{await journal.edit(id,{pending_pacing:body})}catch{error=l('Could not save. Retry.');renderStatus();return}
  if(e!==epoch||record?.id!==id)return;
  const value=await run(()=>request('/'+id+'/pacing',{method:'POST',body}),id);
  if(e!==epoch||!value)return;
  await journal.edit(id,{pending_pacing:null,step:0});if(e!==epoch)return;
  const rebased=await journal.rebase(id,value);if(e!==epoch)return;record=rebased;render();
 }
 function pacingUI(v,panel){
  const phases=pacingPhases(v),timeline=el('ol');timeline.className='dictation-timeline';timeline.setAttribute('aria-label',l('pacing.plan'));panel.append(timeline);
  const label=p=>{const segment=v.plan[p.steps[0]];return l(p.kind==='whole'?'pacing.intro':p.kind==='final'?'Optional final reading':'pacing.fragment',{n:segment.sentence&&segment.fragment?`${segment.sentence}.${segment.fragment}`:p.fragment})};
  function update(){
   const step=policyStep(v),index=Math.max(0,phases.findIndex(p=>p.steps.includes(step))),next=pacingNeedsNext(v)&&!policy.waiting&&selectedManualStep!==v.id+':'+v.playback.cursor;
   const current=next?Math.max(0,index-1):index,groups=[...new Set(phases.map(p=>v.plan[p.steps[0]].sentence).filter(Boolean))];
   const group=v.plan[phases[current].steps[0]].sentence,start=group?groups.indexOf(group):current===0?0:Math.max(0,groups.length-2),visible=groups.slice(start,start+2);
   timeline.replaceChildren();let previous=null;
   phases.forEach((p,i)=>{
    const segment=v.plan[p.steps[0]],group=segment.sentence;
    if(p.fragment&&(group?!visible.includes(group):Math.abs(i-current)>2))return;
    const siblings=group?phases.filter(q=>v.plan[q.steps[0]].sentence===group):[],activeSibling=siblings.indexOf(phases[current]),first=Math.max(0,activeSibling-1),childIndex=siblings.indexOf(p);
    if(group&&(childIndex<first||childIndex>=first+5))return;
    if(group&&group!==previous){const heading=el('li',l('pacing.sentence',{n:group}));heading.className='dictation-sentence';timeline.append(heading);previous=group;}
    const row=el('li');row.className=(p.complete?'is-complete ':'')+(i===current?'is-current ':'')+(group?'dictation-fragment':'');
    const state=i===current?(v.pending_stop?l('pacing.stopPending'):next?l('pacing.writing'):v.playback?.active?.intent==='extra'?l('pacing.extra'):policy.waiting?l('pacing.gap',{n:v.pacing.gap_seconds}):p.fragment?l('pacing.repeat',{n:p.steps.indexOf(step)+1,total:p.steps.length}):l('pacing.current')):l(p.complete?'pacing.completed':'pacing.upcoming');
    row.textContent=(p.complete?'✓ ':'')+label(p);row.setAttribute('aria-label',label(p)+' · '+state);
    if(i===current){row.setAttribute('aria-current','step');const status=el('span',' · '+state);status.className='dictation-now';row.append(status)}
    timeline.append(row);
   });
  }
  update();return update;
 }
 function render(){const focused=practice.contains(document.activeElement)&&document.activeElement.tagName==='TEXTAREA', selection=focused?[document.activeElement.selectionStart,document.activeElement.selectionEnd]:null;renderStatus();list.replaceChildren();practice.replaceChildren();list.hidden=!!record;practice.hidden=!record;
  if(!record){
   activeAttemptMenu=null;
   if(session&&error&&!hydrating)list.append(refresh);
   const savedForm=journal.form(),hasCreation=!!(savedForm.title||savedForm.text||journal.createBody());
   if(session&&loaded&&!items.length&&!loading&&!hydrating&&!error&&!Object.keys(journal.entries()).length&&!Object.keys(journal.recoveries()).length&&!hasCreation)list.append(el('p',l('No dictations yet.')),el('p',l('dictation.onboarding')),button(l('Add text'),openAdd));
   if(session&&!hydrating&&hasCreation){const resume=button((savedForm.title?savedForm.title+' · ':'')+l('Draft'),openAdd);resume.disabled=busy;list.append(resume);}
   for(const [id,recovery] of Object.entries(journal.recoveries())){const row=el('div');row.append(el('p',l('Deleted on another device. Your draft is available to export.')+' '+recovery.title),button(l('Export draft'),()=>exportDraft(recovery.title,recovery.draft)),button(l('Dismiss recovery'),async()=>{const e=epoch;await journal.clearRecovery(id);if(e===epoch)render();}));list.append(row);}for(const v of items){const row=button('',async()=>{const e=epoch,cached=journal.get(v.id);if(cached){record=cached;render();}const result=await run(()=>request('/'+v.id));if(e!==epoch)return;if(result){accept(result);render();}else if(record?.id===v.id)await inspectConflict(v.id);});row.className='dictation-card';row.append(el('strong',v.title));const metadata=libraryMetadata(v);if(metadata)row.append(el('small',metadata));const lifecycle=libraryLifecycle(v);if(lifecycle)row.append(lifecycle);list.append(row);}return;}
  const v=record;const back=button(l('History'),async()=>{if(busy)return;const e=epoch;stop();try{await save();}catch{return}if(e!==epoch)return;record=null;await load();render();});back.className='dictation-back';back.setAttribute('aria-label',l('History'));practice.append(back);const heading=el('div');heading.className='dictation-heading';heading.append(el('h1',v.title));practice.append(heading);
  const again=button(l('New attempt'),async()=>{if(busy)return;const e=epoch;stop();try{await save();}catch{return}if(e!==epoch)return;let id;try{id=await journal.reserveAttempt(v.id,2)}catch{if(e===epoch){error=l('Could not save. Retry.');renderStatus()}return}if(e!==epoch)return;const value=await run(()=>request('/'+v.id+'/attempts',{method:'POST',body:{id,...(journal.attemptPolicy(v.id)?{playback_policy_version:journal.attemptPolicy(v.id)}:{})}}),v.id);if(e!==epoch)return;if(value){await journal.clearAttempt(v.id);if(e!==epoch)return;accept(value);render();}});
  const remove=button(l('Delete attempt'),async()=>{if(busy)return;if(!confirm(l('Delete this attempt and its draft?')))return;const e=epoch;stop();try{await save();}catch{return}if(e!==epoch)return;const value=await run(()=>request('/'+v.id,{method:'DELETE',body:{revision:record.revision}}),v.id);if(e!==epoch)return;if(value){await journal.remove(v.id);if(e!==epoch)return;record=null;await load();if(e===epoch)render();}});again.disabled=remove.disabled=busy;const attemptMenu=el('details'),attemptSummary=el('summary','•••');activeAttemptMenu=attemptMenu;attemptMenu.className='dictation-attempt-menu';attemptSummary.setAttribute('aria-label',l('More options'));attemptMenu.append(attemptSummary);if(!v.checked)attemptMenu.append(again);attemptMenu.append(remove);attemptMenu.onkeydown=e=>{if(e.key==='Escape'){attemptMenu.open=false;attemptSummary.focus();}};attemptMenu.onfocusout=e=>{if(e.relatedTarget&&!attemptMenu.contains(e.relatedTarget))attemptMenu.open=false;};heading.append(attemptMenu);attemptMenu.addEventListener('change',()=>{attemptMenu.open=false});
  if(conflict?.id===v.id){const panel=el('div');panel.className='dictation-conflict';panel.append(el('h3',l('Resolve conflict')),el('p',l('Compare your draft with the server version.')));const compare=el('div');compare.className='dictation-compare';for(const [label,value] of [[l('Your draft'),v.draft],[l('Server draft'),conflict.remote.draft]]){const column=el('div');column.append(el('strong',label),el('pre',value));compare.append(column);}panel.append(compare,button(l('Rebase and retry'),async()=>{const e=epoch,rebased=await journal.rebase(v.id,conflict.remote);if(e!==epoch)return;record=rebased;conflict=null;render();try{await save();}catch{}}),button(l('Use server version'),async()=>{const e=epoch,server=await journal.useServer(v.id,conflict.remote);if(e!==epoch)return;record=server;conflict=null;error='';render();}),button(l('Export draft'),()=>exportDraft(v.title,v.draft)));panel.querySelector('button').disabled=!!conflict.remote.checked;practice.append(panel);}
  if(v.assisted)practice.append(el('small',l('With hint · assisted')));
  const modes=el('div');modes.className='dictation-modes';modes.setAttribute('role','group');modes.setAttribute('aria-label',l('Practice mode'));for(const [key,label]of [['whole','Whole text'],['sentences','By sentences']]){const b=button(l(label),()=>{if(!busy)void transition(key)});b.setAttribute('aria-pressed',String(v.mode===key));b.disabled=v.checked||busy;modes.append(b);}attemptMenu.append(modes);
  const segment=v.plan[supportedPolicy(v)?policyStep(v):v.mode==='whole'?0:v.step];
  const stage={whole:'Listen, then write',sentence:'Listen to the sentence',chunk:'Listen to this part',sentence_repeat:'Listen to the sentence again',final:'Optional final reading'};
  const panel=el('div');panel.className='dictation-work';panel.setAttribute('aria-label',l(v.mode==='whole'?'Whole text':'By sentences'));practice.append(panel);
  const hint=el('aside');hint.className='dictation-hint';hint.id='dictation-mode-hint';hint.setAttribute('aria-label',l('Hint'));hint.append(el('p',l((v.playback_policy_version===2&&v.mode==='sentences'?'pacing.hint':(supportedPolicy(v)?'dictation.policy.hint.':'dictation.hint.')+v.mode),{n:v.pacing?.repeats})));if(!v.checked&&v.playback_policy_version!==2)panel.append(hint);
  const instruction=el('p',v.checked?l('Checked'):l(stage[segment.kind]));instruction.className='dictation-step';if(v.checked||(v.mode==='sentences'&&v.playback_policy_version!==2))panel.append(instruction);
  if(v.mode==='sentences'&&v.playback_policy_version!==2)panel.append(el('small',l(supportedPolicy(v)?'dictation.policy.step':'step',{n:supportedPolicy(v)?policyStep(v):v.step+1,total:supportedPolicy(v)?v.plan.length-1:v.plan.length})));
  const updatePacing=v.playback_policy_version===2&&v.mode==='sentences'?pacingUI(v,panel):()=>{};
  if(!v.checked&&!v.playback?.active){
   if(v.playback_policy_version!==2){const upgrade=button(l('pacing.upgrade'),()=>configurePacing());upgrade.disabled=busy;attemptMenu.append(upgrade);}
   else if(!v.playback?.listens?.length){const settings=el('div');settings.className='dictation-pacing-settings';const repeats=el('select');repeats.setAttribute('aria-label',l('pacing.repeats'));for(const n of [2,3]){const option=el('option',l('pacing.times',{n}));option.value=n;option.selected=n===v.pacing.repeats;repeats.append(option)}const label=el('label'),long=el('input');long.type='checkbox';long.checked=v.pacing.gap_seconds===8;long.disabled=repeats.disabled=busy;label.append(long,el('span',l('pacing.long')));repeats.onchange=()=>configurePacing(Number(repeats.value),long.checked?8:3);long.onchange=()=>configurePacing(Number(repeats.value),long.checked?8:3);settings.append(repeats,label);attemptMenu.append(settings);}
   if(v.pending_pacing)attemptMenu.append(button(l('pacing.retry'),()=>configurePacing()));
  }
  const cached=v.playback_policy_version===2?v.ready.includes(segment.asset):supportedPolicy(v)?policyAssets(v).every(asset=>v.ready.includes(asset)):v.ready.includes(segment.asset),controls=el('div');controls.className='dictation-player';
  const action=button('',async event=>{
   if(busy||event?.detail>1)return;
   if(v.playback_policy_version===2&&(record.pending_stop||policy.active)){await policy.explicitStop();return}
   if(v.playback_policy_version===2&&pacingNeedsNext(v)&&!cached&&selectedManualStep!==v.id+':'+v.playback.cursor){selectedManualStep=v.id+':'+v.playback.cursor;render();return}
   if(supportedPolicy(v)){if(cached){error='';await policy.play();return}const id=v.id,assets=policyAssets(v).filter(asset=>!v.ready.includes(asset));flight=new AbortController();const signal=flight.signal;await run(async()=>{for(const index of assets){await request(`/${id}/audio/${index}`,{method:'POST',body:{},signal});if(record?.id===id)record.ready=[...new Set([...record.ready,index])];}return true},null,'Audio preparation failed. Try again.');void refreshSpend();render();return;}
   if(!cached){const id=v.id,index=segment.asset;flight=new AbortController();const signal=flight.signal;const value=await run(()=>request(`/${id}/audio/${index}`,{method:'POST',body:{},signal}),null,'Audio preparation failed. Try again.');if(value&&record?.id===id){record.ready=[...new Set([...record.ready,index])];render();}return;}
   if(!audio.paused&&playback?.id===v.id){audio.pause();updatePlayer();return;}
   const e=epoch,id=v.id;const mediaTicket=++mediaEpoch;const same=mediaAttempt?.id===id&&mediaAttempt?.asset===segment.asset;
   mediaAttempt=playback={id,epoch:e,asset:segment.asset};if(!same||audio.ended)audio.src=root+'/'+v.id+'/audio/'+segment.asset;audio.playbackRate=Number(speed.value);
   try{await audio.play();if(e!==epoch||record?.id!==id)stop();else updatePlayer();}catch{if(e===epoch&&mediaTicket===mediaEpoch&&playback&&record?.id===id){playback=null;error=l('Playback did not start. Tap Play again.');renderStatus();}}
  });
  const speed=el('select');for(const n of [.75,1,1.25]){const o=el('option',n+'×');o.value=n;o.selected=n===audio.playbackRate;speed.append(o)}speed.setAttribute('aria-label',l('Playback speed'));speed.onchange=()=>audio.playbackRate=Number(speed.value);
  controls.append(action);attemptMenu.append(speed);panel.append(controls);
  let extraReplay=null;
  if(v.playback_policy_version===2&&v.mode==='sentences'&&!v.checked){const completed=pacingPhases(v).filter(p=>p.fragment&&p.complete&&p.steps.at(-1)<v.playback.cursor).at(-1);if(completed){extraReplay=button(l('Replay'),async()=>{if(busy||policy.working||policy.active||record.pending_stop)return;await policy.play(completed.steps[0])});extraReplay.className='dictation-extra-replay';extraReplay.setAttribute('aria-label',l('pacing.extraReplay'));}}
  const cancelAudio=button(l('Cancel'),()=>{flight?.abort();stop();updatePlayer();});cancelAudio.setAttribute('aria-label',l('Cancel preparation'));cancelAudio.className='dictation-cancel';controls.append(cancelAudio);
  const disclosure=el('details');disclosure.className='dictation-disclosure';const audioInfo=el('summary'),infoIcon=el('span','ⓘ');audioInfo.setAttribute('aria-label',l('Audio details'));infoIcon.setAttribute('aria-hidden','true');audioInfo.append(infoIcon);disclosure.append(audioInfo,el('p',l('dictation.paid.notice')),el('p',l('dictation.budget.notice')));if(v.mode==='whole'&&!supportedPolicy(v))disclosure.append(el('p',l('readings',{n:v.replays})));attemptMenu.append(disclosure);
  if(!supportedPolicy(v)&&!v.checked&&v.mode==='sentences'&&v.step<v.plan.length-1){const next=button(l('Next'),()=>{if(!busy)void transition('next')});next.className='dictation-next';panel.append(next);}
  const draft=el('textarea');draft.rows=4;draft.value=v.draft;draft.maxLength=2400;draft.spellcheck=false;draft.autocomplete='off';draft.setAttribute('aria-label',l('What you heard'));if(supportedPolicy(v)){const progress=el('p');progress.className='dictation-playback-status';progress.setAttribute('role','status');const count=v.playback?.whole_starts||0;progress.textContent=l('dictation.listens',{n:count,total:4});if(!v.playback?.active&&count>=4)progress.textContent+=' · '+l('dictation.limit');(v.playback_policy_version===2&&count<4?disclosure:panel).append(progress);const stamp=el('small');const stampTime=()=>{const seconds=Math.floor(audio.currentTime||0),duration=Math.floor(audio.duration||0);stamp.textContent=`${Math.floor(seconds/60)}:${String(seconds%60).padStart(2,'0')} / ${Math.floor(duration/60)}:${String(duration%60).padStart(2,'0')}`;};stampTime();audio.ontimeupdate=stampTime;(v.playback_policy_version===2?disclosure:panel).append(stamp);}
  if(!v.checked&&v.playback_policy_version!==2)draft.setAttribute('aria-describedby',hint.id);draft.disabled=checking||v.checked||(busy&&!v.playback_policy_version);
  const check=button(l('Check'),async()=>{if(busy||checking||!record.draft.trim())return;const e=epoch,complete=completeAttempts.get(v.id)===true;checking=true;renderStatus();stop();try{await save();}catch{if(e===epoch){checking=false;renderStatus();}return}if(e!==epoch)return;
   const revision=record.revision;let reading=false;
   const poll=setInterval(async()=>{if(reading||e!==epoch)return;reading=true;try{await recoverAssessment(v.id,e)}finally{reading=false}},700);
   try{const value=await run(()=>request('/'+v.id+'/check',{method:'POST',body:{revision,hybrid:true,complete,locale:locale()}}),v.id);if(value){accept(value);render();}else if(e===epoch)await recoverAssessment(v.id,e);}finally{clearInterval(poll);if(e===epoch){checking=false;renderStatus();}}
  });
  updatePlayer=()=>{if(record?.id!==v.id)return;updatePacing();if(extraReplay)extraReplay.disabled=busy||policy.working||policy.active||!!record.pending_stop;const preparing=busy&&!!flight;action.textContent=l(preparing?'Preparing audio…':!cached?'Prepare audio':!audio.paused&&playback?.id===v.id?'Pause':audio.ended&&mediaAttempt?.id===v.id&&mediaAttempt?.asset===segment.asset?'Replay':'Play');if(supportedPolicy(v)){const active=v.playback?.active;action.textContent=l(preparing?'Preparing audio…':!cached?'Prepare audio':policy.waiting?'dictation.pause':!audio.paused?'dictation.listening':active?'dictation.resume':segment.kind==='final'?'Optional final reading':'Play');action.disabled=v.checked||busy||policy.working||policy.waiting||!audio.paused||(!active&&((policyStep(v)===0||segment.kind==='final')&&v.playback?.whole_starts>=4||segment.kind==='final'&&v.playback?.final_used));}else action.disabled=busy;if(v.playback_policy_version===2){const stopping=record.pending_stop||policy.active;action.textContent=l(stopping?(record.pending_stop?'pacing.retryStop':'Stop'):preparing?'Preparing audio…':pacingNeedsNext(v)&&selectedManualStep!==v.id+':'+v.playback.cursor?'Next':!cached?'Prepare audio':v.playback?.active?'dictation.resume':segment.kind==='final'?'Optional final reading':'Play');if(stopping)action.disabled=busy||policy.stopping;action.disabled=action.disabled||!!record.pending_pacing;}action.setAttribute('aria-busy',String(preparing));action.className=(v.playback_policy_version===2||!record?.draft?.trim())&&!v.checked?'dictation-primary':'';cancelAudio.hidden=!preparing;speed.hidden=preparing;speed.disabled=busy;back.disabled=again.disabled=remove.disabled=reveal.disabled=busy;for(const b of modes.children)b.disabled=busy||v.checked||!!record.pending_stop||!!record.pending_pacing||(supportedPolicy(v)&&policy.working);check.disabled=checking||busy||!!record?.pending_stop||!!record?.pending_pacing||!record?.draft?.trim();check.className=record?.draft?.trim()?'dictation-primary':'';};
  draft.oninput=()=>{record.draft=draft.value;updatePlayer();void journal.edit(record.id,{draft:draft.value}).catch(()=>{error=l('Could not save. Retry.');renderStatus();});dirty++;clearTimeout(timer);timer=setTimeout(()=>save().catch(()=>{}),500)};const inputHeader=el('div');inputHeader.className='dictation-input-header';panel.append(draft);if(!v.checked){const completeLabel=el('label'),complete=el('input');complete.type='checkbox';complete.checked=completeAttempts.get(v.id)===true;complete.onchange=()=>completeAttempts.set(v.id,complete.checked);completeLabel.className='dictation-complete-choice';completeLabel.append(complete,el('span',l('assessment.finished')));if(extraReplay)attemptMenu.append(extraReplay);inputHeader.append(check);attemptMenu.append(completeLabel);panel.append(inputHeader);const checkInfo=el('details');checkInfo.className='dictation-assessment-context';checkInfo.append(el('summary',l('assessment.context')),el('p',l('assessment.budget')));attemptMenu.append(checkInfo);}
  const actions=el('div');actions.className='dictation-answer-actions';
  const reveal=button(l('Show original'),async()=>{if(busy)return;const focused=attemptMenu.contains(document.activeElement),restoreFocus=()=>{if(focused)activeAttemptMenu?.querySelector('summary')?.focus({preventScroll:true});};if(v.checked){originalVisible=v.id;render();restoreFocus();return;}if(!confirm(l('Showing the original counts as help for this attempt. Continue?')))return;const e=epoch;try{await save();}catch{return}if(e!==epoch)return;const value=await run(()=>request('/'+v.id+'/reveal',{method:'POST',body:{revision:record.revision}}),v.id);if(value){accept(value);originalVisible=v.id;render();}if(e===epoch&&record?.id===v.id)restoreFocus();});
  if(!(v.text&&(v.assisted||originalVisible===v.id)))attemptMenu.append(reveal);panel.append(actions);
  if(v.text&&(v.assisted||originalVisible===v.id)){const original=el('pre',v.text);original.className='dictation-original';panel.append(el('h3',l('Original')),original);}
  updatePlayer();
  if(v.checked){
   if(v.assessment?.alignment){practice.append(renderAssessment(v.assessment,{l,refresh:()=>recoverAssessment(v.id),cancel:async()=>{const e=epoch;try{await request('/'+v.id+'/cancel-assessment',{method:'POST',body:{revision:v.assessment.revision}});if(e===epoch)await recoverAssessment(v.id,e);}catch(err){if(e===epoch){error=l('Could not save. Retry.');renderStatus();if(err.status===401)unauthorized(err);}}}}));}
   else{practice.append(el('p',l('Exact text comparison, not a language-level assessment.')));if(!v.differences?.length)practice.append(el('p',l('Matches the original.')));for(const kind of ['missing','extra','substitution','case','punctuation']){const group=(v.differences||[]).filter(d=>d.kind===kind);if(!group.length)continue;const details=el('details');details.append(el('summary',`${l(kind)} · ${group.length}`),el('p',group.map(d=>`${d.original||'—'} → ${d.written||'—'}`).join(' · ')));practice.append(details);}}
   again.className='dictation-primary';practice.append(again);
  }
  if(focused&&!draft.disabled){draft.focus({preventScroll:true});draft.setSelectionRange(...selection);}
 }
 audio.onended=()=>{if(supportedPolicy(record)){void policy.ended();return;}if(!record||!playback||playback.epoch!==epoch||playback.id!==record.id||playback.asset!==(record.plan[record.mode==='whole'?0:record.step]?.asset))return;playback=null;record=practiceTransition(record,'ended');void journal.edit(record.id,record);dirty++;save().catch(()=>{});render();};audio.onerror=async()=>{
  if(supportedPolicy(record)){if(!policy.ownsMedia||!audio.error)return;const e=epoch,id=record.id,asset=record.plan[policyStep(record)]?.asset;policy.interrupted(Error('media error'));try{await request(`/${id}/audio/${asset}`,{method:'HEAD'})}catch(err){if(e!==epoch||record?.id!==id)return;if(err.status===401)unauthorized(err);else if(err.status===404){record.ready=record.ready.filter(n=>n!==asset);error=l('Saved audio unavailable. Prepare it again.');render();}}return;}
  const failed=mediaAttempt,mediaTicket=mediaEpoch,src=audio.getAttribute('src');
  if(!failed||failed.epoch!==epoch||failed.id!==record?.id||!src)return;
  mediaAttempt=null;playback=null;error=l('Audio unavailable. Try playing again.');renderStatus();
  // Media elements hide HTTP status. Probe only after failure, preserving the
  // original click's direct src/play path; HEAD never prepares or retries audio.
  try{await request('/'+failed.id+'/audio/'+failed.asset,{method:'HEAD'});}
  catch(err){if(failed.epoch!==epoch||mediaTicket!==mediaEpoch||failed.id!==record?.id||src!==audio.getAttribute('src'))return;if(err.status===401)unauthorized(err);else if(err.status===404){record.ready=record.ready.filter(asset=>asset!==failed.asset);error=l('Saved audio unavailable. Prepare it again.');render();}}
 };
 document.addEventListener('visibilitychange',()=>{if(document.hidden){policy.stop();audio.pause();playback=null;save().catch(()=>{});}});
 syncForm();render();return {identity(value){const next=value?.user?.id?value:null;const changed=session?.user?.id!==next?.user?.id;if(changed){epoch++;checking=false;completeAttempts.clear();originalVisible=null;stop();void cache.clear();lease=null;journal.reset();clearTimeout(timer);items=[];speechSpend=null;selectedManualStep=null;record=null;busy=false;loading=false;loaded=false;hydrating=false;error='';conflict=null;syncForm();dialog.close();}session=next;if(changed&&next){hydrating=true;lease=cache.open(next);const e=epoch;lease.load().then(value=>{if(e!==epoch)return;if(value){journal.restore(value);syncForm();items=Object.values(value.entries).map(v=>v.local);}hydrating=false;}).catch(()=>{if(e===epoch)error=l('Could not save. Retry.');}).finally(()=>{if(e===epoch){render();if(!hydrating&&!host.hidden)void load();}});}if(changed)render();else renderStatus();if(!host.hidden&&!record)void load();},route(){if(host.hidden){policy.stop();audio.pause();playback=null;save().catch(()=>{});}else if(!record)void load();},localize(){localizeStatic();render();}};
}
