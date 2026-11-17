import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// Execute the actual empty-state condition without a Swift build or simulator.
const source=readFileSync(new URL('../App/DictationView.swift',import.meta.url),'utf8');
const gate=source.match(/if (model\.session\.canWrite && historyConfirmed[^\{]+)\{/)[1];
function onboarding(overrides={}){
 const values={
  'model.session.canWrite':true,historyConfirmed:true,loaded:true,busy:false,'error == nil':true,
  'items.isEmpty':true,'model.dictationDrafts.records.isEmpty':true,'model.dictationDrafts.recoveries.isEmpty':true,
  'model.dictationDrafts.addForm.title.isEmpty':true,'model.dictationDrafts.addForm.original.isEmpty':true,
  'model.dictationDrafts.addForm.pending == nil':true,...overrides,
 };
 let expression=gate;for(const [token,value] of Object.entries(values).sort((a,b)=>b[0].length-a[0].length))expression=expression.replaceAll(token,String(value));
 return Function(`return (${expression});`)();
}
test('native onboarding source gate excludes each saved Add text field and pending creation',()=>{
 assert.equal(onboarding(),true);
 for(const field of ['title.isEmpty','original.isEmpty','pending == nil']){
  assert.equal(onboarding({['model.dictationDrafts.addForm.'+field]:false}),false,`saved ${field} must suppress onboarding`);
 }
});

const resume=source.match(/if (model\.session\.canWrite && \([^\n]+) \{/);
test('native saved creation has an owner-only resume row for title, text or pending creation',()=>{
 assert.ok(resume,'missing saved creation resume gate');
 const tokens=['model.session.canWrite','!model.dictationDrafts.addForm.title.isEmpty','!model.dictationDrafts.addForm.original.isEmpty','model.dictationDrafts.addForm.pending != nil'];
 const visible=values=>{let expression=resume[1];tokens.forEach((token,i)=>expression=expression.replaceAll(token,String(values[i])));return Function(`return (${expression});`)();};
 assert.equal(visible([true,false,false,false]),false);
 for(let i=1;i<4;i++){
  const values=[true,false,false,false];values[i]=true;assert.equal(visible(values),true);
  values[0]=false;assert.equal(visible(values),false);
 }
 const row=source.slice(resume.index,source.indexOf('ForEach(items)',resume.index));
 assert.match(row,/Button \{[^}]*title = model\.dictationDrafts\.addForm\.title[^}]*original = model\.dictationDrafts\.addForm\.original[^}]*showAdd = true/s);
 assert.match(row,/if !model\.dictationDrafts\.addForm\.title\.isEmpty \{ Text\(model\.dictationDrafts\.addForm\.title\)/);
 assert.match(row,/Text\(AppL10n\.text\("In progress"\)\)/);
 assert.match(row,/accessibilityIdentifier\("dictation-resume-create"\)/);
});
test('native keeps the existing empty CTA, sheet fields and history identifiers',()=>{
 for(const id of ['dictation-empty-create','dictation-title','dictation-original','dictation-create','dictation-row','dictation-recovery'])assert.ok(source.includes(`accessibilityIdentifier("${id}")`));
 assert.match(source,/Button\("Add text"\) \{ showAdd = true \}/);
 assert.match(source,/\.sheet\(isPresented: \$showAdd\)/);
});
