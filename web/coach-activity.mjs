// Read-only retained activity, not mastery or complete all-app totals.
const labels={en:['Weekly activity','Known completions','Partial history','Not supported','Unavailable','Undated','Close','Translator','Coach','Dictation','Podcasts'],de:['Wochenaktivität','Bekannte Abschlüsse','Unvollständiger Verlauf','Nicht unterstützt','Nicht verfügbar','Ohne Datum','Schließen','Übersetzer','Coach','Diktat','Podcasts'],ru:['Активность за неделю','Известные завершения','Неполная история','Не поддерживается','Недоступно','Без даты','Закрыть','Переводчик','Тренер','Диктант','Подкасты'],es:['Actividad semanal','Finalizaciones conocidas','Historial parcial','No compatible','No disponible','Sin fecha','Cerrar','Traductor','Entrenador','Dictado','Podcasts'],fr:['Activité hebdomadaire','Activités terminées connues','Historique partiel','Non pris en charge','Indisponible','Sans date','Fermer','Traducteur','Coach','Dictée','Podcasts']};
const text=locale=>labels[locale.split('-')[0]]||labels.en;
export const localDate=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
export function activityWeek(now,locale){const l=new Intl.Locale(locale);const first=(l.getWeekInfo?.()||l.weekInfo)?.firstDay??(locale.startsWith('en')?7:1);const start=new Date(now.getFullYear(),now.getMonth(),now.getDate(),12);start.setDate(start.getDate()-(start.getDay()-first+7)%7);return Array.from({length:7},(_,i)=>{const d=new Date(start);d.setDate(d.getDate()+i);return localDate(d);});}
export function activityDetails(day,snapshot,locale){const l=text(locale);return [day.date,`${l[1]}: ${day.known_count??'—'}`,l[2],...['translator','coach','dictation','podcasts'].map((source,i)=>`${l[i+7]}: ${snapshot.sources?.[source]==='retained'?(day.counts?.[source]??'—'):l[snapshot.sources?.[source]==='unsupported'?3:4]}`),`${l[5]}: ${snapshot.undated??'—'}`].join('\n');}
export function createActivityState(api,changed){
 let epoch=0,key='',scope='';
 const state={value:null,error:false,
  invalidate(){key='';},
  clear(){epoch++;key='';scope='';state.value=null;state.error=false;changed();},
  async load(owner,start,zone,revision=''){
   const nextScope=JSON.stringify([owner,start,zone]),next=JSON.stringify([owner,start,zone,revision]);
   if(key===next)return;
   const version=++epoch;key=next;state.error=false;
   if(scope!==nextScope){scope=nextScope;state.value=null;changed();}
   try{
    const value=await api.request('/v1/learning/activity?'+new URLSearchParams({start,time_zone:zone}),{activityOwner:owner});
    if(epoch===version){state.value=value;changed();}
   }catch{if(epoch===version){state.error=true;state.value=null;changed();}}
  }
 };return state;
}
export function mountCoachActivity({host,api,locale,document:doc}){
 const bar=doc.createElement('div');bar.className='coach-activity';const detail=doc.createElement('div');detail.className='coach-activity-detail';detail.hidden=true;detail.setAttribute('role','dialog');const body=doc.createElement('p'),close=doc.createElement('button');close.type='button';detail.append(body,close);host.append(bar,detail);
 let owner=null,selected=null;const state=createActivityState(api,render);
 function dismiss(restore=false){const date=selected;detail.hidden=true;selected=null;if(restore)[...bar.children].find(b=>b.dataset.activityDate===date)?.focus({preventScroll:true});}
 close.onclick=()=>dismiss(true);detail.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();dismiss(true);}});
 doc.addEventListener('pointerdown',e=>{if(!detail.hidden&&!detail.contains(e.target)&&!bar.contains(e.target))dismiss();});
 function render(){const focusedDate=doc.activeElement?.dataset?.activityDate;const l=text(locale()),dates=activityWeek(new Date(),locale());bar.setAttribute('aria-label',l[0]);bar.replaceChildren();close.textContent=l[6];detail.setAttribute('aria-label',l[0]);
  for(const date of dates){const day=state.value?.days?.find(d=>d.date===date),b=doc.createElement('button');b.type='button';b.dataset.activityDate=date;b.className='coach-activity-day';b.textContent=new Intl.DateTimeFormat(locale(),{weekday:'narrow'}).format(new Date(date+'T12:00:00'));b.dataset.intensity=day?String(Math.min(4,Math.max(0,day.known_count))):'unknown';if(date===localDate(new Date()))b.setAttribute('aria-current','date');b.setAttribute('aria-label',`${date}: ${day?l[1]+': '+day.known_count+' · '+l[2]:l[4]}`);b.disabled=!owner;b.onclick=()=>{selected=date;body.textContent=day?activityDetails(day,state.value,locale()):`${date}\n${l[4]}`;detail.hidden=false;close.focus({preventScroll:true});};bar.append(b);}
  if(focusedDate)[...bar.children].find(b=>b.dataset.activityDate===focusedDate)?.focus({preventScroll:true});
  if(selected){const day=state.value?.days?.find(d=>d.date===selected);body.textContent=day?activityDetails(day,state.value,locale()):l[4];}
 }
 render();return {refresh(){state.invalidate();},sync(id,revision=''){if(owner!==id){owner=id;dismiss();state.clear();}render();if(id)void state.load(id,activityWeek(new Date(),locale())[0],Intl.DateTimeFormat().resolvedOptions().timeZone,revision);},clear(){owner=null;dismiss();state.clear();}};
}
