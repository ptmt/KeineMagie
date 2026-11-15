import test from 'node:test';
import assert from 'node:assert/strict';
import {createDraftJournal} from '../dictation-journal.mjs';
const record=()=>({id:'one',revision:0,draft:'',mode:'whole',step:0,replays:0});
test('persist pending operation before sending; lost acknowledgment retries exact body',async()=>{
 const writes=[];let disk;let fail=true;
 const journal=createDraftJournal({persist:async value=>{disk=structuredClone(value);},send:async(id,body)=>{assert.equal(disk.entries[id].pending.mutation_id,body.mutation_id);writes.push(structuredClone(body));if(fail){fail=false;throw Error('lost ack')}return {...record(),...body,revision:1};}});
 journal.accept(record());await journal.edit('one',{draft:'first'});
 await assert.rejects(journal.flush('one'));
 await journal.edit('one',{draft:'first plus later'});
 await journal.flush('one');
 assert.deepEqual(writes[0],writes[1]);assert.equal(writes[2].draft,'first plus later');assert.equal(journal.get('one').draft,'first plus later');
});
test('late save cannot overwrite newer typing and refresh cannot erase dirty draft',async()=>{
 let resume;const journal=createDraftJournal({persist:async()=>{},send:async(id,body)=>new Promise(r=>{resume=()=>r({...record(),...body,revision:1})})});
 journal.accept(record());await journal.edit('one',{draft:'a'});const saving=journal.flush('one');await new Promise(r=>setImmediate(r));
 await journal.edit('one',{draft:'ab'});journal.accept({...record(),draft:'remote'});assert.equal(journal.get('one').draft,'ab');
 // reset fences all late completions, including cleanup of a replacement owner.
 journal.reset();journal.accept({...record(),draft:'new owner'});resume();await saving;
 assert.equal(journal.get('one').draft,'new owner');
});
test('restart retains acknowledged versus pending and conflicts keep local draft',async()=>{
 let disk;const original=createDraftJournal({persist:async v=>{disk=structuredClone(v)},send:async()=>{throw Object.assign(Error('conflict'),{status:409})}});
 original.accept(record());await original.edit('one',{draft:'keep me'});await assert.rejects(original.flush('one'));
 const restored=createDraftJournal({persist:async()=>{},send:async()=>{throw Object.assign(Error('conflict'),{status:409})}});restored.restore(disk);
 assert.equal(restored.get('one').draft,'keep me');await assert.rejects(restored.flush('one'));assert.equal(restored.get('one').draft,'keep me');
});
test('add form and each source attempt ID survive restart until acknowledged',async()=>{
 let disk;const persist=async value=>{disk=structuredClone(value)};
 const first=createDraftJournal({persist,send:async()=>{}});
 await first.editForm({title:'Unsent',text:'Hallo Welt',language:'de'});
 const form=first.form(),one=await first.reserveAttempt('source-one'),two=await first.reserveAttempt('source-two');
 assert.notEqual(one,two);
 const second=createDraftJournal({persist,send:async()=>{}});second.restore(disk);
 assert.deepEqual(second.form(),form);assert.equal(await second.reserveAttempt('source-one'),one);assert.equal(await second.reserveAttempt('source-two'),two);
 await second.clearAttempt('source-one');assert.notEqual(await second.reserveAttempt('source-one'),one);assert.equal(second.attempt('source-two'),two);
 await second.clearForm();assert.equal(second.form().text,'');assert.notEqual(second.form().id,form.id);
});
test('pending create survives lost acknowledgment and restart with its exact body',async()=>{
 let disk;const persist=async value=>{disk=structuredClone(value)};
 const first=createDraftJournal({persist,send:async()=>{}});
 await first.editForm({title:'First',text:'Hallo Welt',language:'de'});
 const body=await first.pendingCreate();
 assert.deepEqual(disk.pendingCreate,body);
 await assert.rejects(first.editForm({title:'Changed'}));
 const restored=createDraftJournal({persist,send:async()=>{}});restored.restore(disk);
 assert.deepEqual(await restored.pendingCreate(),body);
 await restored.finishCreate(body.id);
 assert.equal(restored.form().text,'');assert.notEqual(restored.form().id,body.id);
});
test('validation rejection unlocks create form with a fresh ID and preserved fields',async()=>{
 const journal=createDraftJournal({persist:async()=>{},send:async()=>{}});
 await journal.editForm({title:'Keep',text:'Hallo',language:'de'});
 const body=await journal.pendingCreate();
 await journal.rejectCreate(body.id);
 assert.equal(journal.form().title,'Keep');assert.equal(journal.form().text,'Hallo');
 assert.notEqual((await journal.pendingCreate()).id,body.id);
});
test('failed attempt reservation is durably recommitted before retry transport',async()=>{
 let fail=true,disk;const journal=createDraftJournal({persist:async value=>{if(fail){fail=false;throw Error('disk full')}disk=structuredClone(value)},send:async()=>{}});
 await assert.rejects(journal.reserveAttempt('source'));
 const id=journal.attempt('source');assert.equal(disk,undefined);
 assert.equal(await journal.reserveAttempt('source'),id);
 assert.equal(disk.attempts.source,id);
});
test('conflict comparison can rebase or use server while retaining exportable local text',async()=>{
 let disk;const sent=[];const journal=createDraftJournal({persist:async v=>{disk=structuredClone(v)},send:async(id,body)=>{sent.push(body);if(sent.length===1)throw Object.assign(Error('conflict'),{status:409});return {...record(),...body,revision:8}}});
 journal.accept(record());await journal.edit('one',{draft:'my words'});await assert.rejects(journal.flush('one'));
 assert.equal(journal.entry('one').pending.draft,'my words');
 const remote={...record(),draft:'their words',revision:7};await journal.rebase('one',remote);
 assert.equal(journal.get('one').draft,'my words');assert.equal(journal.entry('one').pending,null);
 await journal.flush('one');assert.equal(sent[1].revision,7);assert.equal(sent[1].draft,'my words');
 await journal.useServer('one',{...remote,revision:9});assert.equal(journal.get('one').draft,'their words');assert.equal(disk.entries.one.local.draft,'their words');
});
test('remote deletion removes pending mutation and keeps a recovery draft',async()=>{
 let disk,calls=0;const journal=createDraftJournal({persist:async v=>{disk=structuredClone(v)},send:async()=>{calls++;throw Object.assign(Error('missing'),{status:404})}});
 journal.accept({...record(),title:'Text'});await journal.edit('one',{draft:'keep this'});await assert.rejects(journal.flush('one'));
 await journal.recoverDeleted('one');assert.equal(journal.get('one'),undefined);assert.equal(journal.recoveries().one.draft,'keep this');
 await journal.flush('one');assert.equal(calls,1);assert.equal(disk.entries.one,undefined);
});
test('logout fences a delayed save acknowledgement and new owner state',async()=>{
 let finish;const journal=createDraftJournal({persist:async()=>{},send:async(id,body)=>new Promise(resolve=>{finish=()=>resolve({...record(),...body,revision:1})})});
 journal.accept(record());await journal.edit('one',{draft:'private'});const old=journal.flush('one');await new Promise(r=>setImmediate(r));
 journal.reset();journal.accept({...record(),draft:'second owner'});finish();await old;
 assert.equal(journal.get('one').draft,'second owner');assert.equal(journal.snapshot().entries.one.pending,null);
});
