# Web interface languages

The shipped browser interface supports `de`, `en`, `ru`, `es`, and `fr`.
`web/i18n.mjs` owns shell messages and locale selection; `web/episode-i18n.mjs`
owns the episode reader namespace. Both namespaces are tested for complete keys
and matching interpolation parameters in all five languages.

The compact header selector is available before login. The account selector uses
the same value. Only an explicit choice writes
`keinemagie:interface-language:v1` to localStorage. Otherwise supported browser
languages are checked in order (regional tags supported), with German fallback.
Storage failure does not prevent changing the current UI language.

Language changes reapply app-owned labels, attributes, dates and numbers; they do
not restore identity, navigate, restart podcast polling, or fetch APIs. Existing
account/import/style dialogs, input drafts and selections are retained. The
translation direction remains independent (fresh default Russian → German).
Custom shortcut names/instructions, translation/history text, podcast titles,
transcripts and generated analysis remain unchanged. Server diagnostic payloads
are not machine-translated.

Official Apple artwork is vendored unchanged for every supported locale from:

```
https://appleid.cdn-apple.com/appleid/button?height=48&width=320&color=black&border=false&type=sign-in&border_radius=8&scale=3&locale=LOCALE
```

Locales: `de_DE`, `en_US`, `ru_RU`, `es_ES`, `fr_FR`. All PNGs are 960 × 144.
Static serving is an explicit allowlist, and Docker copies each runtime asset.
No remote script, stylesheet, or CSP exception is required.

## Regression commands

```
node --test web/tests/*.test.mjs
cd server && go test ./...
```

`web/tests/i18n_browser.py` and `session_browser.py` run through `browser_exec`
against actual shipped DOM/scripts and explicitly synthetic APIs.
`web/tests/i18n_http_browser.py` and `episode_browser.py` run with Python
Playwright/Chromium against a local HTTP fixture. The i18n HTTP test covers
actual reload persistence, all five reader locales, open account/quote drafts,
unchanged user/history/result text, no language-change API requests, responsive
widths, artwork responses and guest selection. No test authenticates a live
account or sends a real provider request.
