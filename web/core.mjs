// Only called by an explicit copy action. Preserve the exact result, never HTML.
export async function copyText(text) {
  if (typeof text !== 'string' || !text.length) throw new Error('Empty clipboard text');
  if (globalThis.isSecureContext && globalThis.navigator?.clipboard?.writeText) {
    try { await navigator.clipboard.writeText(text); return; } catch { /* use legacy copy */ }
  }
  const active = document.activeElement;
  const inputSelection = active && typeof active.selectionStart === 'number' ? [active.selectionStart, active.selectionEnd, active.selectionDirection] : null;
  const selection = document.getSelection();
  const ranges = selection ? Array.from({length:selection.rangeCount}, (_, i) => selection.getRangeAt(i).cloneRange()) : [];
  const scroll = [window.scrollX, window.scrollY];
  const textarea = document.createElement('textarea');
  textarea.value = text; textarea.readOnly = true;
  textarea.setAttribute('aria-hidden', 'true');
  textarea.style.cssText = 'position:fixed;top:0;left:0;width:1px;height:1px;opacity:0;pointer-events:none;font-size:16px';
  document.body.append(textarea);
  try {
    textarea.focus({preventScroll:true}); textarea.select(); textarea.setSelectionRange(0, text.length);
    if (!document.execCommand('copy')) throw new Error('Clipboard denied');
  } finally {
    textarea.remove();
    active?.focus({preventScroll:true});
    if (selection) { selection.removeAllRanges(); for (const range of ranges) selection.addRange(range); }
    if (inputSelection) active.setSelectionRange(...inputSelection);
    window.scrollTo(...scroll);
  }
}

export function readiness(session) {
  if (!session?.user?.id) return 'signed-out';
  if (typeof session.csrf_token !== 'string' || !session.csrf_token) return 'session-unavailable';
  if (!session.provider) return 'provider-loading';
  if (session.provider.connected !== true) return 'provider-required';
  return typeof session.provider.selected_model === 'string' && session.provider.selected_model.trim() ? 'ready' : 'model-unavailable';
}

export function validDirection(source, target) {
  return (source === 'de' && ['ru', 'de'].includes(target)) || (source === 'ru' && target === 'de');
}

export function inputPayload(text, source = 'ru', instructions = '', target = source === 'de' ? 'ru' : 'de') {
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
      const vocabularyQuery = /^\/v1\/learning\/vocabulary\?language=(?:de|ru)&job_id=[A-Za-z0-9_-]{1,200}$/.test(path);
      if ((!/^\/v1\/[A-Za-z0-9/_-]+$/.test(path) && !vocabularyQuery) || path.split('/').some(part => part === '.' || part === '..')) throw new Error('Only same-origin API paths are allowed');
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
        error.remaining = Number.isInteger(value?.remaining) ? value.remaining : undefined;
        error.retry_after = Number.isInteger(value?.retry_after) ? value.retry_after : undefined;
        error.limits = value?.limits && typeof value.limits === 'object' ? value.limits : null;
        throw error;
      }
      if (value === null) throw new Error('The server returned an invalid response.');
      return value;
    }
  };
}

// Owner-scoped in-memory library. No credentials, URLs or transcripts are persisted.
export function createPodcasts({api, changed = () => {}, unauthorized = () => {}, visible = () => true, schedule = setTimeout, unschedule = clearTimeout} = {}) {
  const state = {phase:'guest', feeds:[], jobs:[], limits:null, worker:false, error:'', pending:new Set(), route:{kind:'library'}};
  let session = null, epoch = 0, active = false, timer = null, rounds = 0, loading = null;
  const controllers = new Set();
  function stop() { unschedule(timer); timer = null; }
  function emit() { changed(state); }
  function identity(value) {
    if (session?.user?.id !== value?.user?.id) {
      epoch++; inflight.clear(); detailCache.clear(); stop(); controllers.forEach(c => c.abort()); controllers.clear(); loading = null;
      state.feeds = []; state.jobs = []; state.pending = new Set(); state.error = ''; state.worker = false;
      state.limits = null;
      state.phase = value?.user?.id ? 'idle' : 'guest'; rounds = 0;
    }
    session = value; emit();
  }
  async function request(path, options = {}) {
    if (!session?.user?.id) throw new Error('Sign in required');
    const run = epoch, controller = new AbortController(); controllers.add(controller);
    try {
      const value = await api.request(path, {...options, csrf:session.csrf_token, signal:controller.signal});
      if (run !== epoch) throw new DOMException('Stale account', 'AbortError');
      return value;
    } catch (error) {
      if (run === epoch && error.status === 401) { identity(null); unauthorized(error); }
      throw error;
    } finally { controllers.delete(controller); }
  }
  async function load() {
    if (!session?.user?.id) return;
    if (loading) return loading;
    const run = epoch;
    state.phase = state.phase === 'loaded' ? 'loaded' : 'loading'; state.error = ''; emit();
    const task = (async () => {
      try {
        const [feeds,jobs] = await Promise.all([request('/v1/podcasts/subscriptions'), request('/v1/podcasts')]);
        if (run !== epoch) return;
        if (!Array.isArray(feeds.items) || !Array.isArray(jobs.items)) throw new Error('Invalid library');
        state.feeds = feeds.items; state.jobs = jobs.items.map(job=>{const prior=state.jobs.find(j=>j.id===job.id);return prior?.segments&&!job.segments?{...prior,...job}:job;});
        if(state.route.kind==='job'&&!state.jobs.some(j=>j.id===state.route.id)){const detailJob=detailCache.get(state.route.id);if(detailJob)state.jobs.push(detailJob);} state.worker = jobs.worker_available === true; state.phase = 'loaded';
        state.limits = jobs.limits || null;
      } catch (error) { if (run === epoch) { state.error = podcastError(error); if (state.phase !== 'loaded') state.phase = 'error'; } }
      finally { if (run === epoch) { loading = null; emit(); poll(); } }
    })();
    loading = task; return task;
  }
  function poll() { stop(); if (active && visible() && session && !state.error && rounds < 120 && state.jobs.some(j => isActive(j))) timer = schedule(async () => { rounds++; await load(); }, 5000); }
  async function activate(hash) {
    active = hash === '#podcasts' || hash.startsWith('#podcasts/'); stop();
    state.route = parsePodcastRoute(hash); emit();
    if (active && visible()) {
      rounds = 0;
      if(state.route.kind==='job'&&session?.user?.id){
        const id=state.route.id;
        // Detail is usable independently of slow feed/library context.
        const context=load();
        await detail(id);
        void context;
      } else await load();
    }
  }
  function pause() { active = false; stop(); }
  function preparation(feed, episode) { return state.jobs.find(j => j.feed_id === feed.id && j.episode_id === episode.id) || episode.preparation || null; }
  function directJobs() {
    const linked = new Set(state.feeds.flatMap(f => (f.episodes || []).map(e => e.preparation?.id).filter(Boolean)));
    return state.jobs.filter(j => !j.feed_id && !j.episode_id && !linked.has(j.id));
  }
  const inflight = new Map();
  function mutation(key, path, options, project = value => value) {
    if (inflight.has(key)) return inflight.get(key);
    const run = epoch; state.pending.add(key); state.error = ''; emit();
    const task = request(path, options).then(value => {
      if (run !== epoch) throw new DOMException('Stale account', 'AbortError');
      return project(value);
    }).catch(error => { if (run === epoch && error.name !== 'AbortError') state.error = podcastError(error); throw error; })
      .finally(() => { if (inflight.get(key) === task) inflight.delete(key); if (run === epoch) { state.pending.delete(key); emit(); poll(); } });
    inflight.set(key,task); return task;
  }
  function saveJob(job) { state.jobs = [job, ...state.jobs.filter(j => j.id !== job.id)]; return job; }
  function prepare(feed_id, episode_id, source_language = 'de') {
    return mutation(`${session?.user?.id}:prepare:${feed_id}:${episode_id}`, '/v1/podcasts', {method:'POST',body:{feed_id,episode_id,source_language}}, saveJob);
  }
  const detailCache=new Map();
  async function detail(id) {
    const value = await request(`/v1/podcasts/${apiID(id)}`); detailCache.set(id,value); saveJob(value); emit(); return value;
  }
  return {state, identity, activate, pause, load, preparation, directJobs, prepare, detail,
    importURL(url,source_language='de') { return mutation(`${session?.user?.id}:import:${url}`, '/v1/podcasts', {method:'POST',body:{url,source_language}}, saveJob); },
    subscribe(url) { return mutation(`${session?.user?.id}:subscribe`, '/v1/podcasts/subscriptions', {method:'POST',body:{url}}, value => value); },
    refresh(id) { return mutation(`${session?.user?.id}:refresh:${id}`, `/v1/podcasts/subscriptions/${apiID(id)}/refresh`, {method:'POST',body:{}}); },
    unsubscribe(id) { return mutation(`${session?.user?.id}:unsubscribe:${id}`, `/v1/podcasts/subscriptions/${apiID(id)}`, {method:'DELETE'}); },
    jobAction(id,action) {
      if (!['retry','cancel','delete'].includes(action)) throw new Error('Invalid action');
      return mutation(`${session?.user?.id}:${action}:${id}`, `/v1/podcasts/${apiID(id)}${action === 'delete' ? '' : '/'+action}`, {method:action === 'delete'?'DELETE':'POST', ...(action === 'delete'?{}:{body:{}})}, value => { if (action === 'delete') state.jobs = state.jobs.filter(j => j.id !== id); else saveJob(value); return value; });
    },
    dispose() { pause(); identity(null); },
  };
}

export function apiID(id) { if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,200}$/.test(id)) throw new Error('Invalid identifier'); return id; }
export function parsePodcastRoute(hash) {
  if (hash === '#podcasts') return {kind:'library'};
  const match = /^#podcasts\/(feed|job)\/([^/]+)$/.exec(hash);
  if (!match) return {kind:'invalid'};
  try { const id = decodeURIComponent(match[2]); return /^[A-Za-z0-9_-]{1,200}$/.test(id) ? {kind:match[1],id} : {kind:'invalid'}; } catch { return {kind:'invalid'}; }
}
export const podcastRoute = (kind,id) => `#podcasts/${kind}/${encodeURIComponent(id)}`;
export const isActive = job => ['queued','fetching','transcribing','translating'].includes(job.state);
export function podcastError(error) {
  if (error.status === 401) return 'Deine Sitzung ist abgelaufen. Bitte erneut anmelden.';
  if (error.status === 429) {
    const reasons = {
      podcast_daily_limit: 'Alle 4 Podcast-Vorbereitungen für heute wurden verbraucht, auch fehlgeschlagene oder gelöschte. Zurücksetzung um 00:00 UTC. Das persönliche Übersetzungsbudget ist davon getrennt.',
      podcast_active_limit: 'Bereits 2 aktive Podcast-Vorbereitungen. Warte oder brich eine davon ab.',
      podcast_storage_limit: 'Bereits 30 Folgen gespeichert. Lösche eine nicht mehr benötigte inaktive Vorbereitung.',
      podcast_global_active_limit: 'Die Warteschlange ist voll. Bitte nach Abschluss laufender Vorbereitungen erneut versuchen.',
      podcast_global_storage_limit: 'Der Serverspeicher für Podcasts ist voll. Bitte die Administration kontaktieren.'
    };
    return reasons[error.code] || 'Zu viele Anfragen. Bitte später erneut versuchen.';
  }
  if (error.status === 400) return 'Diese Quelle ist nicht verfügbar. Nutze einen öffentlichen RSS-/Atom-Feed oder eine Folge mit direktem Audio, ohne Anmeldung oder signierte URL.';
  if (error.status === 403) return 'Anfrage nicht autorisiert. Bitte die Sitzung erneut prüfen.';
  if (error.status === 404) return 'Dieser Podcast ist nicht mehr verfügbar.';
  if (error.status === 409) return 'Aktion in diesem Zustand nicht möglich. Bitte aktualisieren.';
  if (error.status === 503) return 'Vorbereitung derzeit nicht verfügbar. Bitte Worker und persönliche ChatGPT-Verbindung im Konto prüfen.';
  return 'Podcasts konnten nicht geladen werden. Bitte erneut versuchen.';
}
export function reconcileDOM(target,next){
  for(const attr of [...target.attributes])if(!next.hasAttribute(attr.name)&&!(target.tagName==='DETAILS'&&attr.name==='open'))target.removeAttribute(attr.name);
  for(const attr of [...next.attributes])if(target.getAttribute(attr.name)!==attr.value)target.setAttribute(attr.name,attr.value);
  for(const key of ['onclick','onchange','onsubmit','ontoggle'])target[key]=next[key];
  if(target.tagName==='SELECT'){if(document.activeElement!==target)target.value=next.value;[...target.options].forEach((option,index)=>{if(next.options[index])option.textContent=next.options[index].textContent;});return;}
  if(['INPUT','TEXTAREA'].includes(target.tagName))return;
  if(target.tagName==='DETAILS'&&target.querySelector('form')){target.querySelector('summary').textContent=next.querySelector('summary').textContent;return;}
  const children=[...next.childNodes];
  children.forEach((child,index)=>{
   const key=child.nodeType===1&&(child.dataset.key||child.id);
   if(key){const match=[...target.children].find(el=>(el.dataset.key||el.id)===key);if(match&&match!==target.childNodes[index])target.insertBefore(match,target.childNodes[index]||null);}
   const old=target.childNodes[index];if(!old){target.append(child);return;}if(old.nodeType!==child.nodeType||old.nodeName!==child.nodeName||old.id!==child.id||(old.nodeType===1&&old.dataset.key!==child.dataset.key)){old.replaceWith(child);return;}if(child.nodeType===3){if(old.textContent!==child.textContent)old.textContent=child.textContent;}else reconcileDOM(old,child);});
  while(target.childNodes.length>children.length)target.lastChild.remove();
 }
