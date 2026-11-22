import test from 'node:test';
import assert from 'node:assert/strict';
import {createAPI} from '../core.mjs';
import {createEpisodeClient} from '../episode.mjs';
test('episode mutations bind captured owner independently from UI locale',async()=>{
 let sent;
 const api=createAPI(async(path,options)=>{sent={path,options};return {ok:true,status:200,json:async()=>({})};});
 const client=createEpisodeClient({api});client.identity({user:{id:'alice'},csrf_token:'synthetic'});
 await client.request('studied','/v1/learning/episodes/episode/studied',{method:'PUT',body:{}});
 assert.equal(sent.options.headers['X-Passage-Owner'],'alice');
 assert.equal(sent.options.body,'{}');
});
