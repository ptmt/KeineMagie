import test from 'node:test';
import assert from 'node:assert/strict';
import { createProfileSync, legacyProfileID, readLegacyProfiles } from '../profile-sync.mjs';
test('migration reads every legacy record, including duplicate IDs with distinct content',()=>{
 const s=storage(),values=[{id:'custom-one',name:'Same',instructions:'First'},{id:'custom-one',name:'Same',instructions:'Second'}];
 s.setItem('keinemagie:translation-prompts:v1:owner',JSON.stringify(values));
 assert.deepEqual(readLegacyProfiles(s,'owner'),values);
 s.setItem('keinemagie:translation-prompts:v1:owner','{');assert.throws(()=>readLegacyProfiles(s,'owner'));
});
test('identical legacy duplicates enqueue one immutable import',async()=>{
 const legacy={id:'custom-duplicate',name:'Same',instructions:'Exact'};
 const a=createProfileSync({storage:storage(),owner:'owner',origin:'https://example.test',legacy:()=>[legacy,{...legacy}],request:async()=>{throw Error('offline')}});
 await a.ready;assert.equal(a.pendingCount,1);assert.equal(a.list().length,1);
});
test('migration identity is stable, content-sensitive and preserves Unicode bytes',async()=>{
 const a={id:'00000000-0000-0000-0000-000000000001',name:'仕事 🙂',instructions:'Keep meaning.'};
 assert.equal(await legacyProfileID(a), await legacyProfileID({...a}));
 assert.notEqual(await legacyProfileID(a),await legacyProfileID({...a,name:'仕事 🙂 '}));
 console.log('synthetic migration fixture ID:',await legacyProfileID(a));
});
test('failed local persistence never admits an unsaved operation',async()=>{
 const s=storage();const a=createProfileSync({storage:s,owner:'a',origin:'https://example.test',legacy:()=>[],request:async()=>({revision:0,items:[]})});await a.ready;
 s.setItem=()=>{throw Error('full')};assert.throws(()=>a.save({id:'one',name:'One',instructions:'Text'}));assert.equal(a.pendingCount,0);assert.deepEqual(a.list(),[]);
});
test('no guest identity and no corrupt-journal overwrite',()=>{
 const s=storage();assert.throws(()=>createProfileSync({storage:s,owner:'',origin:'https://example.test'}));
 const key='keinemagie:profile-sync:v1:https%3A%2F%2Fexample.test:a';s.setItem(key,'{');assert.throws(()=>createProfileSync({storage:s,owner:'a',origin:'https://example.test'}));assert.equal(s.getItem(key),'{');
});
test('lost acknowledgement does not rebase a queued edit over another device',async()=>{
 let remote={revision:0,items:[]}, delivered=false, lose=true;
 const request=async(method,body)=>{
  if(method==='GET')return structuredClone(remote);
  if(method==='PUT'&&delivered)return structuredClone(remote);
  if(method==='PUT'){delivered=true;remote={revision:1,items:[{id:body.id,title:body.title,instruction:body.instruction,revision:1,deleted:false}]};if(lose)throw Error('lost acknowledgement');}
  if(method==='PATCH'){
   if(body.base_revision!==remote.items[0].revision)throw {status:409};
   remote={revision:3,items:[{id:body.id,title:body.title,instruction:body.instruction,revision:3,deleted:false}]};
  }
  return structuredClone(remote);
 };
 const a=createProfileSync({storage:storage(),owner:'owner',origin:'https://example.test',legacy:()=>[],request});await a.ready;
 a.save({id:'one',name:'Original',instructions:'Text'});a.save({id:'one',name:'Queued local edit',instructions:'Text'});
 await a.sync();lose=false;remote={revision:2,items:[{id:'one',title:'Other device edit',instruction:'Text',revision:2,deleted:false}]};
 await a.sync();assert.equal(a.issue,'conflict');assert.equal(a.pendingCount,1);assert.equal(remote.items[0].title,'Other device edit');assert.equal(a.list()[0].name,'Queued local edit');
});
const storage=()=>{const d=new Map();return {getItem:k=>d.get(k)??null,setItem:(k,v)=>d.set(k,v),removeItem:k=>d.delete(k)}};
test('an empty HTTP success cannot acknowledge a queued profile',async()=>{
 const a=createProfileSync({storage:storage(),owner:'owner',origin:'https://example.test',legacy:()=>[],request:async()=>({revision:0,items:[]})});await a.ready;
 a.save({id:'missing',name:'Retain',instructions:'Do not erase'});await a.sync();assert.equal(a.pendingCount,1);assert.equal(a.list()[0].name,'Retain');
});
test('capacity-blocked create does not block an independent deletion',async()=>{
 let revision=1,items=[{id:'existing',title:'Existing',instruction:'Text',revision:1,deleted:false}];
 const request=async(method,body)=>{
  if(method==='PUT'&&items.some(v=>!v.deleted))throw {status:422};
  if(method==='PUT')items.push({id:body.id,title:body.title,instruction:body.instruction,revision:++revision,deleted:false});
  if(method==='DELETE'){items=items.map(v=>v.id===body.id?{...v,deleted:true,title:'',instruction:'',revision:++revision}:v);}
  return {revision,items:structuredClone(items)};
 };
 const a=createProfileSync({storage:storage(),owner:'owner',origin:'https://example.test',legacy:()=>[],request});await a.ready;await a.sync();
 a.save({id:'new',name:'Preserved',instructions:'Pending'});await a.sync();assert.equal(a.issue,'limit');assert.equal(a.pendingCount,1);
 a.remove('existing');await a.sync();assert.equal(a.pendingCount,0);assert.deepEqual(a.list().map(v=>v.id),['new']);
});
test('offline edits persist before transport and restore without touching legacy',async()=>{
 const s=storage(), legacy=[{id:'custom-a',name:'Work',instructions:'Be concise.'}];
 const options={storage:s,owner:'owner-a',origin:'https://example.test',legacy:()=>legacy,request:async()=>{throw Error('offline')}};
 const a=createProfileSync(options);await a.ready;
 assert.equal(a.list().length,1);
 a.save({...a.list()[0],name:'Changed'});
 await a.sync();
 const b=createProfileSync(options);await b.ready;
 assert.equal(b.list()[0].name,'Changed');assert.equal(legacy[0].name,'Work');
 assert.equal(b.pendingCount,2);
});
