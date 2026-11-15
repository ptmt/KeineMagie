// All mutations are committed to storage before transport. A pending body is
// immutable until acknowledged or explicitly rebased by the learner.
export function createDraftJournal({persist,send}) {
 let entries={},form={id:crypto.randomUUID(),title:'',text:'',language:'de'},pending=null,attempts={},recoveries={},epoch=0,revision=0,queue=Promise.resolve();
 const flights=new Map(),copy=v=>structuredClone(v);
 const snapshot=()=>({entries:copy(entries),form:copy(form),pendingCreate:copy(pending),attempts:copy(attempts),recoveries:copy(recoveries),revision:++revision});
 function durable(){const value=snapshot(),e=epoch;queue=queue.catch(()=>{}).then(()=>e===epoch?persist(value):undefined);return queue;}
 const fields=v=>({mode:v.mode,step:v.step,replays:v.replays,draft:v.draft});
 const same=(a,b)=>JSON.stringify(fields(a))===JSON.stringify(fields(b));
 return {
  get:id=>entries[id]?.local,
  entry:id=>entries[id]&&copy(entries[id]),
  entries:()=>copy(entries),
  recoveries:()=>copy(recoveries),
  form:()=>copy(form),
  createBody:()=>copy(pending),
  attempt:source=>attempts[source],
  snapshot:()=>copy({entries,form,pendingCreate:pending,attempts,recoveries,revision}),
  restore(value){entries=copy(value?.entries||{});form=copy(value?.form||form);pending=copy(value?.pendingCreate||null);attempts=copy(value?.attempts||{});recoveries=copy(value?.recoveries||{});revision=value?.revision||0;},
  reset(){epoch++;entries={};form={id:crypto.randomUUID(),title:'',text:'',language:'de'};pending=null;attempts={};recoveries={};revision=0;flights.clear();},
  accept(value){const old=entries[value.id];if(old&&(old.pending||!same(old.local,old.ack)))return old.local;entries[value.id]={ack:copy(value),local:copy(value),pending:null};return entries[value.id].local;},
  async edit(id,change){if(!entries[id])throw Error('missing draft');Object.assign(entries[id].local,change);await durable();},
  async remove(id){delete entries[id];await durable();},
  async editForm(change){if(pending)throw Error('create pending');Object.assign(form,change);await durable();},
  async pendingCreate(){if(!pending)pending=copy(form);await durable();return copy(pending);},
  async finishCreate(id){if(pending?.id!==id)return;pending=null;form={id:crypto.randomUUID(),title:'',text:'',language:'de'};await durable();},
  async rejectCreate(id){if(pending?.id!==id)return;pending=null;form={...form,id:crypto.randomUUID()};await durable();},
  async clearForm(){pending=null;form={id:crypto.randomUUID(),title:'',text:'',language:'de'};await durable();},
  async reserveAttempt(source){if(!attempts[source])attempts[source]=crypto.randomUUID();await durable();return attempts[source];},
  async clearAttempt(source){delete attempts[source];await durable();},
  async rebase(id,server){const entry=entries[id];if(!entry)throw Error('missing draft');entry.ack=copy(server);entry.local={...copy(server),...fields(entry.local),revision:server.revision};entry.pending=null;await durable();return entry.local;},
  async useServer(id,server){entries[id]={ack:copy(server),local:copy(server),pending:null};await durable();return entries[id].local;},
  async recoverDeleted(id){const entry=entries[id];if(!entry)return;recoveries[id]={title:entry.local.title,draft:entry.local.draft,sourceId:id};delete entries[id];await durable();},
  async clearRecovery(id){delete recoveries[id];await durable();},
  persist:durable,
  flush(id){
   if(flights.has(id))return flights.get(id);
   const e=epoch;
   const work=(async()=>{
    while(e===epoch){
     const entry=entries[id];if(!entry||entry.local.checked)return;
     if(!entry.pending&&same(entry.local,entry.ack))return;
     if(!entry.pending)entry.pending={...fields(entry.local),revision:entry.ack.revision,mutation_id:crypto.randomUUID()};
     const body=copy(entry.pending);await durable();if(e!==epoch)return;
     const result=await send(id,body);if(e!==epoch)return;
     entry.ack=copy(result);entry.local.revision=result.revision;entry.pending=null;
     await durable();
    }
   })();
   flights.set(id,work);work.finally(()=>{if(e===epoch)flights.delete(id)}).catch(()=>{});return work;
  }
 };
}
