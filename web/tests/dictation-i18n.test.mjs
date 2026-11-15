import test from 'node:test';
import assert from 'node:assert/strict';
import {dictationStrings,dt} from '../dictation-i18n.mjs';
test('five complete dictation locales and interpolation parity',()=>{
 assert.deepEqual(Object.keys(dictationStrings).sort(),['de','en','es','fr','ru']);
 for(const locale of Object.keys(dictationStrings))for(const [key,value]of Object.entries(dictationStrings.en)){
  assert.ok(dictationStrings[locale][key],locale+': '+key);
  assert.deepEqual(dictationStrings[locale][key].match(/\{\w+\}/g)||[],value.match(/\{\w+\}/g)||[]);
 }
 assert.equal(dt('de','Check'),'Prüfen');
 assert.ok(dictationStrings.en['dictation.paid.notice']?.includes('OpenAI'));
});
