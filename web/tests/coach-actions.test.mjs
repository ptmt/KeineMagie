import test from 'node:test';
import assert from 'node:assert/strict';
import {coachQuickActions,coachQuickLabel} from '../coach-chat.mjs';
test('server-authoritative actions and safe old snapshot fallback',()=>{
 assert.deepEqual(coachQuickActions({turns:[]}),[{action:'practice',turn_id:''}]);
 assert.deepEqual(coachQuickActions({turns:[{kind:'cloze'}]}),[]);
 assert.deepEqual(coachQuickActions({actions:[{action:'more',turn_id:''}],turns:[]}),[{action:'more',turn_id:''}]);
 for(const locale of ['en','ru','de','es','fr']) for(const key of ['practice','more','explain','progress','reveal']) assert.ok(coachQuickLabel(key,locale));
 assert.equal(coachQuickLabel('more','ru'),'Ещё');
});
