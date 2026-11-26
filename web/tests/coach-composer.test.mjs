import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture} from './coach-mount-fixture.mjs';

const snapshot={turns:[],observations:[]};
test('a late send cannot focus the composer after owner changes away and back',async()=>{
 let release;
 const f=fixture({request:async(_,options)=>options?.body?.action==='message'?await new Promise(r=>release=r):snapshot});
 f.controller.identity(f.session);await f.show();
 const input=f.host.querySelector('textarea');input.value='old draft';input.focus();
 const pending=f.host.querySelector('form').onsubmit({preventDefault(){}});
 f.controller.identity(null);f.controller.identity(f.session);await f.flush();
 const other=f.host.querySelector('.coach-menu-trigger');other.focus();input.value='new owner-era draft';
 release(snapshot);await pending;await f.flush();
 assert.equal(input.value,'new owner-era draft');assert.equal(f.doc.activeElement,other);
});
test('successful send keeps a newer draft and does not steal an opened menu focus',async()=>{
 let release;
 const f=fixture({request:async(_,options)=>options?.body?.action==='message'?await new Promise(r=>release=r):snapshot});
 f.controller.identity(f.session);await f.show();
 const input=f.host.querySelector('textarea');input.value='sent draft';input.focus();
 const pending=f.host.querySelector('form').onsubmit({preventDefault(){}});
 input.value='newer draft';const other=f.host.querySelector('.coach-menu-trigger');other.focus();
 release(snapshot);await pending;await f.flush();
 assert.equal(input.value,'newer draft');assert.equal(f.doc.activeElement,other);
});
