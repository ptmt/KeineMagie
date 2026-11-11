"""Run with browser_exec: real DOM/shipped modules, synthetic APIs only."""
from pathlib import Path
from typing import TYPE_CHECKING
if TYPE_CHECKING:
 def js(expression: str): ...
import json,re,time
root=Path('/Users/tinyserve/Projects/KeineMagie/web')
base=(root/'tests/session_browser.py').read_text().split('checks=[]')[0]
base=base.replace("getItem:()=> 'de',setItem:()=>{}", "getItem:key=>window.__prefs[key]??null,setItem:(key,value)=>window.__prefs[key]=value")
base=base.replace('window.__calls=[];', "Object.defineProperty(crypto,'randomUUID',{configurable:true,value:()=> 'fixture-custom'});window.__prefs={};Object.defineProperty(navigator,'languages',{configurable:true,value:['ru-RU','en-US']});window.__calls=[];")
base=base.replace('window.__holdSession=true;window.__holdProvider=true;window.__holdHistory=true;', 'window.__holdSession=false;window.__holdProvider=false;window.__holdHistory=false;')
base=base.replace("location.hash=\"#podcasts\"", "location.hash=\"#translator\"")
exec(base)
time.sleep(.3)
checks=[]
def check(name,expr):
 result=js(expr);assert result is True,(name,result);checks.append(name)
def change(locale,where='header'):
 js(f"document.querySelector('#interface-language-{where}').value='{locale}';document.querySelector('#interface-language-{where}').dispatchEvent(new Event('change'))")
check('browser Russian preference selected without saving',"document.documentElement.lang==='ru' && document.querySelector('#interface-language-header').value==='ru' && Object.keys(window.__prefs).length===0")
check('default translation direction remains Russian to German',"document.querySelector('#language-direction').value==='ru-de'")
js("document.querySelector('#source-text').value='Freundlich user draft';document.querySelector('#source-text').dispatchEvent(new Event('input'));document.querySelector('#source-text').setSelectionRange(3,7);document.querySelector('#account').click();window.__before=JSON.stringify(window.__calls)")
for locale in ['en','de','es','fr','ru']:
 change(locale,'account')
 check(locale+' synchronized open account and draft selection without network',f"document.documentElement.lang==='{locale}'&&document.querySelector('#interface-language-header').value==='{locale}'&&document.querySelector('#account-dialog').open&&document.querySelector('#source-text').value==='Freundlich user draft'&&document.querySelector('#source-text').selectionStart===3&&document.querySelector('#source-text').selectionEnd===7&&document.querySelector('#language-direction').value==='ru-de'&&window.__before===JSON.stringify(window.__calls)")
change('en','account')
check('dynamic account and translator labels English',"document.querySelector('#provider-status').textContent==='Connected'&&document.querySelector('#translate').textContent==='Translate ↗'&&document.querySelector('#account-title').textContent==='Your account'")
js("document.querySelector('#close-account').click();document.querySelector('#add-prompt').click();document.querySelector('#prompt-name').value='Freundlich';document.querySelector('#prompt-instructions').value='Do not translate this custom instruction';document.querySelector('#prompt-name').dispatchEvent(new Event('input'));document.querySelector('#prompt-form').requestSubmit()")
change('fr')
check('custom shortcut label untouched and builtin translated',"[...document.querySelectorAll('.style-chip')].some(el=>el.textContent==='Freundlich')&&[...document.querySelectorAll('.style-chip')].some(el=>el.textContent==='Amical')")
js("document.querySelector('#edit-prompt').click();document.querySelector('#prompt-instructions').setSelectionRange(2,9);window.__before=JSON.stringify(window.__calls)")
change('de')
check('open prompt values and selection retained',"document.querySelector('#prompt-dialog').open&&document.querySelector('#prompt-name').value==='Freundlich'&&document.querySelector('#prompt-instructions').value==='Do not translate this custom instruction'&&document.querySelector('#prompt-instructions').selectionStart===2&&window.__before===JSON.stringify(window.__calls)")
js("document.querySelector('#close-prompt').click();location.hash='#podcasts'");time.sleep(.3)
js("document.querySelector('#podcast-add').click();document.querySelector('#podcast-url').value='https://example.org/user-feed';document.querySelector('#podcast-mode').value='episode';document.querySelector('#podcast-mode').dispatchEvent(new Event('change'));window.__before=JSON.stringify(window.__calls)")
change('en')
check('podcast import dialog and draft retained with localized dynamic help',"document.querySelector('#podcast-dialog').open&&document.querySelector('#podcast-url').value==='https://example.org/user-feed'&&document.querySelector('#podcast-submit').textContent==='Prepare'&&document.querySelector('#podcast-add-help').textContent.startsWith('Public episode')&&document.querySelector('#podcast-content').textContent.includes('Synthetic private podcast')&&window.__before===JSON.stringify(window.__calls)")
check('explicit choice persisted',"window.__prefs['keinemagie:interface-language:v1']==='en'")
# Re-execute the shipped locale module in isolation with the same storage object.
module=re.sub(r'export (?=(function|async function|const))','',(root/'i18n.mjs').read_text())
check('reload initializes explicit locale instead of Russian browser preference', '(()=>{'+module+";return getInterfaceLanguage()==='en';})()")
print(json.dumps({'fixture_only':True,'checks_passed':len(checks),'checks':checks},indent=2))
