# Source/feed integration handoff

Source discovery and native UI compiled and tested. Integration completed: all eight keys below are now translated in `native/App/Localizable.xcstrings` in de/en/ru/es/fr. The builder is upgraded to published `golang:1.27.3-bookworm`, and an actual network-enabled dependency/image build plus native localization/build/test gates passed. See [PODCAST-INTEGRATION-VERIFICATION.md](PODCAST-INTEGRATION-VERIFICATION.md) for artifact IDs, official-version availability, security review and exact limits. The original dependency handoff below records the pre-integration state.

| Key | Suggested German | Suggested English |
| --- | --- | --- |
| podcast.sources.expanded | Öffentliche Audiodatei oder Episodenseite mit Audio. RSS-/Atom-Feeds kannst du abonnieren. | Public audio file or episode page with audio. Subscribe to RSS/Atom feeds. |
| podcast.subscribe | Feed abonnieren | Subscribe to feed |
| podcast.discovery.privacy | Ein Abonnement lädt nur Episodeninfos. Erst „Vorbereiten“ startet Transkription und Übersetzung. Neue Folgen über „Feed aktualisieren“ laden. | Subscribing only discovers episode metadata. Prepare starts transcription and translation. Use Refresh feed to find new episodes. |
| podcast.subscriptions | Abonnierte Podcasts | Subscribed podcasts |
| podcast.subscriptions.empty | Noch keine Feeds abonniert. | No subscribed feeds yet. |
| podcast.feed.refresh | Feed aktualisieren | Refresh feed |
| podcast.unsubscribe | Abonnement entfernen | Unsubscribe |
| podcast.source.failed | Keine öffentlich abrufbare Audiospur oder kein Feed gefunden. Nutze eine Seite mit HTML-Audio oder einen öffentlichen RSS-/Atom-Feed. JavaScript-Player, geschützte Spotify-/Apple-Inhalte und Anmeldungen werden nicht unterstützt. | No public audio or feed found. Use an HTML-audio page or public RSS/Atom feed. JavaScript players, protected Spotify/Apple media and sign-in content are unsupported. |

Dependency: `golang.org/x/net/html` added at v0.43.0 (Go >=1.23). Initial v0.33.0 was rejected by real govulncheck due to reachable HTML tokenizer issue. v0.43.0 scan reports no reachable vulnerabilities (there are uncalled vulnerabilities in other packages of the module). `server/go.mod` is now Go 1.23.0; the current Dockerfile still says `golang:1.22-bookworm`, so its builder MUST be upgraded by parent/worker-deployment owner before Docker verification. Prefer an up-to-date Go builder rather than reintroducing the vulnerable parser. No Dockerfile changes made here to avoid concurrent worker scope.

Verified locally: full Go race suite; all Podcast tests with real local Whisper; Swift full package suite (46 Swift Testing + 3 XCTest); normal iOS simulator app build. Real HTTP httptest RSS discovered one episode, real HTML audio fixture fed the durable worker, real Whisper recognized German, terminal state completed/one segment/progress 100. Provider translation wire events are synthetic; no real provider inference or paid call claimed.

Manual refresh only: subscription initial discovery plus explicit refresh button, no scheduler and no automatic feed-to-AI enqueue. Public URLs still exclude queries/signed capabilities. Feed order is publisher latest-first; bounded first 50, no backfill. One HTML rel=alternate hop only; no invented Apple/Spotify endpoints.
