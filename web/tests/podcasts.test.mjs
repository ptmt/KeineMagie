import test from 'node:test';
import assert from 'node:assert/strict';
import { createAPI } from '../core.mjs';
import { createPodcasts, parsePodcastRoute, podcastRoute } from '../core.mjs';

function harness() {
  const calls=[]; let resolvePost;
  const api={request:async(path,opts={})=>{
    calls.push({path,...opts});
    if(opts.method==='POST' && path==='/v1/podcasts') return new Promise(r=>resolvePost=r);
    return path.endsWith('subscriptions')?{items:[]}:{items:[],worker_available:true};
  }};
  const lib=createPodcasts({api}); lib.identity({user:{id:'a'},csrf_token:'csrf-a'});
  return {lib,calls,release:value=>resolvePost(value)};
}
test('prepare coalesces one owner/feed/episode submission and sends only server identity',async()=>{
 const {lib,calls,release}=harness();
 const a=lib.prepare('Feed_A','Episode_A','de'), b=lib.prepare('Feed_A','Episode_A','de');
 assert.equal(calls.length,1); assert.deepEqual(calls[0].body,{feed_id:'Feed_A',episode_id:'Episode_A',source_language:'de'});
 assert.equal(calls[0].csrf,'csrf-a');
 release({id:'Job_A',feed_id:'Feed_A',episode_id:'Episode_A',state:'queued'});
 assert.equal((await a).id,(await b).id); assert.equal(lib.state.jobs.length,1); lib.dispose();
});
test('late library and prepare responses cannot repopulate another owner',async()=>{
 let release; const lib=createPodcasts({api:{request:()=>new Promise(r=>release=r)}});
 lib.identity({user:{id:'a'},csrf_token:'a'}); const pending=lib.prepare('Feed_A','Episode_A');
 lib.identity({user:{id:'b'},csrf_token:'b'}); release({id:'private',state:'queued'});
 await assert.rejects(pending,{name:'AbortError'}); assert.deepEqual(lib.state.jobs,[]); assert.equal(lib.state.pending.size,0); lib.dispose();
});
test('routes encode IDs and reject malformed and traversal routes',()=>{
 assert.deepEqual(parsePodcastRoute(podcastRoute('feed','Ab_-12')),{kind:'feed',id:'Ab_-12'});
 for(const hash of ['#podcasts/feed/%',' #podcasts','#podcasts/feed/%2F','#podcasts/feed/..','#podcasts/feed/a/b']) assert.equal(parsePodcastRoute(hash).kind,'invalid');
});
test('direct imports exclude server-associated feed preparations without URL guessing',()=>{
 const {lib}=harness(); lib.state.feeds=[{id:'f',episodes:[{id:'e',preparation:{id:'associated'}}]}];
 lib.state.jobs=[{id:'linked',feed_id:'f',episode_id:'e'},{id:'associated'},{id:'direct',title:'Import'}];
 assert.deepEqual(lib.directJobs().map(j=>j.id),['direct']); lib.dispose();
});
test('hidden pages never schedule polling and visible polling is bounded',async()=>{
 let timer, count=0; const lib=createPodcasts({visible:()=>false,schedule:fn=>{timer=fn;count++;},api:{request:async p=>p.endsWith('subscriptions')?{items:[]}:{items:[{id:'a',state:'queued'}]}}});
 lib.identity({user:{id:'a'}}); await lib.activate('#podcasts'); assert.equal(count,0); assert.equal(timer,undefined); lib.dispose();
});

test('library refresh retains previous data on errors and first load has no empty state', async()=>{
 let reject=false; const lib=createPodcasts({api:{request:async p=>{if(reject)throw Object.assign(new Error(),{status:503});return p.endsWith('subscriptions')?{items:[{id:'f',episodes:[]}]}:{items:[],worker_available:true};}}});
 lib.identity({user:{id:'a'}}); const first=lib.activate('#podcasts');assert.equal(lib.state.phase,'loading');await first;reject=true;await lib.load();assert.equal(lib.state.phase,'loaded');assert.equal(lib.state.feeds.length,1);assert.match(lib.state.error,/nicht verfügbar/);lib.dispose();
});
test('late initial library is discarded on owner switch even if transport ignores abort',async()=>{
 const releases=[]; const lib=createPodcasts({api:{request:()=>new Promise(r=>releases.push(r))}});
 lib.identity({user:{id:'a'}});const pending=lib.activate('#podcasts');lib.identity({user:{id:'b'}});releases[0]({items:[{id:'private'}]});releases[1]({items:[{id:'private'}]});await pending;assert.deepEqual(lib.state.feeds,[]);assert.equal(lib.state.phase,'idle');lib.dispose();
});
test('visible polling is single-flight and stops after 120 rounds or leaving route',async()=>{
 let callback,scheduled=0,cleared=0;const lib=createPodcasts({schedule:fn=>{callback=fn;scheduled++;return scheduled;},unschedule:()=>cleared++,api:{request:async p=>({items:p.endsWith('subscriptions')?[]:[{id:'j',state:'queued'}]})}});
 lib.identity({user:{id:'a'}});await lib.activate('#podcasts');for(let i=0;i<120;i++)await callback();assert.equal(scheduled,120);await lib.activate('#translator');assert.ok(cleared>0);lib.dispose();
});
test('all explicit mutations use the existing server contracts and no translation on subscribe/refresh',async()=>{
 const calls=[];const lib=createPodcasts({api:{request:async(path,options={})=>{calls.push({path,...options});return {id:'Job_A',state:'queued'};}}});lib.identity({user:{id:'a'},csrf_token:'csrf'});
 await lib.subscribe('https://public.example/rss');await lib.refresh('Feed_A');await lib.unsubscribe('Feed_A');await lib.importURL('https://public.example/audio','ru');await lib.jobAction('Job_A','cancel');await lib.jobAction('Job_A','retry');await lib.jobAction('Job_A','delete');await lib.detail('Job_A');
 assert.deepEqual(calls.map(c=>[c.path,c.method||'GET',c.body]),[
 ['/v1/podcasts/subscriptions','POST',{url:'https://public.example/rss'}],['/v1/podcasts/subscriptions/Feed_A/refresh','POST',{}],['/v1/podcasts/subscriptions/Feed_A','DELETE',undefined],['/v1/podcasts','POST',{url:'https://public.example/audio',source_language:'ru'}],['/v1/podcasts/Job_A/cancel','POST',{}],['/v1/podcasts/Job_A/retry','POST',{}],['/v1/podcasts/Job_A','DELETE',undefined],['/v1/podcasts/Job_A','GET',undefined]]);
 assert.ok(calls.every(c=>c.csrf==='csrf'));lib.dispose();
});
test('transport accepts real base64url IDs but blocks arbitrary URL and traversal',async()=>{
 const calls=[];const api=createAPI(async(path)=>{calls.push(path);return new Response('{}');});await api.request('/v1/podcasts/Ab_C-123');for(const path of ['https://evil.example/','/v1/podcasts/../secrets','/v1/podcasts/%2f','//evil.example'])await assert.rejects(api.request(path));assert.equal(calls.length,1);
});
test('podcast 401 revokes all in-memory library data before notifying the shell',async()=>{
 let notified=false;const lib=createPodcasts({unauthorized:()=>{notified=true;assert.equal(lib.state.feeds.length,0);},api:{request:async()=>{throw Object.assign(new Error(),{status:401});}}});lib.identity({user:{id:'a'}});lib.state.feeds=[{id:'private'}];await lib.activate('#podcasts');assert.equal(notified,true);assert.equal(lib.state.phase,'guest');assert.equal(lib.state.jobs.length,0);lib.dispose();
});
test('first-load error remains distinct from an authenticated empty library',async()=>{
 const lib=createPodcasts({api:{request:async()=>{throw new Error('offline');}}});lib.identity({user:{id:'a'}});await lib.activate('#podcasts');assert.equal(lib.state.phase,'error');lib.dispose();
});
// A vertical slice: owner library discovery uses the real cookie API client.
test('podcast library loads subscriptions and jobs without starting AI work', async () => {
  const { createPodcasts } = await import('../core.mjs');
  const calls = [];
  const api = createAPI(async (path, opts) => {
    calls.push({path, ...opts});
    return new Response(JSON.stringify(path.endsWith('subscriptions') ? {items:[{id:'Feed_A',title:'Fixture show',episodes:[]}]} : {items:[],worker_available:true}));
  });
  const library = createPodcasts({api});
  library.identity({user:{id:'owner-a'},csrf_token:'fixture'});
  await library.activate('#podcasts');
  assert.equal(library.state.phase, 'loaded');
  assert.equal(library.state.feeds[0].title, 'Fixture show');
  assert.deepEqual(calls.map(c => c.path), ['/v1/podcasts/subscriptions','/v1/podcasts']);
  assert.ok(calls.every(c => c.method === 'GET' && c.credentials === 'same-origin' && c.cache === 'no-store'));
  library.dispose();
});
