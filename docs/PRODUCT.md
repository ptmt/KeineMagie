# Keine Magie — product specification

## Goal
A native iOS companion for learning German from the learner's own translations, texts and podcasts. SwiftUI client, Go backend hosted on this Mac through tinyserve. The legacy Expo app has been removed (available in Git history); native development lives in `native/`.

## Four tabs

### 1. Translator
- German ↔ Russian initially (Russian is an initial assumption based on the request; other native languages later).
- Two language panels, swap direction, editable input and selectable result.
- Persist translation history; reopen earlier results.
- Explain idiomatic rather than merely literal meaning, with usage examples.
- Extract useful vocabulary and grammatical/lexical patterns.
- Later: aggregate repeated vocabulary/patterns across history, with provenance and frequency. Token frequency is not lemma frequency; idioms/patterns are model annotations, not deterministic linguistic truth.

### 2. Dictation
- Paste German text; segment into sentences without naively splitting common abbreviations.
- Read a sentence, replay, navigate, reveal original; configurable speed, pauses and repeats.
- OpenAI TTS first, using the existing Go audio proxy and cache.
- Later: typed attempts, word-level comparison, mistake persistence and review.
- Make synthetic speech explicit. Assess voice quality with German listening samples before selecting a production default; no quality claim based on model name alone.

### 3. Podcasts and shadowing
- Import audio or an episode; transcribe with timestamps.
- Preparation view: aligned original/translation, idioms, vocabulary.
- Playback, sentence/segment looping, speed control, follow-along highlighting.
- Shadowing: listen → pause/repeat → record attempt. Scoring only after a separate validated implementation.
- Long files require bounded uploads, async jobs, chunking, cancellation, retry and cost estimates. Do not fetch arbitrary user URLs without SSRF protections; prefer file upload for the first iteration.

### 4. Coach
- Consume permissioned learning events from all three workflows.
- Explain recurring difficulties and recommend a short next exercise with evidence from actual activity.
- Never fabricate progress, errors or a learner profile when no data exists.
- Proactive reminders opt-in, quiet hours, snooze and frequency limits.
- Local notifications first; server-originated pushes later need APNs credentials, device registration and scheduled jobs. Permission must follow an explicit user action.

## Payments and providers
OpenAI API first. ChatGPT and API billing are separate, but eligible Pro and Business subscriptions can now activate promotional API credits for one linked API organization; Plus is not included in that benefit. Activation, eligibility and the actual grant must be checked. An API key is still used for these API calls, but separate paid API credit purchases are not necessarily required. Eligible partner tools can also use opt-in ChatGPT subscription sharing; do not assume a new independent app automatically qualifies.
Sources:
- https://help.openai.com/en/articles/20001626-api-credits-benefit-for-eligible-chatgpt-subscriptions
- https://help.openai.com/en/articles/20001542
- https://help.openai.com/en/articles/8156019-is-api-usage-included-in-chatgpt-plus

Initial distribution is a single-user private deployment with a server-held API key. No App Store purchase or ChatGPT login is implemented. Future options: user-supplied API credentials stored securely on the backend, OpenRouter where supported, or an app subscription backed by StoreKit entitlement verification and server-side quotas. Subscription pricing must account for audio minutes and tokens. Do not promise unlimited usage.

## Milestones and acceptance
1. **Foundation / first vertical slice**: SwiftUI four-tab shell; real translation request and idiom/pattern/vocabulary result; durable server history; pasted-text dictation through existing TTS; core tests and Go tests; documented setup. Podcasts/coach explicitly marked planned. iOS build is a separate gate requiring Xcode.
2. **Learning loop**: aggregate analytics, typed dictation attempts and errors, local reminders, data export/deletion.
3. **Podcast preparation**: file upload, queued timestamped transcription, aligned translations, playback and looping.
4. **Coach**: event-based recommendations with evidence and controllable proactive notifications.
5. **Distribution**: per-user identities and isolation, quotas, billing, production observability, backup/restore and App Store/TestFlight checks.

## Open product decisions
- Learner's level and preferred explanation language (initial UI Russian; German learning content).
- Whether this remains personal or becomes a multi-user product.
- Podcast import sources and expected episode duration.
- API budget / per-day limits; a provider dashboard budget may not act as a hard cap, so implement an application quota before public access.
