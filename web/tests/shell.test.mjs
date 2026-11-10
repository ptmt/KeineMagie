import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const js = await readFile(new URL('../app.mjs', import.meta.url), 'utf8');

test('minimal translator keeps accessible controls and history without enrichment panels or remote code', () => {
  for (const id of ['translator', 'source-text', 'source-language', 'target-language', 'swap', 'result', 'history-list', 'account-dialog', 'translate', 'cancel', 'copy', 'clear']) {
    assert.match(html, new RegExp(`id="${id}"`), id);
  }
  assert.match(html, /aria-live="polite"/);
  assert.match(html, /<label[^>]*for="source-text"/);
  assert.doesNotMatch(html, /(?:src|href)="https?:/);
  assert.doesNotMatch(html, /id="(?:idioms|patterns|vocabulary)"|page-heading|page-footer|empty-result|connection-banner|<aside/);
  assert.doesNotMatch(js, /sessionStorage|innerHTML|Bearer/);
  assert.match(js, /promptStore\(window.localStorage, session.user.id\)/);
  assert.doesNotMatch(js, /localStorage\.(?:setItem|getItem)/);
  assert.doesNotMatch(js, /\$\('(?:idioms|patterns|vocabulary|model-note)'\)/);
});

test('initial HTML is locked before scripts resolve and offers official in-place Apple sign-in', () => {
 for (const id of ['source-text','source-language','target-language','swap','clear','add-prompt','translate']) assert.match(html,new RegExp(`<[^>]+id="${id}"[^>]*\\sdisabled(?:\\s|>)`),id);
 assert.match(html, /id="connection-action"[^>]*>[\s\S]*?src="\.\/apple-sign-in-de.png"/);
 assert.match(html, /id="connection-action-art"[^>]*hidden/);
});

test('header contains real section routes with honest unavailable pages', () => {
  const header = html.match(/<header[\s\S]*?<\/header>/)[0];
  assert.match(header, /<nav[^>]*aria-label="Bereiche"/);
  for (const [route, label] of [['translator', 'Übersetzer'], ['dictation', 'Diktat'], ['podcasts', 'Podcasts'], ['coach', 'Coach']]) {
    assert.match(header, new RegExp(`<a href="#${route}"[^>]*>${label}</a>`));
    assert.match(html, new RegExp(`<section id="${route}"`));
    if (route !== 'translator') assert.match(html, new RegExp(`<section id="${route}"[^>]*hidden[^>]*>[\\s\\S]*?<h1[^>]*>${label}</h1>\\s*<p[^>]*>Noch nicht verfügbar</p>\\s*</section>`));
  }
  assert.match(js, /addEventListener\('hashchange'/);
  assert.match(js, /aria-current/);
});
