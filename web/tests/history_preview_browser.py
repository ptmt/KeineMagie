"""Real shipped history rendering against local synthetic HTTP data only."""
import json
from pathlib import Path
from threading import Thread
from http.server import ThreadingHTTPServer
from playwright.sync_api import sync_playwright
from podcast_design_fixture import Handler, RECORD

# Exact text contract: no trim, HTML/entity conversion, truncation or Unicode loss.
RECORD['translation'] = ('  \tÜbersetzung 👩🏽‍💻 e\u0301 &lt;literal&gt; <img src=x onerror=alert(1)>\n'
                         + ('Привет 日本語 {"literal":"\\n"}\n' * 1200)
                         + '\n  Ende.\t  \n')

server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Thread(target=server.serve_forever,daemon=True).start()
origin='http://127.0.0.1:'+str(server.server_port)
try:
    with sync_playwright() as p:
        browser=p.chromium.launch()
        page=browser.new_page(locale='en-US')
        errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
        page.goto(origin)
        page.locator('#history-list li').wait_for()
        source=page.locator('#history-list .history-source')
        output=page.locator('#history-list .history-translation')
        assert source.inner_text()==RECORD['text']
        assert output.text_content()==RECORD['translation']
        assert source.get_attribute('lang')=='ru'
        assert output.get_attribute('lang')=='de'
        assert page.locator('#history-list script, #history-list img').count()==0
        for width in [320,390,1440]:
            page.set_viewport_size(dict(width=width,height=900))
            assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
            assert output.evaluate('(el)=>getComputedStyle(el).whiteSpace')=='pre-wrap'
            assert output.evaluate('(el)=>el.scrollHeight<=el.clientHeight+1')
        page.select_option('[data-interface-language]','ru')
        assert output.text_content()==RECORD['translation']
        page.locator('#history-list button').click()
        assert page.locator('#result').text_content()==RECORD['translation']
        assert page.locator('#source-text').input_value()==RECORD['text']
        assert not errors,errors
        browser.close()
        print(json.dumps(dict(fixture_only=True,checks='full multiline source and translation immediately visible, escaped markup, lang attributes, responsive, locale, reopen exact output',errors=errors)))
finally:
    server.shutdown()
