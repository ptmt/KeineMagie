import test from 'node:test';
import assert from 'node:assert/strict';
import * as episode from '../episode.mjs';

test('one explicit start completes a bounded plan without implicit generation', async()=>{
 assert.equal(typeof episode.createAnalysisRunner,'function');
 let calls=0;const updates=[];
 const runner=episode.createAnalysisRunner({request:async()=>{calls++;return {state:calls===3?'completed':'pending',estimate:{total_requests:3,completed_requests:calls,remaining_requests:3-calls}};},active:()=>true,update:v=>updates.push(v)});
 assert.equal(calls,0);
 await runner.start({state:'pending',estimate:{total_requests:3,completed_requests:0,remaining_requests:3}});
 assert.equal(calls,3);assert.equal(updates.length,3);
});
test('cancel aborts current request and prevents subsequent POSTs; resume is explicit',async()=>{
 assert.equal(typeof episode.createAnalysisRunner,'function');
 let calls=0,signal;
 const runner=episode.createAnalysisRunner({request:options=>{calls++;signal=options.signal;return new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(new DOMException('Canceled','AbortError')),{once:true}));},active:()=>true,update:()=>{}});
 const pending=runner.start({estimate:{remaining_requests:4}});
 runner.cancel();await assert.rejects(pending,{name:'AbortError'});
 assert.equal(signal.aborted,true);assert.equal(calls,1);
});
test('leaving the reader stops continuation and changed plans cannot exceed consent',async()=>{
 assert.equal(typeof episode.createAnalysisRunner,'function');
 let calls=0,active=true;
 const runner=episode.createAnalysisRunner({request:async()=>{calls++;active=false;return {state:'pending',estimate:{remaining_requests:99}};},active:()=>active,update:()=>{}});
 await runner.start({estimate:{remaining_requests:3}});assert.equal(calls,1);
 active=true;
 const bounded=episode.createAnalysisRunner({request:async()=>{calls++;return {state:'pending',estimate:{remaining_requests:99}};},active:()=>true,update:()=>{}});
 await bounded.start({estimate:{remaining_requests:2}});assert.equal(calls,3);
});
