import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { episodePath, episodeLocation, transcriptStats, createEpisodeClient } from '../episode.mjs';
import * as episodeHelpers from '../episode.mjs';
import { createAPI } from '../core.mjs';
test('timestamp jumps select containing or nearest valid range, preserve zero, and reject invalid input',()=>{
 const segments=[{start:0,end:3},{start:12,end:15},{start:30,end:33},{start:null,end:40},{start:-4,end:0}];
 assert.equal(typeof episodeHelpers.transcriptTimeIndex,'function');
 const find=episodeHelpers.transcriptTimeIndex;
 for(const [input,index] of [['0:00',0],['0:02',0],['0:04',0],['0:10',1],['0:15',1],['0:29',2],['999:00',2]])assert.equal(find(segments,input),index,input);
 for(const value of ['','-1:00','0:60','1:2','Infinity:00','99999999999999999999999:00'])assert.equal(find(segments,value),-1,value);
 assert.equal(find([], '0:00'),-1);
});
test('transport permits only the documented owner vocabulary filters',async()=>{
 const calls=[];const api=createAPI(async path=>{calls.push(path);return {ok:true,status:200,json:async()=>({items:[]})};});
 await api.request('/v1/learning/vocabulary?language=de&job_id=Exact_ABC-123');
 assert.deepEqual(calls,['/v1/learning/vocabulary?language=de&job_id=Exact_ABC-123']);
 for(const path of ['/v1/podcasts?url=https://evil.test','/v1/learning/vocabulary?language=de&job_id=bad/identifier','/v1/learning/vocabulary?language=de&job_id=Exact&extra=x','//evil.test/v1/a'])await assert.rejects(api.request(path));
});
globalThis.crypto ||= webcrypto;

test('permalink hashes the exact opaque job ID, with a cosmetic slug', async () => {
 const job={id:'User_Provided-Token_ABC',title:'The Nut Sisters'};
 const suffix=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(job.id))).toString('hex').slice(0,12);
 assert.equal(await episodePath(job),`/podcasts/episodes/the-nut-sisters-${suffix}`);
 assert.equal((await episodePath({...job,title:'Changed title'})).slice(-12),suffix);
 assert.notEqual(await episodePath({...job,id:job.id.toLowerCase()}),await episodePath(job));
 assert.equal(episodeLocation('/podcasts/episodes/any-slug-'+suffix,''),'any-slug-'+suffix);
 assert.equal(episodeLocation('/podcasts/episodes/any-slug-'+suffix,'#translator'),null);
 assert.equal(episodeLocation('/podcasts/episodes/any-slug-'+suffix,'#podcasts'),null);
 assert.equal(episodeLocation('/podcasts/episodes/any-slug-ABCDEF123456',''),null);
});

test('partial transcripts count saved translations, never job stage percentages',()=>{
 const segments=Array.from({length:1000},(_,i)=>({start:i,end:i+1,text:'saved source',...(i<954?{translation:'saved target'}:{})}));
 assert.deepEqual(transcriptStats({state:'translating',progress:91,segments}),{recognized:1000,translated:954,pending:46});
});

test('owner-scoped reads coalesce and stale results never revive after identity change',async()=>{
 let release;const calls=[];const client=createEpisodeClient({api:{request(path,options){calls.push({path,options});return new Promise(resolve=>release=resolve);}}});
 client.identity({user:{id:'one'},csrf_token:'csrf'});
 const first=client.resolve('title-a1b2c3d4e5f6'),second=client.resolve('title-a1b2c3d4e5f6');
 assert.equal(calls.length,1);assert.equal(calls[0].path,'/v1/podcasts/episodes/title-a1b2c3d4e5f6');
 assert.equal(calls[0].options.method,'GET');
 client.identity(null);release({id:'private'});
 await assert.rejects(first,{name:'AbortError'});await assert.rejects(second,{name:'AbortError'});
 assert.equal(calls[0].options.signal.aborted,true);
 assert.equal(calls.some(c=>c.options.method==='POST'),false);
});
