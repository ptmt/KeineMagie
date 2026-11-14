// No persistent browser cache, inference polling, or hidden retry. Server owns receipts.
const errorKey=e=>['storage','session','invalid','quota','canceled','connection_required','catalog_unavailable','model_unavailable','sources_unavailable','sources_required','conflict'].includes(e.code?.replace(/^coach_/,''))?e.code.replace(/^coach_/,''):({401:'session',403:'session',429:'quota'}[e.status]||(e.code==='invalid_response'||e instanceof SyntaxError?'response':e.status?'server':e.name==='TimeoutError'?'timeout':e instanceof TypeError?'network':'unknown'));
export function createCoachState(api,changed,unauthorized,locale){
 let owner=null,session=null,epoch=0,read=null,controller=null;
 const state={value:null,error:'',busy:false,pendingID:null,
 identity(next){const id=next?.user?.id||null;if(id!==owner){epoch++;controller?.abort();read=null;controller=null;state.value=null;state.error='';state.busy=false;state.pendingID=null;owner=id;}session=next;changed();},
 get signedIn(){return !!owner;},
 async load(){if(!owner||read||state.busy)return;const version=epoch,id=Symbol();read=id;
  try{const value=await api.request('/v1/learning/coach');if(version===epoch){state.value=value;state.error='';}}
  catch(error){if(version===epoch){state.error=errorKey(error);if(error.status===401)unauthorized(error);}}
  finally{if(version===epoch&&read===id){read=null;changed();}}
 },
 async act(action,text='',turn_id=''){
  if(!owner||(state.busy&&action!=='cancel'))return false;
  const version=++epoch,request_id=crypto.randomUUID(),cancel=action==='cancel';read=null;
  if(cancel){controller?.abort();state.busy=true;state.pendingID=null;}
  if(!cancel){state.busy=true;controller=new AbortController();if(action==='message')state.pendingID=request_id;}
  state.error='';changed();
  try{
   const value=await api.request('/v1/learning/coach',{method:'POST',csrf:session.csrf_token,body:{action,text,turn_id,request_id,locale:locale()},signal:cancel?undefined:controller.signal});
   if(version!==epoch)return false;
   // A cancel response dominates a late original request response.
   if(cancel){epoch++;controller?.abort();state.busy=false;state.pendingID=null;read=null;}
   state.value=value;changed();return true;
  }catch(error){if(version===epoch){if(error.name!=='AbortError')state.error=errorKey(error);if(error.status===401)unauthorized(error);}return false;}
  finally{if(version===epoch){state.busy=false;state.pendingID=null;controller=null;changed();}}
 }
 };return state;
}
