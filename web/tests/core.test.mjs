import test from 'node:test';
import assert from 'node:assert/strict';

test('translation transport uses same-origin cookies and memory-only CSRF, never bearer credentials', async () => {
  const { createAPI } = await import('../core.mjs');
  const calls = [];
  const api = createAPI(async (path, options) => {
    calls.push({ path, options });
    return new Response(JSON.stringify({ translation: 'Test' }), { status: 201 });
  });
  await api.request('/v1/translations', { method: 'POST', body: { text: 'Hallo', source_language: 'de', target_language: 'ru' }, csrf: 'one-time-session-csrf' });
  assert.equal(calls[0].path, '/v1/translations');
  assert.equal(calls[0].options.credentials, 'same-origin');
  assert.equal(calls[0].options.cache, 'no-store');
  assert.equal(calls[0].options.headers['X-CSRF-Token'], 'one-time-session-csrf');
  assert.equal(calls[0].options.headers.Authorization, undefined);
  assert.deepEqual(JSON.parse(calls[0].options.body), { text: 'Hallo', source_language: 'de', target_language: 'ru' });
  await assert.rejects(api.request('https://other.example/v1/translations'), /same-origin/);
});

test('translation readiness fails closed and validates Unicode length and supported directions', async () => {
  const { readiness, inputPayload, swapDraft } = await import('../core.mjs');
  assert.equal(readiness(null), 'signed-out');
  assert.equal(readiness({ user: { id: 'u' }, csrf_token: 'csrf', provider: { connected: false } }), 'provider-required');
  assert.equal(readiness({ user: { id: 'u' }, provider: { connected: true } }), 'session-unavailable');
  assert.equal(readiness({ user: { id: 'u' }, csrf_token: 'csrf', provider: { connected: true, selected_model: 'gpt-6-luna' } }), 'ready');
  assert.deepEqual(inputPayload(' Hallo ', 'de'), { text: 'Hallo', source_language: 'de', target_language: 'ru' });
  assert.throws(() => inputPayload(' ', 'de'), /text/);
  assert.throws(() => inputPayload('x'.repeat(8001), 'de'), /8000/);
  assert.throws(() => inputPayload('Hallo', 'en'), /language/);
  assert.equal(inputPayload('😀'.repeat(8000), 'ru').text.length, 16000);
  assert.deepEqual(swapDraft('de', 'original', 'result'), { source: 'ru', target: 'de', text: 'result' });
  assert.deepEqual(swapDraft('ru', 'original', ''), { source: 'de', target: 'ru', text: 'original' });
});

test('catalog_unavailable preserves connection but withholds translation readiness', async () => {
  const { readiness } = await import('../core.mjs');
  const provider = { connected: true, status: 'catalog_unavailable', message: 'ChatGPT connection saved; model catalog unavailable. Check the connection again.', models: [], selected_model: '' };
  const session = { user: { id: 'u' }, csrf_token: 'csrf', provider };
  assert.equal(readiness(session), 'model-unavailable');
  for (const selected_model of [undefined, null, '', '   ', 123, {}]) {
    assert.equal(readiness({ ...session, provider: { connected: true, selected_model } }), 'model-unavailable');
  }
  assert.equal(readiness({ ...session, provider: { connected: true, selectedModel: 'wrong-field' } }), 'model-unavailable');
  assert.equal(readiness({ ...session, provider: { connected: false, selected_model: 'stale-model' } }), 'provider-required');
  assert.equal(readiness({ ...session, provider: { connected: true, selected_model: 'offered-model' } }), 'ready');
});

test('transport preserves status for expired sessions and never exposes raw upstream errors', async () => {
  const { createAPI } = await import('../core.mjs');
  const api = createAPI(async () => new Response(JSON.stringify({ error: 'private upstream detail', code: 'provider_not_connected' }), { status: 401 }));
  await assert.rejects(api.request('/v1/web/session'), error => error.status === 401 && error.code === 'provider_not_connected' && !error.message.includes('private'));
});

test('provider bootstrap is a CSRF-protected POST, not a guessed remote OAuth redirect', async () => {
  const { startProviderConnection } = await import('../core.mjs');
  const calls = [];
  const value = await startProviderConnection({ request: async (...args) => { calls.push(args); return { bootstrap_token: 'test-fixture', expires_in: 300 }; } }, 'csrf');
  assert.equal(value.bootstrap_token, 'test-fixture');
  assert.deepEqual(calls, [['/v1/provider/connect', { method: 'POST', body: {}, csrf: 'csrf' }]]);
  await assert.rejects(startProviderConnection({ request: async () => ({}) }, 'csrf'), /connection/);
});
