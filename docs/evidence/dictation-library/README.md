# Dictation library — local candidate

Base: freshly fetched `origin/main` **c0c6ff3** (integrated release merge **78e2ebf**).
Scope: web library and additive server list metadata. No native changes, simulator use, push or deployment.

## What changed and why

- The orphan ellipsis was **not** the attempt detail menu. `mountDictation` explicitly mounted a separate library `details` containing only Refresh between its title and +; `justify-content: space-between` placed it in the middle. The normal library header now has only title/+; failed reads retain a direct Refresh action. The detail attempt menu, reveal, new attempt and confirmed deletion remain in their original owner/revision-aware handlers.
- “В процессе” was the localization of `In progress` for **every `checked == false` item**, including untouched new records. It did not describe a background job. The server deliberately redacts drafts from list responses, so no attempt draft state is invented. A genuinely saved creation form is labeled “Черновик”/Draft. Real explicit audio preparation feedback stays unchanged in the detail player.
- Spacious neutral cards have larger semibold titles, 24px padding, whole-card keyboard/click navigation and responsive one/two-column layout. Empty onboarding keeps its prior block flow and create CTA.
- `word_count` is additive, list-only metadata derived from the stored original using the existing Unicode word tokenizer after NFC normalization, before redaction. Source text, learner draft and differences remain hidden.
- Optional `audio_duration_seconds` comes from the **existing ready whole recording**: one local stat and a 44-byte canonical PCM WAV header read. No payload reads, per-card HTTP requests, provider calls, duration estimation or summed sentence/pause durations. Missing, truncated, unsupported/noncanonical legacy WAVs and segment-only recordings omit duration. No stored-record migration or native DTO changes.

## Verified

- RED: actual Chromium baseline reproduced the orphan header menu; mounted Node regression failed on the extra DETAILS element, unchecked label, missing card metadata and misleading creation label. Real Go HTTP regression initially lacked word count. Empty-flow geometry regression also failed before scoping the grid to populated libraries.
- Full Node: **164 passed, 0 failed, 1 existing opt-in Go-wire profile test skipped** (`node-all.log`).
- Full `go test ./...`: PASS (`go-all.log`); focused library/owner/audio `-race`: PASS; `go vet ./...`: PASS.
- Library Chromium: **45 layout cases**, 0/1/3 items × five locales × 320/390/1280 widths. Localized metadata, keyboard creation/card/menu navigation, accessible names, no nested buttons, confirmation cancel/accept, exact attempt selection, checked-to-list, stale cached deletion, draft resume, owner clearing and no inference (`result.json`).
- Full actual app + Go handler: real source word counts and a real **synthetic silent 95-second WAV**, with **zero library media requests** (`app-result.json`). These are isolated synthetic records, not personal account data or generated speech.
- Existing Chromium regressions passed: policy with real Go bridge/HTMLMediaElement; headings (20 cases); reveal menu (10); preparation geometry (five locales); actual-media pause/resume/replay; focused flow; delayed preparation and logout lifecycle. Receipts are beside this file.
- Lifecycle harness needed an explicit legacy-create adapter because its Next/Pause assertions predate policy v1; v1 remains covered by its separate real Go/browser harness. The local Go fixture gained an optional port to avoid the concurrently occupied 8799. No other worker's server or worktree was touched.

## Inspected preview images

All are actual Chromium renders; no mock design images.

- `app-1-cards-ru-1280.png` — recommended desktop preview.
- `app-1-cards-ru-390.png` — recommended mobile preview.
- `app-3-cards-ru-1280.png`, `app-3-cards-ru-320.png` — multiple cards and long titles.
- `app-one-no-audio-ru-390.png` — no invented duration.
- `app-empty-ru.png` — empty onboarding.
- `before-ru-1280.png`, `before-ru-390.png` — original module/CSS baseline matching the supplied screenshot's defect.

## Reproduce safely

Run the module fixture from this worktree (`python3 -m http.server 8876 --bind 127.0.0.1 --directory web`), then `python web/tests/dictation_library_browser.py` with Playwright/Chromium installed. For full-app captures, start `TestDictationLocalFixture` from `server` with a **fresh scratch** `DICTATION_FIXTURE_DIR`, an unused `DICTATION_FIXTURE_PORT` and matching `WEB_ORIGIN`; pass the same directory to `web/tests/dictation_library_app_browser.py`. That test seeds only its disposable store with silent WAV bytes. Never point these fixtures at production storage.

Preview approval/release remains with the parent/user. This candidate is not deployed.
