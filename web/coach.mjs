import {createCoachState} from './coach-state.mjs';
import {coachVisibleTurns,coachRecentTurns,coachHistoryWindow,coachExerciseStatus,coachPresentationLabel as pl} from './coach-presentation.mjs';
import {reconcileDOM} from './core.mjs';
import {coachMasksAnswer,coachUnread,coachChatLabel,coachQuickActions,coachQuickLabel} from './coach-chat.mjs';
const words={
 en:['Your daily practice and questions.','Message','Send','Practice · ~30 sec','Skip','Show source / hint','Check','Cancel','Skills','No observations yet. Your self-assessed CEFR stays separate.','Answer','Refresh','Reset observations','Correct','Needs practice','I can’t check this confidently','Skipped','Excluded','Pending · reload never retries. Cancel to continue.','Failed · send a new message to try again.','Canceled','With help','Examples','Answers','Limited evidence','Self-assessment','Sign in to use Coach.','Saved translations and saved podcast passages only. One personal gpt-6.1-terra call per message; shared daily limit 100.','Exclude','Count as correct','Count as needs practice','Reset observations? Your chat and self-assessed CEFR stay unchanged.'],
 de:['Dein tägliches Training und deine Fragen.','Nachricht','Senden','Üben · ~30 Sek.','Überspringen','Quelle / Hinweis','Prüfen','Abbrechen','Fähigkeiten','Noch keine Beobachtungen. Deine CEFR-Selbsteinschätzung bleibt getrennt.','Antwort','Aktualisieren','Beobachtungen zurücksetzen','Richtig','Weiter üben','Das kann ich nicht sicher beurteilen','Übersprungen','Ausgeschlossen','Ausstehend · Neuladen wiederholt nichts. Zum Fortfahren abbrechen.','Fehlgeschlagen · zum Wiederholen eine neue Nachricht senden.','Abgebrochen','Mit Hilfe','Beispiele','Antworten','Begrenzte Evidenz','Selbsteinschätzung','Melde dich für Coach an.','Nur gespeicherte Übersetzungen und Podcaststellen. Ein persönlicher gpt-6.1-terra-Aufruf pro Nachricht; gemeinsames Tageslimit 100.','Ausschließen','Als richtig werten','Zum Üben markieren','Beobachtungen zurücksetzen? Chat und CEFR-Selbsteinschätzung bleiben erhalten.'],
 ru:['Ежедневная практика и ваши вопросы.','Сообщение','Отправить','Практика · ~30 сек','Пропустить','Источник / подсказка','Проверить','Отменить','Навыки','Наблюдений пока нет. Самооценка CEFR остаётся отдельно.','Ответ','Обновить','Сбросить наблюдения','Верно','Стоит повторить','Не могу уверенно проверить','Пропущено','Исключено','Ожидание · перезагрузка не повторит запрос. Отмените, чтобы продолжить.','Не удалось · отправьте новое сообщение для повтора.','Отменено','С подсказкой','Примеры','Ответы','Мало данных','Самооценка','Войдите, чтобы использовать тренера.','Только сохранённые переводы и отмеченные фрагменты подкастов. Один личный запрос gpt-6.1-terra на сообщение; общий лимит — 100 в день.','Исключить','Засчитать как верный','Оставить для повторения','Сбросить наблюдения? Чат и самооценка CEFR останутся.'],
 es:['Tu práctica diaria y tus preguntas.','Mensaje','Enviar','Practicar · ~30 s','Omitir','Fuente / pista','Comprobar','Cancelar','Habilidades','Sin observaciones. Tu autoevaluación MCER sigue separada.','Respuesta','Actualizar','Restablecer observaciones','Correcto','Para practicar','No puedo evaluarlo con seguridad','Omitido','Excluido','Pendiente · recargar no repite la solicitud. Cancela para continuar.','Error · envía un mensaje nuevo para reintentar.','Cancelado','Con ayuda','Ejemplos','Respuestas','Pocos datos','Autoevaluación','Inicia sesión para usar el entrenador.','Solo traducciones y pasajes guardados. Una llamada personal a gpt-6.1-terra por mensaje; límite diario compartido de 100.','Excluir','Marcar correcto','Marcar para practicar','¿Restablecer observaciones? Se conservan el chat y tu autoevaluación MCER.'],
 fr:['Ta pratique quotidienne et tes questions.','Message','Envoyer','Pratiquer · ~30 s','Passer','Source / indice','Vérifier','Annuler','Compétences','Pas encore d’observations. Ton autoévaluation CECR reste séparée.','Réponse','Actualiser','Réinitialiser les observations','Correct','À pratiquer','Je ne peux pas vérifier avec certitude','Passé','Exclu','En attente · actualiser ne relance rien. Annule pour continuer.','Échec · envoie un nouveau message pour réessayer.','Annulé','Avec aide','Exemples','Réponses','Peu de données','Autoévaluation','Connecte-toi pour utiliser Coach.','Uniquement les traductions et passages enregistrés. Un appel personnel gpt-6.1-terra par message ; limite commune de 100 par jour.','Exclure','Marquer correct','Marquer à pratiquer','Réinitialiser les observations ? Le chat et ton autoévaluation CECR sont conservés.']
};
const coachStrings={"coach.openSource": {"de": "Original öffnen", "en": "Open original", "ru": "Открыть оригинал", "es": "Abrir original", "fr": "Ouvrir l’original"}, "coach.sourceMissing": {"de": "Quelle nicht verfügbar. Verlauf aktualisieren.", "en": "Source unavailable. Refresh saved history.", "ru": "Источник недоступен. Обновите историю.", "es": "Fuente no disponible. Actualiza el historial.", "fr": "Source indisponible. Actualise l’historique."}, "coach.error.network": {"de": "Keine Verbindung zum Keine-Magie-Server. Verbindung prüfen und Chat aktualisieren.", "en": "Can’t reach the Keine Magie server. Check your connection and refresh the chat.", "ru": "Нет связи с сервером Keine Magie. Проверьте соединение и обновите чат.", "es": "No se puede conectar con el servidor de Keine Magie. Revisa la conexión y actualiza el chat.", "fr": "Connexion au serveur Keine Magie impossible. Vérifie la connexion et actualise le chat."}, "coach.error.session": {"de": "Erneut anmelden und aktualisieren.", "en": "Sign in again, then refresh.", "ru": "Войдите снова и обновите.", "es": "Vuelve a iniciar sesión y actualiza.", "fr": "Reconnecte-toi puis actualise."}, "coach.error.storage": {"de": "Speichern nicht möglich. Aktualisieren, bevor du fortfährst.", "en": "Could not save. Refresh before continuing.", "ru": "Не удалось сохранить. Обновите перед продолжением.", "es": "No se pudo guardar. Actualiza antes de continuar.", "fr": "Enregistrement impossible. Actualise avant de continuer."}, "coach.error.invalid": {"de": "Eingabe prüfen und erneut senden.", "en": "Check your input and send again.", "ru": "Проверьте ввод и отправьте снова.", "es": "Revisa el texto y envíalo de nuevo.", "fr": "Vérifie le texte et renvoie-le."}, "coach.error.quota": {"de": "Tageslimit oder aktive Anfrage. Später erneut versuchen.", "en": "Daily limit or active request. Try again later.", "ru": "Дневной лимит или активный запрос. Попробуйте позже.", "es": "Límite diario o solicitud activa. Inténtalo más tarde.", "fr": "Limite quotidienne ou requête active. Réessaie plus tard."}, "coach.error.canceled": {"de": "Anfrage abgebrochen. Gespeicherten Chat aktualisieren.", "en": "Request canceled. Refresh the saved chat.", "ru": "Запрос отменён. Обновите сохранённый чат.", "es": "Solicitud cancelada. Actualiza el chat guardado.", "fr": "Requête annulée. Actualise le chat enregistré."}, "coach.error.conflict": {"de": "Chat hat sich geändert. Vor dem Fortfahren aktualisieren.", "en": "Chat changed. Refresh before continuing.", "ru": "Чат изменился. Обновите перед продолжением.", "es": "El chat cambió. Actualiza antes de continuar.", "fr": "Le chat a changé. Actualise avant de continuer."}, "coach.error.connection_required": {"de": "Persönliches ChatGPT-Konto im Profil verbinden.", "en": "Connect your personal ChatGPT account in Profile.", "ru": "Подключите личный аккаунт ChatGPT в профиле.", "es": "Conecta tu cuenta personal de ChatGPT en Perfil.", "fr": "Connecte ton compte ChatGPT personnel dans Profil."}, "coach.error.catalog_unavailable": {"de": "Modellliste nicht verfügbar. Später erneut versuchen; keine KI-Anfrage gesendet.", "en": "Model catalog unavailable. Try later; no inference sent.", "ru": "Список моделей недоступен. Попробуйте позже; запрос к ИИ не отправлен.", "es": "Catálogo no disponible. Inténtalo luego; no se envió inferencia.", "fr": "Catalogue indisponible. Réessaie plus tard ; aucune inférence envoyée."}, "coach.error.model_unavailable": {"de": "gpt-6.1-terra ist für dieses Konto nicht verfügbar. Kein Ersatzmodell verwendet.", "en": "gpt-6.1-terra is unavailable for this account. No fallback used.", "ru": "gpt-6.1-terra недоступна для этого аккаунта. Замена не использована.", "es": "gpt-6.1-terra no está disponible para esta cuenta. No se usó otro modelo.", "fr": "gpt-6.1-terra est indisponible pour ce compte. Aucun autre modèle utilisé."}, "coach.error.sources_required": {"de": "Zuerst eine Übersetzung oder Podcaststelle speichern.", "en": "Save a translation or podcast passage first.", "ru": "Сначала сохраните перевод или фрагмент подкаста.", "es": "Guarda primero una traducción o un pasaje de podcast.", "fr": "Enregistre d’abord une traduction ou un passage de podcast."}, "coach.error.sources_unavailable": {"de": "Gespeicherte Quellen nicht verfügbar. Verlauf aktualisieren.", "en": "Saved sources unavailable. Refresh history.", "ru": "Сохранённые источники недоступны. Обновите историю.", "es": "Fuentes guardadas no disponibles. Actualiza el historial.", "fr": "Sources enregistrées indisponibles. Actualise l’historique."}, "coach.target.grammar.case": {"de": "Kasus", "en": "Case", "ru": "Падежи", "es": "Casos", "fr": "Cas"}, "coach.target.grammar.gender_article": {"de": "Genus und Artikel", "en": "Gender and articles", "ru": "Род и артикли", "es": "Género y artículos", "fr": "Genre et articles"}, "coach.target.grammar.adjective_agreement": {"de": "Adjektivendungen", "en": "Adjective agreement", "ru": "Согласование прилагательных", "es": "Concordancia adjetival", "fr": "Accord des adjectifs"}, "coach.target.grammar.tense_aspect": {"de": "Zeitform und Aspekt", "en": "Tense and aspect", "ru": "Время и вид", "es": "Tiempo y aspecto", "fr": "Temps et aspect"}, "coach.target.verb_government.preposition_case": {"de": "Verb + Präposition und Kasus", "en": "Verb + preposition and case", "ru": "Глагол + предлог и падеж", "es": "Verbo + preposición y caso", "fr": "Verbe + préposition et cas"}, "coach.target.verb_government.object_case": {"de": "Verb + Objektkasus", "en": "Verb + object case", "ru": "Глагол + падеж дополнения", "es": "Verbo + caso del objeto", "fr": "Verbe + cas du complément"}, "coach.target.vocabulary.collocation": {"de": "Wortverbindungen", "en": "Collocations", "ru": "Сочетаемость слов", "es": "Colocaciones", "fr": "Collocations"}, "coach.target.vocabulary.word_choice": {"de": "Wortwahl", "en": "Word choice", "ru": "Выбор слова", "es": "Elección de palabras", "fr": "Choix des mots"}, "coach.target.vocabulary.word_formation": {"de": "Wortbildung", "en": "Word formation", "ru": "Словообразование", "es": "Formación de palabras", "fr": "Formation des mots"}, "coach.target.word_order.main_clause": {"de": "Wortstellung im Hauptsatz", "en": "Main-clause word order", "ru": "Порядок слов в главном предложении", "es": "Orden en oración principal", "fr": "Ordre dans la proposition principale"}, "coach.target.word_order.subordinate_clause": {"de": "Wortstellung im Nebensatz", "en": "Subordinate-clause word order", "ru": "Порядок слов в придаточном", "es": "Orden en subordinadas", "fr": "Ordre dans la subordonnée"}, "coach.target.register.formality": {"de": "Formell oder informell", "en": "Formal and informal language", "ru": "Формальная и неформальная речь", "es": "Lenguaje formal e informal", "fr": "Langage formel et informel"}, "coach.hint": {"de": "Hinweis", "en": "Hint", "ru": "Подсказка", "es": "Pista", "fr": "Indice"}, "coach.source": {"de": "Quelle", "en": "Source", "ru": "Источник", "es": "Fuente", "fr": "Source"}, "coach.savedTranslation": {"de": "Gespeicherte Übersetzung", "en": "Saved translation", "ru": "Сохранённый перевод", "es": "Traducción guardada", "fr": "Traduction enregistrée"}, "coach.savedPassage": {"de": "Gespeicherte Podcaststelle", "en": "Saved podcast passage", "ru": "Сохранённый фрагмент подкаста", "es": "Pasaje de podcast guardado", "fr": "Passage de podcast enregistré"}, "coach.ambiguous": {"de": "Das kann ich nicht sicher beurteilen", "en": "I can’t check this confidently", "ru": "Не могу уверенно проверить", "es": "No puedo evaluarlo con seguridad", "fr": "Je ne peux pas vérifier avec certitude"}, "coach.error.server": {"de": "Der Keine-Magie-Server hat einen Fehler gemeldet. Chat vor dem erneuten Senden aktualisieren.", "en": "The Keine Magie server returned an error. Refresh the chat before sending again.", "ru": "Сервер Keine Magie вернул ошибку. Обновите чат перед повторной отправкой.", "es": "El servidor de Keine Magie devolvió un error. Actualiza el chat antes de volver a enviar.", "fr": "Le serveur Keine Magie a renvoyé une erreur. Actualise le chat avant de renvoyer."}, "coach.error.response": {"de": "Die Serverantwort konnte nicht gelesen werden. Chat aktualisieren.", "en": "Couldn’t read the server response. Refresh the chat.", "ru": "Не удалось прочитать ответ сервера. Обновите чат.", "es": "No se pudo leer la respuesta del servidor. Actualiza el chat.", "fr": "Impossible de lire la réponse du serveur. Actualise le chat."}, "coach.error.timeout": {"de": "Keine rechtzeitige Serverantwort. Chat vor dem erneuten Senden aktualisieren.", "en": "The server didn’t respond in time. Refresh the chat before sending again.", "ru": "Сервер не ответил вовремя. Обновите чат перед повторной отправкой.", "es": "El servidor no respondió a tiempo. Actualiza el chat antes de volver a enviar.", "fr": "Le serveur n’a pas répondu à temps. Actualise le chat avant de renvoyer."}, "coach.error.unknown": {"de": "Coach konnte die Anfrage nicht abschließen. Chat vor dem erneuten Senden aktualisieren.", "en": "Coach couldn’t complete the request. Refresh the chat before sending again.", "ru": "Тренер не смог завершить запрос. Обновите чат перед повторной отправкой.", "es": "El entrenador no pudo completar la solicitud. Actualiza el chat antes de volver a enviar.", "fr": "Coach n’a pas pu terminer la demande. Actualise le chat avant de renvoyer."}};
Object.assign(coachStrings,{"coach.assessment.pending": {"en": "AI check pending…", "de": "KI-Prüfung ausstehend…", "ru": "AI проверяет…", "es": "Evaluación de IA pendiente…", "fr": "Vérification IA en cours…"}, "coach.assessment.failed": {"en": "Assessment unavailable. Your answer is saved; no skill evidence added.", "de": "Prüfung nicht verfügbar. Antwort gespeichert; keine neue Beobachtung.", "ru": "Проверка недоступна. Ответ сохранён; данные о навыке не изменены.", "es": "Evaluación no disponible. Respuesta guardada; sin nuevas observaciones.", "fr": "Évaluation indisponible. Réponse enregistrée ; aucune observation ajoutée."}, "coach.assessment.canceled": {"en": "Assessment canceled. Your answer is saved.", "de": "Prüfung abgebrochen. Antwort gespeichert.", "ru": "Проверка отменена. Ответ сохранён.", "es": "Evaluación cancelada. Respuesta guardada.", "fr": "Évaluation annulée. Réponse enregistrée."}, "coach.assessment.recheck": {"en": "Check again with AI", "de": "Erneut mit KI prüfen", "ru": "Проверить заново с AI", "es": "Volver a evaluar con IA", "fr": "Vérifier à nouveau avec l’IA"}, "coach.assessment.confirm": {"en": "Make a new personal gpt-6.1-terra call? An earlier call may already have used quota. The saved answer stays unchanged.", "de": "Neuen persönlichen gpt-6.1-terra-Aufruf senden? Ein früherer Aufruf kann bereits Kontingent verbraucht haben. Die gespeicherte Antwort bleibt unverändert.", "ru": "Отправить новый личный запрос gpt-6.1-terra? Предыдущий запрос уже мог потратить лимит. Сохранённый ответ не изменится.", "es": "¿Hacer otra llamada personal a gpt-6.1-terra? La anterior puede haber consumido cuota. La respuesta guardada no cambia.", "fr": "Faire un nouvel appel personnel à gpt-6.1-terra ? Le précédent peut avoir utilisé du quota. La réponse enregistrée ne change pas."}, "coach.partially_correct": {"en": "Partially correct", "de": "Teilweise richtig", "ru": "Частично верно", "es": "Parcialmente correcto", "fr": "Partiellement correct"}, "coach.incorrect": {"en": "Incorrect", "de": "Nicht richtig", "ru": "Неверно", "es": "Incorrecto", "fr": "Incorrect"}, "coach.uncertain": {"en": "I can’t check this confidently", "de": "Das kann ich nicht sicher beurteilen", "ru": "Не могу уверенно проверить", "es": "No puedo evaluarlo con seguridad", "fr": "Je ne peux pas vérifier avec certitude"}, "coach.scope": {"en": "Saved translations and passages only. Each message and Check makes one personal gpt-6.1-terra call; shared daily limit 100.", "de": "Nur gespeicherte Übersetzungen und Textstellen. Jede Nachricht und Prüfung sendet einen persönlichen gpt-6.1-terra-Aufruf; gemeinsames Tageslimit 100.", "ru": "Только сохранённые переводы и фрагменты. Каждое сообщение и «Проверить» — один личный запрос gpt-6.1-terra; общий лимит 100 в день.", "es": "Solo traducciones y pasajes guardados. Cada mensaje y comprobación usa una llamada personal a gpt-6.1-terra; límite diario compartido de 100.", "fr": "Uniquement les traductions et passages enregistrés. Chaque message et vérification utilise un appel personnel gpt-6.1-terra ; limite commune de 100 par jour."}});
const ct=(key,locale)=>coachStrings[key]?.[locale]||coachStrings[key]?.en||key;
const targets={en:['Grammar','Verb government','Vocabulary','Word order','Register'],de:['Grammatik','Verbanschlüsse','Wortschatz','Wortstellung','Register'],ru:['Грамматика','Управление глаголов','Словарь','Порядок слов','Регистр'],es:['Gramática','Régimen verbal','Vocabulario','Orden de palabras','Registro'],fr:['Grammaire','Régime verbal','Vocabulaire','Ordre des mots','Registre']};
export function coachShowsInstruction(turn){
 if(!turn.message||turn.attempt)return false;
 if(!['cloze','preposition_case'].includes(turn.kind)||!turn.prompt?.includes('___'))return true;
 const generic=/^(fill in (the )?missing (preposition|word)|ergänze (die fehlende präposition|den satz)|вставьте пропущенн(ый предлог|ое слово)|completa la preposición que falta|complète la préposition manquante)[.!]?$/iu;
 return !generic.test(turn.message.trim());
}
export function coachSourceLink(id){
 const translation=/^translation:([A-Za-z0-9_-]{1,128})$/.exec(id||'');
 if(translation)return '/?translation='+encodeURIComponent(translation[1])+'#translator';
 const passage=/^passage:([A-Za-z0-9_-]{1,128}):(0|[1-9][0-9]{0,3})$/.exec(id||'') || /^passage-group:([A-Za-z0-9_-]{1,128}):(0|[1-9][0-9]{0,3}):pg_[a-f0-9]{64}$/.exec(id||'');
 return passage?'/?section=transcript&segment='+passage[2]+'#podcasts/job/'+encodeURIComponent(passage[1]):null;
}
export function mountCoach({host,api,locale,unauthorized,account,document:doc=globalThis.document}){
 const el=(tag,text,cls)=>{const e=doc.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 const l=i=>(words[locale()]||words.en)[i],target=t=>coachStrings['coach.target.'+t]?ct('coach.target.'+t,locale()):(targets[locale()]||targets.en)[['grammar','verb_government','vocabulary','word_order','register'].indexOf(t)]||t;
 let owner=null,signature='',answerDrafts=new Map(),turnCount=0,returnSource=null,showEarlier=0,follow=true,ownSend=false,latestScroll=false,wasVisible=false,historyNow=Date.now();
 const resize=()=>{if(host.hidden)return;const viewport=globalThis.visualViewport;host.style.height=Math.max(240,(viewport?.height||globalThis.innerHeight)-Math.max(0,host.getBoundingClientRect().top)+ (viewport?.offsetTop||0)-12)+'px';};
 globalThis.visualViewport?.addEventListener('resize',resize);
 globalThis.addEventListener?.('resize',resize);
 host.className='coach-page';host.replaceChildren();
 const header=el('div',undefined,'coach-header'),title=el('h1','Coach'),actions=el('div',undefined,'coach-actions');header.append(title,actions);
 const button=(text,action)=>{const b=el('button',text);b.type='button';b.onclick=action;return b;};
 const profile=el('details',undefined,'coach-profile'),summary=el('summary'),profileContent=el('div');profile.append(summary,profileContent);
 const messages=el('div',undefined,'coach-messages');messages.setAttribute('role','log');messages.setAttribute('aria-live','polite');
 const status=el('p',undefined,'coach-status');status.setAttribute('role','status');
 const form=el('form',undefined,'coach-composer'),input=el('textarea');input.rows=1;input.maxLength=2000;input.id='coach-input';
 const send=el('button');send.type='submit';form.append(input,send);host.append(header,messages,status,form);
 const checking=()=>{const e=el('span','•••','coach-checking');e.setAttribute('role','status');e.setAttribute('aria-label',pl('working',locale()));return e;};
 const state=createCoachState(api,render,unauthorized,locale);
 function sendAssessment(action,text='',turnID=''){if(state.busy||!state.signedIn)return;ownSend=true;follow=true;return state.act(action,text,turnID);}
 doc.getElementById('learning-profile')?.append(profile);
 const refresh=button('',()=>state.load()),quick=el('div',undefined,'coach-command-menu');
 quick.id='coach-command-menu';quick.hidden=true;quick.setAttribute('role','menu');
 const menuTrigger=button('+',()=>toggleMenu());menuTrigger.className='coach-menu-trigger';menuTrigger.setAttribute('aria-haspopup','menu');menuTrigger.setAttribute('aria-controls',quick.id);menuTrigger.setAttribute('aria-expanded','false');
 const composer=el('div',undefined,'coach-composer-shell');composer.append(menuTrigger,input,send,quick);form.append(composer);
 actions.append(button(coachChatLabel('profile',locale()),()=>account('de')));
 let menuReturn=null,menuSelection=null,pointerOpen=false;
 function closeMenu(restore=false){quick.hidden=true;menuTrigger.setAttribute('aria-expanded','false');if(restore){const target=menuReturn?.isConnected?menuReturn:menuTrigger;target.focus({preventScroll:true});if(menuSelection&&target.setSelectionRange)target.setSelectionRange(...menuSelection);}pointerOpen=false;}
 function toggleMenu(){
  if(!quick.hidden){closeMenu(true);return;}
  if(!pointerOpen){menuReturn=menuTrigger;menuSelection=null;}
  quick.hidden=false;menuTrigger.setAttribute('aria-expanded','true');quick.querySelector('button:not(:disabled)')?.focus({preventScroll:true});pointerOpen=false;
 }
 menuTrigger.addEventListener('pointerdown',()=>{pointerOpen=true;menuReturn=doc.activeElement;menuSelection=['TEXTAREA','INPUT'].includes(menuReturn?.tagName)?[menuReturn.selectionStart,menuReturn.selectionEnd]:null;});
 menuTrigger.addEventListener('keydown',e=>{if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();pointerOpen=false;if(quick.hidden)toggleMenu();if(e.key==='ArrowUp')[...quick.querySelectorAll('button:not(:disabled)')].at(-1)?.focus();}});
 quick.addEventListener('keydown',e=>{
  if(e.key==='Escape'){e.preventDefault();e.stopPropagation();closeMenu(true);return;}
  if(e.key==='Tab'){closeMenu(false);menuTrigger.focus();return;}
  const items=[...quick.querySelectorAll('button:not(:disabled)')],index=items.indexOf(doc.activeElement);
  if(['ArrowDown','ArrowUp','Home','End'].includes(e.key)&&items.length){e.preventDefault();const next=e.key==='Home'?0:e.key==='End'?items.length-1:(index+(e.key==='ArrowDown'?1:-1)+items.length)%items.length;items[next].focus();}
 });
 doc.addEventListener('pointerdown',e=>{if(!quick.hidden&&!composer.contains(e.target))closeMenu(!e.target.closest?.('button,input,textarea,select,a'));});
 doc.addEventListener('keydown',e=>{if(e.key==='Escape'&&!quick.hidden){e.preventDefault();closeMenu(true);}});
 const jump=button('',()=>{follow=true;bottom();checkSeen();});jump.className='coach-jump';host.insertBefore(jump,status);
 const atBottom=()=>messages.scrollHeight-messages.clientHeight-messages.scrollTop<80;
 function updateJump(){jump.hidden=atBottom();jump.textContent=pl('latest',locale());}
 function bottom(){manualScroll=false;messages.scrollTop=messages.scrollHeight;lastScroll=messages.scrollTop;updateJump();}
 let observedHeight=0;
 const contentObserver=globalThis.ResizeObserver?new ResizeObserver(()=>{
  const height=messages.scrollHeight,grew=height>observedHeight;observedHeight=height;
  // Preserve reading intent across async row growth, but do not re-anchor for
  // viewport/theme/receipt-only notifications or the initial observer delivery.
  if(grew&&hydrated&&follow&&!host.hidden)bottom();else updateJump();
 }):null;
 contentObserver?.observe(messages);
 let lastScroll=0,manualScroll=false;
 messages.addEventListener('wheel',()=>{manualScroll=true;},{passive:true});
 messages.addEventListener('pointerdown',()=>{manualScroll=true;},{passive:true});
 messages.addEventListener('touchstart',()=>{manualScroll=true;},{passive:true});
 messages.addEventListener('keydown',e=>{if(['ArrowUp','ArrowDown','PageUp','PageDown','Home','End',' '].includes(e.key))manualScroll=true;});
 messages.addEventListener('scroll',()=>{if(manualScroll){follow=atBottom();}lastScroll=messages.scrollTop;updateJump();},{passive:true});
 let messageRevision='',hydrated=false,known=new Set(),entered=false;const seeing=new Set(),arriving=new Set();
 messages.addEventListener('animationend',e=>{if(e.animationName==='coach-enter'&&e.target.dataset.turn){arriving.delete(e.target.dataset.turn);e.target.classList.remove('coach-arrival');}});
 let checkingSeen=false;
 async function checkSeen(){
  if(checkingSeen)return;
  checkingSeen=true;
  try {
  if(host.hidden||doc.visibilityState!=='visible'||state.busy||messages.scrollHeight-messages.clientHeight-messages.scrollTop>80)return;
  const bounds=messages.getBoundingClientRect();
  for(const row of messages.querySelectorAll('[data-turn]')){if(host.hidden||doc.visibilityState!=='visible'||state.busy||messages.scrollHeight-messages.clientHeight-messages.scrollTop>80)return;const r=row.getBoundingClientRect(),t=state.value?.turns.find(t=>t.id===row.dataset.turn);if(!t||!coachUnread(t)||seeing.has(t.message_version)||r.top>=bounds.bottom||r.bottom<=bounds.top||Math.min(r.bottom,bounds.bottom)-Math.max(r.top,bounds.top)<Math.min(r.height, bounds.height)*.6)continue;seeing.add(t.message_version);await state.seen(t);seeing.delete(t.message_version);}
  } finally {checkingSeen=false;}
 }
 messages.addEventListener('scroll',checkSeen);doc.addEventListener('visibilitychange',checkSeen);
 const observer=globalThis.IntersectionObserver?new IntersectionObserver(checkSeen,{root:messages,threshold:[0,.6,1]}):null;
 messages.addEventListener('touchstart',e=>{messages.dataset.touch=String(e.touches[0].clientY);},{passive:true});
 messages.addEventListener('touchend',e=>{if(messages.scrollTop===0&&e.changedTouches[0].clientY-Number(messages.dataset.touch)>70)void state.load();},{passive:true});
 form.onsubmit=async e=>{e.preventDefault();const draft=input.value;if(!draft.trim())return;ownSend=true;follow=true;const success=await state.act('message',draft);if(success&&input.value===draft){input.value='';grow();}input.focus({preventScroll:true});};
 const grow=()=>{input.style.height='auto';input.style.height=Math.min(input.scrollHeight,140)+'px';};input.oninput=grow;
 function render(){
  summary.textContent=l(8);refresh.textContent=l(11);input.placeholder=l(1);input.setAttribute('aria-label',l(1));send.textContent=l(2);
  input.disabled=!state.signedIn;send.disabled=!state.signedIn||state.busy;
  menuTrigger.setAttribute('aria-label',coachChatLabel('actions',locale()));quick.setAttribute('aria-label',coachChatLabel('actions',locale()));
  const focusedCommand=quick.hidden?-1:[...quick.children].indexOf(doc.activeElement);
  quick.replaceChildren(...coachQuickActions(state.value).map(a=>{const actionOwner=owner;const b=button(a.action==='progress'?coachChatLabel('progressMenu',locale()):coachQuickLabel(a.action,locale()),async()=>{if(owner!==actionOwner||!state.signedIn||state.busy)return;closeMenu(true);ownSend=a.action!=='reveal';if(ownSend)follow=true;await state.act(a.action,a.action==='reveal'?'source':coachQuickLabel(a.action,locale()),a.turn_id);});b.setAttribute('role','menuitem');b.tabIndex=-1;b.disabled=!state.signedIn||state.busy;return b;}));refresh.disabled=!state.signedIn||state.busy;
  const lastExercise=[...coachVisibleTurns(state.value?.turns||[])].reverse().find(t=>t.kind&&!['clarification','nudge'].includes(t.kind));
  const activeEarlier=lastExercise&&!lastExercise.attempt&&!coachRecentTurns([lastExercise],historyNow).length?lastExercise:null;
  if(activeEarlier){const open=button(pl('awaiting',locale()),()=>{const older=coachVisibleTurns(state.value?.turns||[]).filter(t=>!coachRecentTurns([t],historyNow).length),index=older.indexOf(activeEarlier);showEarlier=(Math.floor((older.length-index-1)/50)+1)*50;follow=false;render();[...messages.querySelectorAll('[data-turn]')].find(e=>e.dataset.turn===activeEarlier.id)?.scrollIntoView({block:'center'});});open.className='coach-active-earlier';open.setAttribute('role','menuitem');open.tabIndex=-1;open.addEventListener('click',()=>closeMenu(true));quick.append(open);}
  menuTrigger.disabled=quick.children.length===0;if(!state.signedIn)closeMenu(false);if(!quick.hidden&&focusedCommand>=0)quick.children[focusedCommand]?.focus({preventScroll:true});
  status.textContent=state.error?ct('coach.error.'+state.error,locale()):'';
  const next=JSON.stringify([state.value,state.busy,state.pendingID,state.signedIn,locale(),showEarlier]);if(next===signature)return;signature=next;
  const active=doc.activeElement, focusedTurn=active?.closest?.('[data-turn]')?.dataset.turn, selection=focusedTurn&&active.tagName==='INPUT'?[active.selectionStart,active.selectionEnd]:null;
  const expanded=[...messages.querySelectorAll?.('details[open]')||[]].map(e=>e.closest('[data-turn]')?.dataset.turn);
  const scroll=messages.scrollTop,nearBottom=messages.scrollHeight-messages.clientHeight-scroll<80;
  const nextMessages=el('div');
  const recent=coachRecentTurns(state.value?.turns||[],historyNow);
  const olderCount=coachVisibleTurns(state.value?.turns||[]).length-recent.length;
  if(olderCount){const earlier=button(pl('earlier',locale()),()=>{showEarlier=showEarlier<olderCount?showEarlier+50:0;follow=false;render();messages.scrollTop=0;});earlier.setAttribute('aria-expanded',String(showEarlier>0));earlier.className='coach-earlier';nextMessages.append(earlier);if(showEarlier){const latest=button(pl('latest',locale()),()=>{showEarlier=0;follow=true;latestScroll=true;render();});latest.className='coach-earlier';nextMessages.append(latest);}}
  if(!coachVisibleTurns(state.value?.turns||[]).length){const bubble=el('div',undefined,'coach-bubble');bubble.append(el('p',state.signedIn?l(0):l(26)));nextMessages.append(bubble);}
  for(const turn of coachHistoryWindow(state.value?.turns||[],historyNow,showEarlier)){
   if(turn.text){const user=el('div',turn.text,'coach-bubble coach-user');user.dataset.key='user:'+turn.id;nextMessages.append(user);}
   const bubble=el('div',undefined,'coach-bubble');bubble.dataset.turn=turn.id;bubble.dataset.key='coach:'+turn.id;
   if(coachUnread(turn))bubble.classList.add('coach-unread');
   if(hydrated&&!known.has(turn.id)&&!globalThis.matchMedia?.('(prefers-reduced-motion: reduce)').matches)arriving.add(turn.id);
   if(arriving.has(turn.id))bubble.classList.add('coach-arrival');
   if(coachShowsInstruction(turn))bubble.append(el('p',turn.message));
   if(turn.state==='pending'){bubble.append(checking(),button(l(7),()=>state.act('cancel','',turn.id)));}
   if(turn.state==='failed'||turn.state==='canceled')bubble.append(el('p',l(turn.state==='failed'?19:20)));
   if(turn.kind&&!['clarification','nudge'].includes(turn.kind)){
    const presentation=coachExerciseStatus(turn);bubble.classList.add('coach-'+presentation);
    if(!['completed','success','incorrect','working'].includes(presentation))bubble.append(el('small',pl(presentation,locale()),'coach-task-status'));
    const card=el('section',undefined,'coach-exercise');card.setAttribute('aria-label',target(turn.target));
    const prompt=el('p',turn.prompt,'coach-prompt'),word=turn.target_text;
    if(turn.kind==='context_translation'&&typeof word==='string'&&word&&turn.prompt?.split(word).length===2){
     const index=turn.prompt.indexOf(word);
     prompt.replaceChildren(el('span',turn.prompt.slice(0,index)),el('strong',word),el('span',turn.prompt.slice(index+word.length)));
    }
    card.append(prompt);
    if(!turn.attempt){
     const answer=el('input');answer.value=answerDrafts.get(turn.id)||'';answer.maxLength=300;answer.setAttribute('aria-label',l(10));answer.placeholder=l(10);answer.disabled=state.busy;answer.oninput=e=>answerDrafts.set(turn.id,e.currentTarget.value);
     const check=button(l(6),()=>{const value=answerDrafts.get(turn.id)||'';if(value.trim())sendAssessment('answer',value,turn.id);});check.disabled=state.busy;
     answer.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();check.click();}};
     const skip=button(l(4),()=>sendAssessment('skip','',turn.id));skip.disabled=state.busy;card.append(answer,check,skip);
    }else if(coachMasksAnswer(turn,state.value.turns)){
     const reveal=button(coachChatLabel('answer',locale()),()=>state.act('reveal','answer',turn.id));reveal.disabled=state.busy;card.append(reveal);
    }else{
     const a=turn.attempt, pending=a.assessment_state&&a.assessment_state!=='completed';
     const feedback=pending?ct('coach.assessment.'+a.assessment_state,locale()):a.assessment&&!a.excluded&&!a.reviewed_at?(a.assessment.verdict==='correct'?l(13):ct('coach.'+a.assessment.verdict,locale())):l(a.excluded?17:({correct:13,wrong:14,ambiguous:15,skipped:16}[a.outcome]||15));
     card.append(el('p',a.answer,'coach-answer'),a.assessment_state==='pending'?checking():el(pending||a.outcome==='ambiguous'?'p':'strong',feedback));
     if(a.assessment_state==='pending')card.append(button(l(7),()=>state.act('cancel','',a.id)));
     if(a.outcome!=='skipped'&&!['pending','completed'].includes(a.assessment_state)){
      const recheck=button(ct('coach.assessment.recheck',locale()),()=>{if(window.confirm(ct('coach.assessment.confirm',locale())))sendAssessment('recheck','',turn.id);});recheck.disabled=state.busy;const menu=el('details',undefined,'coach-secondary');menu.append(el('summary','•••'),recheck);card.append(menu);
     }
     if(a.assessment?.corrected_answer&&a.assessment.verdict!=='correct')card.append(el('p',a.assessment.corrected_answer));
     if(a.assisted)card.append(el('small',l(21)));
     if(turn.explanation&&!pending)card.append(el('p',turn.explanation,'coach-explanation'));
    }
    bubble.append(card);
   }

   if(!turn.attempt&&turn.source_reveals&&turn.quote){const hint=el('div',undefined,'coach-hint');hint.append(el('small',coachQuickLabel('reveal',locale())),el('p',turn.quote));if(turn.explanation)hint.append(el('p',turn.explanation));bubble.append(hint);}
   nextMessages.append(bubble);
  }
  if(state.busy&&!state.value?.turns?.some(t=>t.attempt?.assessment_state==='pending')){const busy=el('div',undefined,'coach-bubble');busy.append(checking());if(state.pendingID)busy.append(button(l(7),()=>state.act('cancel','',state.pendingID)));nextMessages.append(busy);}
  // Reconcile stable keyed bubbles: refreshing/pending state must not replay
  // every entry animation or discard the currently edited input.
  nextMessages.className=messages.className;nextMessages.setAttribute('role','log');nextMessages.setAttribute('aria-live','polite');
  const handlers=[...nextMessages.querySelectorAll('input')].map(e=>({oninput:e.oninput,onkeydown:e.onkeydown}));
  reconcileDOM(messages,nextMessages);
  [...messages.querySelectorAll('input')].forEach((e,i)=>{e.oninput=handlers[i]?.oninput;e.onkeydown=handlers[i]?.onkeydown;});
  for(const row of messages.children){if(expanded.includes(row.dataset?.turn))for(const d of row.querySelectorAll?.('details')||[])d.open=true;if(selection&&row.dataset?.turn===focusedTurn){const field=row.querySelector('input');if(field&&!field.disabled){field.focus({preventScroll:true});field.setSelectionRange(...selection);}}}
  messages.scrollTop=scroll;
  const revision=JSON.stringify(coachVisibleTurns(state.value?.turns||[]).map(t=>[t.id,t.state,t.message,t.prompt,t.attempt?.id,t.attempt?.assessment_state]));
  const changedMessages=revision!==messageRevision;messageRevision=revision;
  const shouldScroll=!!state.value&&(!hydrated||ownSend||latestScroll||(changedMessages&&follow&&nearBottom));
  if(shouldScroll)(globalThis.requestAnimationFrame||setTimeout)(()=>{if(!host.hidden&&(ownSend||follow))bottom();});
  ownSend=false;latestScroll=false;
  observedHeight=messages.scrollHeight;
  contentObserver?.disconnect();contentObserver?.observe(messages);for(const row of messages.children)contentObserver?.observe(row);
  turnCount=state.value?.turns?.length||0;
  if(state.value){hydrated=true;known=new Set(state.value.turns.map(t=>t.id));}
  updateJump();
  observer?.disconnect();for(const row of messages.querySelectorAll('[data-turn]'))observer?.observe(row);
  (globalThis.requestAnimationFrame||setTimeout)(checkSeen);
  resize();
  profileContent.replaceChildren();
  for(const o of state.value?.observations||[]){const row=el('div',undefined,'coach-observation');row.append(el('strong',target(o.target)+' · '+o.language),el('p',`${l(23)}: ${o.count} · ${l(22)}: ${o.distinct_examples}`),el('small',`${l(13)}: ${o.correct} · ${l(14)}: ${o.needs_practice} · ${l(21)}: ${o.assisted} · ${l(24)}`));profileContent.append(row);}
  if(!state.value?.observations?.length)profileContent.append(el('p',l(9)));
  for(const turn of state.value?.turns||[]){if(!turn.attempt)continue;
   const review=el('details'),label=el('summary',turn.prompt);review.append(label,el('p',turn.attempt.answer));
   for(const [value,i] of [['excluded',28],['correct',29],['wrong',30]]){const b=button(l(i),()=>state.act('review',value,turn.id));b.disabled=state.busy||!!turn.attempt.assessment_state&&turn.attempt.assessment_state!=='completed';review.append(b);}profileContent.append(review);
  }
  profileContent.append(button(l(25),()=>account('de')));
  const reset=button(l(12),()=>{if(window.confirm(l(31)))state.act('reset');});reset.disabled=!state.signedIn||state.busy;profileContent.append(reset);
 }
 doc.addEventListener('visibilitychange',()=>{if(doc.visibilityState==='visible')enter();else entered=false;});
 render();
 function enter(){if(host.hidden||!state.signedIn){entered=false;return;}if(doc.visibilityState!=='visible')return;if(!entered){entered=true;void state.act('entry');}else void state.load();}
 return {identity(session){const id=session?.user?.id||null;if(id!==owner){closeMenu(false);owner=id;input.value='';answerDrafts.clear();signature='';returnSource=null;hydrated=false;showEarlier=false;follow=true;known.clear();seeing.clear();entered=false;}state.identity(session);enter();},route(){if(!host.hidden&&!wasVisible){historyNow=Date.now();showEarlier=false;hydrated=false;follow=true;signature='';render();}wasVisible=!host.hidden;if(host.hidden){entered=false;closeMenu(false);}resize();enter();if(!host.hidden&&returnSource){const link=[...messages.querySelectorAll('[data-coach-source]')].find(e=>e.dataset.coachSource===returnSource);link?.closest('details')?.setAttribute('open','');link?.focus({preventScroll:true});}},localize(){signature='';render();grow();}};
}
