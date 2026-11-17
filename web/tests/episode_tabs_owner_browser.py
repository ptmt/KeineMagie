"""Real view with deliberately late owner responses, no real credentials."""
from episode_fixture import Handler,PATH
from http.server import ThreadingHTTPServer
from threading import Thread
from playwright.sync_api import sync_playwright
import json
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page()
  page.goto(f'http://127.0.0.1:{server.server_port}'+PATH)
  page.locator('#episode-summary .episode-citation').first.wait_for()
  result=page.evaluate('''async()=>{
   const {createEpisodeView}=await import('/episode-view.mjs');
   const host=document.createElement('article');document.body.append(host);
   const pending=[];const view=createEpisodeView({api:{request:path=>path.endsWith('/analysis')?new Promise(resolve=>pending.push(resolve)):Promise.resolve(path.includes('/vocabulary')?{items:[]}:{cefr:'B1'})}});
   const job=id=>({id,title:id,source_language:'de',target_language:'ru',state:'completed',segments:[{start:0,end:3,text:id,translation:id}]});
   view.identity({user:{id:'A'}});view.render(host,job('PRIVATE_OWNER_A'));
   await new Promise(r=>setTimeout(r,20));
   const before=host.querySelector('#episode-transcript').hidden&&host.textContent.includes('PRIVATE_OWNER_A');
   view.identity({user:{id:'B'}});const cleared=host.childNodes.length===0;
   view.render(host,job('PRIVATE_OWNER_B'));await new Promise(r=>setTimeout(r,20));
   pending[0]({state:'completed',result:{narrative:[{text:'LATE_PRIVATE_OWNER_A'}]}});
   await new Promise(r=>setTimeout(r,30));
   const isolated=!host.textContent.includes('OWNER_A')&&host.textContent.includes('PRIVATE_OWNER_B');
   view.identity(null);pending[1]({state:'completed',result:{narrative:[{text:'LATE_PRIVATE_OWNER_B'}]}});
   await new Promise(r=>setTimeout(r,30));
   return {before,cleared,isolated,logoutEmpty:host.childNodes.length===0,hiddenPanels:host.querySelectorAll('[role=tabpanel]').length};
  }''')
  assert result=={'before':True,'cleared':True,'isolated':True,'logoutEmpty':True,'hiddenPanels':0},result
  print(json.dumps({'passed':'mounted hidden DOM purged synchronously on owner change/logout; late analysis cannot revive private text','checks':result}))
  browser.close()
finally:server.shutdown()
