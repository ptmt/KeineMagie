import test from 'node:test';
import assert from 'node:assert/strict';
import {createAPI, createPodcasts, podcastError} from '../core.mjs';

test('structured daily admission error retains reset and is distinct from translation budget', async()=>{
 const limits={daily_limit:4,daily_attempts:4,daily_remaining:0,resets_at:'2026-11-12T00:00:00Z'};
 const api=createAPI(async()=>new Response(JSON.stringify({code:'podcast_daily_limit',error:'safe backend explanation',remaining:0,retry_after:120,limits}),{status:429}));
 let error;try{await api.request('/v1/podcasts');}catch(e){error=e;}
 assert.equal(error.remaining,0);assert.equal(error.retry_after,120);assert.deepEqual(error.limits,limits);
 assert.match(podcastError(error),/00:00 UTC/);assert.match(podcastError(error),/Übersetzungsbudget/);
 for(const [code,pattern] of [['podcast_active_limit',/aktive/],['podcast_storage_limit',/gespeichert/],['podcast_global_active_limit',/Warteschlange/],['podcast_global_storage_limit',/Serverspeicher/]]){
  assert.match(podcastError(Object.assign(new Error(),{status:429,code})),pattern);
 }
 assert.doesNotMatch(podcastError({status:429,code:'unknown'}),/4 Versuche/);
});

test('owner quota status is retained from GET and cleared on owner change',async()=>{
 const limits={daily_remaining:3,resets_at:'2026-11-12T00:00:00Z'};
 const lib=createPodcasts({api:{request:async p=>p.endsWith('subscriptions')?{items:[]}:{items:[],limits,worker_available:true}}});
 lib.identity({user:{id:'a'}});await lib.activate('#podcasts');assert.deepEqual(lib.state.limits,limits);
 lib.identity({user:{id:'b'}});assert.equal(lib.state.limits,null);lib.dispose();
});
