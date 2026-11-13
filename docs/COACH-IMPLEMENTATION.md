# Coach implementation and release

## Status

Integrated Go API, web Coach tab and SwiftUI Coach tab; independent follow-up review completed locally. The user reauthorized publication with “выкладывай”. Release readback is recorded below after execution; local tests alone do not establish deployment or Apple upload.

No real owner credentials, personal source content, provider catalog or inference were used in testing. Production has no fixture fallback. Existing sign-in feedback and fixed 30-day **new browser session** issuance remain unchanged. No domain migration, translation-history rewrite, passage deletion or CEFR reassessment is included.

## Contracts and privacy

`GET /v1/learning/coach` reads saved state only. `POST` takes bounded `request_id`, `action`, `text`, `turn_id`, `locale`. Actions: message, answer, skip, reveal, review, reset, cancel.

- Existing browser-cookie authentication, exact-origin CSRF and native bearer gates; each durable Coach write revalidates the exact session under the auth-store lock, serializing with revocation.
- Owner-hashed JSON, process-cooperating file locks, atomic fsync/rename, private permissions. No persistent browser chat cache; native uses existing protected owner cache/provenance for read-only offline access.
- Exact personal catalog match for **`gpt-6.1-terra`**, same owner token for catalog and Responses. No global chooseModel, paid/shared fallback or automatic inference on GET, navigation, reload or cache hydration.
- Shared translation-attempt reservation (configured default 100/day UTC); one durable charge immediately before one bounded Responses request. Missing connection/catalog/model/source does not charge. 60-second context, 2400 output-token cap, `store:false`, `stream:true`, strict `text.format` JSON schema, no tools.
- Bounded retrieval: up to 12 eligible saved sources, including up to six explicitly marked, still-matching podcast passages and recent saved translation results. Each source at most 1800 Unicode code points. Unsaved transcript segments and vocabulary favorites are not implicit sources.
- Sources and user messages are untrusted data. Server rejects unknown/duplicate/case-variant keys, wrong shapes, enum/length violations, foreign source IDs and fabricated quotes. Exact contiguous quotes are independently validated.
- Accepted/incorrect answer arrays remain server-private. Quote/explanation and original-source navigation become available after attempt or explicit assisted reveal. Clarification conservatively marks earlier unanswered exercises assisted. Visible exercise text containing a normalized accepted-answer word sequence is rejected; this is not a semantic proof against every paraphrased hint.
- Exact accepted/known-incorrect matching only; unrecognized free answers abstain. No hidden second grading call.
- Durable receipts suppress repeated inference and reject changed payload reuse. Pending/failed/unknown responses never retry automatically. Cancel persists a terminal result and fences late output, including a **pre-admission cancellation tombstone during slow catalog discovery**. Already-dispatched upstream work may still consume quota until cancellation/deadline.
- Storage bounded to 250 turns / 10,000 action receipts per owner, without automatic deletion.

## Official routing/schema verification (documentation + fixtures only)

Re-read official contracts during review:

- [GPT-6.1 Terra model](https://developers.openai.com/api/docs/models/gpt-6.1-terra): exact ID `gpt-6.1-terra`, Responses, streaming and structured outputs supported; text/image input, text output, no audio.
- [ChatGPT account models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference.md): selected-account `GET https://api.openai.com/v1/models`, `models[].slug` with `visibility:list`; same token to public `POST https://api.openai.com/v1/responses`, required `store:false` / `stream:true`, success only on completed event.
- [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs): Responses `text.format`, `type:json_schema`, `strict:true`, root object with all properties required and `additionalProperties:false`.

Real-handler synthetic transport asserts exact model/endpoint/store/stream/token cap/strict schema/no tools. Existing shared Responses parser rejects incomplete/refused/invalid events. **Public metadata plus wire fixtures are not the selected owner's entitlement or real output-quality verification.** Missing Terra produces a typed localized failure, not another model.

## Learning evidence

Twelve concrete skill IDs across five dimensions: case; gender/article; adjective agreement; tense/aspect; verb preposition+case; verb object case; collocation; word choice; word formation; main-clause order; subordinate-clause order; formality. New generated results must use a concrete ID. Historical broad IDs remain readable without inventing more specific evidence.

Observations group by language and skill and show answer count, distinct source examples, independent correct/needs-practice counts, assisted count and conservative limited confidence. Attempts retain original/current outcome, answer, source identity/quote, timestamp, assistance, correction timestamp and exclusion. Review controls correct or exclude individual observations. Reset timestamps exclude earlier evidence without deleting the conversation or altering self-assessed CEFR. No inferred speaking/listening/global CEFR mastery.

## Clients and source navigation

- User/coach bubbles with inline cloze, preposition/case and short-rephrase exercises, clarification composer, skip/reveal/review/reset/cancel. Restrained entry/feedback/disclosure motion; reduced-motion branches on both platforms.
- Web keeps stable keyed bubbles during updates rather than recreating the conversation and replaying every animation. Existing input nodes/drafts survive. Mobile scroll region and visualViewport-aware bottom composer; text-only DOM rendering.
- Citation links only accept exact local source identifier forms. Web translation links focus the full saved history row without overwriting the translator draft; podcast links preserve section/segment through canonical permalink replacement and jump to the exact transcript segment. Browser Back restores the originating Coach source control in the same page session. Links reload under normal owner authentication.
- Native citation navigation opens the saved original translation or existing episode reader at the cited segment; native Back returns to the conversation. Missing/deleted/noncached sources show a localized unavailable state. No invented source content.
- AppModel owns/coalesces mutations, independently fences older reads, ignores uncancellable late results after owner/session reset, and persists acknowledged snapshots. Offline reads never enable inference.
- User-facing admission/network errors are typed, allowlisted and localized in all five UI languages; unknown provider bodies are never displayed. Concrete skill labels and source navigation are likewise localized.

## Independent review fixes and actual verification

Reproduced RED → GREEN: web cancel releasing its mutation slot before acknowledgement; raw English/upstream errors on both clients; broad-only generated skill taxonomy; cancellation during slow catalog admission returning conflict and allowing late dispatch; missing citation target parsers/navigation; whole-chat DOM replacement replaying animations. Browser exercise exposed query loss during podcast canonicalization, now preserved.

Final local executions (synthetic transport, not live inference):

- Full Go ordinary suite, full `go test -race ./...`, `go vet ./...` passed. Targeted Coach tests include CSRF, owner isolation, exact-model gate, Responses/schema wire assertions, source-mark admission, quota/receipt paths, duplicate suppression, revoked session, late cancel, slow-catalog cancellation, answer-key hiding, grounded validation, ambiguous/wrong/skip/assisted/deduplicated evidence, corrections/exclusion/reset.
- **76 Node tests passed**. Full-shell Playwright synthetic HTTP verifies correct/wrong/ambiguous/skip/reload/cancel, translation focus+reload, podcast segment 2012 and source-control return, stable bubble identity, five locales, 390px composer, reduced-motion CSS, logout/private draft clearing and no JavaScript errors.
- Swift Core: **65 Swift Testing + 15 XCTest** passed, including source ID rejection and typed error privacy.
- Native CI: **45 tests, one built-plist environment skip**; separate actual Release plist rerun **3/3 passed**. Actual AppModel harness **31 tests passed**, including slow read vs fast save, canceled late send, 401 clearing, duplicate coalescing, offline cold cache and reset fences.
- Release iPhone 17e / iOS 27.2 XCTest: **4 tests passed**. Correct/clarification and real software keyboard geometry; original translation navigation+Back; wrong/ambiguous/skip/cancel; max Dynamic Type/profile. Repeated with actual simulator dark appearance set and restored afterward. Screenshots visually inspected; initial appearance argument alone had remained light and was not counted as dark proof.
- `git diff --check` passed. Existing Apple sign-in/30-day session changes are retained; no signing/deployment configuration changes.

Evidence under `/Users/tinyserve/.hermes/cache/scratch/` (ephemeral): `coach-review-go.log`, `coach-review-go-race.log`, `coach-review-web.log`, `coach-review-native-ci.log`, `coach-review-core.log`; `coach-browser/{desktop-feedback,citation-return,mobile-reduced-motion}.png`; `coach-review-final-ui.xcresult`; `coach-review-final-attachments/` (manifest maps eight actual UI captures); `coach-review-derived/Build/Products/Release-iphonesimulator/KeineMagie.app`.

## Remaining limitations, not release claims

- Owner catalog entitlement and pedagogical quality require an explicit owner-started Coach message. No real inference was authorized or spent by release verification.
- No physical iPhone/mobile Safari keyboard or full VoiceOver traversal. Native reduce-motion branch is implemented but not separately toggled in XCTest. Maximum text is scrollable rather than fitting a whole exercise on one screen.
- Native source navigation uses already loaded/protected cached history/jobs; an unavailable older source asks for history refresh. Native passage-mark creation remains a pre-existing parity gap; Coach consumes web-created marks.
- Retrieval/context is deliberately bounded (six recent exchanges). No full-history search/picker, multi-chat archive, new-chat deletion or elaborate mastery prediction. Drafts are memory-only across cold restart.
- Historical source quotes remain in Coach when an original source is later deleted; original navigation fails closed. No cascading source deletion or final-commit source revalidation. Corrections keep original/current/latest timestamp, not a full multi-edit audit log.
- Exactly-once upstream inference/refunds are not guaranteed; a crash between durable charge and send is conservatively one spent attempt. A recovered pending turn may require explicit cancel.

## Integration scope

`server/coach*.go`; learning router/static allowlist/Docker assets. `web/coach{,-state}.mjs`, `coach.css`, shell integration and tests. `native/App/CoachView.swift`, AppModel/MainTabs/Profile/episode navigation, Core Coach/API, five-language catalogs and simulator-only tests/harness. Isolated `spikes/` and `docs/DOMAIN-MIGRATION-PLAN.md` remain untracked and excluded from release.

## Release execution

Released source **`e0456d12a9e04a0a7243279b6cfbcaf83909e19d`** (includes prior sign-in feedback and fixed 30-day new-session changes).

- Server publication [43426909526](https://github.com/ptmt/KeineMagie/actions/runs/43426909526), job `131890450794`: **success**. Existing host uses the documented local arm64 Compose workaround, not that separate registry artifact. Built only from a clean `git archive` of the combined source with network-disabled build steps.
- Running backend **`sha256:031c5cec14b0cb632fef24d5fee97b0f6d36eb106bbfd0cb1feeead290c320cc`**; exact OCI revision above. Worker unchanged **`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`**. Full merged config changed only backend image; worker/unrelated container IDs, environment, resources, canonical mounts, routing labels and private network unchanged.
- Locked preflight: **0 active jobs, 1 completed job, 1 subscription, 2113 saved segments and translations**. All **8 non-runtime durable files byte-identical** after replacement. Private backups and before/after evidence: `/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/release-coach-20261113T123910Z/`. No owner retries/reset/inference. Rollback retains prior backend `sha256:ebf21a142a082a4f266f1d83ad91268ba4cf4f265338791b808d712583e4da9e`; restore only its image pin using saved `compose.previous.yml`, never historical data.
- Public certificate-validating HTTPS health **200**; guest session/Coach/podcasts/subscriptions **401**; server source and isolated spike routes **404**. All **21 public runtime assets** exact bytes/SHA256 against the clean committed archive. Strict CSP and no-store preserved. Actual public guest Coach renders real signed-out UI, zero private exercises and disabled composer; 390px mobile has no horizontal overflow. No account login or provider request used.
- iOS [43426909482](https://github.com/ptmt/KeineMagie/actions/runs/43426909482): **success** for exact source. Validate job `131890450681`; upload job `131892233178`. Signed archive/export succeeded, build **`2735.81.58`**, explicit Apple **`UPLOAD SUCCEEDED with no errors` at 2026-11-13 12:48:21Z**; signing cleanup succeeded. Apple processing/tester availability/physical installation remain unverified.

No domain/worker/signing workflow migration. `spikes/`, `docs/DOMAIN-MIGRATION-PLAN.md` and Python caches were excluded from the scoped source commit.
