import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {interfaceCatalog,interfaceLocales,resolveInterfaceLanguage,setInterfaceLanguage,getInterfaceLanguage,t} from '../i18n.mjs';
import {episodeMessages} from '../episode-i18n.mjs';
test('all five shell and episode dictionaries have complete nonempty keys and matching parameters',()=>{
 assert.deepEqual(Object.keys(interfaceLocales),['de','en','ru','es','fr']);
 for(const catalog of [interfaceCatalog,episodeMessages])for(const locale of Object.keys(interfaceLocales)){
  assert.deepEqual(Object.keys(catalog[locale]).sort(),Object.keys(catalog.de).sort());
  for(const [key,value]of Object.entries(catalog[locale])){assert.ok(value.trim(),`${locale}:${key}`);assert.deepEqual([...value.matchAll(/\{\w+\}/g)].map(x=>x[0]).sort(),[...catalog.de[key].matchAll(/\{\w+\}/g)].map(x=>x[0]).sort());}
 }
});
test('explicit locale wins; browser regional preferences resolve in order; unsupported defaults German',()=>{
 assert.equal(resolveInterfaceLanguage('fr',['ru-RU']),'fr');
 assert.equal(resolveInterfaceLanguage(null,['ja-JP','ru-RU','en-US']),'ru');
 assert.equal(resolveInterfaceLanguage('invalid',['EN-us']),'en');
 assert.equal(resolveInterfaceLanguage(null,['zh-CN']),'de');
 assert.equal(resolveInterfaceLanguage(null,[]),'de');
});
test('locale changes never alter unknown user content, invalid preferences or interpolation values',()=>{
 for(const locale of Object.keys(interfaceLocales)){assert.equal(setInterfaceLanguage(locale),true);assert.equal(t('user custom instruction'),'user custom instruction');assert.ok(t('{source} → {target} · Gespeichert',{source:'ru',target:'de'}).startsWith('ru → de'));}
 assert.equal(setInterfaceLanguage('it'),false);assert.equal(getInterfaceLanguage(),'fr');setInterfaceLanguage('de');
});
test('UI module ships through exact static allowlist and Docker copy',async()=>{
 const server=await readFile(new URL('../../server/static.go',import.meta.url),'utf8');
 const docker=await readFile(new URL('../../server/Dockerfile',import.meta.url),'utf8');
 assert.match(server,/case "\/i18n\.mjs"/);assert.match(docker,/web\/i18n\.mjs/);
});
