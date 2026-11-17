export const coachVisibleTurns=turns=>turns.filter(t=>!t.is_offer&&t.kind!=='nudge');
// Presentation only: never mutate snapshots, evidence, receipts or assistance.
export function coachRecentTurns(turns,now=Date.now()){
 return coachVisibleTurns(turns).filter(t=>{
  const dates=[t.at,t.attempt?.at,t.attempt?.reviewed_at].map(v=>typeof v==='string'?Date.parse(v):NaN).filter(Number.isFinite);
  return !dates.length||Math.max(...dates)>=now-86400000;
 });
}
export function coachHistoryWindow(turns,now,earlierLimit=0){
 turns=coachVisibleTurns(turns);
 const recent=new Set(coachRecentTurns(turns,now));
 const older=turns.filter(t=>!recent.has(t));
 const earlier=new Set(earlierLimit>0?older.slice(Math.max(0,older.length-earlierLimit),Math.max(0,older.length-earlierLimit+50)):[]);
 return turns.filter(t=>recent.has(t)||earlier.has(t));
}
export function coachExerciseStatus(turn){
 if(turn.state==='pending'||turn.attempt?.assessment_state==='pending')return 'working';
 if(turn.attempt?.outcome==='skipped')return 'unanswered';
 const a=turn.attempt;
 if(a&&!a.excluded&&(!a.assessment_state||a.assessment_state==='completed')){
  const result=a.reviewed_at?a.outcome:a.assessment?.verdict||a.outcome;
  if(result==='correct')return 'success';
  if(['wrong','incorrect','partially_correct'].includes(result))return 'incorrect';
 }
 return a?'completed':'awaiting';
}
export const coachPresentationLabel=(key,locale)=>({earlier:{en:'Earlier',de:'Früher',ru:'Ранее',es:'Anteriores',fr:'Plus tôt'},latest:{en:'Latest',de:'Zum neuesten',ru:'К последнему',es:'Lo más reciente',fr:'Derniers messages'},awaiting:{en:'Awaiting answer',de:'Antwort ausstehend',ru:'Ожидает ответа',es:'Esperando respuesta',fr:'En attente de réponse'},unanswered:{en:'Unanswered',de:'Unbeantwortet',ru:'Без ответа',es:'Sin responder',fr:'Sans réponse'},working:{en:'Checking…',de:'Wird geprüft…',ru:'Проверка…',es:'Comprobando…',fr:'Vérification…'}}[key]?.[locale]||key);
