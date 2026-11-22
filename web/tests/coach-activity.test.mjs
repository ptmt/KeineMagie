import test from 'node:test';import assert from 'node:assert/strict';
import {activityWeek,createActivityState,activityDetails} from '../coach-activity.mjs';
test('locale calendar week uses local dates across DST and Sunday',()=>{
 assert.equal(activityWeek(new Date(2026,10,22,12),'en-US')[0],'2026-11-22');
 assert.equal(activityWeek(new Date(2026,10,22,12),'de')[0],'2026-11-16');
 assert.equal(activityWeek(new Date(2026,2,29,12),'de')[6],'2026-03-29');
});
test('a different owner/week/timezone clears old values before awaiting a response',async()=>{
 let release;const s=createActivityState({request:async()=>release?await new Promise(r=>release=r):{days:[{known_count:3}]}},()=>{});
 await s.load('a','2026-11-16','UTC');release=true;const pending=s.load('a','2026-11-16','Europe/Berlin');assert.equal(s.value,null);release({days:[]});await pending;
});
test('late previous owner cannot repopulate activity; unavailable is not zero',async()=>{
 const pending=[];const s=createActivityState({request:(url)=>new Promise(r=>pending.push({url,r}))},()=>{});
 const a=s.load('a','2026-11-16','Europe/Berlin');const b=s.load('b','2026-11-16','Europe/Berlin');
 pending[1].r({days:[{date:'2026-11-16',known_count:2}],sources:{podcasts:'unsupported'}});await b;
 pending[0].r({days:[{known_count:99}]});await a;assert.equal(s.value.days[0].known_count,2);
 s.clear();assert.equal(s.value,null);
 assert.match(activityDetails({date:'2026-11-16',known_count:2,counts:{coach:2,podcasts:0}},{sources:{coach:'retained',podcasts:'unsupported'},undated:1},'en'),/Podcasts: Not supported/);
});
