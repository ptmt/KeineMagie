import test from 'node:test';
import assert from 'node:assert/strict';
import {createPodcasts} from '../core.mjs';
test('job deep link fetches detail without waiting for unrelated subscriptions',async()=>{
 const calls=[];let release;
 const lib=createPodcasts({api:{request:async path=>{calls.push(path);if(path.endsWith('/subscriptions'))return new Promise(r=>release=r);if(path==='/v1/podcasts/Job_A')return {id:'Job_A',state:'completed'};return {items:[]};}}});
 lib.identity({user:{id:'a'}});
 const flight=lib.activate('#podcasts/job/Job_A');await new Promise(r=>setTimeout(r,0));
 assert.ok(calls.includes('/v1/podcasts/Job_A'));
 assert.equal(lib.state.jobs[0]?.id,'Job_A');
 release?.({items:[]});await flight;lib.dispose();
});
