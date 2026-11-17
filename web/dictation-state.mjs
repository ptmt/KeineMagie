// Playback transport is deliberately not part of the persisted practice state.
export function practiceTransition(record,event){
 const s={...record,playing:false};
 if(s.checked)return s;
 if(event==='whole'||event==='sentences'){s.mode=event;s.step=0;if(s.playback_policy_version!==1)s.replays=0;}
 if(event==='next'&&s.mode==='sentences')s.step=Math.min(s.step+1,s.plan.length-1);
 if(event==='ended')s.replays++;
 return s;
}
