import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const css=readFileSync(new URL('../styles.css',import.meta.url),'utf8');
test('direction immediately precedes panels and compact style links belong below first textarea',()=>{
 assert.match(html,/<\/div>\s*<div class="translation-panels">/);
 const input=html.slice(html.indexOf('<div class="input-panel">'),html.indexOf('<div class="output-panel">'));
 assert.ok(input.indexOf('id="style-controls"')>input.indexOf('</textarea>'));
 assert.ok(!html.slice(0,html.indexOf('<div class="translation-panels">')).includes('id="style-controls"'));
 assert.match(css,/\.style-chip\{[^}]*border:0/);
 assert.match(css,/\.style-chip\[aria-pressed="true"\]\{[^}]*background:transparent/);
});
test('programmatic route panels suppress only their own outline, controls retain visible focus',()=>{
 assert.match(css,/main>section\[tabindex="-1"\]:focus\{outline:none\}/);
 assert.match(css,/button:focus-visible[^}]*outline:3px solid/);
 assert.doesNotMatch(css,/\*:focus[^}]*outline:none/);
});
