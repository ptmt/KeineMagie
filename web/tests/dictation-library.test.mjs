import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture,record} from './dictation-mount-fixture.mjs';

test('unchecked library items never claim background processing and use a spacious card title',async()=>{
 const f=fixture({request:async()=>({items:[record(),{...record('two'),checked:true}]})});await f.start();
 const list=f.host.children[2];
 assert.equal(list.children[0].textContent,'Test one');
 assert.equal(list.children[0].className,'dictation-card');
 assert.equal(list.children[0].children[0].tagName,'STRONG');
 assert.match(list.children[1].textContent,/Completed/);
 f.controller.identity(null);
});

test('card metadata uses only provided counts and known whole-audio duration',async()=>{
 const f=fixture({request:async()=>({items:[{...record(),word_count:120,audio_duration_seconds:95},record('old')]})});await f.start();
 assert.equal(f.host.children[2].children[0].children[1].textContent,'120 words · 1:35');
 assert.equal(f.host.children[2].children[1].children.length,1,'old API has no invented metadata');
 f.controller.identity(null);
});

test('authoritative lifecycle renders four passive localized milestones and one current step',async()=>{
 for(const stage of ['added','ready','started','completed']){
  const f=fixture({locale:()=> 'ru',request:async()=>({items:[{...record(),lifecycle_stage:stage}]})});await f.start();
  const lifecycle=f.host.children[2].children[0].children.at(-1);
  assert.equal(lifecycle.className,'dictation-lifecycle');
  assert.deepEqual(lifecycle.children.map(e=>e.textContent),['Добавлен','Аудио готово','Начат','Завершён']);
  assert.equal(lifecycle.children.filter(e=>e.getAttribute('aria-current')==='step').length,1);
  assert.equal(lifecycle.children[['added','ready','started','completed'].indexOf(stage)].getAttribute('aria-current'),'step');
  assert.ok(lifecycle.children.every(e=>e.tagName==='SPAN'));
  f.controller.identity(null);
 }
});

test('unknown old API state stays unknown, checked fallback is completed',async()=>{
 const f=fixture({request:async()=>({items:[record(),{...record('checked'),checked:true},{...record('future'),lifecycle_stage:'future-v2'}]})});await f.start();
 const rows=f.host.children[2].children;
 assert.equal(rows[0].children.length,1);
 assert.equal(rows[2].children.length,1);
 assert.equal(rows[1].children.at(-1).children.at(-1).getAttribute('aria-current'),'step');
 f.controller.identity(null);
});

test('saved creation is a draft, not background processing',async()=>{
 const f=fixture({request:async()=>({items:[]})});
 f.disk.set('dictation:synthetic',{entries:{},form:{id:'saved',title:'Saved title',text:'Hallo',language:'de'},recoveries:{},revision:1});
 await f.start();assert.ok(f.button('Saved title · Draft'));f.controller.identity(null);
});

test('metadata is localized, pluralized and omitted for absent or invalid optional fields',async()=>{
 for(const [locale,n,expected] of [['ru',1,'1 слово'],['ru',2,'2 слова'],['ru',5,'5 слов'],['ru',21,'21 слово'],['de',1,'1 Wort'],['de',2,'2 Wörter'],['en',1,'1 word'],['es',1,'1 palabra'],['fr',1,'1 mot']]){
  const f=fixture({locale:()=>locale,request:async()=>({items:[{...record(),word_count:n},{...record('old'),word_count:'120',audio_duration_seconds:null}]})});await f.start();
  assert.equal(f.host.children[2].children[0].children[1].textContent,expected);
  assert.equal(f.host.children[2].children[1].children.length,1);
  f.controller.identity(null);
 }
});

test('failed library read retains an explicit refresh action without header overflow',async()=>{
 let failed=true;const f=fixture({request:async()=>{if(failed)throw Error('offline');return {items:[record()]};}});await f.start();
 assert.equal(f.host.children[0].children.length,2);
 failed=false;await f.click('Refresh');assert.ok(f.button('Test one'));
 assert.ok(!f.host.all().some(e=>e.tagName==='BUTTON'&&e.textContent==='Refresh'));
 f.controller.identity(null);
});

test('library header has only title and create; attempt actions belong to detail',async()=>{
 const f=fixture({request:async()=>({items:[record()]})});await f.start();
 assert.deepEqual(f.host.children[0].children.map(e=>e.tagName),['H1','BUTTON']);
 assert.equal(f.host.children[0].children[1].getAttribute('aria-label'),'Add text');
 assert.equal(f.host.all().filter(e=>e.tagName==='SUMMARY').length,0);
 f.controller.identity(null);
});
