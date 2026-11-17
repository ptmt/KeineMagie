# Coach daily entry, chat, and Dictation empty state — local candidate

## Authorization and isolation

The latest request explicitly authorizes an actual AI exercise on authenticated, visible Coach entry, at most once per owner local calendar day. This supersedes earlier free five-hour-offer/no-entry-inference policy **for updated clients opting in with `time_zone`**. Explicit practice remains available. It does not authorize background generation, paid OpenAI TTS fallback, deployment, or release.

Fresh isolated worktree: `/Users/tinyserve/Projects/KeineMagie-coach-daily-chat`, branch `candidate/coach-daily-chat`, created clean from freshly fetched `origin/main` `5d532e9` (preceding acceptance documentation `f787b40`). The original worktree reported **59** dirty entries at discovery, rather than the supplied 54; none were edited. No other worktree was modified. Translator changes are separate and require parent integration, especially AppModel, MainTabsView and localization. Podcast inline3, Translator followup implementations, Dictation budget/worker code and provider identifiers are preserved.

## Durable daily admission

- `entry` adds optional IANA `time_zone`; absent/empty preserves released-client request/digest compatibility and free admission. Once an owner opts in, old clients no longer append greetings and all clients receive a non-destructively filtered view of legacy offers. GET never generates.
- The first authenticated opt-in pins a single owner time zone. Different device zones cannot mint a second entitlement. This is deliberately **not** a travel-zone settings feature; changing the owner zone is not implemented.
- Auth-revocation lock + cross-process owner storage lock atomically persist a receipt, calendar-day claim and pending turn **before** provider auth/catalog/source or inference work. Claim and turn survive new handler/store instances and process interruption; there is no timeout lease that automatically reissues uncertain work.
- Concurrent entries reuse the same durable turn. Existing pending generation, pending/failed/canceled assessment, or unanswered exercise is resumed and consumes that day's automatic opportunity rather than being replaced after completion.
- Preflight crossing midnight also claims the dispatch day before quota consumption. Entry and dispatch claims remain immutable; no second automatic dispatch on that local day after an uncertain failure. Calendar dates use the owner IANA zone, not elapsed 24-hour windows.
- Existing personal-provider catalog, exact model, shared quota, owner and revocation fences remain in force. No fallback provider/TTS route is introduced. Daily clarification-only model output fails instead of creating another offer.
- Ordinary preflight failures persist a failed turn. Process death can leave a pending/uncertain turn; automatic entry never reissues it. Explicit cancellation and user-requested practice remain the recovery routes. Already-dispatched provider work cannot be recalled and may consume quota.
- Generation is at-most-once admission, **not** a claim that every entry succeeds or that network/provider acceptance can be atomically transacted with local storage. Claims fail closed at storage limits.

## Root causes and client changes

Old greetings were genuine durable `nudge` turns admitted every five hours, not merely duplicated rendering. Updated clients filter structured legacy `nudge`/`is_offer` rows without deleting stored history. Entry now carries the local IANA zone and is fenced to an authenticated visible active Coach view.

Old result styling shared a neutral surface across correct/wrong. Correct completed exercises use restrained green; checked incorrect/partial outcomes muted red; pending stays neutral with a spinner/static reduced-motion dots and localized Checking accessibility text. Check/Skip have separate 44-point targets and spacing. Explanations, assisted disclosure, answer masking, elapsed-24-hour/Earlier history and grounded progress remain.

Old scroll anchoring reacted to broad snapshot/layout changes. Native uses measured eager content and a render-relevant revision; seen receipts do not trigger scrolling. Web follows content changes rather than every render. Runtime geometry acceptance is recorded separately below; source-level tests do not prove keyboard stability.

Native AppModel exposes an injectable haptic sink, triggered only by the matching explicit foreground completed assessment acknowledgement. Cache/read/reveal/history/recovery/network errors stay silent; system notification feedback handles device haptics settings. Physical feel is not asserted.

Dictation empty onboarding is restricted to a successful authenticated empty read with no draft/recovery data; loading/failure is not an empty state. The permanent Refresh button is removed, real native pull-refresh remains. Web retains keyboard-accessible refresh in a quiet menu rather than inventing an unsupported desktop pull gesture. Creation still uses the existing flow and never starts generation automatically.

## Executed verification

All provider responses were deterministic fixture transports; no real product AI or paid TTS calls.

- New daily-entry concurrency test observed RED (400/zero calls), then GREEN (12 concurrent entries, exactly one accepted fixture inference, one completed exercise, new-handler reload reuse).
- Daily lifecycle/security race tests cover uncertain response failure, nonexercise result rejection, failed-assessment resume, catalog/inflight cancellation, revocation, owner separation, shared-quota exhaustion, source/provider preflight, invalid zone, storage failure, GET nonadmission and timezone mismatch.
- Independent backend review identified dispatch-midnight and reserved-last-slot bugs. Both gained observed RED regressions and passed after fixes.
- Full Go suite and full Go `-race` suite passed before the final boundary followup; focused daily `-race` passed after it. `go vet ./...` passed. Final rerun status will be recorded below.
- UI implementation agent ran 72 scoped Node tests, 20 Coach Swift Core tests, 16 synthetic AppModel tests and 20 localization/surface checks successfully. Independent final runs and runtime evidence follow below.

## Runtime evidence / remaining gates

Local Release verification uses only the existing Coach simulator `775A82E7-8B2D-4117-B3DE-2BAFDD234E48`, serial tests with simulator cloning disabled. The Translator xcodebuild process was observed and allowed to finish before starting this candidate's build. No simulator reset or private owner login.

### Final executed gates

- Full Go `go test ./... -race -count=1 -timeout=180s` and `go vet ./...` passed after the final migration change. All daily tests also passed under `-race`, including actual 23-hour spring and 25-hour fall calendar days.
- Full Node suite plus native onboarding source contract: **135 passed, zero failed/skipped**.
- Full Swift Core: **61 XCTest executions, one skip, zero failures**, plus **72 Swift Testing tests passed**.
- Native Python CI: **54 tests, one skip, passed**; underlying production AppModel harness **95 passed**. Dedicated daily foreground/cancellation-ID/haptic-counter harness **16 passed**. The pending daily cancellation ID had its own observed RED and GREEN.
- Dedicated real-Go/two-independent-AppModel bridge passed (**95-test harness**): concurrent foreground entries reuse one unfinished exercise and one durable daily claim; GET/seen/revision behavior preserved; exactly one provider request is the subsequent explicit assessment. Separate concurrent-empty-owner handler tests prove exactly one automatic generation.
- Actual Chromium presentation suite passed all five locales, light-independent dark theme, initial and own-send bottom, manual history/draft preservation, viewport resize, async growth, 200/1000 archived-turn windows, and computed contrast checks. A genuine async-growth scroll regression was observed and fixed by following only measured content growth when follow intent remains enabled. One later first-load timeout was not reproduced on the diagnostic repeat; it is not counted as a pass. Default Python lacked Playwright; the existing isolated `coach-history-python` interpreter ran the real browser tests.

### Release simulator evidence

`coach-daily-green.xcresult`: **5/5 passed**; `coach-daily-scroll.xcresult`: **2/2 passed**. These are bounded serial batches, not a claim that the entire native UI suite ran. The second batch verifies initial last-row geometry stays within one point, manual older reading survives tab exit/reentry/readback within two points, and explicit progress remains above the keyboard while preserving the exact draft. No swipe is used to conceal failed own-send geometry. Ad-hoc `codesign --verify --deep --strict` passed.

Exported originals and manifest: `/Users/tinyserve/.hermes/cache/scratch/coach-daily-green-shots/`. Inspected contact sheets are derivative indexes, not replacement UI screenshots:

- `contact-sheet.png`: actual dark green success, muted-red incorrect, neutral checking, reduced-motion dots, Dictation empty CTA, keyboard.
- `locales-contact-sheet.png`: actual English/German/Russian/Spanish/French maximum Dynamic Type keyboard/composer and context actions. Conversation content remains scrollable above the compact keyboard-safe composer; this is not a claim that a whole exercise fits onscreen at maximum type.
- `interval-pixels.json`: two normal checking captures 250 ms apart differ in **624 pixels**, only within the spinner rectangle `[84,807,126,849]`; corresponding reduced-motion captures are **pixel-identical**. This tests the injected production reduce-motion branch, not the OS setting. Physical haptic feel is not claimed.
- Web evidence: `/Users/tinyserve/.hermes/cache/scratch/coach-daily-browser/coach-history-evidence/`.

The initial Dictation UI failure first exposed an incomplete synthetic history envelope; after fixing the fixture, the missing primary CTA was reproduced on the real empty screen and then fixed. No fabricated success output replaced either failure. Release logs retain existing unrelated actor-isolation warnings and an existing AVAudioSession main-thread warning.

Independent read-only backend and client reviews found six concrete issues (midnight dispatch, reserved capacity, web cancellation, explicit Latest, creation-draft classification, stale onboarding during refresh); all were addressed with regression coverage. A final followup makes saved creation drafts visibly resumable and adds web's empty-state CTA. `coach-daily-final-ui.xcresult` passed **2/2** after that followup: empty CTA → existing sheet → saved title → Cancel → visible resume row → exact restored title, plus pending/corrected assessment. The exported `coach-daily-final-ui-shots/831E54D4-6A56-40E8-9D55-C922092BC148.png` was inspected and shows the real saved-draft row without misleading onboarding. Across batches, tests have repeat executions; do not sum them as nine distinct cases.

### Remaining release gates

Only one iPhone 17 Pro simulator was used. No physical two-device UI, physical haptics, real VoiceOver traversal, actual OS Reduce Motion toggle, native Dictation five-locale screenshot matrix or exhaustive entrance-frame timing claim. The server pins the first owner timezone; travel-zone settings/migration are intentionally not added. Exact screenshots are synthetic fixture UI, not live provider quality. Parent must integrate the separate Translator candidate and repeat integrated gates before any release.

No push, deployment, Apple upload or release was performed.

## Independent review followup (2026-11-17)

Reviewed candidate `61b96edb66b2feff18cc3a336e85afddd6ba14d5` against clean base `5d532e9`; candidate worktree was clean before review. Original worktree still had 59 dirty entries. Recorded their file hashes in scratch `coach-daily-review-original-manifest.json`; all recorded hashes remained unchanged after review. No other worktree was edited.

**Fixed one release-blocking behavior:** the daily resume scan selected *any historical* failed/canceled/unknown assessment, even after the user explicitly created and finished another exercise. Such an old answer could consume every future automatic opportunity forever. `TestDailyEntryHistoricalAssessmentDoesNotBlockNewPractice` reproduced all three states RED (one provider request rather than two). Resume now considers settled assessment failures only on the latest exercise; any pending generation/assessment still blocks globally, and unanswered exercises still resume. Historical answers and claims are unchanged. The regression and focused daily race suite passed GREEN; a separate old-pending regression proves fail-closed behavior remains.

**Ambiguous failed patch resolved:** inspected the exact saved tool-call payload (message 31304 in session `20261117_105826_74d6e7`) and the failure log, rather than trusting the generic mutation warning. The attempted patch added `TestDailyEntryRejectsNonExerciseResultWithoutRetry`, `TestDailyEntryResumeMidnightDSTAndReplay`, and `TestDailyEntryUncertainFailureDoesNotRetry` to `coach_daily_test.go`. All three are present in `coach_daily_lifecycle_test.go`, with the corrected nonempty explanation and controlled session-expiry fixture, and execute successfully. It contained no additional missing assertion in `dailyFixture`. `coach_daily_test.go` itself remains unchanged by this review.

**Additional independent proof:** new `TestDailyEntryPersistsBeforeCatalogAndUsesProductionWire` inspects real owner-file claims/receipt/pending turn during catalog transport, then captures the actual production Responses request: POST `/v1/responses`, exact `gpt-6.1-terra`, `store:false`, streaming, 2400 output tokens, strict `coach_turn` schema, untrusted-input instructions, `action:practice`, and exact owner source. A second branch revokes authentication inside catalog preflight and proves 401, zero inference requests, and no committed result. These are deterministic transports through production handlers, not live model-quality or account-entitlement proof.

**Fresh executed gates after fix:** full `go test ./... -race -count=1 -timeout=180s` passed (170.810 seconds), followed by `go vet ./...`; focused daily race tests passed. Full Node + native onboarding suite: 135 tests, zero failures. Actual production AppModel synthetic harness: 16 tests passed, including coalesced foreground haptics and silent cache/recovery/background paths. Actual Go-handler JSON decoded by production Swift DTOs in all nine existing wire fixtures. An initial `unittest` invocation discovered zero tests and is explicitly *not* evidence; the harness was rerun via its executable Python entry point. Individual-file editor vet warnings about package-local symbols are not package test failures.

Archived contact sheet and saved-creation-draft screenshot were inspected: green correct, muted-red wrong, neutral checking/static dots, empty CTA, keyboard-safe composer, and saved creation draft without empty onboarding are visible. Existing `interval-pixels.json` records 624 spinner pixels changed and zero reduced-motion pixels changed. No simulator was started, no new screenshots were produced, and no physical haptic/OS Reduce Motion claim is added.

**Integration remains a parent gate:** preserve combined AppModel/MainTabs visibility and ownership fences, simulator fixtures, Coach DTO/localization changes, and `server/coach.go` source changes when integrating Translator/passage groups. This review does not merge those branches or validate their combined release. Protocol compatibility remains additive (`time_zone` omitted means legacy free entry); first owner zone remains pinned. Existing limits remain 250 turns, 10,000 receipts/claims, 128-byte request/turn IDs, 2,000-rune input (300 for assessment), 100-byte timezone, and 60-second generation context. Storage exhaustion fails closed rather than recycling uncertain receipts. No live AI/TTS, push, deployment or release.
