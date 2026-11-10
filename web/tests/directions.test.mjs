import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as core from '../core.mjs';

test('German proofreading submits equal languages with the selected style', () => {
  assert.deepEqual(core.inputPayload(' Ich habe ein frage. ', 'de', 'Bitte formell.', 'de'), {
    text: 'Ich habe ein frage.', source_language: 'de', target_language: 'de', instructions: 'Bitte formell.'
  });
  assert.throws(() => core.inputPayload('Text', 'ru', '', 'ru'), /language/i);
  assert.throws(() => core.inputPayload('Text', 'de', '', 'en'), /language/i);
});

test('direction validation accepts only the two translations and German proofreading', () => {
  for (const [source, target] of [['de', 'ru'], ['ru', 'de'], ['de', 'de']]) assert.equal(core.validDirection(source, target), true);
  for (const [source, target] of [['ru', 'ru'], ['de', 'en'], ['en', 'de'], ['', 'de']]) assert.equal(core.validDirection(source, target), false);
});

test('swapping German proofreading keeps the direction and reuses the result', () => {
  assert.deepEqual(core.swapDraft('de', 'draft', 'corrected', 'de'), { source: 'de', target: 'de', text: 'corrected' });
  assert.deepEqual(core.swapDraft('de', 'draft', '', 'de'), { source: 'de', target: 'de', text: 'draft' });
});

test('compact direction selector exposes all three choices with accessible full meanings', () => {
  const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(html, /<select[^>]+id="language-direction"/);
  for (const [value, label] of [['de-ru', 'de → ru'], ['ru-de', 'ru → de'], ['de-de', 'de → de']]) {
    assert.match(html, new RegExp(`<option[^>]+value="${value}"[^>]*>${label}</option>`));
  }
  assert.match(html, /<option[^>]+value="de-de"[^>]+aria-label="Deutsch verbessern"/);
  assert.doesNotMatch(html, /id="(?:source|target)-language"/);
});
