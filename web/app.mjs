// Keep session bootstrap independent of the episode reader/module graph.
function episodeLocation(pathname,hash) { return hash ? null : /^\/podcasts\/episodes\/([a-z0-9]+(?:-[a-z0-9]+)*-[a-f0-9]{12})$/.exec(pathname)?.[1] || null; }
async function episodePath(job) { return (await import('./episode.mjs')).episodePath(job); }
import { mountTranslatorFollowup } from './translator-followup.mjs';
import { mountCoach } from './coach.mjs';
import { t, interfaceCatalog, getInterfaceLanguage, setInterfaceLanguage, bindInterfaceText, unbindInterfaceText, applyInterfaceLanguage, registerStaticInterface } from './i18n.mjs';
import { copyText, reconcileDOM, createPodcasts, podcastRoute, podcastError, isActive, apiID, createAPI, readiness, inputPayload, swapDraft, validDirection, startProviderConnection, startBrowserPairing, startAppleLogin, promptStore, translationPresets } from './core.mjs';

const $ = id => document.getElementById(id);
const api = createAPI();
registerStaticInterface();
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
let providerError = '';
const sessionFreshness = 60_000;
const sessionTimeout = 8_000;
let bootstrapTimer = null;
let accountRun = 0;
let pairingTimer = null;
let pairingRun = 0;
let appleAttempt = null;
function cancelAppleLogin({leaving = false} = {}) {
  if (!appleAttempt) return;
  clearTimeout(appleAttempt.timer);
  appleAttempt.controller.abort();
  if (appleAttempt.navigating && !leaving) window.stop();
  appleAttempt = null;
}
function clearPairing() { pairingRun++; clearTimeout(pairingTimer); pairingTimer = null; $('browser-pairing').hidden = true; setText('pairing-code', ''); }

let stylesOwner = null;
let savedPrompts = [];
let selectedInstructions = '';
let editingPrompt = null;
let styleSignature = null;
let appliedTranslation = null;
const editingLabels={en:{edit:'Edit translation',done:'Done',draft:'Current draft only; original kept in history.'},de:{edit:'Übersetzung bearbeiten',done:'Fertig',draft:'Nur aktueller Entwurf; Original bleibt im Verlauf.'},ru:{edit:'Изменить перевод',done:'Готово',draft:'Только текущий черновик; оригинал остаётся в истории.'},es:{edit:'Editar traducción',done:'Listo',draft:'Solo borrador actual; el original sigue en el historial.'},fr:{edit:'Modifier la traduction',done:'Terminé',draft:'Brouillon actuel uniquement ; original conservé dans l’historique.'}};
function currentOutput(){return appliedTranslation ?? record?.translation ?? '';}
function localizeTranslationEditor(){
 const labels=editingLabels[getInterfaceLanguage()]||editingLabels.en;
 $('edit-translation').title=labels.edit;$('edit-translation').setAttribute('aria-label',labels.edit);
 $('finish-translation-edit').textContent=labels.done;
 if(record && appliedTranslation!==null)setText('result-caption',labels.draft);
}
function showTranslationEditor(open){
 $('translation-editor').hidden=!open;$('result').hidden=!!open;
 $('edit-translation').hidden=!!open;$('finish-translation-edit').hidden=!open;
 if(open){$('translation-editor').value=currentOutput();$('translation-editor').lang=record.target_language;$('translation-editor').focus();}
 localizeTranslationEditor();
}
function applyCurrentTranslation(text){
 appliedTranslation=text;resetCopy();setText('result',text);$('translation-editor').value=text;
 $('copy').disabled=false;localizeTranslationEditor();
}
$('edit-translation').addEventListener('click',()=>{if(record&&canEditDraft())showTranslationEditor(true);});
$('finish-translation-edit').addEventListener('click',()=>showTranslationEditor(false));
$('translation-editor').addEventListener('input',()=>{if(record)applyCurrentTranslation($('translation-editor').value);});
$('translation-editor').addEventListener('keydown',event=>{if((event.metaKey||event.ctrlKey)&&event.key==='Enter'){event.preventDefault();event.stopPropagation();showTranslationEditor(false);}});

const followup = mountTranslatorFollowup({host:$('translation-followup'),api,locale:getInterfaceLanguage,unauthorized:handleUnauthorized,
  currentDraft:()=>record?{current_source:$('source-text').value,current_translation:currentOutput()}:null,
  saved(item) { history = [item,...history.filter(existing=>existing.id!==item.id)]; renderHistory(); if(record?.id===item.id){record=item;} },
  apply(item,text,source) { if(record?.id!==item.id)return; if(typeof source==='string'){$('source-text').value=source;$('source-text').lang=item.source_language;$('language-direction').value=`${item.source_language}-${item.target_language}`;} applyCurrentTranslation(text);showTranslationEditor(false);updateInput(); }
});
function canEditDraft() { return !!session?.user?.id && !busy; }
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
  const choices = [{name:'Standard', instructions:''}, ...translationPresets, ...savedPrompts];
  if (selectedInstructions && !choices.some(item => item.instructions === selectedInstructions)) choices.push({name:'Aus Verlauf', instructions:selectedInstructions});
  const signature=JSON.stringify([owner,savedPrompts,selectedInstructions,canEditDraft(),getInterfaceLanguage()]);
  if(signature===styleSignature)return;
  styleSignature=signature;
  $('style-chips').replaceChildren();
  for (const item of choices) {
    const button = document.createElement('button'); button.type = 'button'; button.className = 'style-chip';
    button.textContent = item.id === 'friendly' || item.id === 'formal' || !item.instructions || item.name === 'Aus Verlauf' && !item.id ? t(item.name) : item.name; button.disabled = !canEditDraft();
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
  setText('prompt-count', `${count.toLocaleString(getInterfaceLanguage())} / ${(1000).toLocaleString(getInterfaceLanguage())}`);
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

// Learning settings use the existing owner-scoped server profile, never browser storage.
let profileEpoch=0, profileOwner=null, profileLanguage='de', profileValue=null, profileLoading=false,profileFailed=false;
function resetLearningProfile(){profileEpoch++;profileOwner=null;profileValue=null;profileLoading=false;profileFailed=false;$('learning-profile').hidden=true;$('profile-cefr').value='unknown';$('profile-cefr').disabled=true;$('profile-history').replaceChildren();setText('profile-error','');}
function renderLearningProfile(){
 $('learning-profile').hidden=!session?.user?.id;
 $('profile-language').value=profileLanguage;
 $('profile-language').disabled=profileLoading;
 $('profile-cefr').disabled=profileLoading||!profileValue;
 if(profileValue)$('profile-cefr').value=profileValue.cefr;
 $('profile-retry').hidden=profileLoading||!profileFailed;
 $('profile-history').replaceChildren();
 for(const entry of profileValue?.self_assessments||[]){const li=document.createElement('li'),date=new Date(entry.assessed_at),time=document.createElement('time');time.dateTime=entry.assessed_at;time.textContent=Number.isNaN(date.valueOf())?'':date.toLocaleString(getInterfaceLanguage(),{dateStyle:'medium',timeStyle:'short'});li.append(document.createTextNode((entry.cefr==='unknown'?t('Unbekannt'):entry.cefr)+' · '),time);$('profile-history').append(li);}
}
async function loadLearningProfile({cefr,focus=false}={}){
 if(!session?.user?.id)return;
 const epoch=++profileEpoch,owner=session.user.id,language=profileLanguage;profileOwner=owner;profileLoading=true;profileFailed=false;setText('profile-error','Profil wird geladen …');renderLearningProfile();
 const valid=()=>epoch===profileEpoch&&session?.user?.id===owner&&profileLanguage===language;
 try{
  if(cefr!==undefined)await api.request(`/v1/learning/profiles/${language}`,{method:'PUT',csrf:session.csrf_token,body:{cefr}});
  if(!valid())return;
  const value=await api.request(`/v1/learning/profiles/${language}`);
  if(!valid())return;
  if(!['unknown','A1','A2','B1','B2','C1','C2'].includes(value.cefr))throw new Error('Invalid profile');
  profileValue=value;profileOwner=owner;setText('profile-error','');
  if(cefr!==undefined)window.dispatchEvent(new CustomEvent('learning-profile-changed',{detail:{language}}));
 }catch(error){if(valid()){if(error.status===401)handleUnauthorized(error);else {profileFailed=true;setText('profile-error','Profil konnte nicht gespeichert oder geladen werden.');}}}
 finally{if(valid()){profileLoading=false;renderLearningProfile();if(focus&&$('account-dialog').open)$('profile-cefr').focus({preventScroll:true});}}
}
function openLearningProfile(language='de'){
 if(!['de','ru'].includes(language))language='de';
 if(profileLanguage!==language){profileValue=null;profileLanguage=language;}
 $('account-dialog').showModal();void loadLearningProfile({focus:true});
 if(session?.user?.id&&!session.provider)void loadProvider();
}
$('profile-language').addEventListener('change',()=>{profileLanguage=$('profile-language').value;profileValue=null;void loadLearningProfile();});
$('profile-cefr').addEventListener('change',()=>void loadLearningProfile({cefr:$('profile-cefr').value}));
$('profile-retry').addEventListener('click',()=>void loadLearningProfile());
const podcasts = mountPodcasts({api, account:openLearningProfile, unauthorized:handleUnauthorized});
const coach = mountCoach({host:$('coach'),api,locale:getInterfaceLanguage,unauthorized:handleUnauthorized,account:openLearningProfile});
const sectionLinks = [...document.querySelectorAll('.section-nav a')];
let activeSection = 'translator';
function renderRoute(focus = false) {
  // Keep the existing DOM and all requests alive when changing sections.
  // #main belongs to the skip link, not the section router.
  if (location.hash === '#main') return;
  const effectiveHash = episodeLocation(location.pathname, location.hash) ? '#podcasts' : location.hash;
  const selected = sectionLinks.find(link => link.hash === effectiveHash || (link.hash === '#podcasts' && effectiveHash.startsWith('#podcasts/'))) || sectionLinks[0];
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
  coach.route();focusCoachTranslation();
  if (session?.user?.id && !session.provider && next === 'translator') void loadProvider();
  if (!checking || session?.user?.id) podcasts.route(location.hash);
  else podcasts.pause();
}
window.addEventListener('hashchange', () => renderRoute(true));
window.addEventListener('popstate', () => renderRoute(true));
renderRoute();


function setText(id, text) { if (!['result','pairing-code'].includes(id) && Object.hasOwn(interfaceCatalog.de,text)) bindInterfaceText($(id),text); else {unbindInterfaceText($(id));$(id).textContent = text;} }
function status(message, error = false) {
  setText('translation-status', message);
  $('translation-status').classList.toggle('error-state', error);
}
let copyTimer = null;
function resetCopy() { clearTimeout(copyTimer); copyTimer = null; setText('copy', 'Kopieren'); }
function resetResult() {
  followup.select(null); appliedTranslation=null;showTranslationEditor(false);$('edit-translation').disabled=true;
  resetCopy();
  record = null;
  $('translation-editor').value='';
  $('result').replaceChildren();
  setText('result-caption', '');
  $('copy').disabled = true;
}
function clearPrivateData() {
  coach.identity(null);
  cancelAppleLogin();
  resetLearningProfile();
  generation++;
  validatedAt = 0; providerFlight = null; providerError = '';
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
  followup.identity(session, !busy && !checking && !providerFlight && !providerError && readiness(session) === 'ready');
  renderStyles();
  localizeTranslationEditor();$('edit-translation').disabled=!record||!canEditDraft();
  const count = [...$('source-text').value].length;
  setText('input-count', `${count.toLocaleString(getInterfaceLanguage())} / ${(8000).toLocaleString(getInterfaceLanguage())}`);
  $('input-count').classList.toggle('error-state', count > 8000);
  $('translate').disabled = busy || checking || !!providerFlight || !!providerError || readiness(session) !== 'ready' || !count || count > 8000;
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
  setText('translate', busy ? 'Wird übersetzt …' : 'Übersetzen');
}
function renderConnection() {
  coach.identity(session);
  podcasts.identity(session, {checking,config,error:sessionError});
  const signedIn = !!session?.user?.id;
  const applePending = !!appleAttempt;
  document.querySelectorAll('.header-language, .account-language').forEach(control => { control.hidden = !signedIn; });
  const phase = readiness(session);
  const modelUnavailable = phase === 'model-unavailable';
  const catalogWarning = 'Dein ChatGPT-Konto ist verbunden, aber der Modellkatalog ist gerade nicht verfügbar. Bitte die Verbindung erneut prüfen. Eine neue Verbindung ist dafür nicht erforderlich.';
  $('account-indicator').classList.toggle('connected', signedIn);
  if(profileOwner&&profileOwner!==session?.user?.id)resetLearningProfile();
  $('learning-profile').hidden=!signedIn;
  setText('account-label', signedIn ? 'Profil' : 'Anmelden');
  setText('account-title', signedIn ? 'Dein Konto' : 'Anmelden');
  $('sign-in-options').hidden = signedIn;
  $('signed-in-account').hidden = !signedIn;
  $('provider-section').hidden = !signedIn;
  $('retry-session').hidden = !signedIn;
  $('apple-login').hidden = signedIn || config?.apple_available === false;
  $('apple-login').disabled = applePending || checking || config?.apple_available !== true;
  $('apple-login').setAttribute('aria-busy', String(applePending));
  $('apple-login-progress').hidden = !applePending;
  setText('apple-login-progress-label', applePending ? 'Apple-Anmeldung wird geöffnet …' : '');
  $('pair-browser').hidden = signedIn || config?.pairing_available !== true;
  $('pair-browser').disabled = applePending || checking || config?.pairing_available !== true;
  $('logout').hidden = !signedIn;
  $('provider-connect').disabled = checking || !!providerFlight || !!providerError || !signedIn || !session?.provider || config?.chatgpt_connect_available !== true || session?.provider?.connected === true;
  $('refresh-history').disabled = checking || !signedIn;
  setText('apple-status', signedIn ? 'Mit Apple angemeldet' : '');
  setText('provider-status', signedIn ? (providerError ? 'Verbindung konnte nicht geprüft werden' : providerFlight || !session.provider ? 'Verbindung wird geprüft …' : modelUnavailable ? 'Verbunden · Modell nicht verfügbar' : session?.provider?.connected === true ? 'Verbunden' : 'Nicht verbunden') : '');
  if (!signedIn || session?.provider?.connected === true) clearBootstrap();
  setText('provider-detail', !signedIn ? '' : providerError ? providerError : !session.provider ? 'Der Status deines persönlichen ChatGPT-Kontos wird geladen.' : modelUnavailable ? catalogWarning : session?.provider?.connected === true ? 'Dein persönliches ChatGPT-Konto ist verbunden.' : config?.chatgpt_connect_available === true ? 'Verbinde dein eigenes ChatGPT-Konto für Übersetzungen.' : 'Die persönliche ChatGPT-Verbindung ist hier noch nicht verfügbar.');
  $('connection-notice').hidden = !checking && !providerFlight && !providerError && !sessionError && phase === 'ready';
  $('connection-action').hidden = checking;
  const appleSignIn = !checking && !sessionError && !signedIn && config?.apple_available === true;
  $('connection-action').classList.toggle('apple-button', appleSignIn);
  $('connection-action-art').hidden = !appleSignIn;
  $('connection-action-label').hidden = appleSignIn;
  $('translation-form').classList.toggle('sign-in-required', !signedIn);
  setText('connection-action-label', modelUnavailable || providerError ? 'Erneut prüfen' : signedIn ? 'Konto öffnen' : 'Anmelden');
  setText('connection-detail', modelUnavailable ? catalogWarning : '');
  if (sessionError) { setText('connection-title', sessionError); setText('connection-action-label', 'Erneut prüfen'); }
  else if (checking) setText('connection-title', 'Sitzung wird geprüft …');
  else if (providerError) setText('connection-title', providerError);
  else if (providerFlight || phase === 'provider-loading') setText('connection-title', 'ChatGPT-Verbindung wird geprüft …');
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
  providerError = ''; setText('account-error', '');
  const task = (async () => {
    try {
      const provider = await api.request('/v1/provider', {signal:AbortSignal.timeout(sessionTimeout)});
      if (run !== generation || owner !== session?.user?.id) return;
      if (typeof provider?.connected !== 'boolean' || typeof provider?.status !== 'string') throw new Error('Invalid provider status');
      session.provider = provider;
    } catch (error) {
      if (run !== generation || owner !== session?.user?.id) return;
      handleUnauthorized(error);
      if (session) { providerError = 'ChatGPT-Verbindung konnte nicht geprüft werden. Bitte erneut prüfen.'; setText('account-error', providerError); }
    } finally {
      if (providerFlight === task) providerFlight = null;
      if (run === generation) renderConnection();
    }
  })();
  providerFlight = task;
  renderConnection();
  return task;
}
function restore({force = true, refreshProvider = false} = {}) {
  if (sessionFlight) return sessionFlight;
  if (!force && validatedAt && Date.now() - validatedAt < sessionFreshness) { renderRoute(); return Promise.resolve(); }
  const priorUser = session?.user?.id;
  checking = true; sessionError = ''; renderConnection();
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
      // Lean identity responses must not erase verified same-owner provider state.
      if (newSession && newSession.user.id === priorUser && !newSession.provider && session?.provider) newSession.provider = session.provider;
      if (newSession?.user?.id) cancelAppleLogin();
      session = newSession;
      validatedAt = Date.now();
      checking = false; renderConnection();
      // Neither history nor external model discovery is identity validation.
      if (session?.user?.id) { void loadHistory(); if (refreshProvider || (!session.provider && (activeSection === 'translator' || $('account-dialog').open))) void loadProvider(); }
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
  appliedTranslation=null; showTranslationEditor(false);$('translation-editor').value='';followup.select(item);
  resetCopy();
  record = item;
  $('language-direction').value = `${item.source_language}-${item.target_language}`;
  $('source-text').value = item.text;
  selectedInstructions = typeof item.instructions === 'string' ? item.instructions : '';
  $('source-text').lang = item.source_language;
  $('result').lang = item.target_language;
  setText('result', item.translation);
  bindInterfaceText($('result-caption'), '{source} → {target} · Gespeichert', {source:item.source_language,target:item.target_language});
  $('copy').disabled = false;
  updateInput();
}
function validRecord(item) {
  const fields = { idioms: ['expression', 'meaning', 'example'], patterns: ['pattern', 'explanation'], vocabulary: ['word', 'meaning'] };
  return item && typeof item.id === 'string' && typeof item.text === 'string' && typeof item.translation === 'string' && item.translation.trim() && validDirection(item.source_language, item.target_language) && Object.entries(fields).every(([key, required]) => Array.isArray(item[key]) && item[key].every(entry => entry && required.every(field => typeof entry[field] === 'string')));
}
function focusCoachTranslation(){
  if(location.hash!=='#translator'||!location.search||!session?.user?.id)return;
  const id=new URL(location.href).searchParams.get('translation');if(!id)return;
  const row=[...$('history-list').children].find(e=>e.dataset.translationID===id);
  if(row){row.querySelector('button')?.focus({preventScroll:true});row.scrollIntoView?.({block:'center'});}
}
function renderHistory() {
  const owner = session?.user?.id;
  const run = generation;
  $('history-list').replaceChildren();
  setText('history-status', history.length ? 'Gespeicherte Übersetzungen öffnen und weiterlernen.' : 'Noch keine Übersetzungen. Dein erstes Ergebnis wird hier gespeichert.');
  for (const item of history) {
    const li = document.createElement('li');li.dataset.translationID=item.id;
    const button = document.createElement('button'); button.type = 'button';
    const content = document.createElement('span');
    content.className = 'history-text';
    const title = document.createElement('span'); title.className = 'history-source'; title.textContent = item.text; title.lang = item.source_language;
    const translation = document.createElement('strong'); translation.className = 'history-translation'; translation.textContent = item.translation; translation.lang = item.target_language;
    const detail = document.createElement('small');
    const date = new Date(item.created_at);
    detail.dataset.historyDate = item.created_at; detail.dataset.direction = `${item.source_language} → ${item.target_language}`;
    detail.textContent = `${detail.dataset.direction}${Number.isNaN(date.valueOf()) ? '' : ` · ${date.toLocaleString(getInterfaceLanguage(), { dateStyle: 'medium', timeStyle: 'short' })}`}`;
    const arrow = document.createElement('span'); arrow.className = 'history-arrow'; arrow.textContent = '↗'; arrow.setAttribute('aria-hidden', 'true');
    content.append(title, translation, detail); button.append(content, arrow); li.append(button); $('history-list').append(li);
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
    history = value.items; renderHistory();focusCoachTranslation();
  } catch (error) {
    if (run !== generation) return;
    handleUnauthorized(error);
    setText('history-status', error.status === 401 ? 'Bitte erneut anmelden, um deinen Verlauf zu laden.' : 'Verlauf konnte nicht geladen werden. Bitte erneut versuchen.');
  }
}
async function translate(event) {
  event.preventDefault();
  if (busy || checking || providerFlight || providerError || readiness(session) !== 'ready') return;
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
$('swap').addEventListener('click', () => { if (!canEditDraft()) return; const [source, target] = $('language-direction').value.split('-'); const swapped = swapDraft(source, $('source-text').value, appliedTranslation ?? record?.translation, target); $('source-text').value = swapped.text; changeLanguage(swapped.source, swapped.target); });
$('clear').addEventListener('click', () => { if (!canEditDraft()) return; $('source-text').value = ''; resetResult(); updateInput(); status('Text geleert.'); $('source-text').focus(); });
$('cancel').addEventListener('click', () => controller?.abort());
$('copy').addEventListener('click', async () => {
  if (!record?.translation || $('copy').disabled) return;
  const item = record, run = generation;
  resetCopy();
  try {
    await copyText(appliedTranslation ?? item.translation);
    if (run !== generation || record !== item) return;
    setText('copy', 'Kopiert'); status('Übersetzung kopiert.');
    copyTimer = setTimeout(resetCopy, 1800);
  } catch { if (run === generation && record === item) status('Kopieren fehlgeschlagen. Bitte erneut versuchen.', true); }
});
$('refresh-history').addEventListener('click', loadHistory);
$('account').addEventListener('click', () => openLearningProfile(profileLanguage));
function openAppleSignIn() {
  $('account-dialog').showModal();
  if (!session?.user?.id && config?.apple_available === true) $('apple-login').click();
}
$('connection-action').addEventListener('click', () => { if (sessionError || providerError || readiness(session) === 'model-unavailable') return recheckConnection(); if (!config || (!config.apple_available && !config.pairing_available && !session?.user?.id)) return restore(); openAppleSignIn(); if (session?.user?.id && !session.provider) void loadProvider(); });
function resetAccountDialog() { accountRun++; cancelAppleLogin(); clearBootstrap(); clearPairing(); setText('account-error', ''); renderConnection(); }
$('close-account').addEventListener('click', () => { resetAccountDialog(); $('account-dialog').close(); });
$('account-dialog').addEventListener('cancel', resetAccountDialog);
$('account-dialog').addEventListener('close', resetAccountDialog);
async function recheckConnection() { await restore({refreshProvider:true}); await providerFlight; }
$('retry-session').addEventListener('click', recheckConnection);
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
  if (appleAttempt || checking || config?.apple_available !== true || session?.user?.id || !$('account-dialog').open) return;
  const run = generation;
  const attempt = {controller:new AbortController(), timer:null};
  appleAttempt = attempt;
  const active = () => appleAttempt === attempt && run === generation && !session?.user?.id && $('account-dialog').open;
  // Bound both requests AND a stalled/canceled redirect; never retry automatically.
  attempt.timer = setTimeout(() => {
    if (!active()) return;
    cancelAppleLogin();
    setText('account-error', 'Apple-Anmeldung konnte nicht geöffnet werden. Bitte erneut versuchen.');
    renderConnection();
  }, 15_000);
  setText('account-error', '');
  renderConnection();
  clearPairing();
  try {
    const boot = await api.request('/v1/web/config', {signal:attempt.controller.signal});
    if (!active()) return;
    const url = await startAppleLogin(api, boot.csrf_token, attempt.controller.signal);
    if (!active()) return;
    attempt.navigating = true;
    location.assign(url);
    // Keep progress until navigation actually leaves, rather than merely starts.
  } catch (error) {
    if (!active()) return;
    cancelAppleLogin();
    setText('account-error', errorMessage(error));
    renderConnection();
  }
});
$('provider-connect').addEventListener('click', async () => {
  if (!session?.user?.id || checking || providerFlight || providerError || !session.provider || session.provider.connected === true || config?.chatgpt_connect_available !== true) return;
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
    $('bootstrap-expiry').dataset.expires = String(Date.now() + value.expires_in * 1000); renderBootstrapExpiry();
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
window.addEventListener('pagehide', () => cancelAppleLogin({leaving:true}));
window.addEventListener('pageshow', event => { cancelAppleLogin(); if (event.persisted) { clearPrivateData(); restore(); } else renderConnection(); });
window.addEventListener('online', () => restore({force:false}));
document.addEventListener('visibilitychange', () => { if (document.hidden) podcasts.pause(); else restore({force:false}); });
updateInput(); restore();

function renderBootstrapExpiry() { const expires=Number($('bootstrap-expiry').dataset.expires); if(expires)bindInterfaceText($('bootstrap-expiry'),'Gültig bis {time}. Danach „Verbindung erneut prüfen“.',{time:new Date(expires).toLocaleTimeString(getInterfaceLanguage(),{hour:'2-digit',minute:'2-digit'})}); }
document.querySelectorAll('[data-interface-language]').forEach(select=>select.addEventListener('change',()=>{
  if(!setInterfaceLanguage(select.value))return;
  applyInterfaceLanguage(); renderStyles(); updateInput(); renderBootstrapExpiry();
  const appleArt=!checking&&!sessionError&&!session?.user?.id&&config?.apple_available===true;
  $('connection-action').classList.toggle('apple-button',appleArt);$('connection-action-art').hidden=!appleArt;$('connection-action-label').hidden=appleArt;
  document.querySelectorAll('[data-history-date]').forEach(el=>{const date=new Date(el.dataset.historyDate);el.textContent=el.dataset.direction+(Number.isNaN(date.valueOf())?'':` · ${date.toLocaleString(getInterfaceLanguage(),{dateStyle:'medium',timeStyle:'short'})}`);});
  followup.localize(); podcasts.localize();coach.localize();renderLearningProfile();
  document.title=`Keine Magie · ${document.querySelector('.section-nav [aria-current="page"]').textContent}`;
}));


// Explore surface: a compact cover/title list, then episode rows and a reader.
function mountPodcasts({api, account, unauthorized}) {
  const $ = id => document.getElementById(id);
  let session=null, checking=true, config=null, identityError='', ownerRun=0, dialogRun=0;
  const library=createPodcasts({api,changed:render,unauthorized,visible:()=>!document.hidden});
  let episodeView=null, episodeFlight=null;
  async function ensureEpisode() {
    if (!episodeFlight) episodeFlight=import('./episode-view.mjs').then(({createEpisodeView})=>{episodeView=createEpisodeView({api,unauthorized,openProfile:account});episodeView.identity(session);return episodeView;});
    return episodeFlight;
  }
  let renderSignature='', reader=null;
  let resolvedPermalink=null, resolving=null, routeFlight=null, routeKey=null;
  async function openRoute(hash) {
    const permalink=episodeLocation(location.pathname,hash);
    const key=`${session?.user?.id||''}:${location.pathname}:${hash}`;
    if(routeFlight&&routeKey===key)return routeFlight;
    if(routeKey===key&&resolvedPermalink&&library.state.route.kind==='job')return;
    routeKey=key;const epoch=ownerRun;
    const task=(async()=>{
      try {
        if(permalink&&session?.user?.id&&!checking){
          resolving=permalink;resolvedPermalink=null;render();
          const view=await ensureEpisode();
          if(epoch!==ownerRun||routeKey!==key)return;
          const job=await view.client.resolve(permalink);
          if(epoch!==ownerRun||routeKey!==key)return;
          resolvedPermalink={permalink,id:job.id};resolving=null;
          library.state.route={kind:'job',id:job.id};
          library.state.jobs=[job,...library.state.jobs.filter(j=>j.id!==job.id)];
          render();
          void library.activate(podcastRoute('job',job.id));
          if(epoch!==ownerRun||routeKey!==key)return;
          library.state.jobs=[job,...library.state.jobs.filter(j=>j.id!==job.id)];render();
        } else {
          resolvedPermalink=null;await library.activate(permalink?'#podcasts':hash);
          if(epoch!==ownerRun||routeKey!==key)return;
          if(library.state.route.kind==='job'&&session?.user?.id&&!checking){
            const job=await library.detail(library.state.route.id);
            const path=await episodePath(job);
            if(epoch!==ownerRun||routeKey!==key)return;
            resolvedPermalink={permalink:path.split('/').pop(),id:job.id};
            window.history.replaceState(null,'',path+location.search);render();
          }
        }
      } catch(error){if(epoch===ownerRun&&error.name!=='AbortError'){resolving=null;library.state.error=podcastError(error);render();}}
    })().finally(()=>{if(routeFlight===task)routeFlight=null;});
    routeFlight=task;return task;
  }
  const node=(tag,text,cls)=>{const el=document.createElement(tag); if(text!==undefined)el.textContent=text; if(cls)el.className=cls; return el;};
  function action(label,fn,disabled=false) {
    const button=node('button',t(label),'small-button'); button.type='button'; button.disabled=disabled||checking||!session?.user?.id;
    const run=ownerRun;
    button.onclick=async event=>{if(run!==ownerRun||checking||!session?.user?.id)return;const target=event.currentTarget;target.disabled=true;try{await fn();}catch(error){if(run===ownerRun&&error.name!=='AbortError'){library.state.error=podcastError(error);render();}}finally{if(run===ownerRun)target.disabled=false;}}; return button;
  }
  function link(text,hash) { const a=node('a',text==='← Podcasts'?t(text):text); a.href=hash; return a; }
  function cover(feed) {
    const box=node('span',undefined,'podcast-cover'); box.setAttribute('aria-hidden','true');
    box.textContent=(feed.title||'P').slice(0,1);
    if(feed.artwork_url){const img=node('img');img.alt='';img.width=64;img.height=64;img.referrerPolicy='no-referrer';img.src=`/v1/podcasts/subscriptions/${apiID(feed.id)}/artwork`;img.addEventListener('error',()=>img.remove(),{once:true});box.append(img);}return box;
  }
  function status(job) {
    const labels={queued:'In Warteschlange',fetching:'Audio wird geladen',transcribing:'Transkription läuft',translating:'Übersetzung läuft',completed:'Bereit',failed:'Fehlgeschlagen',canceled:'Abgebrochen'};
    const p=node('p',t(labels[job.state]||'Unbekannter Status'),'muted podcast-progress');
    if(isActive(job)){ const progress=node('progress');progress.max=100;if(Number.isFinite(job.progress))progress.value=Math.max(0,Math.min(100,job.progress));progress.setAttribute('aria-label',t('Verarbeitungsschritt, kein Audio-Fortschritt'));p.append(progress); }
    if(job.error)p.append(node('span',job.error,'error-text'));return p;
  }
  function overflow(label, buttons, key) {
    const details=node('details',undefined,'podcast-overflow');details.dataset.key=key;
    const summary=node('summary','⋯');summary.setAttribute('aria-label',label);summary.title=label;
    summary.onclick=event=>{document.querySelectorAll('.podcast-overflow[open]').forEach(menu=>{if(menu!==event.currentTarget.parentElement)menu.open=false;});};
    const panel=node('div',undefined,'podcast-overflow-panel');panel.append(...buttons);details.append(summary,panel);return details;
  }
  document.addEventListener('keydown',event=>{if(event.key!=='Escape')return;const menu=document.activeElement?.closest('.podcast-overflow[open]')||document.querySelector('.podcast-overflow[open]');if(menu){menu.open=false;menu.querySelector('summary').focus();event.preventDefault();}});
  document.addEventListener('click',event=>{document.querySelectorAll('.podcast-overflow[open]').forEach(menu=>{if(!menu.contains(event.target))menu.open=false;});});
  function controls(job,container) {
    if(isActive(job))container.append(action('Abbrechen',async()=>{await library.jobAction(job.id,'cancel');await library.detail(job.id);}));
    if(['failed','canceled'].includes(job.state))container.append(action('Erneut versuchen',async()=>{await library.jobAction(job.id,'retry');await library.detail(job.id);},!library.state.worker));
    if(!isActive(job)){
      const remove=action('Löschen',async()=>{if(!confirm(t('Diese vorbereitete Folge und ihre Transkripte wirklich löschen?')))return;await library.jobAction(job.id,'delete');await library.load();if(library.state.route.kind==='job')location.hash='#podcasts';});remove.classList.add('destructive-action');
      container.append(overflow(t('Folgenaktionen'),[remove],`actions:${job.id}`));
    }
  }
  function render(){
    const content=$('podcast-content');
    if(library.state.route.kind==='job'){renderBody(content);return;}
    const draft=node('div');renderBody(draft);
    if(draft.dataset.skipped)return;
    draft.id=content.id;draft.setAttribute('aria-busy',content.getAttribute('aria-busy')||'false');reconcileDOM(content,draft);
  }
  function renderBody(content) {
    const s=library.state;
    const signature=JSON.stringify([session?.user?.id,checking,identityError,config?.apple_available,s.phase,s.error,s.worker,s.route,s.feeds,s.jobs,[...s.pending],resolvedPermalink,resolving,getInterfaceLanguage(),!!episodeView]);
    if(signature===renderSignature){content.dataset.skipped="true";return;}
    renderSignature=signature;
    const selectedJob=s.route.kind==='job'&&s.jobs.find(j=>j.id===s.route.id);
    const keepReader=!!(selectedJob&&reader?.isConnected&&reader.dataset.job===selectedJob.id);
    if(!keepReader){content.replaceChildren();reader=null;}
    unbindInterfaceText($('podcast-notice'));
    const feedTitle=s.route.kind==='feed'&&s.feeds.find(feed=>feed.id===s.route.id)?.title;
    unbindInterfaceText($('podcasts-title'));$('podcasts-title').textContent=feedTitle||t('Podcasts');
    bindInterfaceText($('podcast-reload'),'Liste aktualisieren');
    $('podcast-reload').hidden=s.route.kind==='feed';
    $('podcast-add').disabled=checking||!session?.user?.id;
    $('podcast-reload').disabled=checking||(!session?.user?.id&&!identityError)||s.phase==='loading';
    $('podcast-signin').hidden=checking||!!session?.user?.id||config?.apple_available!==true;
    $('podcast-notice').classList.toggle('error-text',!!s.error);
    $('podcast-notice').textContent=t(checking?'Sitzung wird geprüft …':identityError||!session?.user?.id?(identityError||'Melde dich an, um deine Podcasts zu öffnen.'):s.error||(!selectedJob&&['idle','loading'].includes(s.phase)?'Podcasts werden geladen …':!s.worker?'Vorbereitung derzeit nicht verfügbar. Abos und Folgen bleiben zugänglich.':''));
    content.setAttribute('aria-busy',String(s.phase==='loading'));
    if(checking||!session?.user?.id)return;
    if(['idle','loading'].includes(s.phase)&&!selectedJob){for(let i=0;i<3;i++)content.append(node('div',undefined,'podcast-skeleton'));return;}
    if(s.phase==='error')return;
    const route=s.route;
    if(episodeLocation(location.pathname,location.hash)&&!resolvedPermalink&&!selectedJob){content.replaceChildren();content.append(node('p',resolving?t('Podcasts werden geladen …'):s.error||t('Vorbereitung nicht gefunden.')));return;}
    if(route.kind==='invalid'){content.append(node('p',t('Ungültiger Podcast-Link.')));content.append(link('← Podcasts','#podcasts'));return;}
    if(route.kind==='feed') {
      content.append(link('← Podcasts','#podcasts'));
      const feed=s.feeds.find(f=>f.id===route.id);if(!feed){content.append(node('p',t('Podcast nicht gefunden.')));return;}
      const header=node('div',undefined,'podcast-feed-heading');
      const bar=node('div',undefined,'podcast-actions podcast-feed-controls');
      const direction=node('select');direction.setAttribute('aria-label',t('Podcast-Sprachrichtung'));for(const [value,label] of [['de','de → ru'],['ru','ru → de']]){const option=node('option',label);option.value=value;direction.append(option);}direction.value=source;direction.disabled=checking;direction.onchange=()=>source=direction.value;
      const directionLabel=node('label',t('Sprachrichtung'),'podcast-direction');directionLabel.append(direction);bar.append(directionLabel);
      const refresh=action('Feed aktualisieren',async()=>{await library.refresh(feed.id);await library.load();});
      const remove=action('Abo entfernen',async()=>{if(!confirm(t('„{title}“ wirklich nicht mehr abonnieren? Vorbereitete Folgen werden nicht gelöscht.',{title:feed.title})))return;await library.unsubscribe(feed.id);await library.load();location.hash='#podcasts';});remove.classList.add('destructive-action');
      const menu=overflow(t('Podcast-Aktionen'),[refresh,remove],`feed-actions:${feed.id}`);menu.dataset.feedActions='';bar.append(menu);header.append(cover(feed),bar);content.append(header);
      content.append(node('p',t('Vorbereiten startet Transkription und Übersetzung über dein Konto.'),'muted podcast-prepare-help'));
      if(!feed.episodes?.length)content.append(node('p',t('Dieser Feed enthält noch keine verfügbaren Folgen.'),'muted'));
      const list=node('ul',undefined,'podcast-list');
      for(const episode of feed.episodes||[]) {
        const job=library.preparation(feed,episode);
        const row=node('li',undefined,'podcast-episode');row.dataset.key=episode.id;row.dataset.state=job?.state||'unprepared';const title=node('div');
        const heading=node('strong',undefined,'podcast-episode-title');heading.append(job?link(episode.title||t('Folge'),podcastRoute('job',job.id)):document.createTextNode(episode.title||t('Folge')));title.append(heading);
        const metadata=node('div',undefined,'podcast-episode-meta');
        if(episode.published){const date=new Date(episode.published);if(!Number.isNaN(date.valueOf()))metadata.append(node('small',date.toLocaleDateString(getInterfaceLanguage()),'muted'));}
        if(job)metadata.append(status(job));if(job?.coverage){const c=job.coverage,coverage=node('small',undefined,'muted');coverage.dataset.coverage='';coverage.append(node('span',t('Übersetzt {translated} / {total} Segmente',{translated:c.translated_segments,total:c.recognized_segments})));if(c.recognized_segments>0)coverage.append(document.createTextNode(' · '),node('span',t('Markierte Passagen {count} / {total}',{count:c.favorite_passages,total:c.recognized_segments})));metadata.append(coverage);}title.append(metadata);row.append(title);
        const actions=node('div',undefined,'podcast-actions');
        if(job){controls(job,actions);}
        else actions.append(action('Vorbereiten',async()=>{const job=await library.prepare(feed.id,episode.id,source);await library.detail(job.id);},!s.worker||s.pending.has(`${session.user.id}:prepare:${feed.id}:${episode.id}`)));
        row.append(actions);list.append(row);
      }content.append(list);return;
    }
    if(route.kind==='job'){
      const job=s.jobs.find(j=>j.id===route.id);
      if(!job){content.append(node('p',t('Vorbereitung nicht gefunden.')));return;}
      if(!episodeView){void ensureEpisode().then(()=>render());return;}
      if(!reader){reader=node('article');reader.dataset.job=job.id;content.replaceChildren(reader);}
      episodeView.render(reader,job,{feed:s.feeds.find(f=>f.id===job.feed_id),controls});return;
    }
    const list=node('ul',undefined,'podcast-list');
    for (const feed of s.feeds){const li=node('li');li.dataset.key=feed.id;const a=link('',podcastRoute('feed',feed.id));a.className='podcast-feed';const text=node('span');text.append(node('strong',feed.title||'Podcast'),node('small',feed.latest_episode_title||feed.episodes?.[0]?.title||t('Noch keine Folgen'),'muted'));a.append(cover(feed),text,node('span','›'));li.append(a);list.append(li);}content.append(list);
    const imports=library.directJobs();if(imports.length){content.append(node('h2',t('Einzelne Folgen')));const list=node('ul',undefined,'podcast-list');for(const job of imports){const li=node('li',undefined,'podcast-episode');li.dataset.key=job.id;const title=node('div');title.append(link(job.title||sourceName(job),podcastRoute('job',job.id)),status(job));li.append(title);list.append(li);}content.append(list);}
    if(!s.feeds.length&&!imports.length)content.append(node('p',t('Noch keine Podcasts. Füge über + einen Podcast oder eine einzelne Folge hinzu.'),'muted'));
  }
  let source='de';
  function close() {dialogRun++;$('podcast-dialog').close();$('podcast-url').value='';unbindInterfaceText($('podcast-add-error'));$('podcast-add-error').textContent='';$('podcast-submit').disabled=false;}
  $('podcast-add').onclick=()=>{if(checking||!session?.user?.id)return;$('podcast-dialog').showModal();$('podcast-url').focus();};
  $('podcast-close').onclick=close;$('podcast-dialog').addEventListener('cancel',close);
  $('podcast-mode').onchange=()=>{const episode=$('podcast-mode').value==='episode';$('podcast-import-language').hidden=!episode;bindInterfaceText($('podcast-submit'),episode?'Vorbereiten':'Abonnieren');bindInterfaceText($('podcast-add-help'),episode?'Öffentliche Folge mit direktem Audio. Startet Transkription und Übersetzung über dein Konto.':'Ein RSS-/Atom-Feed oder eine öffentliche Podcast-Seite. Ein Abo startet keine KI-Verarbeitung.');};
  $('podcast-form').onsubmit=async event=>{event.preventDefault();if(checking||!session?.user?.id||$('podcast-submit').disabled)return;const run=ownerRun,dialog=dialogRun; $('podcast-submit').disabled=true;try{const episode=$('podcast-mode').value==='episode';const value=await (episode?library.importURL($('podcast-url').value,$('podcast-source').value):library.subscribe($('podcast-url').value));if(run!==ownerRun)return;if(episode)await library.detail(value.id);await library.load();if(run!==ownerRun||dialog!==dialogRun)return;close();location.hash=podcastRoute(episode?'job':'feed',value.id);}catch(error){if(run===ownerRun&&dialog===dialogRun)bindInterfaceText($('podcast-add-error'),podcastError(error));}finally{if(run===ownerRun&&dialog===dialogRun)$('podcast-submit').disabled=false;}};
  $('podcast-reload').onclick=async()=>{if(identityError)return restore();if(library.state.route.kind==='job'&&resolvedPermalink){await library.detail(library.state.route.id);return;}await openRoute(location.hash);};
  $('podcast-signin').onclick=openAppleSignIn;
  return {library,
    identity(value,options={}) {if(session?.user?.id!==value?.user?.id){ownerRun++;close();source='de';resolvedPermalink=null;resolving=null;routeFlight=null;routeKey=null;}session=value;episodeView?.identity(value);checking=!!options.checking&&!value?.user?.id;identityError=options.error||(options.checking?'Sitzung wird im Hintergrund geprüft …':'');config=options.config;library.identity(value);if(checking)library.pause();render();},
    route:openRoute,
    localize:()=>{if(library.state.route.kind==='job')episodeView?.localize();else render();$('podcast-mode').onchange();const error=$('podcast-add-error');if(error.dataset.message)error.textContent=t(error.dataset.message);},
    pause:()=>library.pause()
  };
}
function timestamp(seconds){if(!Number.isFinite(seconds)||seconds<0)return '—';const value=Math.floor(seconds);return `${Math.floor(value/60)}:${String(value%60).padStart(2,'0')}`;}
function sourceName(job){try{return new URL(job.source_url||job.url).hostname+' · '+(job.source_language||'de')+' → '+(job.target_language||'ru');}catch{return t('Importierte Folge');}}
