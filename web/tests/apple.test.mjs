import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import * as core from '../core.mjs';

test('Apple web starts with same-origin CSRF POST, then navigates only to Apple', async () => {
 const calls=[];
 const url='https://appleid.apple.com/auth/authorize?client_id=de.keinemagie.web&response_type=code';
 const api=core.createAPI(async(path,options)=>{calls.push({path,options});return {ok:true,status:200,json:async()=>({authorization_url:url})};});
 assert.equal(typeof core.startAppleLogin,'function');
 assert.equal(await core.startAppleLogin(api,'bootstrap-csrf'),url);
 assert.equal(calls[0].path,'/v1/auth/apple/start');
 assert.equal(calls[0].options.method,'POST');
 assert.equal(calls[0].options.credentials,'same-origin');
 assert.equal(calls[0].options.headers['X-CSRF-Token'],'bootstrap-csrf');
 for(const bad of ['https://evil.invalid/auth/authorize','https://appleid.apple.com.evil.invalid/auth/authorize','https://user@appleid.apple.com/auth/authorize','http://appleid.apple.com/auth/authorize','https://appleid.apple.com/other']) {
  await assert.rejects(()=>core.startAppleLogin({request:async()=>({authorization_url:bad})},'csrf'));
 }
 const app=await readFile(new URL('../app.mjs',import.meta.url),'utf8');
 assert.match(app,/await startAppleLogin\(api, boot.csrf_token\)/);
 assert.doesNotMatch(app,/\/v1\/web\/auth\/apple\/start/);
});
