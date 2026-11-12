# Translation correspondence revision

## Contract and design

- Discussion now belongs to the right/output pane, after the current translation and its caption. Narrow screens retain source → output → discussion order. Existing native/fallback composer autogrow is unchanged.
- A quiet, accessible pencil opens a native translation textarea. Done closes editing; copy and swap always use the current exact text, including whitespace, Unicode and literal markup. Edits are local current-result drafts, not new saved history. The localized caption says so. Changing/reopening the source, replacing the owner or clearing the result clears the hidden editor text.
- Provider strict schema now requires `answer`, nullable `revised_text`, nullable `revised_source_text`. A changed source requires a matching translation. Source proposals are bounded to 8,000 code points. Historical turns lacking the new nullable field still decode.
- The task defaults to correcting the current source translation, not expanding a short phrase into a full invented sentence merely because context was added. Broader meaning/context must be returned as a source+translation pair. Source language is the saved actual direction, never interface locale or mixed-language question language. Semantic adherence remains a model instruction, not a claim of mechanically proven equivalence.
- Changed-source proposals preview both values with **Use both / Применить текст и перевод**. Applying explicitly updates source textarea, count, direction association, current output, copy and swap; original history remains immutable.
- A proposal without a changed source remains associated with the source draft from its own turn. Reopening such a proposal against the saved original previews/explicitly restores that source too, preventing mismatched pairs after reload or selecting older proposals.
- POST optionally accepts paired `current_source` / `current_translation`, max 8,000 Unicode code points each, within a 128-KiB JSON body. These are untrusted user draft data in user-role messages, not authoritative history or trusted instructions. Both are captured with the durable question turn for subsequent conversation context. No arbitrary owner/model/output IDs are accepted.
- Completed-request identity compares question and both draft values. Client retry identity changes when the current pair changes; identical failed attempts retain their ID. Overlong current text remains copyable/editable but discussion shows a specific localized limit without sending it.
- No manual edits are silently autosaved. A question explicitly sends its current pair as discussion context, persisted with that question only. Reopening history restores the original source/output and retains the conversation/proposals.

## Execution evidence (synthetic providers only)

- TDD RED: paired-provider test failed on old three-return signature; draft-context test returned HTTP 400 before fields existed; client retry test observed missing current draft; real Chromium first failed because discussion was not in output pane; oversize-draft test observed an unwanted API call before guard.
- `go test -race ./...`: passed (`ok diktat/server 37.198s`), later rerun cached; `go vet ./...`: passed.
- `node --test web/tests/*.test.mjs`: final 69 passed, 0 failed (existing Node localStorage experimental warning only).
- `web/tests/correspondence_browser.py`: 22 passed after independent review. Includes actual manual-edit clipboard, local-only caption/plaintext output, locale preservation, paired apply and next-question context, original history, reopen and contextual source restoration, all three directions, hidden editor clearing, swap, desktop/mobile overflow and zero runtime errors.
- Existing `followup_browser.py`: 31 native and 31 forced-fallback checks passed, preserving autogrow, selection, locale, retry/pending, reload and owner isolation.
- Existing `copy_browser.py`: all 22 passed, including actual 64,838-character clipboard and fallback selection restoration.
- All seven `run_legacy_browser.py` suites passed: smoke 26, directions 19, guest 23, i18n 13, podcasts 41, session 12, styles 13.
- Own actual Chromium screenshots captured and inspected: scratch `correspondence-pair-390.png` and `correspondence-pair-1440.png`. Both show source+translation preview and explicit paired action; mobile has no clipping. Fixture English answers and literal markup are deliberate synthetic data, not production semantic output.

## Independent review

Found one regression: reopening a saved original hid the manual editor but retained its previous private draft value in the hidden textarea. Added a real Chromium regression assertion, observed RED (`reopening original wipes hidden manual editor`), then cleared the editor on `renderRecord`; all 22 correspondence checks passed GREEN. No other blocking findings in the scoped server/UI diff. Authenticated owner lookup, request payload identity, bounded Unicode context, completion/schema validation, revocation-serialized append, expected-turn fence and charge-before-send behavior were reviewed. Durable auth/history locks are not held over network I/O; the existing account admission/quota lock intentionally spans the operation.

Verification commands (repository root, using the existing scratch `episode-browser-venv/bin/python` for browser tests): `cd server && go test -race ./... && go vet ./...`; `node --test web/tests/*.test.mjs`; Python `web/tests/correspondence_browser.py`, `web/tests/followup_browser.py`, `FOLLOWUP_FORCE_FALLBACK=1` follow-up rerun, `web/tests/copy_browser.py`, `web/tests/run_legacy_browser.py`.

Limits: tests use synthetic provider wire responses only, not real inference. Source-language and meaning correspondence are prompt instructions, not mechanical guarantees: even a schema-valid source+translation response can be semantically wrong. Both values are disclosed in the preview and require explicit application. No paid AI, quota resets, retries or fabricated production data were used. Pre-existing `spikes/` and generated `web/tests/__pycache__/` are excluded from the release.
