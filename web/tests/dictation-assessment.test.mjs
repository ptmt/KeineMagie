import test from 'node:test';
import assert from 'node:assert/strict';
import {assessmentGroups} from '../dictation-assessment.mjs';
test('unfinished suffix is grouped separately, never a missing-word flood',()=>{
 const a={alignment:{spans:[{id:'s0',kind:'equal',original:'Die',written:'Die'},{id:'s1',kind:'omission',original:' kleine',written:''},{id:'s2',kind:'unattempted',original:' danach '.repeat(54),written:''}]}};
 const groups=assessmentGroups(a);
 assert.equal(groups.compared.length,2);assert.equal(groups.unattempted.length,1);assert.equal(groups.changes.length,1);
});
