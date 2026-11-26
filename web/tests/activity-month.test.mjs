import test from 'node:test';
import assert from 'node:assert/strict';
import * as activity from '../coach-activity.mjs';
test('whole local months include leap day and locale padding',()=>{
 for(const [year,month,length] of [[2026,1,28],[2024,1,29],[2026,10,30],[2026,2,31]]) {
  const m=activity.activityMonth(new Date(year,month,15),'de');
  assert.equal(m.dates.length,length);assert.match(m.dates[0],/-01$/);
  assert.equal(m.offset,(new Date(year,month,1).getDay()+6)%7);
 }
});
test('fixed count scale does not turn missing evidence into zero',()=>{
 assert.equal(activity.activityIntensity(undefined),'unknown');
 assert.equal(activity.activityIntensity({known_count:0}),'none');
 assert.deepEqual([1,2,3,5,9,10,200].map(n=>activity.activityIntensity({known_count:n})),['1','1','2','3','3','4','4']);
});
test('authentication failure wipes previously retained private evidence',async()=>{
 let fail=false;const s=activity.createActivityState({request:async()=>{if(fail)throw Object.assign(Error(),{status:401});return {days:[{known_count:3}]};}},()=>{});
 await s.load('a','2026-11-01','UTC');fail=true;s.invalidate();await s.load('a','2026-11-01','UTC');assert.equal(s.value,null);
});
test('old server weeks merge bounded dates without duplicating global undated',async()=>{
 const calls=[];const s=activity.createActivityState({request:async(u)=>{const q=new URL('http://local'+u).searchParams;calls.push(q.get('start'));return {days:Array.from({length:7},(_,i)=>{const d=new Date(q.get('start')+'T12:00:00');d.setDate(d.getDate()+i);return {date:activity.localDate(d),known_count:1};}),sources:{coach:'retained'},undated:2};}},()=>{});
 await s.load('a','2026-03-01','Europe/Berlin','',31);assert.equal(calls.length,5);assert.equal(s.value.days.length,31);assert.equal(s.value.undated,2);assert.equal(s.value.days.at(-1).date,'2026-03-31');
});
test('aborted previous month and late failure cannot overwrite current month',async()=>{
 const pending=[];const s=activity.createActivityState({request:(u,o)=>new Promise((resolve,reject)=>pending.push({u,o,resolve,reject}))},()=>{});
 const a=s.load('a','2026-10-01','UTC','',31);const b=s.load('a','2026-11-01','UTC','',30);assert.equal(pending[0].o.signal.aborted,true);
 pending[1].resolve({days:[{date:'2026-11-01',known_count:4}]});await b;pending[0].reject(Error('old failure'));await a;assert.equal(s.error,false);assert.equal(s.value.days[0].date,'2026-11-01');
 s.clear();assert.equal(pending[1].o.signal.aborted,true);assert.equal(s.value,null);
});
test('invalid response and timezone mismatch never replace saved evidence',async()=>{
 for(const value of [null,{}, {time_zone:'wrong',days:[]}]) {
 const s=activity.createActivityState({request:async()=>value},()=>{});await s.load('a','2026-11-01','UTC','',30);assert.equal(s.error,true);assert.equal(s.value,null);
 }
});
test('range request and same-scope refresh failure retain known evidence',async()=>{
 let fail=false,url,options;const s=activity.createActivityState({request:async(u,o)=>{url=u;options=o;if(fail)throw Error('offline');return {days:[{date:'2026-11-01',known_count:3}]};}},()=>{});
 await s.load('a','2026-11-01','UTC','',30);assert.match(url,/days=30/);assert.ok(options.signal);
 fail=true;s.invalidate();await s.load('a','2026-11-01','UTC','',30);assert.equal(s.value.days[0].known_count,3);assert.equal(s.error,true);
});
