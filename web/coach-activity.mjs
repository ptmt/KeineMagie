// Read-only retained activity, not mastery or complete all-app totals.
const labels={en:['Weekly activity','Known completions','Partial history','Not supported','Unavailable','Undated','Close','Translator','Coach','Dictation','Podcasts'],de:['Wochenaktivität','Bekannte Abschlüsse','Unvollständiger Verlauf','Nicht unterstützt','Nicht verfügbar','Ohne Datum','Schließen','Übersetzer','Coach','Diktat','Podcasts'],ru:['Активность за неделю','Известные завершения','Неполная история','Не поддерживается','Недоступно','Без даты','Закрыть','Переводчик','Тренер','Диктант','Подкасты'],es:['Actividad semanal','Finalizaciones conocidas','Historial parcial','No compatible','No disponible','Sin fecha','Cerrar','Traductor','Entrenador','Dictado','Podcasts'],fr:['Activité hebdomadaire','Activités terminées connues','Historique partiel','Non pris en charge','Indisponible','Sans date','Fermer','Traducteur','Coach','Dictée','Podcasts']};
const semantics={"en":"One successful translation or one checked exercise, regardless of correctness. Podcast-source exercises count under Podcasts, not Coach. Mark transcript studied adds one completion per retained episode. Opening, starring and preparation do not count; listening is not tracked. Rechecks count once. Deleted or undated history remains incomplete. Not a mastery score.","de":"Eine erfolgreiche Übersetzung oder eine geprüfte Übung, unabhängig vom Ergebnis. Übungen aus Podcasts zählen unter Podcasts, nicht Coach. Ein als gelernt markiertes Transkript zählt einmal pro gespeicherter Folge. Öffnen, Markieren und Vorbereitung zählen nicht; Hören wird nicht erfasst. Erneute Prüfungen zählen einmal. Gelöschter oder undatierter Verlauf bleibt unvollständig. Keine Kompetenzbewertung.","ru":"Один успешный перевод или одно проверенное упражнение независимо от правильности. Упражнения по подкастам учитываются в Подкастах, а не в Тренере. Отметка изученной расшифровки добавляет одно завершение на сохранённый выпуск. Открытие, звёздочки и подготовка не считаются; прослушивание не отслеживается. Повторные проверки не увеличивают счётчик. Удалённая история и записи без даты остаются неполными. Это не оценка владения языком.","es":"Una traducción correcta o un ejercicio revisado, independientemente del resultado. Los ejercicios basados en podcasts cuentan en Podcasts, no en Entrenador. Marcar una transcripción estudiada añade una finalización por episodio conservado. Abrir, marcar favoritos y preparar no cuenta; la escucha no se registra. Las revisiones repetidas cuentan una vez. El historial eliminado o sin fecha sigue incompleto. No mide el dominio.","fr":"Une traduction réussie ou un exercice vérifié, quel que soit le résultat. Les exercices issus de podcasts comptent dans Podcasts, pas dans Coach. Marquer une transcription étudiée ajoute une activité par épisode conservé. Ouvrir, ajouter aux favoris et préparer ne compte pas ; l’écoute n’est pas suivie. Les vérifications répétées comptent une fois. L’historique supprimé ou sans date reste incomplet. Ce n’est pas un niveau de maîtrise."};
const text=locale=>labels[locale.split('-')[0]]||labels.en;
export const localDate=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
export function activityWeek(now,locale){const l=new Intl.Locale(locale);const first=(l.getWeekInfo?.()||l.weekInfo)?.firstDay??(locale.startsWith('en')?7:1);const start=new Date(now.getFullYear(),now.getMonth(),now.getDate(),12);start.setDate(start.getDate()-(start.getDay()-first+7)%7);return Array.from({length:7},(_,i)=>{const d=new Date(start);d.setDate(d.getDate()+i);return localDate(d);});}
export function activityDetails(day,snapshot,locale){const l=text(locale),sources=day.sources||snapshot.sources;return [day.date,`${l[1]}: ${day.known_count??'—'}`,l[2],...['translator','coach','dictation','podcasts'].map((source,i)=>`${l[i+7]}: ${sources?.[source]==='retained'?(day.counts?.[source]??'—'):(day.counts?.[source]>0?day.counts[source]+' · ':'')+l[sources?.[source]==='unsupported'?3:4]}`),`${l[5]}: ${snapshot.undated??'—'}`,semantics[locale.split('-')[0]]||semantics.en].join('\n');}
export function createActivityState(api,changed){
 let epoch=0,key='',scope='',controller;
 const state={value:null,error:false,pending:false,
  invalidate(){key='';},
  clear(){controller?.abort();epoch++;key='';scope='';state.value=null;state.error=false;state.pending=false;changed();},
  async load(owner,start,zone,revision='',days){
   const nextScope=JSON.stringify([owner,start,zone,days]),next=JSON.stringify([owner,start,zone,days,revision]);
   if(key===next)return;
   controller?.abort();controller=new AbortController();
   const version=++epoch;key=next;state.error=false;state.pending=true;
   if(scope!==nextScope){scope=nextScope;state.value=null;}
   changed();
   try{
    const query=new URLSearchParams({start,time_zone:zone});if(days)query.set('days',days);
    let value=await api.request('/v1/learning/activity?'+query,{activityOwner:owner,signal:controller.signal});
    if(epoch!==version)return;
    const validate=v=>{if(!Array.isArray(v?.days)||(v.time_zone&&v.time_zone!==zone))throw Error('Invalid activity response');return v;};
    validate(value);
    // Older servers ignore days. Read bounded non-overlapping weeks; never fill gaps.
    if(days>7&&value?.days?.length===7){
     const signal=controller.signal,parts=[value];
     for(let i=7;i<days;i+=7){
      if(signal.aborted)return;
      const date=new Date(start+'T12:00:00');date.setDate(date.getDate()+i);
      try{parts.push(validate(await api.request('/v1/learning/activity?'+new URLSearchParams({start:localDate(date),time_zone:zone}),{activityOwner:owner,signal})));}
      catch(error){if(signal.aborted)return;if(error.status===401||error.status===403)throw error;parts.push({days:[],requestFailed:true});}
     }
     value={...value,days:parts.flatMap(p=>(p.days||[]).map(d=>({...d,sources:p.sources}))).filter(d=>d.date>=start&&d.date<=localDate(new Date(new Date(start+'T12:00:00').setDate(days)))),undated:Math.max(...parts.map(p=>p.undated||0)),requestFailed:parts.some(p=>p.requestFailed)};
    }
    if(epoch===version){state.pending=false;state.value=value;changed();}
   }catch(error){if(epoch===version){state.pending=false;state.error=true;key='';if(error.status===401||error.status===403)state.value=null;changed();}}
  }
 };return state;
}
export function activityMonth(now,locale){
 const start=new Date(now.getFullYear(),now.getMonth(),1,12),end=new Date(now.getFullYear(),now.getMonth()+1,0,12);
 const week=activityWeek(start,locale);const offset=week.indexOf(localDate(start));
 return {dates:Array.from({length:end.getDate()},(_,i)=>localDate(new Date(now.getFullYear(),now.getMonth(),i+1,12))),offset,week};
}
export function activityIntensity(day){const n=day?.known_count;return !Number.isInteger(n)||n<0?'unknown':n===0?'none':n<3?'1':n<5?'2':n<10?'3':'4';}
const monthLabels={en:['Activity','Previous month','Next month','This month','Refresh','Recorded · lower bound','Active days · at least','No recorded activity ≠ zero','Refresh failed · saved view','Loading','Limited coverage'],ru:['Активность','Предыдущий месяц','Следующий месяц','Этот месяц','Обновить','Учтено · не менее','Активных дней · не менее','Нет записей ≠ нет активности','Обновление не удалось · сохранённые данные','Загрузка','Неполное покрытие'],de:['Aktivität','Voriger Monat','Nächster Monat','Dieser Monat','Aktualisieren','Erfasst · mindestens','Aktive Tage · mindestens','Keine Einträge ≠ keine Aktivität','Aktualisierung fehlgeschlagen · gespeicherte Ansicht','Laden','Unvollständige Abdeckung'],es:['Actividad','Mes anterior','Mes siguiente','Este mes','Actualizar','Registradas · al menos','Días activos · al menos','Sin registros ≠ sin actividad','Error al actualizar · vista guardada','Cargando','Cobertura limitada'],fr:['Activité','Mois précédent','Mois suivant','Ce mois','Actualiser','Enregistrées · au moins','Jours actifs · au moins','Aucune entrée ≠ aucune activité','Échec de mise à jour · vue conservée','Chargement','Couverture limitée']};
export function mountCoachActivity({host,api,locale,document:doc,now=()=>new Date()}){
 const bar=doc.createElement('div');bar.className='coach-activity';const detail=doc.createElement('div');detail.className='coach-activity-detail';detail.hidden=true;detail.setAttribute('role','dialog');const body=doc.createElement('p'),close=doc.createElement('button');close.type='button';detail.append(body,close);host.append(bar,detail);
 const header=doc.createElement('div'),summary=doc.createElement('div'),legend=doc.createElement('div');header.className='activity-month-header';summary.className='activity-month-summary';legend.className='activity-legend';host.insertBefore(header,bar);host.append(summary,legend);
 let owner=null,selected=null,month=now(),follow=true,revision='',dayKey=calendarKey();const state=createActivityState(api,render);
 function calendarKey(){return localDate(now())+'|'+Intl.DateTimeFormat().resolvedOptions().timeZone;}
 const copy=()=>monthLabels[locale().split('-')[0]]||monthLabels.en;
 function load(){if(owner){const m=activityMonth(month,locale());void state.load(owner,m.dates[0],Intl.DateTimeFormat().resolvedOptions().timeZone,revision,m.dates.length);}}
 function move(delta){dismiss();month=new Date(month.getFullYear(),month.getMonth()+delta,1,12);follow=false;render();load();}
 function dismiss(restore=false){const date=selected;detail.hidden=true;selected=null;if(restore)[...bar.children].find(b=>b.dataset.activityDate===date)?.focus({preventScroll:true});}
 close.onclick=()=>dismiss(true);detail.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();dismiss(true);}});
 doc.addEventListener('pointerdown',e=>{if(!detail.hidden&&!detail.contains(e.target)&&!bar.contains(e.target))dismiss();});
 function observed(date){const day=state.value?.days?.find(d=>d.date===date),sources=day?.sources||state.value?.sources;return day&&(day.known_count>0||Object.values(sources||{}).includes('retained'))?day:undefined;}
 function render(){const focusedDate=doc.activeElement?.dataset?.activityDate,focusedControl=[...header.children].includes(doc.activeElement)?doc.activeElement.getAttribute('aria-label'):null;const l=text(locale()),c=copy(),m=activityMonth(month,locale()),dates=m.dates;bar.setAttribute('aria-label',c[0]);bar.replaceChildren();close.textContent=l[6];detail.setAttribute('aria-label',c[0]);header.replaceChildren();
 const title=doc.createElement('strong');title.textContent=new Intl.DateTimeFormat(locale(),{month:'long',year:'numeric'}).format(month);header.append(title);
 for(const [label,glyph,action] of [[c[1],'‹',()=>move(-1)],[c[2],'›',()=>move(1)],[c[3],c[3],()=>{month=now();follow=true;dismiss();render();load();}],[c[4],'↻',()=>{state.invalidate();load();}]]){const b=doc.createElement('button');b.type='button';b.textContent=glyph;b.setAttribute('aria-label',label);if(label===c[4]){b.disabled=state.pending;b.setAttribute('aria-busy',String(state.pending));}b.onclick=action;header.append(b);}
 for(const date of m.week){const h=doc.createElement('span');h.className='activity-weekday';h.textContent=new Intl.DateTimeFormat(locale(),{weekday:'short'}).format(new Date(date+'T12:00:00'));bar.append(h);}
 for(let i=0;i<m.offset;i++){const spacer=doc.createElement('span');spacer.setAttribute('aria-hidden','true');bar.append(spacer);}
 const known=dates.map(observed).filter(d=>activityIntensity(d)!=='unknown');
 summary.textContent=state.error?(state.value?c[8]:l[4]):!state.value?c[9]:!known.length?l[4]:`${c[5]}: ${known.reduce((n,d)=>n+d.known_count,0)} · ${c[6]}: ${known.filter(d=>d.known_count>0).length}`;
 legend.textContent=`1–2 · 3–4 · 5–9 · 10+ | ${c[7]} · ${l[2]}${state.value&&known.length!==dates.length?' · '+c[10]:''}`;
 for(const date of dates){const day=observed(date),b=doc.createElement('button');b.type='button';b.dataset.activityDate=date;b.className='coach-activity-day';b.textContent=String(Number(date.slice(-2)));b.dataset.intensity=activityIntensity(day);if(date===localDate(now()))b.setAttribute('aria-current','date');b.setAttribute('aria-label',`${date}: ${day?l[1]+': '+day.known_count+' · '+l[2]:l[4]}`);b.disabled=!owner;b.onclick=()=>{selected=date;body.textContent=day?activityDetails(day,state.value,locale()):`${date}\n${l[4]}`;detail.hidden=false;close.focus({preventScroll:true});};bar.append(b);}
  if(focusedDate)[...bar.children].find(b=>b.dataset.activityDate===focusedDate)?.focus({preventScroll:true});
  if(focusedControl)[...header.children].find(b=>b.getAttribute('aria-label')===focusedControl)?.focus({preventScroll:true});
  if(selected){const day=observed(selected);body.textContent=day?activityDetails(day,state.value,locale()):l[4];}
 }
 function tick(){const next=calendarKey();if(next!==dayKey){dayKey=next;if(follow)month=now();state.invalidate();render();load();}}
 const timer=doc.defaultView?.setInterval(tick,30000);doc.addEventListener('visibilitychange',()=>{if(!doc.hidden)tick();});
 render();return {refresh(){state.invalidate();load();},sync(id,nextRevision=''){revision=nextRevision;if(owner!==id){owner=id;month=now();follow=true;dismiss();state.clear();}tick();render();load();},clear(){owner=null;dismiss();state.clear();},destroy(){doc.defaultView?.clearInterval(timer);owner=null;state.clear();}};
}
