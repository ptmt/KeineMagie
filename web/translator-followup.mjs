// Owner-scoped discussion state; interface locale changes never perform I/O.
export const followupLabels = {
 en:{draftLimit:'Discussion accepts up to 8,000 characters in each current text. Shorten the draft to continue.',useBoth:'Use both',source:'Suggested source',clarify:'Clarify translation',prompt:'Add context or ask a question',send:'Send',sending:'Sending…',you:'You',assistant:'Answer',revision:'Suggested translation',use:'Use translation',applied:'Used in the current result; original kept in history.',limit:'Discussion limit reached (6 questions).',error:'Could not send. Your draft is kept; retry or reopen history.',quota:'Translation limit reached or another request is active. Try again later.',auth:'Sign in again to continue.',conflict:'Discussion changed. Reopen the translation from history.',count:'characters',close:'Close discussion'},
 de:{draftLimit:'Für die Diskussion sind je Text bis zu 8.000 Zeichen möglich. Kürze den Entwurf.',useBoth:'Text und Übersetzung übernehmen',source:'Vorgeschlagener Ausgangstext',clarify:'Übersetzung klären',prompt:'Kontext ergänzen oder eine Frage stellen',send:'Senden',sending:'Wird gesendet…',you:'Du',assistant:'Antwort',revision:'Vorgeschlagene Übersetzung',use:'Übersetzung übernehmen',applied:'Im aktuellen Ergebnis übernommen; Original bleibt im Verlauf.',limit:'Diskussionslimit erreicht (6 Fragen).',error:'Senden nicht möglich. Dein Entwurf bleibt erhalten; erneut versuchen oder Verlauf öffnen.',quota:'Übersetzungslimit erreicht oder eine Anfrage läuft. Später erneut versuchen.',auth:'Zum Fortfahren erneut anmelden.',conflict:'Diskussion geändert. Übersetzung erneut im Verlauf öffnen.',count:'Zeichen',close:'Diskussion schließen'},
 ru:{draftLimit:'Для обсуждения каждый текущий текст должен быть не длиннее 8 000 символов. Сократите черновик.',useBoth:'Применить текст и перевод',source:'Предлагаемый исходный текст',clarify:'Уточнить перевод',prompt:'Добавьте контекст или задайте вопрос',send:'Отправить',sending:'Отправляем…',you:'Вы',assistant:'Ответ',revision:'Предлагаемый перевод',use:'Использовать перевод',applied:'Используется в текущем результате; оригинал сохранён в истории.',limit:'Достигнут лимит обсуждения (6 вопросов).',error:'Не удалось отправить. Черновик сохранён; повторите или откройте историю.',quota:'Достигнут лимит переводов или уже выполняется запрос. Повторите позже.',auth:'Войдите снова, чтобы продолжить.',conflict:'Обсуждение изменилось. Откройте перевод заново из истории.',count:'символов',close:'Закрыть обсуждение'},
 es:{draftLimit:'La conversación admite hasta 8.000 caracteres en cada texto actual. Acorta el borrador.',useBoth:'Usar texto y traducción',source:'Texto original propuesto',clarify:'Aclarar traducción',prompt:'Añade contexto o haz una pregunta',send:'Enviar',sending:'Enviando…',you:'Tú',assistant:'Respuesta',revision:'Traducción propuesta',use:'Usar traducción',applied:'Usada en el resultado actual; el original sigue en el historial.',limit:'Límite de conversación alcanzado (6 preguntas).',error:'No se pudo enviar. Tu borrador se conserva; reintenta o abre el historial.',quota:'Límite de traducciones alcanzado u otra solicitud activa. Inténtalo más tarde.',auth:'Vuelve a iniciar sesión para continuar.',conflict:'La conversación cambió. Reabre la traducción desde el historial.',count:'caracteres',close:'Cerrar conversación'},
 fr:{draftLimit:'La discussion accepte 8 000 caractères par texte actuel. Raccourcissez le brouillon.',useBoth:'Utiliser les deux',source:'Texte source proposé',clarify:'Préciser la traduction',prompt:'Ajoutez du contexte ou posez une question',send:'Envoyer',sending:'Envoi…',you:'Vous',assistant:'Réponse',revision:'Traduction proposée',use:'Utiliser la traduction',applied:'Utilisée dans le résultat actuel ; original conservé dans l’historique.',limit:'Limite de discussion atteinte (6 questions).',error:'Envoi impossible. Brouillon conservé ; réessayez ou ouvrez l’historique.',quota:'Limite de traductions atteinte ou demande déjà en cours. Réessayez plus tard.',auth:'Reconnectez-vous pour continuer.',conflict:'La discussion a changé. Rouvrez la traduction depuis l’historique.',count:'caractères',close:'Fermer la discussion'}
};
export function createFollowupState({api,changed,saved,locale,currentDraft=()=>null,requestID=()=>crypto.randomUUID(),unauthorized=()=>{}}) {
 let session=null,ready=false,owner=null,selected=null,epoch=0;
 const entries=new Map();
 const current=()=>entries.get(selected)||null;
 function identity(value,available) {
  const next=value?.user?.id||null;
  if(owner!==next){epoch++;for(const entry of entries.values())entry.controller?.abort();entries.clear();selected=null;owner=next;}
  session=value;ready=!!available;changed();
 }
 function select(record) {
  selected=owner&&record?.id?record.id:null;
  if(selected){let entry=entries.get(selected);if(!entry){entry={record,draft:'',open:false,pending:null,error:null,request:null,applied:null};entries.set(selected,entry);}else {if((record.followups?.length||0)>=(entry.record.followups?.length||0))entry.record=record;entry.applied=null;}}
  changed();
 }
 function send() {
  const entry=current();if(!entry||!ready)return Promise.resolve();if(entry.pending)return entry.pending;
  if(!entry.draft.trim()||[...entry.draft].length>2000||(entry.record.followups?.length||0)>=6)return Promise.resolve();
  const question=entry.draft,run=epoch,id=selected;
  const draft=currentDraft()||{};if(Object.values(draft).some(value=>typeof value!=='string'||[...value].length>8000)){entry.error='draft-limit';changed();return Promise.resolve();}const fingerprint=JSON.stringify([question,draft]);
  if(!entry.request||entry.request.fingerprint!==fingerprint)entry.request={id:requestID(),question,fingerprint};
  const body={history_id:id,request_id:entry.request.id,question,locale:locale(),expected_turns:entry.record.followups?.length||0,...draft};
  entry.controller=new AbortController();entry.error=null;
  const task=api.request('/v1/translation-followups',{method:'POST',csrf:session.csrf_token,body,signal:entry.controller.signal}).then(record=>{
   if(run!==epoch)return;
   if(record?.id!==id||record.text!==entry.record.text||record.translation!==entry.record.translation||!Array.isArray(record.followups)||record.followups.length<body.expected_turns||record.followups.length>6||!record.followups.some(turn=>turn?.request_id===body.request_id&&turn.question===question)||record.followups.some(turn=>typeof turn.question!=='string'||typeof turn.answer!=='string'||!turn.answer.trim()||!(turn.revised_text===null||typeof turn.revised_text==='string')||!(turn.revised_source_text==null||typeof turn.revised_source_text==='string')||turn.revised_source_text!=null&&(!turn.revised_source_text.trim()||[...turn.revised_source_text].length>8000||!turn.revised_text)))throw new Error('Invalid discussion');
   entry.record=record;entry.draft='';entry.request=null;entry.applied=null;saved(record);
  }).catch(error=>{if(run!==epoch)return;entry.error=error.status||0;if(error.status===401)unauthorized(error);}).finally(()=>{if(run!==epoch)return;entry.pending=null;entry.controller=null;changed();});
  entry.pending=task;changed();return task;
 }
 return {identity,select,current,available:()=>ready,send,draft(value){const entry=current();if(!entry||entry.pending)return;entry.draft=value;entry.error=null;changed();},toggle(){const entry=current();if(entry){entry.open=!entry.open;changed();}},applied(index){const entry=current();if(entry){entry.applied=index;changed();}}};
}

export function mountTranslatorFollowup({host,api,locale,saved,apply,currentDraft,unauthorized,document=globalThis.document}) {
 const node=(tag,cls)=>{const el=document.createElement(tag);if(cls)el.className=cls;return el;};
 const toggle=node('button','quiet-button followup-toggle');toggle.type='button';toggle.id='clarify-translation';toggle.setAttribute('aria-controls','translation-discussion');
 const panel=node('section','followup-panel');panel.id='translation-discussion';
 const thread=node('ol','followup-thread');thread.id='followup-thread';
 const label=node('label');label.htmlFor='followup-question';
 const input=node('textarea');input.id='followup-question';input.rows=3;input.setAttribute('aria-describedby','followup-count followup-status');
 const footer=node('div','followup-footer');const count=node('small');count.id='followup-count';const send=node('button','small-button');send.id='send-followup';send.type='button';footer.append(count,send);
 const status=node('p','followup-status');status.id='followup-status';status.setAttribute('role','status');
 panel.append(thread,label,input,footer,status);host.append(toggle,panel);
 // Native content sizing where available; older Safari needs border-box measurement.
 const view=document.defaultView;
 const nativeSizing=view?.CSS?.supports('field-sizing','content');
 function resizeInput() {
  if(nativeSizing||host.hidden||panel.hidden||!input.getClientRects().length)return;
  input.style.height='auto';
  const style=view.getComputedStyle(input);
  const borders=parseFloat(style.borderTopWidth)+parseFloat(style.borderBottomWidth);
  input.style.height=`${Math.ceil(input.scrollHeight+borders)}px`;
 }
 let resizeFrame=0;
 function scheduleResize() {
  if(resizeFrame)return;
  resizeFrame=view.requestAnimationFrame(()=>{resizeFrame=0;resizeInput();});
 }
 if(!nativeSizing&&view){
  let width=-1;
  // Observe only container width: changing textarea height cannot retrigger a loop.
  const observer=new view.ResizeObserver(entries=>{
   const next=entries[0].contentRect.width;if(next===width)return;width=next;scheduleResize();
  });
  observer.observe(panel);
  view.addEventListener('resize',scheduleResize);
  document.fonts?.ready.then(scheduleResize);
 }
 let signature='';
 const state=createFollowupState({api,locale,saved,currentDraft,unauthorized,changed:render});
 function render() {
  const entry=state.current(),l=followupLabels[locale()]||followupLabels.en;
  host.hidden=!entry;toggle.textContent=entry?.open?l.close:l.clarify;toggle.setAttribute('aria-expanded',String(!!entry?.open));panel.hidden=!entry?.open;
  if(!entry){thread.replaceChildren();input.value='';signature='';return;}
  label.textContent=l.prompt;input.placeholder=l.prompt;send.textContent=entry.pending?l.sending:l.send;
  if(input.value!==entry.draft)input.value=entry.draft;
  resizeInput();
  const length=[...entry.draft].length,turns=entry.record.followups||[];
  count.textContent=`${length} / 2,000 ${l.count}`;
  input.disabled=!!entry.pending||!state.available()||turns.length>=6;
  send.disabled=input.disabled||!entry.draft.trim()||length>2000;
  panel.setAttribute('aria-busy',String(!!entry.pending));
  const error=entry.error;status.textContent=error!==null?(error==='draft-limit'?l.draftLimit:error===429?l.quota:error===401?l.auth:error===409?l.conflict:l.error):entry.applied!==null?l.applied:turns.length>=6?l.limit:'';
  status.classList.toggle('error-state',error!==null);
  const next=JSON.stringify([entry.record.id,turns,locale(),!!entry.pending,state.available(),entry.applied,currentDraft?.()?.current_source]);
  if(next===signature)return;signature=next;thread.replaceChildren();
  turns.forEach((turn,index)=>{
   const li=node('li'),who=node('strong'),question=node('p'),answerLabel=node('strong'),answer=node('p');who.textContent=l.you;question.textContent=turn.question;answerLabel.textContent=l.assistant;answer.textContent=turn.answer;li.append(who,question,answerLabel,answer);
   if(turn.revised_text){const title=node('small'),revision=node('div','followup-revision'),use=node('button','quiet-button');title.textContent=l.revision;revision.textContent=turn.revised_text;revision.lang=entry.record.target_language;const source=turn.revised_source_text??turn.current_source??entry.record.text;const changesSource=typeof source==='string'&&source!==(currentDraft?.()?.current_source??entry.record.text);if(changesSource){const sourceTitle=node('small'),sourceText=node('div','followup-revision followup-source');sourceTitle.textContent=l.source;sourceText.textContent=source;sourceText.lang=entry.record.source_language;li.append(sourceTitle,sourceText);}use.textContent=changesSource?l.useBoth:l.use;use.type='button';use.dataset.revision=String(index);use.disabled=!!entry.pending||!state.available()||entry.applied===index;use.onclick=()=>{if(state.current()!==entry||!state.available())return;apply(entry.record,turn.revised_text,source);state.applied(index);};li.append(title,revision,use);}
   thread.append(li);
  });
 }
 toggle.onclick=()=>{state.toggle();if(state.current()?.open)input.focus();};
 input.addEventListener('input',()=>state.draft(input.value));
 // The discussion is inside the translation form: Enter must not translate.
 input.addEventListener('keydown',event=>{if((event.metaKey||event.ctrlKey)&&event.key==='Enter'){event.preventDefault();event.stopPropagation();void state.send();}});
 send.onclick=()=>void state.send();
 return {...state,localize:render};
}
