# Local long-audio candidate verification

Initial candidate verification is recorded below. Independent 2026-11-11 review repeated all container gates successfully in 20.85s (long request 4.60s, peak 1091256320 bytes, zero OOM events), and verified image `/app/worker.py` byte-for-byte against source. Production backend and worker were then deployed; see `../../docs/DEPLOYMENT.md` for live acceptance. Earlier timing/resource figures below are retained as the original candidate run, not the latest run.

- Image tags: `keinemagie-podcast-worker:long-audio`, `keinemagie-podcast-worker:candidate`.
- Exact image ID: `sha256:44b2fccc4df1e32c75cab89e88a0759e72534608cfde3201faf4f1e11c27bdd8`.
- Python unit tests: 10 passed.
- Container verification: passed, total elapsed 30.26 seconds.
- Fixture: actual 660-second 16 kHz mono PCM WAV with German speech at beginning and at 650 seconds; valid RIFF JUNK padding makes upload exactly 314572800 bytes (300 MiB).
- Fixture SHA256: `e6ff1e2c4a1ce2889a2ab9b0dcf02322e5eb8c00e3ac8348cd8a7eddd58e24d4`.
- Long streamed HTTP request elapsed: 4.53 seconds. Final segment 649.8–656.4941875: “Zum Abschluss sprechen wir über die Bibliothek, in der Bibliothek lesen wir deutsche Bücher, auf Wiedersehen.” Ordered/nonoverlapping global timestamps checked.
- Cgroup memory peak: 1123385344 bytes, OOM/OOM-kill/max events all zero, under enforced 2 GiB memory/no-swap and 2 CPUs. CPU usage counter 34760097 microseconds at last sample (includes startup and earlier gates, not isolated long-request CPU time).
- Readiness uses real cached base-model silent inference. Short German transcription, missing-auth 401, oversize-header 413 (300 MiB + 1 without body), rejected manifest, contention 429, disconnect capacity recovery passed.
- Real supervisor 1-second deadline killed child and grandchild process group; decoder UID could not read root-owned 0600 token; read-only app; no published ports, internal-only network, blocked internet egress; no worker auth/transcript logs passed.
- Existing Linux Go `TestPodcastRemoteRealContainer`: passed durable claim -> authenticated real Whisper -> synthetic owner translation -> completed. Earlier runs failed while the parallel Go translation fixture was being updated; the final run passed without worker-side bypasses.

Limits: this is 11 minutes of decoded speech/silence with spoken bookends, not 11 minutes of continuous speech or a 3-hour inference benchmark. No claim of perfect recognition at a word crossing an exact chunk boundary. In-request progress is not exposed or checkpointed; final version-1 JSON adds `language` and retains `segments`. Use updated 512 MiB tmpfs/2 GiB memory settings, not the old 160 MiB/1100 MiB deployment configuration.
