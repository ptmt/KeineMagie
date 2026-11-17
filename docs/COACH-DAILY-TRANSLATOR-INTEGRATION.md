# Coach daily + Translator: local integration, native UI/release pending

## Scope and ancestry (2026-11-17)

Clean worktree `/Users/tinyserve/Projects/KeineMagie-coach-daily-integration`, branch `integration/coach-daily-translator-local`, created from freshly fetched `origin/main` **b52c48de26f55b5f12947b3fa4240b212d2d2562**. This is the independently reviewed Translator result-controls candidate. Origin already contains true web tabs `ade5e02`, their release documentation `16fdc16`, and native podcast inline3 `5d532e9`.

Only the two requested Coach commits were cherry-picked: `61b96ed` → `f3f33dc`, then reviewed followup `e060033f31786e8e15df1b3c07a7c1aed8842b2d` → `a2adaee`. No full Coach-base merge, private work-in-progress, or passage-groups `da6d678` was incorporated. Passage groups remains a separate pending native-UI gate for the parent.

No push, deployment, Apple upload, Xcode build or simulator use. The passage-groups simulator slot (`sa-0-3e38613c`) was not touched. All provider/inference responses were synthetic transports; no product AI, paid inference, real credentials, or TTS synthesis was used. The optional Dictation HTTP fixture created only local test authentication and intercepted audio preparation/download with synthetic responses.

## Conflict and preservation decisions

There were **no textual cherry-pick conflicts**. Git automatically combined AppModel and SimulatorSessionFixture. Rather than replace entire files from the Coach branch, the resulting diff against the Translator base was reviewed:

- AppModel changes are Coach-scoped: active/visible entry, local IANA zone, pending daily cancellation identity, owner/reset clearing, and explicit matching foreground assessment feedback. Translator captured source/result pairing, current-composer preview comparison, quiet idle outbox drain, persistence and ownership fences remain in the base implementation.
- MainTabsView retains Translator/history navigation and supplies Coach visibility only when selected with neither profile nor settings covering it. Existing reduced-motion fixture handling now accepts the Coach fixture family.
- SimulatorSessionFixture retains Translator cases while adding the complete empty-Dictation envelope and controlled Coach checking delay. Localization changes are additive; native localization CI passes.
- TranslatorView (input/footer and output/footer controls, retained result on clear), PodcastLibraryView, EpisodeReaderView, and web episode modules are unchanged relative to the reviewed base. Native history's right-side controls are not replaced by Coach sources. Their integrated native visual acceptance is still pending, not inferred from source inspection.
- Coach green/red outcomes, animated checking/reduced-motion branch, explicit haptic acknowledgement, durable daily claim, Dictation pull-refresh/onboarding/saved-draft resume, and native podcast inline3 are retained.

## Independent integration checks

The fresh integrated full race run and focused daily tests exercise the real production handlers/stores. The reviewer fix is included: settled failed/canceled/unknown historical assessments do not block a new daily exercise after a later completed exercise; old pending assessments still fail closed. Existing tests prove owner separation, current-owner revocation, concurrent admission, duplicate request replay, quota accounting, no uncertain automatic retry, first-owner-zone pinning, dispatch crossing midnight, and 23/25-hour DST calendar days. The entitlement is **at most one automatic admission per owner local day**, not a guarantee of one successful exercise; existing unfinished work consumes the opportunity and explicit practice is separate.

`TestDailyEntryPersistsBeforeCatalogAndUsesProductionWire` verifies receipt + claim + pending turn are durable before catalog access, production strict `coach_turn` schema, exact personal model, `store:false`, streaming and 2400 output tokens. Its revocation branch returns 401 with zero inference. Legacy clients remain compatible; `TestDailyOptInMigratesLegacyOffersWithoutDeletingData` covers filtering old greetings without deleting stored history.

The old ambiguous patch warning is resolved in the reviewed source and remains resolved here: all three requested regressions exist in **server/coach_daily_lifecycle_test.go** (`TestDailyEntryRejectsNonExerciseResultWithoutRetry`, `TestDailyEntryResumeMidnightDSTAndReplay`, `TestDailyEntryUncertainFailureDoesNotRetry`) and passed on this integrated tree. No missing additional dailyFixture assertion was inferred or invented.

## Executed code/unit/browser gates

Evidence directory: `/Users/tinyserve/.hermes/cache/scratch/coach-integration-verification/` (logs, command/result JSON, focused Go JSONL, isolated browser artifacts).

| Gate | Actual result |
| --- | --- |
| `cd server && go test ./... -race -count=1 -timeout=240s` | PASS, server package 86.467 seconds |
| `cd server && go vet ./...` | PASS |
| Focused `TestDailyEntry` race JSON run | 16 top-level tests, 29 passing records including subtests; no failures |
| `node --test web/tests/*.test.mjs native/ci/dictation_onboarding.test.mjs` | 135 passed; zero failed/skipped |
| `swift test --package-path native/Core --jobs 2` | 61 XCTest executions, one skip, zero failures; 72 Swift Testing tests passed |
| `python3 native/ci/test_connection_lifecycle.py` | Actual production AppModel: 101 passed |
| `python3 native/ci/test_coach_daily_ux.py` | Actual production AppModel Coach/daily harness: 16 passed |
| `python3 -m unittest discover -s native/ci -p 'test_*.py'` | 54 Python tests, one skip; embedded 101-test AppModel harness passed |
| `python3 native/ci/test_coach_wire.py` | All nine actual Go Coach handler JSON fixtures decoded by production Swift DTOs |
| `python3 native/ci/verify_podcast_wire.py` | Actual Go serialized fixture + six Swift wire tests passed |
| `python3 native/ci/verify_coach_two_clients.py` | 101-test harness including two independent AppModels against actual race-enabled Go handler/store passed |
| Chromium episode tabs, compatibility, lifecycle, owner suites | All four passed: 10 locale/width cases, one AX panel, keyboard/history/search, bounded pipeline, logout/late-owner purge |
| Chromium followup suite | 37 checks passed: captured pair, clear retention, nullable-source preview, exact Unicode apply, stable retry, owner purge |
| Chromium Coach presentation | Five locales passed: correct/wrong colors, history/draft, initial/own-send scroll, resize/async growth, 200/1000-row archives |
| Chromium Dictation empty, lifecycle, form | All three passed after test-selector correction and fixture setup described below |
| Added-line security scan / whitespace | No literal credentials, shell/eval/pickle injection matches; `git diff --check` passed |

Browser interpreter: `/Users/tinyserve/.hermes/cache/scratch/coach-history-python/bin/python`. Tests with fixed screenshot paths were executed with in-memory artifact-path redirection into the integration evidence directory, not by modifying production code or overwriting earlier evidence.

### Failures encountered, preserved and resolved

1. Initial Go commands were mistakenly run from repository root (no Go module); they failed before running tests. The commands were rerun from `server` and passed. Those failed setup logs are retained, not counted as verification.
2. Existing Dictation browser tests used an unscoped exact `Add text` accessible-name locator. With the reviewed empty-state CTA, two legitimate controls share that name, causing strict-selector failure. The empty test now explicitly exercises the visible text CTA; form/lifecycle tests scope to the header add button. All three had observed failures before this test-only correction; no production behavior was changed.
3. Form/lifecycle scripts require a live opt-in local fixture. Initial attempts had no fixture, then an origin mismatch correctly denied writes. Reruns used the existing compiled Go `TestDictationLocalFixture` with a fresh scratch store per suite and **WEB_ORIGIN=http://localhost:8799**, plus DICTATION_FIXTURE_DIR and DICTATION_BROWSER_ARTIFACT_DIR. Both passed. The fixture processes were terminated afterward. Authentication/CSRF checks were not weakened, no real TTS was invoked, and denied-write attempts are not recorded as passing tests.

## Isolation and remaining gates

The original main worktree remained at 59 dirty entries with the same porcelain status, and the Coach and Translator source worktrees remained clean. All source worktree status snapshots matched discovery except passage-groups, whose concurrent worker added an EpisodeReaderView modification during this run; this integration did not write there, reset it, or copy its work. No force reset/stash was used. The final integration worktree alone contains the local commits and test-selector/documentation changes.

The requested source commits had prior independent reviews; this integration performed fresh diff/security review and executed the gates above. No additional reviewer subagent was available in this focused subagent run; do not interpret the commit as a new independent native-UI signoff.

**Ready for the parent's integrated native UI pass; release remains pending.** macOS harnesses do not typecheck SwiftUI for iOS or prove real gestures, native footer geometry/icons, haptic feel, keyboard, or OS Reduce Motion. No new native screenshots were produced. Parent must finish passage-groups native tests, merge it separately, resolve its overlapping fixtures/source behavior, then rerun relevant combined tests and native Release acceptance before any push/deployment/upload. Translator release work in progress was not interfered with.
