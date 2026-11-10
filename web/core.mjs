export function readiness(session) {
  if (!session?.user?.id) return 'signed-out';
  if (typeof session.csrf_token !== 'string' || !session.csrf_token) return 'session-unavailable';
  if (session.provider?.connected !== true) return 'provider-required';
  return typeof session.provider.selected_model === 'string' && session.provider.selected_model.trim() ? 'ready' : 'model-unavailable';
}

export function validDirection(source, target) {
  return (source === 'de' && ['ru', 'de'].includes(target)) || (source === 'ru' && target === 'de');
}

export function inputPayload(text, source, instructions = '', target = source === 'de' ? 'ru' : 'de') {
  text = text.trim();
  if (!text || [...text].length > 8000) throw new Error('Enter text between 1 and 8000 characters.');
  if (!validDirection(source, target)) throw new Error('Unsupported language direction.');
  if (typeof instructions !== 'string' || [...instructions].length > 1000) throw new Error('Instructions must be at most 1000 characters.');
  return { text, source_language: source, target_language: target, ...(instructions ? { instructions } : {}) };
}

export const translationPresets = Object.freeze([
  { id: 'friendly', name: 'Freundlich', instructions: 'Use a friendly, warm and natural tone while preserving the original meaning.' },
  { id: 'formal', name: 'Formell', instructions: 'Use a formal, professional tone and appropriate polite forms of address while preserving the original meaning.' }
]);

export function promptStore(storage, ownerID) {
  if (typeof ownerID !== 'string' || !ownerID) throw new Error('A verified account ID is required.');
  const key = `keinemagie:translation-prompts:v1:${encodeURIComponent(ownerID)}`;
  const valid = item => item && typeof item.id === 'string' && /^custom-[a-zA-Z0-9-]+$/.test(item.id) && typeof item.name === 'string' && item.name.trim() && [...item.name].length <= 60 && typeof item.instructions === 'string' && item.instructions.trim() && [...item.instructions].length <= 1000;
  const clean = ({id, name, instructions}) => ({id, name, instructions});
  const list = () => {
    try {
      const value = JSON.parse(storage.getItem(key));
      return Array.isArray(value) ? value.filter(valid).map(clean).filter((item, index, all) => all.findIndex(other => other.id === item.id) === index).slice(0, 50) : [];
    } catch { return []; }
  };
  return {
    list,
    save(item) {
      // Project explicitly onto nonsecret text fields; never serialize session state.
      item = clean(item);
      item.name = item.name.trim();
      if (!valid(item)) throw new Error('Invalid shortcut.');
      const items = list().filter(existing => existing.id !== item.id);
      if (items.length >= 50) throw new Error('At most 50 shortcuts.');
      storage.setItem(key, JSON.stringify([...items, item]));
      return item;
    },
    remove(id) { storage.setItem(key, JSON.stringify(list().filter(item => item.id !== id))); }
  };
}

export function swapDraft(source, text, translation, target = source === 'de' ? 'ru' : 'de') {
  return { source: target, target: source, text: translation || text };
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
