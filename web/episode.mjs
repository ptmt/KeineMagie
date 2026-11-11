export async function episodePath(job) {
  const bytes = new TextEncoder().encode(job.id);
  const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(n => n.toString(16).padStart(2,'0')).join('').slice(0,12);
  const slug = (job.title || 'episode').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,80).replace(/-$/,'') || 'episode';
  return `/podcasts/episodes/${slug}-${hash}`;
}
export function episodeLocation(pathname, hash) {
  if (hash) return null;
  return /^\/podcasts\/episodes\/([a-z0-9]+(?:-[a-z0-9]+)*-[a-f0-9]{12})$/.exec(pathname)?.[1] || null;
}
export function transcriptStats(job) {
  const segments=job.segments || [], translated=segments.filter(s => typeof s.translation==='string' && s.translation.trim()).length;
  return {recognized:segments.length,translated,pending:segments.length-translated};
}
// A click authorizes only the displayed remaining plan, never background work.
export function createAnalysisRunner({request,active,update}) {
  let controller=null;
  return {
    cancel(){controller?.abort();},
    async start(view){
      if(controller)return;
      const budget=view?.estimate?.remaining_requests;
      if(!Number.isInteger(budget)||budget<1||budget>10000)throw new Error('Invalid analysis estimate');
      const current=new AbortController();controller=current;
      try {
        for(let i=0;i<budget&&!current.signal.aborted&&active();i++){
          const next=await request({signal:current.signal});
          if(current.signal.aborted)throw new DOMException('Canceled','AbortError');
          if(!active())break;
          update(next);
          if(next.state==='completed')break;
          if(next.state!=='pending')throw new Error('Invalid analysis state');
        }
      } finally {if(controller===current)controller=null;}
    }
  };
}
export function createEpisodeClient({api, unauthorized=()=>{}}) {
  let session=null,epoch=0;const flights=new Map(),controllers=new Set();
  function identity(value) {
    if(session?.user?.id!==value?.user?.id){epoch++;controllers.forEach(c=>c.abort());controllers.clear();flights.clear();}
    session=value;
  }
  function request(key,path,options={}) {
    if(!session?.user?.id)return Promise.reject(new Error('Sign in required'));
    key=path+':'+key;
    if(flights.has(key))return flights.get(key);
    const run=epoch,controller=new AbortController();controllers.add(controller);
    const abort=()=>controller.abort();
    if(options.signal?.aborted)abort();else options.signal?.addEventListener('abort',abort,{once:true});
    const task=Promise.resolve(api.request(path,{method:'GET',...options,csrf:session.csrf_token,signal:controller.signal})).then(value=>{
      if(run!==epoch)throw new DOMException('Stale account','AbortError');return value;
    }).catch(error=>{if(run===epoch&&error.status===401)unauthorized(error);throw error;}).finally(()=>{options.signal?.removeEventListener('abort',abort);controllers.delete(controller);if(flights.get(key)===task)flights.delete(key);});
    flights.set(key,task);return task;
  }
  return {identity,request,resolve(permalink){
    if(!/^[a-z0-9]+(?:-[a-z0-9]+)*-[a-f0-9]{12}$/.test(permalink))return Promise.reject(new Error('Invalid permalink'));
    return request('resolve:'+permalink,`/v1/podcasts/episodes/${permalink}`);
  }};
}
