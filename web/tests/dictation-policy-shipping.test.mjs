import test from 'node:test';
import assert from 'node:assert/strict';
import {dt} from '../dictation-i18n.mjs';
import {readFileSync} from 'node:fs';
test('monthly application cap is localized inside closed audio details',()=>{
 for(const locale of ['de','en','ru','es','fr'])assert.match(dt(locale,'dictation.budget.notice'),/10/);
 const source=readFileSync(new URL('../dictation.mjs',import.meta.url),'utf8');
 assert.match(source,/disclosure\.append\([^\n]*dictation\.budget\.notice/);
});
test('policy player is shipped and served by production',()=>{
 const docker=readFileSync(new URL('../../server/Dockerfile',import.meta.url),'utf8');
 const routes=readFileSync(new URL('../../server/static.go',import.meta.url),'utf8');
 assert.match(docker,/COPY[^\n]*web\/dictation-playback\.mjs[^\n]*\/app\/web\//);
 assert.ok(routes.includes('"/dictation-playback.mjs"'));
});
