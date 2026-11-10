import test from 'node:test';
import assert from 'node:assert/strict';
import * as core from '../core.mjs';

test('translation instructions are optional strings limited by Unicode code points', () => {
 assert.deepEqual(core.inputPayload('Hallo','de'),{text:'Hallo',source_language:'de',target_language:'ru'});
 assert.equal(core.inputPayload('Hallo','de','😀'.repeat(1000)).instructions,'😀'.repeat(1000));
 for (const value of [null,{},42,'😀'.repeat(1001)]) assert.throws(()=>core.inputPayload('Hallo','de',value));
});

test('named shortcuts are account scoped, validated and store only nonsecret user text', () => {
 const data=new Map();const storage={getItem:k=>data.get(k)??null,setItem:(k,v)=>data.set(k,v)};
 const a=core.promptStore(storage,'owner-A'); const b=core.promptStore(storage,'owner-B');
 const entry=a.save({id:'custom-1',name:'Brief',instructions:'Bitte kurz und freundlich übersetzen.',bearer:'must-not-store'});
 assert.deepEqual(a.list(),[entry]);assert.deepEqual(b.list(),[]);
 assert.equal([...data.keys()][0],'keinemagie:translation-prompts:v1:owner-A');
 assert.doesNotMatch([...data.values()][0],/bearer|must-not-store/);
 a.save({...entry,name:'E-Mail'});assert.equal(a.list().length,1);assert.equal(a.list()[0].name,'E-Mail');
 assert.throws(()=>a.save({id:'bad',name:'',instructions:'x'}));
 assert.throws(()=>a.save({id:'bad',name:'x',instructions:'😀'.repeat(1001)}));
 a.remove(entry.id);assert.deepEqual(a.list(),[]);
 assert.throws(()=>core.promptStore(storage,''));
 data.set('keinemagie:translation-prompts:v1:owner-B','{');assert.deepEqual(b.list(),[]);
});

test('storage failure is explicit on save but does not break reading or standard presets', () => {
 const storage={getItem(){throw Error('blocked');},setItem(){throw Error('full');}};
 const store=core.promptStore(storage,'owner');assert.deepEqual(store.list(),[]);
 assert.throws(()=>store.save({id:'custom-x',name:'Name',instructions:'Style'}),/full/);
 assert.deepEqual(core.translationPresets.map(x=>x.name),['Freundlich','Formell']);
});
