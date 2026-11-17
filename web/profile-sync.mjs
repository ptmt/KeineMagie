// Owner/origin-scoped, persist-before-send profile journal. No provider calls.
const validID=id=>typeof id==='string'&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(id);
const validText=(s,n)=>typeof s==='string'&&s.trim()&&[...s].length<=n&&!/[\uD800-\uDFFF]/u.test(s);
const uuid=()=>crypto.randomUUID().toUpperCase();
export function readLegacyProfiles(storage,owner) {
 if(!owner)throw Error('Verified owner required');
 const raw=storage.getItem(`keinemagie:translation-prompts:v1:${encodeURIComponent(owner)}`);
 if(raw===null)return [];
 const values=JSON.parse(raw);
 if(!Array.isArray(values)||values.some(v=>!v||typeof v.id!=='string'||!/^custom-[A-Za-z0-9-]+$/.test(v.id)||!validText(v.name,60)||!validText(v.instructions,1000)))throw Error('Unreadable legacy profiles');
 return values.map(({id,name,instructions})=>({id,name,instructions}));
}
export async function legacyProfileID(item) {
 const encoder=new TextEncoder();
 const text=[item.id,item.name,item.instructions].map(s=>`${encoder.encode(s).length}:${s}`).join('');
 const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(text))),b=>b.toString(16).padStart(2,'0')).join('').slice(0,32).toUpperCase();
 return `${hash.slice(0,8)}-${hash.slice(8,12)}-${hash.slice(12,16)}-${hash.slice(16,20)}-${hash.slice(20)}`;
}
export function createProfileSync({storage,owner,origin,legacy,request,changed=()=>{},unauthorized=()=>{}}) {
 if(!owner||!origin)throw Error('Verified owner and origin required');
 const key=`keinemagie:profile-sync:v1:${encodeURIComponent(origin)}:${encodeURIComponent(owner)}`;
 let state={revision:0,items:[],pending:[],migrated:false},active=true,flight=null,issue=null,initialized=false;
 const raw=storage.getItem(key);
 if(raw){state=JSON.parse(raw);if(!Array.isArray(state.items)||!Array.isArray(state.pending)||typeof state.migrated!=='boolean')throw Error('Unreadable profile journal');}
 const commit=next=>{storage.setItem(key,JSON.stringify(next));state=next;};
 const list=()=>{
  const items=state.items.map(x=>({...x}));
  for(const op of state.pending){const i=items.findIndex(v=>v.id===op.body.id);const item={id:op.body.id,title:op.body.title,instruction:op.body.instruction,revision:op.body.base_revision,deleted:op.method==='DELETE'};if(i<0)items.push(item);else items[i]=item;}
  return items.filter(x=>!x.deleted).map(x=>({id:x.id,name:x.title,instructions:x.instruction}));
 };
 const enqueue=(method,item,expectedRevision)=>{
  if(!active||!initialized)throw Error('Profile storage not ready');
  if(!validID(item.id)||method!=='DELETE'&&(!validText(item.name,60)||!validText(item.instructions,1000)))throw Error('Invalid profile');
  const base=expectedRevision ?? state.items.find(v=>v.id===item.id)?.revision ?? 0;
  const body={operation_id:uuid(),id:item.id,base_revision:base,...(method==='DELETE'?{}:{title:item.name,instruction:item.instructions})};
  commit({...state,pending:[...state.pending,{method,body}]});changed();return item;
 };
 const validate=value=>{
  if(!Number.isSafeInteger(value?.revision)||value.revision<0||!Array.isArray(value.items)||value.items.some(x=>!validID(x.id)||!Number.isSafeInteger(x.revision)||typeof x.deleted!=='boolean'||!x.deleted&&(!validText(x.title,60)||!validText(x.instruction,1000)))||new Set(value.items.map(x=>x.id)).size!==value.items.length)throw Error('Invalid profile response');
  return value;
 };
 const ready=(async()=>{
  if(state.migrated){initialized=true;return;}
  const pending=[...state.pending];
  for(const item of legacy()){
   const id=await legacyProfileID(item);if(!active)return;
   if(pending.some(op=>op.body.operation_id===`import-${id}`))continue;
   pending.push({method:'PUT',body:{operation_id:`import-${id}`,id,base_revision:0,title:item.name,instruction:item.instructions}});
  }
  if(active){commit({...state,pending,migrated:true});initialized=true;changed();}
 })();
 const sync=()=>{
  if(flight)return flight;
  flight=(async()=>{
   await ready;if(!active)return;
   try {
    // One flight serializes reads and writes; pending overlays survive old GETs.
    const value=validate(await request('GET'));
    if(!active)return;
    if(value.revision>=state.revision)commit({...state,revision:value.revision,items:value.items});
    while(active&&state.pending.length){
     // A blocked create must not prevent deletion of an independent existing
     // profile to free capacity. Never move a delete ahead of its own edits.
     if(state.pending[0].conflict || state.pending[0].blocked){
      const index=state.pending.findIndex((v,i)=>v.method==='DELETE'&&!state.pending.slice(0,i).some(p=>p.body.id===v.body.id));
      if(index>0)commit({...state,pending:[state.pending[index],...state.pending.filter((_,i)=>i!==index)]});
     }
     if(state.pending[0].conflict){issue='conflict';changed();return;}
     const op=state.pending[0];
     const result=validate(await request(op.method,op.body));if(!active)return;
     if(!result.items.some(v=>v.id===op.body.id&&v.revision>op.body.base_revision))throw Error('Missing profile acknowledgement');
     const pending=state.pending.slice(1).map(v=>({...v,body:{...v.body}}));
     // Rebase only dependent edits authored on THIS device before the create/edit
     // acknowledged. Never rebase a first operation over a remote revision.
     const current=result.items.find(v=>v.id===op.body.id);
     const next=pending.find(v=>v.body.id===op.body.id);
     // Replay returns the latest snapshot, not necessarily our write. Never
     // rebase a queued local edit across a different remote value/tombstone.
     if(next&&current&&!current.deleted&&current.title===op.body.title&&current.instruction===op.body.instruction){next.body.base_revision=current.revision;if(next.method==='PUT')next.method='PATCH';}
     commit({...state,revision:result.revision,items:result.items,pending});
    }
    issue=null;
   }catch(error){
    if(!active)return;
    if(error.status===401){api.purge();unauthorized();return;}
    if(error.status===409&&state.pending.length){commit({...state,pending:state.pending.map((v,i)=>i?v:{...v,conflict:true})});issue='conflict';}
    else if(error.status===422&&state.pending.length){commit({...state,pending:state.pending.map((v,i)=>i?v:{...v,blocked:'limit'})});issue='limit';}
    else issue=[404,405].includes(error.status)?'unsupported':'offline';
   }finally{if(active)changed();}
  })().finally(()=>{flight=null;});return flight;
 };
 const api={ready,list,sync,get pendingCount(){return state.pending.length},get issue(){return issue},
  revision(id){return state.items.find(v=>v.id===id)?.revision ?? 0},
  save(item,expectedRevision){return enqueue(state.items.some(v=>v.id===item.id)||state.pending.some(v=>v.body.id===item.id)?'PATCH':'PUT',item,expectedRevision)},
  remove(id,expectedRevision){enqueue('DELETE',{id},expectedRevision)},
  resolveConflict(copy){
   const op=state.pending[0];if(!op?.conflict)return;
   const pending=state.pending.slice(1).filter(v=>v.body.id!==op.body.id);
   if(copy&&op.method!=='DELETE'){
    // Preserve the latest pending local version as a distinct new record.
    const latest=[...state.pending].reverse().find(v=>v.body.id===op.body.id);
    if(latest.method!=='DELETE')pending.unshift({method:'PUT',body:{...latest.body,operation_id:uuid(),id:uuid(),base_revision:0}});
   }
   commit({...state,pending});issue=null;changed();return sync();
  },
  stop(){active=false},purge(){active=false;storage.removeItem(key);state={revision:0,items:[],pending:[],migrated:false};issue=null;}
 };
 return api;
}
