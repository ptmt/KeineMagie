import { createAPI, readiness, inputPayload, swapDraft, startProviderConnection, startBrowserPairing, startAppleLogin } from './core.mjs';

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
let bootstrapTimer = null;
let accountRun = 0;
let pairingTimer = null;
let pairingRun = 0;
function clearPairing() { pairingRun++; clearTimeout(pairingTimer); pairingTimer = null; $('browser-pairing').hidden = true; setText('pairing-code', ''); }
const names = { de: 'Deutsch', ru: 'Russisch' };

const sectionLinks = [...document.querySelectorAll('.section-nav a')];
let activeSection = 'translator';
function renderRoute(focus = false) {
  // Keep the existing DOM and all requests alive when changing sections.
  // #main belongs to the skip link, not the section router.
  if (location.hash === '#main') return;
  const selected = sectionLinks.find(link => link.hash === location.hash) || sectionLinks[0];
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
  accountRun++;
  clearPairing();
  controller?.abort();
  clearBootstrap();
  session = null; history = [];
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
  const count = [...$('source-text').value].length;
  setText('input-count', `${count.toLocaleString('de-DE')} / 8.000`);
  $('input-count').classList.toggle('error-state', count > 8000);
  $('translate').disabled = busy || checking || readiness(session) !== 'ready' || !count || count > 8000;
  $('clear').disabled = busy || count === 0;
  $('swap').disabled = busy;
  $('source-language').disabled = busy;
  $('target-language').disabled = busy;
  $('source-text').readOnly = busy;
  $('cancel').hidden = !busy;
  $('translation-form').setAttribute('aria-busy', String(busy));
  setText('translate', busy ? 'Wird übersetzt …' : 'Übersetzen ↗');
}
function renderConnection() {
  const signedIn = !!session?.user?.id;
  const phase = readiness(session);
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
  $('provider-connect').disabled = checking || !signedIn || config?.chatgpt_connect_available !== true || session?.provider?.connected === true;
  $('refresh-history').disabled = checking || !signedIn;
  setText('apple-status', signedIn ? 'Mit Apple angemeldet' : '');
  setText('provider-status', signedIn ? (session?.provider?.connected === true ? 'Verbunden' : 'Nicht verbunden') : '');
  if (!signedIn || session?.provider?.connected === true) clearBootstrap();
  setText('provider-detail', !signedIn ? '' : session?.provider?.connected === true ? 'Dein persönliches ChatGPT-Konto ist verbunden.' : config?.chatgpt_connect_available === true ? 'Verbinde dein eigenes ChatGPT-Konto für Übersetzungen.' : 'Die persönliche ChatGPT-Verbindung ist hier noch nicht verfügbar.');
  $('connection-notice').hidden = !checking && phase === 'ready';
  $('connection-action').hidden = checking;
  setText('connection-action', signedIn ? 'Konto öffnen' : 'Anmelden');
  setText('connection-detail', '');
  if (checking) setText('connection-title', 'Sitzung wird geprüft …');
  else if (phase === 'ready') setText('connection-title', 'Bereit zum Übersetzen');
  else if (signedIn) setText('connection-title', 'ChatGPT im Konto verbinden.');
  else if (!config) {
    setText('connection-title', 'Anmeldung nicht erreichbar.');
    setText('connection-action', 'Erneut prüfen');
  } else if (!config.apple_available && !config.pairing_available) {
    setText('connection-title', 'Anmeldung noch nicht verfügbar.');
    setText('connection-action', 'Erneut prüfen');
  } else setText('connection-title', 'Zum Übersetzen anmelden.');
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
async function restore() {
  if (checking) return;
  const priorUser = session?.user?.id;
  checking = true; renderConnection();
  setText('account-error', '');
  const run = generation;
  try {
    const [newConfig, newSession] = await Promise.all([
      api.request('/v1/web/config'),
      api.request('/v1/web/session').catch(error => { if (error.status === 401) return null; throw error; })
    ]);
    if (run !== generation) return;
    config = newConfig;
    if (priorUser && priorUser !== newSession?.user?.id) clearPrivateData();
    session = newSession;
    if (session?.user?.id) await loadHistory();
  } catch (error) {
    if (run !== generation) return;
    if (session) clearPrivateData();
    config = null;
    setText('account-error', 'Sichere Web-Anmeldung nicht erreichbar. Bitte später erneut prüfen.');
  } finally {
    checking = false; renderConnection();
  }
}
function renderRecord(item) {
  record = item;
  $('source-language').value = item.source_language;
  $('target-language').value = item.target_language;
  $('source-text').value = item.text;
  $('source-text').lang = item.source_language;
  $('result').lang = item.target_language;
  setText('result', item.translation);
  setText('result-caption', `${names[item.source_language]} → ${names[item.target_language]} · Gespeichert`);
  $('copy').disabled = false;
  updateInput();
}
function validRecord(item) {
  const fields = { idioms: ['expression', 'meaning', 'example'], patterns: ['pattern', 'explanation'], vocabulary: ['word', 'meaning'] };
  return item && typeof item.id === 'string' && typeof item.text === 'string' && typeof item.translation === 'string' && item.translation.trim() && ['de', 'ru'].includes(item.source_language) && item.target_language === (item.source_language === 'de' ? 'ru' : 'de') && Object.entries(fields).every(([key, required]) => Array.isArray(item[key]) && item[key].every(entry => entry && required.every(field => typeof entry[field] === 'string')));
}
function renderHistory() {
  $('history-list').replaceChildren();
  setText('history-status', history.length ? 'Gespeicherte Übersetzungen öffnen und weiterlernen.' : 'Noch keine Übersetzungen. Dein erstes Ergebnis wird hier gespeichert.');
  for (const item of history) {
    const li = document.createElement('li');
    const button = document.createElement('button'); button.type = 'button';
    const content = document.createElement('span');
    const title = document.createElement('strong'); title.textContent = item.text;
    const detail = document.createElement('small');
    const date = new Date(item.created_at);
    detail.textContent = `${names[item.source_language]} → ${names[item.target_language]}${Number.isNaN(date.valueOf()) ? '' : ` · ${date.toLocaleString('de-DE', { dateStyle: 'medium', timeStyle: 'short' })}`}`;
    const arrow = document.createElement('span'); arrow.className = 'history-arrow'; arrow.textContent = '↗'; arrow.setAttribute('aria-hidden', 'true');
    content.append(title, detail); button.append(content, arrow); li.append(button); $('history-list').append(li);
    button.addEventListener('click', () => { if (busy) return; renderRecord(item); status('Gespeicherte Übersetzung geöffnet.'); $('source-text').focus({ preventScroll: false }); });
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
  try { payload = inputPayload($('source-text').value, $('source-language').value); }
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
function changeLanguage(source) {
  $('source-language').value = source;
  $('target-language').value = source === 'de' ? 'ru' : 'de';
  $('source-text').lang = source;
  $('result').lang = source === 'de' ? 'ru' : 'de';
  resetResult(); updateInput(); status('Dein Text wird erst beim Übersetzen gesendet.');
}
$('translation-form').addEventListener('submit', translate);
$('source-text').addEventListener('input', () => { if (record) resetResult(); updateInput(); });
$('source-text').addEventListener('keydown', event => { if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); $('translation-form').requestSubmit(); } });
$('source-language').addEventListener('change', () => changeLanguage($('source-language').value));
$('target-language').addEventListener('change', () => changeLanguage($('target-language').value === 'de' ? 'ru' : 'de'));
$('swap').addEventListener('click', () => { const swapped = swapDraft($('source-language').value, $('source-text').value, record?.translation); $('source-text').value = swapped.text; changeLanguage(swapped.source); });
$('clear').addEventListener('click', () => { $('source-text').value = ''; resetResult(); updateInput(); status('Text geleert.'); $('source-text').focus(); });
$('cancel').addEventListener('click', () => controller?.abort());
$('copy').addEventListener('click', async () => { if (!record) return; try { await navigator.clipboard.writeText(record.translation); status('Übersetzung kopiert.'); } catch { status('Kopieren nicht erlaubt. Markiere den Text und kopiere ihn manuell.', true); } });
$('refresh-history').addEventListener('click', loadHistory);
$('account').addEventListener('click', () => $('account-dialog').showModal());
$('connection-action').addEventListener('click', () => { if (!config || (!config.apple_available && !config.pairing_available && !session?.user?.id)) restore(); else $('account-dialog').showModal(); });
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
window.addEventListener('online', restore);
updateInput(); restore();
