"""Opt-in Chromium regression against the synthetic local dictation fixture.

Exercises delayed preparation, rapid switches, and logout during an audio GET.
No speech engine or paid provider is needed for these transport fences.
"""
import asyncio
import io
import json
import os
import wave
from pathlib import Path
from playwright.async_api import async_playwright, expect

fixture = Path(os.environ.get('DICTATION_FIXTURE_DIR', '/private/tmp/diktat-web-fixture'))
artifact = Path(os.environ.get('DICTATION_BROWSER_ARTIFACT_DIR', '/private/tmp/diktat-web-lifecycle'))
artifact.mkdir(parents=True, exist_ok=True)
info = json.loads((fixture / 'fixture.json').read_text())

with io.BytesIO() as output:
    with wave.open(output, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(22050)
        wav.writeframes(b'\0\0' * 22050)
    audio = output.getvalue()

async def main():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch()
        context = await browser.new_context()
        await context.add_cookies([{'name': '__Host-km-session', 'value': info['browser'], 'domain': 'localhost', 'path': '/', 'secure': True, 'httpOnly': True, 'sameSite': 'Strict'}])
        page = await context.new_page()
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        # This transport-fence regression intentionally exercises legacy Next/
        # Pause behavior; v1 sequencing has its own real Go/Chromium harness.
        async def legacy_creation(route):
            if route.request.method == 'POST':
                body = route.request.post_data_json
                body.pop('playback_policy_version', None)
                await route.continue_(post_data=json.dumps(body))
            else:
                await route.continue_()
        await page.route('**/v1/learning/dictations', legacy_creation)
        await page.goto(info['url'] + '/#dictation')
        await page.locator('#dictation header').get_by_role('button', name='Add text', exact=True).click()
        await page.get_by_role('textbox', name='Title', exact=True).fill('Lifecycle fence')
        await page.get_by_role('textbox', name='Original text', exact=True).fill('Heute scheint die Sonne. Morgen regnet es.')
        await page.get_by_role('button', name='Save text', exact=True).click()
        await expect(page.get_by_role('textbox', name='What you heard')).to_be_visible()

        preparing = asyncio.Event()
        release_preparation = asyncio.Event()
        async def delayed_preparation(route):
            preparing.set()
            await release_preparation.wait()
            await route.fulfill(status=200, content_type='application/json', body='{}')
        async def preparation_route(route):
            if route.request.method == 'POST':
                await delayed_preparation(route)
            else:
                await route.continue_()
        await page.route('**/v1/learning/dictations/*/audio/*', preparation_route)
        await page.get_by_role('button', name='Prepare audio', exact=True).click()
        await asyncio.wait_for(preparing.wait(), 10)
        await page.get_by_role('button', name='Cancel preparation', exact=True).click()
        await expect(page.get_by_role('button', name='Prepare audio', exact=True)).to_be_enabled()
        await page.get_by_role('button', name='By sentences', exact=True).click()
        await page.get_by_role('button', name='Whole text', exact=True).click()
        await page.get_by_role('button', name='By sentences', exact=True).click()
        await page.get_by_role('button', name='Next', exact=True).click()
        release_preparation.set()
        await expect(page.get_by_role('button', name='Prepare audio', exact=True)).to_be_enabled()
        await page.unroute_all(behavior='ignoreErrors')

        async def ready_route(route):
            if route.request.method == 'POST':
                await route.fulfill(status=200, content_type='application/json', body='{}')
            else:
                await route.continue_()
        await page.route('**/v1/learning/dictations/*/audio/*', ready_route)
        await page.get_by_role('button', name='Prepare audio', exact=True).click()
        await expect(page.get_by_role('button', name='Play', exact=True)).to_be_enabled()
        await page.unroute_all(behavior='ignoreErrors')
        downloading = asyncio.Event()
        release_download = asyncio.Event()
        async def delayed_download(route):
            downloading.set()
            await release_download.wait()
            await route.fulfill(status=200, content_type='audio/wav', body=audio)
        async def download_route(route):
            if route.request.method == 'GET':
                await delayed_download(route)
            else:
                await route.continue_()
        await page.route('**/v1/learning/dictations/*/audio/*', download_route)
        await page.get_by_role('button', name='Play', exact=True).click()
        await asyncio.wait_for(downloading.wait(), 10)
        await page.get_by_role('button', name='Profile', exact=True).click()
        await page.locator('#logout').click()
        release_download.set()
        await expect(page.locator('#dictation')).not_to_contain_text('Lifecycle fence')
        await page.wait_for_timeout(300)
        await expect(page.locator('#dictation')).not_to_contain_text('Lifecycle fence')
        assert not errors, errors
        await page.screenshot(path=str(artifact / 'signed-out.png'))
        (artifact / 'result.json').write_text(json.dumps({'checks': ['delayed preparation interruption', 'rapid mode switches', 'logout during delayed audio download'], 'page_errors': errors}, indent=2))
        await browser.close()

asyncio.run(main())
