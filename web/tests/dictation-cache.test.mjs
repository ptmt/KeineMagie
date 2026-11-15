import test from 'node:test';
import assert from 'node:assert/strict';
import {createOwnerDraftCache} from '../dictation-cache.mjs';
test('cache requires validated identity and rejects queued writes after owner change',async()=>{
 const data=new Map();const storage={get:k=>data.get(k),set:(k,v)=>data.set(k,v),delete:k=>data.delete(k)};
 const cache=createOwnerDraftCache(storage);assert.throws(()=>cache.open(null));
 const a=cache.open({user:{id:'a'},csrf_token:'proof'});await a.save({revision:1,entries:{a:1}});
 const b=cache.open({user:{id:'b'},csrf_token:'other'});await a.save({revision:2,entries:{leaked:1}});
 assert.equal(await b.load(),undefined);await b.save({revision:2,entries:{b:1}});await b.save({revision:1,entries:{older:1}});
 assert.deepEqual((await b.load()).entries,{b:1});
 await cache.clear();assert.equal(await b.load(),undefined);
});
test('logout purge precedes a new session save for the same owner',async()=>{
 const data=new Map(),calls=[];
 const storage={get:async k=>data.get(k),set:async(k,v)=>{calls.push('set '+v.revision);data.set(k,v)},delete:async k=>{calls.push('delete');data.delete(k)}};
 const cache=createOwnerDraftCache(storage),session={user:{id:'a'},csrf_token:'proof'};
 await cache.open(session).save({revision:1,entries:{old:1}});
 const purge=cache.clear(),next=cache.open(session),saved=next.save({revision:1,entries:{new:1}});
 await Promise.all([purge,saved]);
 assert.deepEqual(calls,['set 1','delete','set 1']);
 assert.deepEqual((await next.load()).entries,{new:1});
});
