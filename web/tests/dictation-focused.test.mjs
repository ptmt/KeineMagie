import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture,record} from './dictation-mount-fixture.mjs';
test('uncached exercise has one audio action, visible paid disclosure and secondary attempt menu',async()=>{
 const value={...record(),ready:[]};
 const f=fixture({request:async path=>path.endsWith('/one')?value:{items:[value]}});
 await f.start();await f.click('Test one · In progress');
 const controls=f.host.all().find(e=>e.className==='dictation-player');
 assert.ok(controls,'focused player');
 assert.equal(controls.all().filter(e=>e.tagName==='BUTTON'&&!e.hidden).length,1);
 assert.match(f.host.textContent,/Via OpenAI API · paid/);
 const more=f.host.all().find(e=>e.className==='dictation-attempt-menu');
 assert.ok(more.all().includes(f.button('Delete attempt')));
 assert.equal(f.requests.filter(r=>r.method==='POST').length,0);
 f.controller.identity(null);
});
test('missing cached media returns to explicit paid preparation, never auto-retries',async()=>{
 const f=fixture({request:async(path,options)=>{if(options.method==='HEAD')throw Object.assign(Error('missing'),{status:404});return path.endsWith('/one')?record():{items:[record()]};}});
 await f.start();await f.click('Test one · In progress');await f.click('Play');await f.media[0].onerror();
 assert.ok(f.button('Prepare audio'));
 assert.equal(f.requests.filter(r=>r.method==='POST').length,0);
 f.controller.identity(null);
});
