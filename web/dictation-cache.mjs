// IndexedDB is never identity authority. Only a server-validated session can open
// a cache; a fresh offline browser cannot unlock another account's persisted data.
export function createOwnerDraftCache(storage){
 let epoch=0,current=null,queue=Promise.resolve();
 function enqueue(fn){queue=queue.catch(()=>{}).then(fn);return queue;}
 return {
  open(session){if(!session?.user?.id||!session.csrf_token)throw Error('validated session required');
   const e=++epoch,key='dictation:'+session.user.id;current=key;let revision=-1,readFailed=false;
   return {load:()=>enqueue(async()=>{if(e!==epoch)return;try{const value=await storage.get(key);readFailed=false;return value;}catch(error){readFailed=true;throw error;}}),save:value=>enqueue(async()=>{if(e!==epoch)return;if(readFailed)throw Error('draft hydration failed');if(value.revision<=revision)return;await storage.set(key,structuredClone(value));revision=value.revision;})};
  },
  clear(){const key=current;++epoch;current=null;return enqueue(()=>key?storage.delete(key):undefined);}
 };
}
export function indexedDraftStorage(){
 let opened;
 function db(){return opened??=new Promise((resolve,reject)=>{const r=indexedDB.open('keinemagie-dictation',1);r.onupgradeneeded=()=>r.result.createObjectStore('drafts');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});}
 async function tx(mode,action){const d=await db();return new Promise((resolve,reject)=>{const t=d.transaction('drafts',mode),request=action(t.objectStore('drafts'));t.oncomplete=()=>resolve(request.result);t.onerror=()=>reject(t.error);t.onabort=()=>reject(t.error||Error('cache aborted'));});}
 return {get:key=>tx('readonly',s=>s.get(key)),set:(key,value)=>tx('readwrite',s=>s.put(value,key)),delete:key=>tx('readwrite',s=>s.delete(key))};
}
