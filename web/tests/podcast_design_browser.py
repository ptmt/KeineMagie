"""Podcast design/interaction regression against synthetic fixture only."""
from http.server import ThreadingHTTPServer
from threading import Thread
from pathlib import Path
import json
from playwright.sync_api import sync_playwright
from podcast_design_fixture import Handler, STATE, JOB

server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
origin='http://127.0.0.1:'+str(server.server_port)
out=Path('/Users/tinyserve/.hermes/cache/scratch/podcast-design-evidence');out.mkdir(exist_ok=True)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch();page=browser.new_page(locale='en-US',viewport=dict(width=1280,height=847))
  errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
  page.goto(origin+'/#podcasts/feed/Feed_A');page.locator('.podcast-episode').first.wait_for()
  assert page.locator('.podcast-episode').count()==50
  assert page.locator('#podcasts-title').inner_text()=='Radio RTW · synthetic fixture'
  ready=page.locator('.podcast-episode').first
  assert ready.locator('.podcast-episode-title a').inner_text()=='The Nut Sisters'
  assert ready.get_by_role('link',name='Open',exact=True).count()==0
  assert not ready.get_by_role('button',name='Delete',exact=True).is_visible()
  summary=ready.locator('summary');summary.focus();page.keyboard.press('Enter')
  assert ready.get_by_role('button',name='Delete',exact=True).is_visible()
  page.keyboard.press('Escape');assert not ready.locator('details').evaluate('(el)=>el.open')
  assert summary.evaluate('(el)=>el===document.activeElement')
  summary.click();page.locator('#podcasts-title').click();assert not ready.locator('details').evaluate('(el)=>el.open')
  page.locator('[data-feed-actions] summary').click()
  page.select_option('[data-interface-language]','ru')
  assert page.locator('[data-feed-actions]').evaluate('(el)=>el.open')
  assert page.locator('[data-feed-actions]').get_by_role('button',name='Отписаться',exact=True).is_visible()
  page.keyboard.press('Escape');page.select_option('[data-interface-language]','en')
  page.locator('[data-feed-actions] summary').click()
  page.locator('[data-feed-actions]').get_by_role('button',name='Refresh feed',exact=True).click()
  assert len([c for c in STATE['calls'] if c['method']=='POST' and c['path'].endswith('/refresh')])==1
  assert not [c for c in STATE['calls'] if c['method']=='POST' and c['path']=='/v1/podcasts']
  for state in ['queued','transcribing','translating','failed','canceled','completed']:
   STATE['job']['state']=state;page.reload()
   page.wait_for_function('(state)=>document.querySelector(".podcast-episode").dataset.state===state',arg=state)
   assert page.locator('.podcast-episode').count()==50
   assert not ready.get_by_role('button',name='Delete',exact=True).is_visible()
  for mode in ['light','dark']:
   page.emulate_media(color_scheme=mode)
   for width in [320,390,768,1280]:
    page.set_viewport_size(dict(width=width,height=847));assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    assert page.locator('#podcast-add').bounding_box()['width']>=44
    assert page.locator('.podcast-episode').nth(1).get_by_role('button',name='Prepare',exact=True).bounding_box()['height']>=44
    if width in [390,1280]:page.screenshot(path=str(out/f'feed-{mode}-{width}.png'))
  page.emulate_media(color_scheme='light');page.set_viewport_size(dict(width=1280,height=847))
  ready.locator('.podcast-episode-title a').click();page.wait_for_url('**/podcasts/episodes/**');page.locator('.episode-header').wait_for()
  assert page.locator('.episode-header').inner_text().find('The Nut Sisters')>=0
  page.go_back();ready.wait_for();summary=ready.locator('summary');summary.click()
  page.once('dialog',lambda dialog:dialog.dismiss());ready.get_by_role('button',name='Delete',exact=True).click()
  assert STATE['job'] is not None
  if not ready.locator('details').evaluate('(el)=>el.open'):summary.click()
  page.once('dialog',lambda dialog:dialog.accept());ready.get_by_role('button',name='Delete',exact=True).click()
  page.wait_for_function('() => !document.querySelector(".podcast-episode-title a")')
  deleted=[c for c in STATE['calls'] if c['method']=='DELETE']
  assert len(deleted)==1 and deleted[0]['path']=='/v1/podcasts/Fixture_Ready' and deleted[0]['csrf']=='fixture-csrf'
  page.locator('[data-feed-actions] summary').click()
  page.once('dialog',lambda dialog:dialog.accept());page.get_by_role('button',name='Unsubscribe',exact=True).click()
  page.wait_for_url('**/#podcasts');assert not STATE['subscribed']
  assert not errors,errors
  print(json.dumps(dict(fixture_only=True,checks='50 rows, feed hierarchy, title deep link/back, quiet confirmed delete, native disclosure Enter/Escape/outside/focus, locale preserves menu, feed refresh scope/no inference, six job states, four widths/light+dark, 44px targets, unsubscribe CSRF readback',screenshots=str(out),errors=errors)))
  browser.close()
finally:server.shutdown()
