import { createPodcasts, podcastRoute, podcastError, isActive, apiID, createAPI, readiness, inputPayload, swapDraft, validDirection, startProviderConnection, startBrowserPairing, startAppleLogin, promptStore, translationPresets } from './core.mjs';

const $ = id => document.getElementById(id);
const api = createAPI();
let session = null;
let config = null;
let record = null;
let history = [];
let busy = false;
let controller = null;
let generation = 0;
let checking = false;
let sessionFlight = null;
let validatedAt = 0;
let sessionError = '';
let providerFlight = null;
const sessionFreshness = 60_000;
const sessionTimeout = 8_000;
let bootstrapTimer = null;
let accountRun = 0;
let pairingTimer = null;
let pairingRun = 0;
function clearPairing() { pairingRun++; clearTimeout(pairingTimer); pairingTimer = null; $('browser-pairing').hidden = true; setText('pairing-code', ''); }

let stylesOwner = null;
let savedPrompts = [];
let selectedInstructions = '';
let editingPrompt = null;
function canEditDraft() { return !!session?.user?.id && !checking && !busy; }
function styleStore() {
  // owner ID comes exclusively from the authenticated /v1/web/session response.
  return promptStore(window.localStorage, session.user.id);
}
function closePrompt() {
  $('prompt-dialog').close(); editingPrompt = null;
  $('prompt-name').value = ''; $('prompt-instructions').value = '';
  setText('prompt-error', ''); setText('prompt-count', '0 / 1.000');
}
function renderStyles() {
  const owner = session?.user?.id || null;
  if (owner !== stylesOwner) {
    closePrompt(); selectedInstructions = ''; savedPrompts = []; stylesOwner = owner;
    if (owner) { try { savedPrompts = styleStore().list(); } catch { /* blocked storage */ } }
  }
  $('style-controls').hidden = false;
  $('style-chips').replaceChildren();
  const choices = [{name:'Standard', instructions:''}, ...translationPresets, ...savedPrompts];
  if (selectedInstructions && !choices.some(item => item.instructions === selectedInstructions)) choices.push({name:'Aus Verlauf', instructions:selectedInstructions});
  for (const item of choices) {
    const button = document.createElement('button'); button.type = 'button'; button.className = 'style-chip';
    button.textContent = item.name; button.disabled = !canEditDraft();
    button.setAttribute('aria-pressed', String(selectedInstructions === item.instructions));
    button.addEventListener('click', () => { if (!canEditDraft() || owner !== session?.user?.id) return; selectedInstructions = item.instructions; renderStyles(); });
    $('style-chips').append(button);
  }
  $('add-prompt').disabled = !canEditDraft();
  $('edit-prompt').hidden = !savedPrompts.some(item => item.instructions === selectedInstructions);
  $('edit-prompt').disabled = !canEditDraft();
}
function openPrompt(item = null) {
  if (!canEditDraft()) return;
  editingPrompt = item?.id || null;
  $('prompt-name').value = item?.name || '';
  $('prompt-instructions').value = item?.instructions || '';
  $('delete-prompt').hidden = !item;
  setText('prompt-error', ''); updatePromptCount();
  $('prompt-dialog').showModal(); $('prompt-name').focus();
}
function updatePromptCount() {
  const count = [...$('prompt-instructions').value].length;
  setText('prompt-count', `${count.toLocaleString('de-DE')} / 1.000`);
  $('save-prompt').disabled = !canEditDraft() || !count || count > 1000 || !$('prompt-name').value.trim() || [...$('prompt-name').value].length > 60;
}
$('add-prompt').addEventListener('click', () => openPrompt());
$('edit-prompt').addEventListener('click', () => openPrompt(savedPrompts.find(item => item.instructions === selectedInstructions)));
$('close-prompt').addEventListener('click', closePrompt);
$('prompt-dialog').addEventListener('cancel', closePrompt);
$('prompt-name').addEventListener('input', updatePromptCount);
$('prompt-instructions').addEventListener('input', updatePromptCount);
$('prompt-form').addEventListener('submit', event => {
  event.preventDefault(); if (!canEditDraft() || !$('prompt-dialog').open) return;
  try {
    const item = styleStore().save({id:editingPrompt || `custom-${crypto.randomUUID()}`, name:$('prompt-name').value, instructions:$('prompt-instructions').value});
    savedPrompts = styleStore().list(); selectedInstructions = item.instructions;
    closePrompt(); renderStyles();
  } catch { setText('prompt-error', 'Speichern nicht möglich. Name (1–60 Zeichen), Anweisungen (1–1.000 Zeichen) und Browser-Speicher prüfen. Maximal 50 eigene Stile.'); }
});
$('delete-prompt').addEventListener('click', () => {
  if (!canEditDraft() || !$('prompt-dialog').open || !editingPrompt) return;
  try { styleStore().remove(editingPrompt); savedPrompts = styleStore().list(); selectedInstructions = ''; closePrompt(); renderStyles(); }
  catch { setText('prompt-error', 'Löschen nicht möglich. Bitte den Browser-Speicher prüfen.'); }
});

const podcasts = mountPodcasts({api, account:() => $('account-dialog').showModal(), unauthorized:handleUnauthorized});
const sectionLinks = [...document.querySelectorAll('.section-nav a')];
let activeSection = 'translator';
function renderRoute(focus = false) {
  // Keep the existing DOM and all requests alive when changing sections.
  // #main belongs to the skip link, not the section router.
  if (location.hash === '#main') return;
  const selected = sectionLinks.find(link => link.hash === location.hash || (link.hash === '#podcasts' && location.hash.startsWith('#podcasts/'))) || sectionLinks[0];
  const next = selected.hash.slice(1);
  for (const link of sectionLinks) {
    $(link.hash.slice(1)).hidden = link !== selected;
    if (link === selected) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  }
  document.title = `Keine Magie · ${selected.textContent}`;
  if (focus && $('account-dialog').open) {
    // Native fragment navigation may move focus outside an open modal.
    if (!$('account-dialog').contains(document.activeElement)) $('close-account').focus({ preventScroll: true });
  } else if (focus && next !== activeSection) $(next).focus({ preventScroll: true });
  activeSection = next;
  if (session?.user?.id && !session.provider && next === 'translator') void loadProvider();
  if (!checking || session?.user?.id) podcasts.route(location.hash);
  else podcasts.pause();
}
window.addEventListener('hashchange', () => renderRoute(true));
renderRoute();


function setText(id, text) { $(id).textContent = text; }
function status(message, error = false) {
  setText('translation-status', message);
  $('translation-status').classList.toggle('error-state', error);
}
function resetResult() {
  record = null;
  $('result').replaceChildren();
  setText('result-caption', '');
  $('copy').disabled = true;
}
function clearPrivateData() {
  generation++;
  validatedAt = 0; providerFlight = null;
  accountRun++;
  clearPairing();
  controller?.abort();
  clearBootstrap();
  session = null; podcasts.identity(null, {checking,config,error:sessionError}); history = []; renderStyles();
  resetResult();
  $('source-text').value = '';
  $('history-list').replaceChildren();
  setText('history-status', 'Melde dich an, um deinen persönlichen Verlauf zu laden.');
}
function clearBootstrap() {
  clearTimeout(bootstrapTimer);
  bootstrapTimer = null;
  $('bootstrap-code').value = '';
  $('provider-bootstrap').hidden = true;
}
function updateInput() {
  renderStyles();
  const count = [...$('source-text').value].length;
  setText('input-count', `${count.toLocaleString('de-DE')} / 8.000`);
  $('input-count').classList.toggle('error-state', count > 8000);
  $('translate').disabled = busy || checking || readiness(session) !== 'ready' || !count || count > 8000;
  const locked = !canEditDraft();
  $('clear').disabled = locked || count === 0;
  $('swap').disabled = locked;
  $('language-direction').disabled = locked;
  $('source-text').disabled = locked;
  $('source-text').readOnly = locked;
  $('prompt-name').disabled = locked;
  $('prompt-instructions').disabled = locked;
  $('delete-prompt').disabled = locked;
  updatePromptCount();
  $('cancel').hidden = !busy;
  $('translation-form').setAttribute('aria-busy', String(busy));
  setText('translate', busy ? 'Wird übersetzt …' : 'Übersetzen ↗');
}
function renderConnection() {
  podcasts.identity(session, {checking,config,error:sessionError});
  const signedIn = !!session?.user?.id;
  const phase = readiness(session);
  const modelUnavailable = phase === 'model-unavailable';
  const catalogWarning = 'Dein ChatGPT-Konto ist verbunden, aber der Modellkatalog ist gerade nicht verfügbar. Bitte die Verbindung erneut prüfen. Eine neue Verbindung ist dafür nicht erforderlich.';
  $('account-indicator').classList.toggle('connected', signedIn);
  setText('account-label', signedIn ? 'Dein Konto' : 'Anmelden');
  setText('account-title', signedIn ? 'Dein Konto' : 'Anmelden');
  $('sign-in-options').hidden = signedIn;
  $('signed-in-account').hidden = !signedIn;
  $('provider-section').hidden = !signedIn;
  $('retry-session').hidden = !signedIn;
  $('apple-login').hidden = signedIn || config?.apple_available === false;
  $('apple-login').disabled = checking || config?.apple_available !== true;
  $('pair-browser').hidden = signedIn || config?.pairing_available !== true;
  $('pair-browser').disabled = checking || config?.pairing_available !== true;
  $('logout').hidden = !signedIn;
  $('provider-connect').disabled = checking || !signedIn || !session?.provider || config?.chatgpt_connect_available !== true || session?.provider?.connected === true;
  $('refresh-history').disabled = checking || !signedIn;
  setText('apple-status', signedIn ? 'Mit Apple angemeldet' : '');
  setText('provider-status', signedIn ? (!session.provider ? 'Verbindung wird geprüft …' : modelUnavailable ? 'Verbunden · Modell nicht verfügbar' : session?.provider?.connected === true ? 'Verbunden' : 'Nicht verbunden') : '');
  if (!signedIn || session?.provider?.connected === true) clearBootstrap();
  setText('provider-detail', !signedIn ? '' : modelUnavailable ? catalogWarning : session?.provider?.connected === true ? 'Dein persönliches ChatGPT-Konto ist verbunden.' : config?.chatgpt_connect_available === true ? 'Verbinde dein eigenes ChatGPT-Konto für Übersetzungen.' : 'Die persönliche ChatGPT-Verbindung ist hier noch nicht verfügbar.');
  $('connection-notice').hidden = !checking && !sessionError && phase === 'ready';
  $('connection-action').hidden = checking;
  const appleSignIn = !checking && !sessionError && !signedIn && config?.apple_available === true;
  $('connection-action').classList.toggle('apple-button', appleSignIn);
  $('connection-action-art').hidden = !appleSignIn;
  $('connection-action-label').hidden = appleSignIn;
  $('translation-form').classList.toggle('sign-in-required', !signedIn);
  setText('connection-action-label', modelUnavailable ? 'Erneut prüfen' : signedIn ? 'Konto öffnen' : 'Anmelden');
  setText('connection-detail', modelUnavailable ? catalogWarning : '');
  if (sessionError) { setText('connection-title', sessionError); setText('connection-action-label', 'Erneut prüfen'); }
  else if (checking) setText('connection-title', 'Sitzung wird geprüft …');
  else if (phase === 'ready') setText('connection-title', 'Bereit zum Übersetzen');
  else if (modelUnavailable) setText('connection-title', 'ChatGPT verbunden · Modell nicht verfügbar.');
  else if (signedIn) setText('connection-title', 'ChatGPT im Konto verbinden.');
  else if (!config) {
    setText('connection-title', 'Anmeldung nicht erreichbar.');
    setText('connection-action-label', 'Erneut prüfen');
  } else if (!config.apple_available && !config.pairing_available) {
    setText('connection-title', 'Anmeldung noch nicht verfügbar.');
    setText('connection-action-label', 'Erneut prüfen');
  } else setText('connection-title', 'Melde dich an, um zu übersetzen.');
  updateInput();
}
function errorMessage(error) {
  if (error.status === 401) return 'Deine Sitzung ist abgelaufen. Bitte erneut anmelden.';
  if (error.status === 403) return 'Diese Anfrage wurde nicht autorisiert. Bitte die Sitzung erneut prüfen.';
  if (error.status === 429) return 'Zu viele Anfragen. Warte bitte einen Moment und versuche es erneut.';
  if (error.code === 'provider_not_connected') return 'ChatGPT ist nicht verbunden. Bitte dein Konto prüfen.';
  if (error.status === 502 || error.status === 503) return 'Der Übersetzungsdienst ist gerade nicht verfügbar. Es wurde kein Ergebnis übernommen.';
  return 'Keine Verbindung zum Server oder ungültige Antwort. Bitte erneut versuchen.';
}
function handleUnauthorized(error) {
  if (error.status !== 401) return;
  clearPrivateData();
  renderConnection();
}
async function loadProvider() {
  if (!session?.user?.id) return;
  if (providerFlight) return providerFlight;
  const run = generation, owner = session.user.id;
  const task = (async () => {
    try {
      const provider = await api.request('/v1/provider', {signal:AbortSignal.timeout(sessionTimeout)});
      if (run !== generation || owner !== session?.user?.id) return;
      session.provider = provider;
    } catch (error) {
      if (run !== generation || owner !== session?.user?.id) return;
      handleUnauthorized(error);
      if (session) setText('account-error', 'ChatGPT-Verbindung konnte nicht geprüft werden. Bitte erneut prüfen.');
    } finally {
      if (providerFlight === task) providerFlight = null;
      if (run === generation) renderConnection();
    }
  })();
  providerFlight = task;
  return task;
}
function restore({force = true} = {}) {
  if (sessionFlight) return sessionFlight;
  if (!force && validatedAt && Date.now() - validatedAt < sessionFreshness) { renderRoute(); return Promise.resolve(); }
  const priorUser = session?.user?.id;
  checking = true; sessionError = ''; closePrompt(); renderConnection();
  setText('account-error', '');
  const run = generation;
  const task = (async () => {
    try {
      // Configuration and identity are independent; config must never gate private
      // library reads, nor may a late config response revive an invalid identity.
      void api.request('/v1/web/config', {signal:AbortSignal.timeout(sessionTimeout)}).then(value => {
        if (run === generation) { config = value; renderConnection(); }
      }).catch(() => { if (run === generation) renderConnection(); });
      const newSession = await api.request('/v1/web/session', {signal:AbortSignal.timeout(sessionTimeout)}).catch(error => { if (error.status === 401) return null; throw error; });
      if (run !== generation) return;
      if (newSession && (!newSession.user?.id || !newSession.csrf_token)) throw new Error('Invalid session');
      if (priorUser && priorUser !== newSession?.user?.id) clearPrivateData();
      session = newSession;
      validatedAt = Date.now();
      checking = false; renderConnection();
      // Neither history nor external model discovery is identity validation.
      if (session?.user?.id) { void loadHistory(); if (!session.provider && (activeSection === 'translator' || $('account-dialog').open)) void loadProvider(); }
    } catch (error) {
      if (run !== generation) return;
      sessionError = 'Sitzung konnte nicht geprüft werden. Bitte erneut versuchen.';
      setText('account-error', sessionError);
    } finally {
      if (sessionFlight === task) sessionFlight = null;
      checking = false; renderConnection(); renderRoute();
    }
  })();
  sessionFlight = task;
  return task;
}
function renderRecord(item) {
  record = item;
  $('language-direction').value = `${item.source_language}-${item.target_language}`;
  $('source-text').value = item.text;
  selectedInstructions = typeof item.instructions === 'string' ? item.instructions : '';
  $('source-text').lang = item.source_language;
  $('result').lang = item.target_language;
  setText('result', item.translation);
  setText('result-caption', `${item.source_language} → ${item.target_language} · Gespeichert`);
  $('copy').disabled = false;
  updateInput();
}
function validRecord(item) {
  const fields = { idioms: ['expression', 'meaning', 'example'], patterns: ['pattern', 'explanation'], vocabulary: ['word', 'meaning'] };
  return item && typeof item.id === 'string' && typeof item.text === 'string' && typeof item.translation === 'string' && item.translation.trim() && validDirection(item.source_language, item.target_language) && Object.entries(fields).every(([key, required]) => Array.isArray(item[key]) && item[key].every(entry => entry && required.every(field => typeof entry[field] === 'string')));
}
function renderHistory() {
  const owner = session?.user?.id;
  const run = generation;
  $('history-list').replaceChildren();
  setText('history-status', history.length ? 'Gespeicherte Übersetzungen öffnen und weiterlernen.' : 'Noch keine Übersetzungen. Dein erstes Ergebnis wird hier gespeichert.');
  for (const item of history) {
    const li = document.createElement('li');
    const button = document.createElement('button'); button.type = 'button';
    const content = document.createElement('span');
    const title = document.createElement('strong'); title.textContent = item.text;
    const detail = document.createElement('small');
    const date = new Date(item.created_at);
    detail.textContent = `${item.source_language} → ${item.target_language}${Number.isNaN(date.valueOf()) ? '' : ` · ${date.toLocaleString('de-DE', { dateStyle: 'medium', timeStyle: 'short' })}`}`;
    const arrow = document.createElement('span'); arrow.className = 'history-arrow'; arrow.textContent = '↗'; arrow.setAttribute('aria-hidden', 'true');
    content.append(title, detail); button.append(content, arrow); li.append(button); $('history-list').append(li);
    button.addEventListener('click', () => { if (!canEditDraft() || owner !== session?.user?.id || run !== generation) return; renderRecord(item); status('Gespeicherte Übersetzung geöffnet.'); $('source-text').focus({ preventScroll: false }); });
  }
}
async function loadHistory() {
  if (!session?.user?.id) return;
  const run = generation;
  setText('history-status', 'Verlauf wird geladen …');
  try {
    const value = await api.request('/v1/translations');
    if (run !== generation) return;
    if (!Array.isArray(value.items) || !value.items.every(validRecord)) throw new Error('Invalid history');
    history = value.items; renderHistory();
  } catch (error) {
    if (run !== generation) return;
    handleUnauthorized(error);
    setText('history-status', error.status === 401 ? 'Bitte erneut anmelden, um deinen Verlauf zu laden.' : 'Verlauf konnte nicht geladen werden. Bitte erneut versuchen.');
  }
}
async function translate(event) {
  event.preventDefault();
  if (busy || checking || readiness(session) !== 'ready') return;
  let payload;
  const [source, target] = $('language-direction').value.split('-');
  try { payload = inputPayload($('source-text').value, source, selectedInstructions, target); }
  catch { status('Bitte 1 bis 8.000 Zeichen eingeben.', true); return; }
  busy = true; controller = new AbortController();
  const run = generation;
  resetResult(); updateInput(); status('Dein Text wird übersetzt und erklärt …');
  try {
    const item = await api.request('/v1/translations', { method: 'POST', body: payload, csrf: session.csrf_token, signal: controller.signal });
    if (run !== generation) return;
    if (!validRecord(item)) throw new Error('Invalid result');
    renderRecord(item);
    history = [item, ...history.filter(existing => existing.id !== item.id)]; renderHistory();
    status('Übersetzung gespeichert.');
  } catch (error) {
    if (run !== generation) return;
    handleUnauthorized(error);
    if (error.code === 'provider_not_connected' && session) { session.provider = { connected: false }; renderConnection(); }
    status(error.name === 'AbortError' ? 'Anfrage abgebrochen. Falls sie bereits abgeschlossen war, prüfe den Verlauf.' : errorMessage(error), error.name !== 'AbortError');
  } finally { busy = false; controller = null; updateInput(); }
}
function changeLanguage(source, target) {
  if (!canEditDraft()) return;
  $('language-direction').value = `${source}-${target}`;
  $('source-text').lang = source;
  $('result').lang = target;
  resetResult(); updateInput(); status('Dein Text wird erst beim Übersetzen gesendet.');
}
$('translation-form').addEventListener('submit', translate);
$('source-text').addEventListener('input', () => { if (record) resetResult(); updateInput(); });
$('source-text').addEventListener('keydown', event => { if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); $('translation-form').requestSubmit(); } });
$('language-direction').addEventListener('change', () => changeLanguage(...$('language-direction').value.split('-')));
$('swap').addEventListener('click', () => { if (!canEditDraft()) return; const [source, target] = $('language-direction').value.split('-'); const swapped = swapDraft(source, $('source-text').value, record?.translation, target); $('source-text').value = swapped.text; changeLanguage(swapped.source, swapped.target); });
$('clear').addEventListener('click', () => { if (!canEditDraft()) return; $('source-text').value = ''; resetResult(); updateInput(); status('Text geleert.'); $('source-text').focus(); });
$('cancel').addEventListener('click', () => controller?.abort());
$('copy').addEventListener('click', async () => { if (!record) return; try { await navigator.clipboard.writeText(record.translation); status('Übersetzung kopiert.'); } catch { status('Kopieren nicht erlaubt. Markiere den Text und kopiere ihn manuell.', true); } });
$('refresh-history').addEventListener('click', loadHistory);
$('account').addEventListener('click', () => { $('account-dialog').showModal(); if (session?.user?.id && !session.provider) void loadProvider(); });
$('connection-action').addEventListener('click', () => { if (sessionError || readiness(session) === 'model-unavailable' || !config || (!config.apple_available && !config.pairing_available && !session?.user?.id)) return restore(); else $('account-dialog').showModal(); });
function resetAccountDialog() { accountRun++; clearBootstrap(); clearPairing(); setText('account-error', ''); }
$('close-account').addEventListener('click', () => { resetAccountDialog(); $('account-dialog').close(); });
$('account-dialog').addEventListener('cancel', resetAccountDialog);
$('account-dialog').addEventListener('close', resetAccountDialog);
$('retry-session').addEventListener('click', restore);
$('pair-browser').addEventListener('click', async () => {
 clearPairing(); const run = pairingRun;
 $('pair-browser').disabled = true;
 try {
  // Refresh bootstrap after expiry; it is never an application session.
  const boot = await api.request('/v1/web/config');
  const pair = await startBrowserPairing(api, boot.csrf_token);
  if (run !== pairingRun || !$('account-dialog').open) return;
  setText('pairing-code', pair.user_code); $('browser-pairing').hidden = false;
  setText('pairing-status', 'Warte auf ausdrückliche Bestätigung in der iOS-App …');
  const until = Date.now() + pair.expires_in * 1000;
  const poll = async () => {
   if (run !== pairingRun) return;
   if (Date.now() >= until) { clearPairing(); setText('account-error', 'Code abgelaufen. Bitte neu beginnen.'); return; }
   try {
    const result = await api.request('/v1/web/pairing/poll', {method:'POST',body:{},csrf:boot.csrf_token});
    if (run !== pairingRun) return;
    if (result.status === 'approved') { clearPairing(); await restore(); return; }
   } catch (error) {
    if (run !== pairingRun) return;
    if (error.status !== 429) { clearPairing(); setText('account-error', 'Verbindung abgelehnt oder abgelaufen. Bitte neu beginnen.'); return; }
   }
   pairingTimer = setTimeout(poll, 3000);
  };
  pairingTimer = setTimeout(poll, 3000);
 } catch (error) { if (run === pairingRun) setText('account-error', errorMessage(error)); }
 finally { renderConnection(); }
});
$('apple-login').addEventListener('click', async () => {
  if (checking || config?.apple_available !== true || session?.user?.id) return;
  const run = generation;
  $('apple-login').disabled = true;
  clearPairing();
  try {
    const boot = await api.request('/v1/web/config');
    const url = await startAppleLogin(api, boot.csrf_token);
    if (run !== generation || !$('account-dialog').open) return;
    location.assign(url);
  } catch (error) { if (run === generation) setText('account-error', errorMessage(error)); }
  finally { renderConnection(); }
});
$('provider-connect').addEventListener('click', async () => {
  if (!session?.user?.id || config?.chatgpt_connect_available !== true) return;
  const run = generation;
  const dialogRun = accountRun;
  $('provider-connect').disabled = true;
  setText('account-error', '');
  try {
    const value = await startProviderConnection(api, session.csrf_token);
    if (run !== generation || dialogRun !== accountRun || !session?.user?.id || !$('account-dialog').open) return;
    clearBootstrap();
    $('bootstrap-code').value = value.bootstrap_token;
    $('provider-bootstrap').hidden = false;
    setText('bootstrap-expiry', `Gültig bis ${new Date(Date.now() + value.expires_in * 1000).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}. Danach „Verbindung erneut prüfen“. `);
    bootstrapTimer = setTimeout(clearBootstrap, value.expires_in * 1000);
  } catch (error) { if (run !== generation || dialogRun !== accountRun) return; handleUnauthorized(error); setText('account-error', errorMessage(error)); }
  finally { renderConnection(); }
});
$('logout').addEventListener('click', async () => {
  if (!session || checking) return;
  const csrf = session.csrf_token;
  clearPrivateData(); busy = false; renderConnection();
  status('Lokale Inhalte entfernt. Abmeldung wird bestätigt …');
  try {
    await api.request('/v1/web/logout', { method: 'POST', csrf });
    try { await api.request('/v1/web/session'); throw new Error('Session still active'); }
    catch (error) { if (error.status !== 401) throw error; }
    status('Abgemeldet.'); $('account-dialog').close();
  } catch { setText('account-error', 'Lokale Inhalte entfernt, aber der Server-Widerruf ist nicht bestätigt. Bitte Verbindung erneut prüfen und nochmals abmelden.'); }
});
window.addEventListener('pageshow', event => { if (event.persisted) { clearPrivateData(); restore(); } });
window.addEventListener('online', () => restore({force:false}));
document.addEventListener('visibilitychange', () => { if (document.hidden) podcasts.pause(); else restore({force:false}); });
updateInput(); restore();


// Explore surface: a compact cover/title list, then episode rows and a reader.
function mountPodcasts({api, account, unauthorized}) {
  const $ = id => document.getElementById(id);
  let session=null, checking=true, config=null, identityError='', ownerRun=0, dialogRun=0;
  const library=createPodcasts({api,changed:render,unauthorized,visible:()=>!document.hidden});
  const node=(tag,text,cls)=>{const el=document.createElement(tag); if(text!==undefined)el.textContent=text; if(cls)el.className=cls; return el;};
  function action(label,fn,disabled=false) {
    const button=node('button',label,'small-button'); button.type='button'; button.disabled=disabled||checking||!session?.user?.id;
    const run=ownerRun;
    button.addEventListener('click',async()=>{if(run!==ownerRun||checking||!session?.user?.id)return; button.disabled=true; try{await fn();}catch(error){if(run===ownerRun&&error.name!=='AbortError'){library.state.error=podcastError(error);render();}}finally{if(run===ownerRun)button.disabled=false;}}); return button;
  }
  function link(text,hash) { const a=node('a',text); a.href=hash; return a; }
  function cover(feed) {
    const box=node('span',undefined,'podcast-cover'); box.setAttribute('aria-hidden','true');
    box.textContent=(feed.title||'P').slice(0,1);
    if(feed.artwork_url){const img=node('img');img.alt='';img.width=64;img.height=64;img.referrerPolicy='no-referrer';img.src=`/v1/podcasts/subscriptions/${apiID(feed.id)}/artwork`;img.addEventListener('error',()=>img.remove(),{once:true});box.append(img);}return box;
  }
  function status(job) {
    const labels={queued:'In Warteschlange',fetching:'Audio wird geladen',transcribing:'Transkription läuft',translating:'Übersetzung läuft',completed:'Bereit',failed:'Fehlgeschlagen',canceled:'Abgebrochen'};
    const p=node('p',labels[job.state]||'Unbekannter Status','muted podcast-progress');
    if(isActive(job)){ const progress=node('progress');progress.max=100;if(Number.isFinite(job.progress))progress.value=Math.max(0,Math.min(100,job.progress));progress.setAttribute('aria-label','Verarbeitungsschritt, kein Audio-Fortschritt');p.append(progress); }
    if(job.error)p.append(node('span',job.error,'error-text'));return p;
  }
  function controls(job,container) {
    if(isActive(job))container.append(action('Abbrechen',async()=>{await library.jobAction(job.id,'cancel');await library.detail(job.id);}));
    if(['failed','canceled'].includes(job.state))container.append(action('Erneut versuchen',async()=>{await library.jobAction(job.id,'retry');await library.detail(job.id);},!library.state.worker));
    if(!isActive(job))container.append(action('Löschen',async()=>{if(!confirm('Diese vorbereitete Folge und ihre Transkripte wirklich löschen?'))return;await library.jobAction(job.id,'delete');await library.load();if(library.state.route.kind==='job')location.hash='#podcasts';}));
  }
  function render() {
    const s=library.state, content=$('podcast-content'); content.replaceChildren();
    $('podcast-add').disabled=checking||!session?.user?.id;
    $('podcast-reload').disabled=checking||(!session?.user?.id&&!identityError)||s.phase==='loading';
    $('podcast-signin').hidden=checking||!!session?.user?.id||config?.apple_available!==true;
    $('podcast-notice').classList.toggle('error-text',!!s.error);
    $('podcast-notice').textContent=checking?'Sitzung wird geprüft …':identityError||!session?.user?.id?(identityError||'Melde dich an, um deine Podcasts zu öffnen.'):s.error||(['idle','loading'].includes(s.phase)?'Podcasts werden geladen …':!s.worker?'Vorbereitung derzeit nicht verfügbar. Abos und Folgen bleiben zugänglich.':'');
    content.setAttribute('aria-busy',String(s.phase==='loading'));
    if(checking||!session?.user?.id)return;
    if(['idle','loading'].includes(s.phase)){for(let i=0;i<3;i++)content.append(node('div',undefined,'podcast-skeleton'));return;}
    if(s.phase==='error')return;
    const route=s.route;
    if(route.kind==='invalid'){content.append(node('p','Ungültiger Podcast-Link.'));content.append(link('← Podcasts','#podcasts'));return;}
    if(route.kind==='feed') {
      content.append(link('← Podcasts','#podcasts'));
      const feed=s.feeds.find(f=>f.id===route.id);if(!feed){content.append(node('p','Podcast nicht gefunden.'));return;}
      const header=node('div',undefined,'podcast-feed-heading');header.append(cover(feed),node('h2',feed.title));content.append(header);
      const bar=node('div',undefined,'podcast-actions');
      const direction=node('select');direction.setAttribute('aria-label','Podcast-Sprachrichtung');for(const [value,label] of [['de','de → ru'],['ru','ru → de']]){const option=node('option',label);option.value=value;direction.append(option);}direction.value=source;direction.disabled=checking;direction.onchange=()=>source=direction.value;bar.append(direction);
      bar.append(action('Feed aktualisieren',async()=>{await library.refresh(feed.id);await library.load();}));
      bar.append(action('Abo entfernen',async()=>{if(!confirm(`„${feed.title}“ wirklich nicht mehr abonnieren? Vorbereitete Folgen werden nicht gelöscht.`))return;await library.unsubscribe(feed.id);await library.load();location.hash='#podcasts';}));content.append(bar);
      if(!feed.episodes?.length)content.append(node('p','Dieser Feed enthält noch keine verfügbaren Folgen.','muted'));
      const list=node('ul',undefined,'podcast-list');
      for(const episode of feed.episodes||[]) {
        const row=node('li',undefined,'podcast-episode');const title=node('div');title.append(node('strong',episode.title||'Folge'));
        if(episode.published){const date=new Date(episode.published);if(!Number.isNaN(date.valueOf()))title.append(node('small',date.toLocaleDateString('de-DE'),'muted'));}
        const job=library.preparation(feed,episode);if(job)title.append(status(job));row.append(title);
        const actions=node('div',undefined,'podcast-actions');
        if(job){actions.append(link(job.state==='completed'?'Öffnen':'Details',podcastRoute('job',job.id)));controls(job,actions);}
        else actions.append(action('Vorbereiten',async()=>{const job=await library.prepare(feed.id,episode.id,source);await library.detail(job.id);},!s.worker||s.pending.has(`${session.user.id}:prepare:${feed.id}:${episode.id}`)));
        row.append(actions);list.append(row);
      }content.append(list);return;
    }
    if(route.kind==='job'){
      const job=s.jobs.find(j=>j.id===route.id);content.append(link('← Podcasts',job?.feed_id?podcastRoute('feed',job.feed_id):'#podcasts'));
      if(!job){content.append(node('p','Vorbereitung nicht gefunden.'));return;}
      content.append(node('h2',job.title||'Importierte Folge'),status(job));const bar=node('div',undefined,'podcast-actions');controls(job,bar);content.append(bar);
      content.append(node('p',`${job.source_language} → ${job.target_language} · Zeitmarken aus der Transkription`,'muted'));
      const segments=node('ol',undefined,'podcast-segments');
      for(const segment of job.segments||[]){const li=node('li');li.append(node('time',`${timestamp(segment.start)}–${timestamp(segment.end)}`));const text=node('div',segment.text);text.lang=job.source_language;li.append(text);if(segment.translation){const translation=node('div',segment.translation,'segment-translation');translation.lang=job.target_language;li.append(translation);}segments.append(li);}content.append(segments);
      if(!job.segments?.length)content.append(node('p',job.state==='completed'?'Keine Transkriptsegmente verfügbar.':'Transkriptsegmente erscheinen nach der Erkennung.','muted'));return;
    }
    const list=node('ul',undefined,'podcast-list');
    for(const feed of s.feeds){const li=node('li');const a=link('',podcastRoute('feed',feed.id));a.className='podcast-feed';const text=node('span');text.append(node('strong',feed.title||'Podcast'),node('small',feed.latest_episode_title||feed.episodes?.[0]?.title||'Noch keine Folgen','muted'));a.append(cover(feed),text,node('span','›'));li.append(a);list.append(li);}content.append(list);
    const imports=library.directJobs();if(imports.length){content.append(node('h2','Einzelne Folgen'));const list=node('ul',undefined,'podcast-list');for(const job of imports){const li=node('li',undefined,'podcast-episode');const title=node('div');title.append(link(job.title||sourceName(job),podcastRoute('job',job.id)),status(job));li.append(title);list.append(li);}content.append(list);}
    if(!s.feeds.length&&!imports.length)content.append(node('p','Noch keine Podcasts. Füge über + einen Podcast oder eine einzelne Folge hinzu.','muted'));
  }
  let source='de';
  function close() {dialogRun++;$('podcast-dialog').close();$('podcast-url').value='';$('podcast-add-error').textContent='';$('podcast-submit').disabled=false;}
  $('podcast-add').onclick=()=>{if(checking||!session?.user?.id)return;$('podcast-dialog').showModal();$('podcast-url').focus();};
  $('podcast-close').onclick=close;$('podcast-dialog').addEventListener('cancel',close);
  $('podcast-mode').onchange=()=>{const episode=$('podcast-mode').value==='episode';$('podcast-import-language').hidden=!episode;$('podcast-submit').textContent=episode?'Vorbereiten':'Abonnieren';$('podcast-add-help').textContent=episode?'Öffentliche Folge mit direktem Audio. Startet Transkription und Übersetzung über dein Konto.':'Ein RSS-/Atom-Feed oder eine öffentliche Podcast-Seite. Ein Abo startet keine KI-Verarbeitung.';};
  $('podcast-form').onsubmit=async event=>{event.preventDefault();if(checking||!session?.user?.id||$('podcast-submit').disabled)return;const run=ownerRun,dialog=dialogRun; $('podcast-submit').disabled=true;try{const episode=$('podcast-mode').value==='episode';const value=await (episode?library.importURL($('podcast-url').value,$('podcast-source').value):library.subscribe($('podcast-url').value));if(run!==ownerRun)return;if(episode)await library.detail(value.id);await library.load();if(run!==ownerRun||dialog!==dialogRun)return;close();location.hash=podcastRoute(episode?'job':'feed',value.id);}catch(error){if(run===ownerRun&&dialog===dialogRun)$('podcast-add-error').textContent=podcastError(error);}finally{if(run===ownerRun&&dialog===dialogRun)$('podcast-submit').disabled=false;}};
  $('podcast-reload').onclick=async()=>{if(identityError)return restore();await library.activate(location.hash);if(library.state.route.kind==='job')await library.detail(library.state.route.id).catch(()=>{});};
  $('podcast-signin').onclick=account;
  return {library,
    identity(value,options={}) {if(session?.user?.id!==value?.user?.id){ownerRun++;close();source='de';}session=value;checking=!!options.checking&&!value?.user?.id;identityError=options.error||(options.checking?'Sitzung wird im Hintergrund geprüft …':'');config=options.config;library.identity(value);if(checking)library.pause();render();},
    async route(hash) {await library.activate(hash);if(library.state.route.kind==='job'&&session?.user?.id&&!checking){try{await library.detail(library.state.route.id);}catch(error){if(error.name!=='AbortError'){library.state.error=podcastError(error);render();}}}},
    pause:()=>library.pause()
  };
}
function timestamp(seconds){if(!Number.isFinite(seconds)||seconds<0)return '—';const value=Math.floor(seconds);return `${Math.floor(value/60)}:${String(value%60).padStart(2,'0')}`;}
function sourceName(job){try{return new URL(job.source_url||job.url).hostname+' · '+(job.source_language||'de')+' → '+(job.target_language||'ru');}catch{return 'Importierte Folge';}}
