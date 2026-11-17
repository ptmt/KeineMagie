import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createProfileSync,legacyProfileID} from '../profile-sync.mjs';
const directory=process.env.KM_PROFILE_BRIDGE_DIR;
const storage=()=>{const d=new Map();return {getItem:k=>d.get(k)??null,setItem:(k,v)=>d.set(k,v),removeItem:k=>d.delete(k)}};
test('real Go wire: two browsers migrate, merge, conflict, delete, retry and fence owners',{skip:!directory},async t=>{
 const f=JSON.parse(await readFile(directory+'/ready.json','utf8'));
 const call=async(method,body,token=f.token)=>{const r=await fetch(f.url+'/v1/translation-profiles',{method,headers:{Authorization:'Bearer '+token,'X-Translation-Owner':f.owner,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const v=await r.json();if(!r.ok)throw Object.assign(Error('HTTP'),{status:r.status});return v;};
 const legacyA=[{id:'custom-legacy-shared',name:'Same name',instructions:'First content 🙂'}],legacyB=[{...legacyA[0],instructions:'Different content é'}];
 const sa=storage(),sb=storage();let offline=false,lostAck=false;
 const request=async(method,body)=>{if(offline)throw Error('offline');const v=await call(method,body);if(lostAck&&method!=='GET'){lostAck=false;throw Error('lost acknowledgement')};return v;};
 let a=createProfileSync({storage:sa,owner:f.owner,origin:f.url,legacy:()=>legacyA,request});
 const b=createProfileSync({storage:sb,owner:f.owner,origin:f.url,legacy:()=>legacyB,request:(m,v)=>call(m,v,f.second_token)});
 await Promise.all([a.ready,b.ready]);await Promise.all([a.sync(),b.sync()]);await a.sync();await b.sync();
 const id=await legacyProfileID(legacyA[0]),idB=await legacyProfileID(legacyB[0]);
 await t.test('same legacy ID and name with different contents survives as two full records',()=>{assert.notEqual(id,idB);assert.ok(a.list().some(v=>v.id===id));assert.ok(a.list().some(v=>v.id===idB));assert.equal(a.pendingCount,0);assert.equal(b.pendingCount,0)});
 const revision=a.revision(id);
 a.save({...a.list().find(v=>v.id===id),name:'Changed remotely'},revision);await a.sync();
 b.save({...b.list().find(v=>v.id===id),name:'Offline conflicting title'},revision);await b.sync();
 await t.test('concurrent stale edit is explicit, retains local draft and can keep both',async()=>{assert.equal(b.issue,'conflict');assert.equal(b.list().find(v=>v.id===id).name,'Offline conflicting title');await b.resolveConflict(true);await a.sync();assert.ok(a.list().some(v=>v.name==='Changed remotely'));assert.ok(a.list().some(v=>v.name==='Offline conflicting title'))});
 await t.test('lost acknowledgement restarts and replays exact operation once',async()=>{
  offline=true;a.save({id:crypto.randomUUID().toUpperCase(),name:'Pending',instructions:'Literal'});await a.sync();
  a.stop();a=createProfileSync({storage:sa,owner:f.owner,origin:f.url,legacy:()=>legacyA,request});await a.ready;assert.equal(a.pendingCount,1);
  offline=false;lostAck=true;await a.sync();assert.equal(a.pendingCount,1);await a.sync();assert.equal(a.pendingCount,0);assert.equal(a.list().filter(v=>v.name==='Pending').length,1);
 });
 await t.test('lost acknowledgement plus later remote edit cannot silently rebase dependent local work',async()=>{
  const recordID=crypto.randomUUID().toUpperCase();
  a.save({id:recordID,name:'Original accepted',instructions:'Exact content'});
  a.save({id:recordID,name:'Local queued edit',instructions:'Exact content'});
  lostAck=true;await a.sync();assert.equal(a.pendingCount,2);
  await b.sync();b.save({id:recordID,name:'Remote intervening edit',instructions:'Remote content'});await b.sync();
  await a.sync();assert.equal(a.issue,'conflict');assert.equal(a.pendingCount,1);
  const remote=await call('GET');assert.equal(remote.items.find(v=>v.id===recordID).title,'Remote intervening edit');
  assert.equal(a.list().find(v=>v.id===recordID).name,'Local queued edit');
  await a.resolveConflict(false);
 });
 await t.test('deleted record cannot be resurrected by old-device import or stale offline edit',async()=>{
  await b.sync();const oldRevision=b.revision(id);a.remove(id);await a.sync();
  b.save({id,name:'Stale offline',instructions:'Keep me as a conflict'},oldRevision);await b.sync();assert.equal(b.issue,'conflict');
  const oldDevice=createProfileSync({storage:storage(),owner:f.owner,origin:f.url,legacy:()=>legacyA,request});await oldDevice.ready;await oldDevice.sync();assert.equal(oldDevice.pendingCount,0);assert.ok(!oldDevice.list().some(v=>v.id===id));
  await b.resolveConflict(false);assert.ok(!b.list().some(v=>v.id===id));
 });
 await t.test('stale response after owner stop cannot update another scope; 401 purges active journal',async()=>{
  let release;const s=storage();const c=createProfileSync({storage:s,owner:f.owner,origin:f.url,legacy:()=>[],request:()=>new Promise(r=>release=r)});await c.ready;const pending=c.sync();await new Promise(r=>setImmediate(r));c.stop();release(await call('GET'));await pending;assert.deepEqual(c.list(),[]);
  let revoked=false;const d=createProfileSync({storage:s,owner:'different',origin:f.url,legacy:()=>[],request:async()=>{throw {status:401}},unauthorized:()=>{revoked=true}});await d.ready;d.save({id:'private',name:'Private',instructions:'Private text'});await d.sync();assert.equal(revoked,true);assert.deepEqual(d.list(),[]);assert.equal(d.pendingCount,0);
 });
 await t.test('older server does not erase offline profiles and edits',async()=>{
  const old=createProfileSync({storage:storage(),owner:'older',origin:f.url,legacy:()=>legacyA,request:async()=>{throw {status:404}}});await old.ready;await old.sync();assert.equal(old.issue,'unsupported');assert.equal(old.list()[0].name,'Same name');assert.equal(old.pendingCount,1);
 });
});
