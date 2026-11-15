# Coach contextual actions — reviewed release

Parent approved deterministic grounded progress facts plus a strictly allowlisted Terra next step. Full-sentence correction stays deferred because `corrected_answer` may be a fragment. Release finalizer freshly fetched the unchanged `d807d5726ba138ec51d67d39079ed3d3c4d9719f` baseline and re-exercised full Go race/vet, 105 Node, 53 native Python CI tests (one built-plist skip), actual 81-case AppModel and nine-state Go→Swift contracts, and Swift Core. Full native CI caught a localization scanner treating the dynamic `coach.quick.` prefix as a literal; fixed scanner excludes concatenations and explicitly requires all five complete action keys. No runtime or translation change was needed. Delivery evidence follows after backend-first release verification.

## Delivery — 15 November 2026

- Source **`40a1c25146f2fafd853354ca131781b3bd60b7a3`**, scoped 31-file commit, normal non-force push over the freshly fetched baseline; remote exact SHA read back. All other worktrees' dirty status and file hashes remained unchanged, including original main.
- [Server CI 43749461298](https://github.com/ptmt/KeineMagie/actions/runs/43749461298) **success**, build job **132919943777**. Published native **ARM64** image **`sha256:4e40ce1a54d6152b17edbf9f1658bdc49b60f0d5b116f260bde2da020154feba`**, exact OCI source revision verified and deployed **before** explicit native upload.
- Current durable base + `compose.translator.yml`: merged configuration changed **only backend image**. Worker/unrelated container IDs, all env, mounts, security/resource settings, routing labels and edge/private network membership preserved; Traefik network fix retained. TTS key read-only, readable as UID **65532**, owner **65532**, mode **0400**; no contents exposed. tinyserve registration remains the previously documented local-image lifecycle caveat; do not run a bare regenerating deploy that omits the durable override.
- Store/account locks held through replacement; stopped-backend global runner lock used for private backup. Fresh inventory: **17 nonruntime files byte-identical**, no additions; **1 completed podcast, 0 active, 2113 segments and translations**. Single November ledger entry/acceptance ID, **$1 reserved / 826 micro-USD reported / at most 9 new attempts** unchanged. No provider/TTS calls, automatic inference, retries, data resets or historical restores.
- Public certificate-validating HTTPS `/health` **200**, **28/28 public assets exact** with expected cache policy. Private Coach, Diktat/audio, podcasts/history **401**; key/source/env/ledger probes **404**. Real deployed Chromium mobile-dark guest Coach: no runtime errors, one disabled practice control, no horizontal overflow. Existing top-edge shell clipping remains; signed-in production inference was not exercised.
- [Native push validation 43749461390](https://github.com/ptmt/KeineMagie/actions/runs/43749461390) **success**, validate **132919944072**, upload correctly skipped. Then exactly one explicit `publish=UPLOAD`: [43749962713](https://github.com/ptmt/KeineMagie/actions/runs/43749962713) **success on exact source SHA**, validate **132921528276**, upload **132922916676**, build **2755.39.35**. Apple **`UPLOAD SUCCEEDED with no errors` at 19:09:23.608656Z**, signing cleanup success. Local watcher timed out; resumed the **same run**, no duplicate dispatch.
- Fresh local full Go race/vet, **105 Node**, two synthetic Chromium suites, **53 native Python CI** (one built-plist skip), **81 actual AppModel**, **9 Go→Swift states**, Core **52 XCTest** (one existing skip) + **69 Swift Testing** passed. Hosted unsigned simulator build and actual built-plist metadata also passed. Previously reviewed Release five-locale + largest-type light/dark/keyboard/AX/arrival/Reduce Motion evidence below was retained; no runtime native source changed during finalization.
- Private deployment backup/readbacks: `/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/release-coach-contextual-20261115T190023Z/`. Minimal release logs/public checks: `/Users/tinyserve/.hermes/cache/scratch/coach-contextual-release/`. Previous image `sha256:689afba605775682865705f352e0338bd2734eae44fd00f01236f48727b2c949` retained for binary-only rollback; never restore stale data.

Apple processing, tester availability, physical-device installation/VoiceOver and real personal Terra recommendation quality remain unverified. No domain migration or App Store Review submission. Full-sentence corrected presentation is deliberately not invented. Existing Translate shimmer, off-main durable-before-POST persistence and async owner leases are untouched and passed actual-model regressions.

The candidate-stage statements below are historical verification context, not current delivery status.

## Scope and baseline

Isolated worktree: `/Users/tinyserve/Projects/KeineMagie-coach-actions`, branch `coach-contextual-actions`, fetched `origin/main` at `d807d5726ba138ec51d67d39079ed3d3c4d9719f` (contains `288ae17a831e203033cc02368c96cf667d76e8a8`). Original worktree's dirty Dictation and other changes were not copied or modified. No commit, push, deployment, real credentials or paid inference.

The supplied screenshot was inspected with vision. Source confirms the duplication: both `CoachTurnView`/web offer bubble and unconditional composer rendered the same practice action. It was not a user transcription. Offer bubbles now contain text only; composer is the single action location. Context is derived on the server from retained structured state, not parsed localized assistant prose.

## Context table

| State | Composer actions (localized independently of exercise language) |
|---|---|
| Empty or free entry offer | 30 seconds |
| Unfinished exercise | Hint, My progress; no new exercise |
| Hint already disclosed | My progress (hint remains in its source disclosure) |
| Correct or skipped | More, My progress |
| Incorrect / uncertain | Explain, More, My progress |
| Failed assessment | My progress; existing explicit recheck stays in exercise menu |
| Failed / canceled generation | More, My progress |
| Pending generation / assessment | No server actions; local pending operations disable submission, not editing |
| Progress response / clarification, no unfinished exercise | More, My progress |

Five locales: en, de, ru, es, fr; maximum three plain controls, 44-point/pixel height. Empty legacy snapshots use only practice fallback; nonempty snapshots without the new optional actions field omit shortcuts until refreshed. Released clients ignore the additive field; progress uses existing clarification kind (no new kind).

Entry and viewport receipts remain free. Five-hour admission remains authenticated, server-timed and durable, and suppresses offers over unfinished exercises. No hidden AI on open/reload. Hint is a free explicit reveal with assistedness, not generation. Explain is explicit generation constrained to clarification. More excludes the last source if an alternative exists and rejects an identical recent prompt without retrying. Ordinary messages during an unfinished exercise are constrained to clarification. Existing Skip is the explicit way to finish/abandon an exercise before requesting another; there is no new cancel-confirmation UI.

Canned action text is captured independently of composer contents. Web rapid-tap test proves one progress POST; actual AppModel harness proves native coalescing/draft retention using the new progress operation. Durable receipt identity stays exactly as submitted, including legacy `message` text aliases (`Фидбек`, `Мой прогресс`, `Ещё`, corresponding localized labels). Inference uses the existing personal Terra catalog/admission/100-per-day quota, cancellation, revocation and durable receipt path; no new provider.

## Progress evidence

`progress` is an authenticated explicit Coach POST, not a new read-triggered inference. The model receives bounded aggregates, never raw translations, dictation drafts/audio, owner IDs or private source IDs:

- Translation usage: latest 100 retained owner records, creation timestamps; no correctness inference.
- Coach: retained completed, nonexcluded answer snapshots since observation reset; original assistedness and existing grammar/vocabulary observations (counts, distinct examples, correct, needs-practice, assistance, recency). Pending/failed assessments are not evidence. No regrading.
- Saved vocabulary: retained item count, self-reported saved/learning/known counts, latest-update recency; not mastery.
- Saved podcast passages: retained owner passage count; no timestamps exist, so recent count is omitted. Saves do not establish listening ability.
- Dictation: read-only, bounded adapter for the separately developed owner `dictations/<owner-hash>/history.json` format. Uses checked flag, item creation time, assisted flag and recorded difference count only. Missing, corrupt or inaccessible data is **unavailable**, with count omitted, never fabricated zero. Current format stores the latest check per item, not attempt history, check timestamps or standardized scores. This candidate does not claim all-attempt score trends. Adapter intentionally does not import uncommitted Dictation implementation.

Progress facts are now deterministic localized server text, not model prose. The model can return only an allowlisted `next_step` enum (`practice`, `review`, `save`); invented numeric prose, including spelled-out quantities, fails the response and adds no claims. Counts, self-reported vocabulary statuses, Coach correct/repeat evidence and latest Dictation difference totals are rendered directly from the owner snapshot in all five locales. This deliberately sacrifices free-form AI strengths/trends rather than claiming that schema-valid prose is fact-checked. No regrading or new assessment architecture. Live recommendation quality remains untested because inference was forbidden.

## Verification and evidence

Executed locally with synthetic transports only:

- Go full `go test ./...`; full `go test -race ./...`; `go vet ./...`: pass. New state, owner coverage, missing/corrupt Dictation, explicit progress/replay, legacy text replay, different-source More and stale-More rejection tests.
- Web full Node suite: 105 pass. Coach-focused suite: 13 pass. Real Chromium mobile/dark contextual browser: one offer button/no bubble button, progress after saved feedback, one rapid-tap POST, retained draft, no horizontal overflow, 44px actions. Existing Coach browser regression passes keyed-bubble identity, no hydration animation, unread/visibility receipts, scrolled-up preservation and reduced motion.
- Swift Core suite ran successfully (51 XCTest cases, one existing podcast fixture skip, plus 69 Swift Testing cases); subsequent Coach subset: 13 pass including new optional-action/cache compatibility.
- Actual AppModel lifecycle harness: 81 Swift Testing cases pass; progress coalescing retains draft; owner replacement/revocation/cancel/cache tests retained.
- Actual Go HTTP JSON decoded by production Swift DTOs: nine states, including progress, offer, pending, failure and legacy. Compact native localization contract tests: 2 pass.
- Release XCTest `testContextualChipsAndProgressRetainDraft`: passed on iPhone 17 Pro, iOS 27.2, exact simulator `775A82E7-8B2D-4117-B3DE-2BAFDD234E48`, in light and actual simctl dark appearance. One executed test per result, not zero-test success. Assertions include no practice over active exercise, feedback -> dynamic actions, draft unchanged and summary frame above composer while keyboard is open. Appearance restored to light.

Runtime screenshots (synthetic, no private data):

- `/Users/tinyserve/.hermes/cache/scratch/coach-contextual-evidence/web-offer-mobile-dark.png`
- `/Users/tinyserve/.hermes/cache/scratch/coach-contextual-evidence/web-after-feedback-mobile-dark.png`
- `/Users/tinyserve/.hermes/cache/scratch/coach-contextual-evidence/web-progress-mobile-dark.png`
- `/Users/tinyserve/.hermes/cache/scratch/coach-actions-native-evidence-3/4C286FC3-A468-43BE-AC3F-3F521A0AC58B.png`
- `/Users/tinyserve/.hermes/cache/scratch/coach-actions-native-evidence-3/6ED6DAE9-E388-46B4-B6B8-1935B00869FE.png`
- `/Users/tinyserve/.hermes/cache/scratch/coach-actions-native-dark/1C35FEE3-BAC3-4737-9A37-873251625097.png`
- `/Users/tinyserve/.hermes/cache/scratch/coach-actions-native-dark/F08D84BA-7429-4277-A826-68FE80F03A4A.png`

Screenshots were vision-inspected. Initial native progress capture exposed insufficient following with keyboard open; explicit quick replies now follow their result without clearing or blurring the draft. Final XCTest asserts geometry without manual scrolling. Normal scrolled-up receipt behavior is unchanged. The web shell header can remain slightly above viewport after focus (existing shell scroll behavior); message/actions do not overflow. Native earlier history can scroll behind the translucent navigation bar normally. Existing unrelated XCTest actor warnings remain.

## Remaining acceptance / review gates

- Independent finalizer reviewed and corrected the local candidate; parent final review remains required. Fresh `git fetch origin main` still resolves `d807d5726ba138ec51d67d39079ed3d3c4d9719f`. Original dirty main worktree was untouched; no commit/push/deployment.
- No live model accuracy, deployed auth, production runtime, physical device or delivery verification.
- No all-attempt Dictation scores exist in the observed format; adding real score histories requires coordination with that separate work, not fake metrics.
- Finalizer reran all five native locales at maximum accessibility Dynamic Type with keyboard and exact draft in Release, in actual light and dark appearance. Initial horizontal labels split into syllables (116–175pt heights); a RED height assertion reproduced it. Native vertical fallback passes the same assertion and screenshots show complete labels. Ordinary five-locale feedback, AI assessment pending/correction, accessibility hierarchy and explicit progress geometry also passed. Existing motion/seen and injected Reduce Motion branch tests reran; frame-by-frame motion was not re-recorded.
- Corrected full-sentence primary presentation remains intentionally deferred: current `corrected_answer` contract permits a gap fragment or a rewritten full sentence; there is no authoritative template/slot contract. Blind replacement can invent syntax. Existing fragment display stays unchanged for parent decision. Post-answer instruction repetition is removed in both clients; human source links already distinguish saved translations/passages and open their exact original targets.
- Finalizer evidence: `/Users/tinyserve/.hermes/cache/scratch/coach-largest-green-2.xcresult` (2 passed tests, including five-locale largest loop and exact-draft/result geometry); `/Users/tinyserve/.hermes/cache/scratch/coach-largest-dark-green.xcresult` (3 passed, including five locales plus arrival/seen and injected Reduce Motion); screenshots exported to matching `coach-largest-green-shots` and `coach-largest-dark-green-shots` directories. Earlier finalizer five-test light bundle: `coach-final-light.xcresult`. Largest light/dark screenshots inspected visually; no syllable fragmentation remains. Scrollable conversation has little height with largest fonts and keyboard, but fixed actions/composer remain readable.
- Rerun Go full race + vet passes; Node 105 passes; AppModel 81 passes; Swift Core 52 XCTest (one existing skip) plus 69 Swift Testing passes; Coach 13; Go→Swift nine states; compact localization two. Both synthetic Chromium contextual and chat regressions pass via existing `coach-chat-venv` interpreter (system Python lacked Playwright). No credential or live inference/TTS access.
