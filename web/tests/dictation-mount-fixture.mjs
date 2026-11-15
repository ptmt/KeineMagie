// Small DOM/IndexedDB/media adapters for executing the real mounted controller.
// Every request stays in process; no backend, credentials or synthesis is used.
import assert from 'node:assert/strict';
import {mountDictation} from '../dictation.mjs';
export const tick=()=>new Promise(resolve=>setImmediate(resolve));
class Element {
 constructor(tag){this.tagName=tag.toUpperCase();this.children=[];this.attributes={};this.value='';this.hidden=false;this.disabled=false;this.listeners={};this._text='';}
 set textContent(value){this._text=String(value);this.children=[];}
 get textContent(){return this._text+this.children.map(c=>typeof c==='string'?c:c.textContent).join('');}
 append(...children){this.children.push(...children);}
 replaceChildren(...children){this._text='';this.children=children;}
 setAttribute(k,v){this.attributes[k]=v;}
 getAttribute(k){return this.attributes[k]??null;}
 removeAttribute(k){delete this.attributes[k];}
 addEventListener(k,fn){this.listeners[k]=fn;}
 querySelector(selector){return this.all().find(e=>selector==='button'?e.tagName==='BUTTON':e.tagName===selector.toUpperCase())??null;}
 all(){return this.children.filter(c=>typeof c!=='string').flatMap(c=>[c,...c.all()]);}
 contains(e){return this.all().includes(e);}
 showModal(){this.open=true;}
 close(){this.open=false;}
}
export function fixture({request,readError=false}={}){
 const disk=new Map(),writes=[],requests=[],media=[];let gesture=false,unauthorized=0;
 const doc={createElement:tag=>new Element(tag),addEventListener(){},activeElement:null,hidden:false};
 globalThis.document=doc;
 globalThis.Audio=class extends Element {
  constructor(){super('audio');this.playbackRate=1;media.push(this);this.plays=0;}
  set src(v){this.setAttribute('src',v);}
  get src(){return this.getAttribute('src');}
  pause(){}
  load(){}
  play(){assert.equal(gesture,true,'audio.play must run synchronously in the click gesture');this.plays++;return this.playError?Promise.reject(this.playError):Promise.resolve();}
 };
 globalThis.indexedDB={open(){const r={};queueMicrotask(()=>{r.result={transaction(_store,mode){const t={objectStore(){return {
   get(key){const q={};queueMicrotask(()=>{if(readError){t.error=Error('read failed');t.onerror();}else{q.result=structuredClone(disk.get(key));t.oncomplete();}});return q;},
   put(value,key){const q={};queueMicrotask(()=>{disk.set(key,structuredClone(value));writes.push(structuredClone(value));t.oncomplete();});return q;},
   delete(key){const q={};queueMicrotask(()=>{disk.delete(key);t.oncomplete();});return q;}
  };}};return t;}};r.onsuccess();});return r;}};
 const host=new Element('main');let controller;
 controller=mountDictation({host,api:{request:async(path,options)=>{requests.push({path,...options});return request(path,options);}},unauthorized:error=>{assert.equal(error?.status,401,'real app callback requires the HTTP error');unauthorized++;controller.identity(null);}});
 const session={user:{id:'synthetic'},csrf_token:'synthetic'};
 return {host,disk,writes,requests,media,controller,session,get unauthorized(){return unauthorized;},
  button(label){const b=host.all().find(e=>e.tagName==='BUTTON'&&(e.textContent===label||e.getAttribute('aria-label')===label));assert.ok(b,`missing ${label}`);return b;},
  async click(label){const b=this.button(label);assert.equal(b.disabled,false,`${label} disabled`);gesture=true;let result;try{result=b.onclick();}finally{gesture=false;}await result;await tick();},
  async create(){const form=host.all().find(e=>e.tagName==='FORM');await form.onsubmit({preventDefault(){}});await tick();},
  async start(){controller.identity(session);await tick();await tick();},
 };
}
export const record=(id='one')=>({id,title:'Test '+id,revision:0,draft:'',mode:'whole',step:0,replays:0,checked:false,plan:[{kind:'whole',asset:0}],ready:[0]});
