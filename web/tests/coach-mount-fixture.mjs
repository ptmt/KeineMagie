// Minimal DOM for the real mounted Coach controller; all transport is in process.
import {mountCoach} from '../coach.mjs';
export const tick=()=>new Promise(r=>setImmediate(r));
class Node {
 constructor(tag,text=''){this.nodeName=this.tagName=tag.toUpperCase();this.nodeType=tag==='#text'?3:1;this._text=text;this.childNodes=[];this.attrs=new Map();this.dataset={};this.style={};this.listeners={};this.value='';this.hidden=false;this.scrollHeight=1200;this.clientHeight=400;this._scrollTop=0;this.scrollWrites=0;}
 get children(){return this.childNodes.filter(n=>n.nodeType===1);}
 get attributes(){return [...this.attrs].map(([name,value])=>({name,value}));}
 get textContent(){return this._text+this.childNodes.map(n=>n.textContent).join('');}
 set textContent(v){this._text=String(v);this.childNodes=[];}
 get scrollTop(){return this._scrollTop;}
 set scrollTop(v){this.scrollWrites++;this._scrollTop=Math.min(Math.max(0,v),this.scrollHeight-this.clientHeight);}
 get lastChild(){return this.childNodes.at(-1);}
 setAttribute(k,v){this.attrs.set(k,String(v));}
 getAttribute(k){return this.attrs.get(k)??null;}
 hasAttribute(k){return this.attrs.has(k);}
 removeAttribute(k){this.attrs.delete(k);}
 append(...nodes){for(let n of nodes){if(typeof n==='string')n=new Node('#text',n);n.remove();n.parentNode=this;this.childNodes.push(n);}}
 prepend(n){this.insertBefore(n,this.childNodes[0]);}
 insertBefore(n,before){n.remove();n.parentNode=this;const i=this.childNodes.indexOf(before);this.childNodes.splice(i<0?this.childNodes.length:i,0,n);}
 replaceChildren(...nodes){this.childNodes=[];this._text='';this.append(...nodes);}
 remove(){if(this.parentNode){const a=this.parentNode.childNodes;a.splice(a.indexOf(this),1);this.parentNode=null;}}
 replaceWith(n){const p=this.parentNode,i=p.childNodes.indexOf(this);n.remove();p.childNodes[i]=n;n.parentNode=p;this.parentNode=null;}
 get classList(){return {add:(c)=>{this.className=(this.className||'')+' '+c;},remove:()=>{}};}
 addEventListener(k,fn){(this.listeners[k]??=[]).push(fn);}
 dispatch(k,e={}){for(const fn of this.listeners[k]||[])fn(e);}
 matches(s){if(s==='[data-turn]')return !!this.dataset.turn;if(s==='details[open]')return this.tagName==='DETAILS'&&this.open;if(s.startsWith('.'))return (this.className||'').split(' ').includes(s.slice(1));return this.tagName===s.toUpperCase();}
 querySelectorAll(s){return this.children.flatMap(n=>[...(n.matches(s)?[n]:[]),...n.querySelectorAll(s)]);}
 querySelector(s){return this.querySelectorAll(s)[0]||null;}
 closest(s){return this.matches(s)?this:this.parentNode?.closest(s);}
 getBoundingClientRect(){return {top:0,bottom:400,height:400};}
 focus(){globalThis.document.activeElement=this;}
 setSelectionRange(){}
}
export function fixture({snapshot={turns:[],observations:[]},request}={}){
 const doc=new Node('document');doc.visibilityState='visible';doc.createElement=tag=>new Node(tag);doc.getElementById=()=>null;globalThis.document=doc;
 const frames=[];globalThis.requestAnimationFrame=fn=>frames.push(fn);globalThis.innerHeight=800;
 globalThis.matchMedia=()=>({matches:true});
 const host=new Node('main');host.hidden=true;const requests=[];
 const controller=mountCoach({host,document:doc,locale:()=> 'en',unauthorized:()=>{},account:()=>{},api:{request:async(path,options)=>{requests.push({path,...options});return request?request(path,options):structuredClone(snapshot);}}});
 const messages=host.querySelector('.coach-messages');
 return {host,doc,controller,requests,messages,frames,session:{user:{id:'fixture'},csrf_token:'synthetic'},
 async flush(){await tick();while(frames.length)frames.shift()();await tick();},
 async show(){host.hidden=false;controller.route();await this.flush();}};
}
