// Literal text only: provider notes never enter innerHTML or a Markdown parser.
export function assessmentGroups(a){const spans=a?.alignment?.spans||[];return {compared:spans.filter(s=>s.kind!=='unattempted'),unattempted:spans.filter(s=>s.kind==='unattempted'),changes:spans.filter(s=>!['equal','unattempted'].includes(s.kind))};}
export function renderAssessment(a,{l,refresh,cancel}){
 const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;};
 const root=el('section');root.className='dictation-assessment';root.setAttribute('aria-label',l('assessment.title'));
 const groups=assessmentGroups(a),alignment=a.alignment;
 root.append(el('h2',l('assessment.title')));
 const metrics=el('p',l('assessment.coverage',{exact:alignment.exact_words,attempted:alignment.attempted_words,total:alignment.source_words}));metrics.className='dictation-assessment-metrics';root.append(metrics);
 root.append(el('p',l(alignment.complete?'assessment.complete':alignment.unattempted_words>0?'assessment.partial':'assessment.covered')));
 const comparison=el('div');comparison.className='dictation-alignment';
 for(const [field,label]of [['original','Original'],['written','What you heard']]){
  const column=el('div'),paragraph=el('p');column.append(el('h3',l(label)));paragraph.className='dictation-inline-diff';
  for(const s of groups.compared){if(!s[field])continue;const span=el('span',s[field]);span.className='dictation-diff-'+s.kind;span.dataset.spanId=s.id;if(s.kind!=='equal'){span.title=l('assessment.'+s.kind);span.setAttribute('aria-label',l('assessment.'+s.kind)+': '+s[field]);}paragraph.append(span);}
  column.append(paragraph);comparison.append(column);
 }
 root.append(comparison);
 if(groups.changes.length){const legend=el('p');legend.className='dictation-diff-legend';for(const kind of [...new Set(groups.changes.map(s=>s.kind))]){const chip=el('span',l('assessment.'+kind));chip.className='dictation-diff-'+kind;legend.append(chip);}root.append(legend);}
 if(groups.unattempted.length){const detail=el('details');detail.className='dictation-unattempted';detail.append(el('summary',l('assessment.unattempted',{n:alignment.unattempted_words})));const text=el('p',groups.unattempted.map(s=>s.original).join(''));detail.append(text);root.append(detail);}
 const state=el('p',l('assessment.state.'+a.state));state.setAttribute('role','status');root.append(state);
 if(a.state==='failed'){root.append(el('p',l(a.error==='llm_quota'?'assessment.llmQuota':'assessment.failure')));}
 if(a.state==='pending'||a.state==='failed'){
  const b=el('button',l('assessment.recover'));b.type='button';b.onclick=refresh;root.append(b);
  if(a.state==='pending'){const stop=el('button',l('Cancel'));stop.type='button';stop.onclick=cancel;root.append(stop);}
 }
 for(const note of a.result?.notes||[]){const s=alignment.spans.find(s=>s.id===note.span_id);if(!s||s.kind==='unattempted'||s.original!==note.source_quote||s.written!==note.answer_quote)continue;const row=el('div');row.className='dictation-assessment-note';row.append(el('strong',l('assessment.'+note.category)),el('p',`${note.source_quote||'—'} → ${note.answer_quote||'—'}`),el('p',note.explanation));root.append(row);}
 const context=el('details');context.className='dictation-assessment-context';context.append(el('summary',l('assessment.context')),el('p',l(a.assisted?'assessment.assisted':'assessment.unassisted')));
 const assistance=a.assistance_summary;
 if(assistance?.tracking==='partial'){
  context.append(el('p',l('assessment.acceptedOnly')));
  for(const s of (assistance.segments||[])){const row=el('p',l('assessment.replayCounts',{n:s.step+1,planned:s.planned_repetitions,extra:s.extra_requested,started:s.started,ended:s.completed}));context.append(row);}
  if(assistance.archived_unknown||assistance.unknown_admissions)context.append(el('p',l('assessment.replaysUnknown')));
 }else context.append(el('p',l('assessment.replaysUnknown')));
 context.append(el('p',l('assessment.budget')));root.append(context);
 return root;
}
