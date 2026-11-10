export function readiness(session) {
  if (!session?.user?.id) return 'signed-out';
  if (typeof session.csrf_token !== 'string' || !session.csrf_token) return 'session-unavailable';
  if (session.provider?.connected !== true) return 'provider-required';
  return typeof session.provider.selected_model === 'string' && session.provider.selected_model.trim() ? 'ready' : 'model-unavailable';
}

export function inputPayload(text, source) {
  text = text.trim();
  if (!text || [...text].length > 8000) throw new Error('Enter text between 1 and 8000 characters.');
  if (!['de', 'ru'].includes(source)) throw new Error('Unsupported language.');
  return { text, source_language: source, target_language: source === 'de' ? 'ru' : 'de' };
}

export function swapDraft(source, text, translation) {
  return { source: source === 'de' ? 'ru' : 'de', text: translation || text };
}

export async function startProviderConnection(api, csrf) {
  const value = await api.request('/v1/provider/connect', { method: 'POST', body: {}, csrf });
  if (typeof value?.bootstrap_token !== 'string' || !value.bootstrap_token || !Number.isFinite(value.expires_in) || value.expires_in <= 0 || value.expires_in > 300) throw new Error('Invalid provider connection response');
  return value;
}

export async function startBrowserPairing(api, csrf) {
 const value = await api.request('/v1/web/pairing/start', { method: 'POST', body: {}, csrf });
 if (!/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/.test(value?.user_code) || value.expires_in !== 300 || value.interval !== 3) throw new Error('Invalid pairing response');
 return value;
}

export async function startAppleLogin(api, csrf) {
  const value = await api.request('/v1/auth/apple/start', { method: 'POST', body: {}, csrf });
  const url = new URL(value?.authorization_url);
  if (url.origin !== 'https://appleid.apple.com' || url.pathname !== '/auth/authorize' || url.username || url.password || url.hash) throw new Error('Invalid Apple authorization response');
  return url.href;
}

export function createAPI(fetcher = globalThis.fetch.bind(globalThis)) {
  return {
    async request(path, { method = 'GET', body, csrf, signal } = {}) {
      if (!/^\/v1\/[a-z0-9/_-]+$/.test(path)) throw new Error('Only same-origin API paths are allowed');
      const headers = { Accept: 'application/json' };
      if (body !== undefined) headers['Content-Type'] = 'application/json';
      if (csrf) headers['X-CSRF-Token'] = csrf;
      const response = await fetcher(path, { method, headers, credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
      if (response.status === 204) return null;
      const value = await response.json().catch(() => null);
      if (!response.ok) {
        const error = new Error('The request could not be completed.');
        error.status = response.status;
        error.code = typeof value?.code === 'string' ? value.code : '';
        throw error;
      }
      if (value === null) throw new Error('The server returned an invalid response.');
      return value;
    }
  };
}
