import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('minimal translator keeps accessible controls and history without planned features or remote code', async () => {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  for (const id of ['translator', 'source-text', 'source-language', 'target-language', 'swap', 'result', 'history-list', 'account-dialog', 'translate', 'cancel', 'copy', 'clear']) {
    assert.match(html, new RegExp(`id="${id}"`), id);
  }
  assert.match(html, /aria-live="polite"/);
  assert.match(html, /<label[^>]*for="source-text"/);
  assert.doesNotMatch(html, /(?:src|href)="https?:/);
  assert.doesNotMatch(html, /class="navigation"|id="(?:dictation|podcasts|coach|idioms|patterns|vocabulary)"|page-heading|page-footer|empty-result|connection-banner/);
  const js = await readFile(new URL('../app.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(js, /localStorage|sessionStorage|innerHTML|Bearer/);
  assert.doesNotMatch(js, /\$\('(?:idioms|patterns|vocabulary|model-note)'\)|function route\(/);
});
