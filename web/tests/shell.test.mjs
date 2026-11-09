import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('web shell provides accessible translation, four workflows and no remote executable dependencies', async () => {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  for (const id of ['translator', 'dictation', 'podcasts', 'coach', 'source-text', 'source-language', 'target-language', 'swap', 'result', 'history-list', 'idioms', 'patterns', 'vocabulary', 'account-dialog']) {
    assert.match(html, new RegExp(`id="${id}"`), id);
  }
  assert.match(html, /aria-live="polite"/);
  assert.match(html, /<label[^>]*for="source-text"/);
  assert.doesNotMatch(html, /(?:src|href)="https?:/);
  const js = await readFile(new URL('../app.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(js, /localStorage|sessionStorage|innerHTML|Bearer/);
});
