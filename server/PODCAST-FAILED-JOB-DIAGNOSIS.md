# Read-only terminal job diagnosis

Authoritative live `/app/data/podcasts/jobs.json` was read from `tinyserve-keinemagie-1` via in-memory `docker cp` tar parsing. Only aggregates and bounded safe stored error fields were printed. No transcript, identifiers, provider credentials, retry/cancel/delete, quota changes or inference requests were issued.

Observed retained job: `failed`, progress `72`, `2113` transcript segments, `954` nonempty translations, attempts `1`, updated `2026-11-11T11:06:00.93491663Z`. Exact persisted safe error:

```
personal batch translation failed or incomplete; saved progress retained
```

No `code` field was stored. The authoritative translation quota record held `18` attempts dated `2026-11-11`; running backend configuration was `TRANSLATION_DAILY_ATTEMPTS=100`. Thus daily personal quota exhaustion is **not** the observed explanation. Existing code emits a different error for insufficient whole-plan quota; this job failed inside an attempted translation batch. The deployed wrapper collapses transport timeout, incomplete/refused Responses SSE, and invalid segment mapping into that same stored string. Those sub-causes **cannot honestly be distinguished from the retained store**; no invented timeout/invalid-map attribution.

Regression `TestPodcastFailed2113Segments954TranslationsResumeAfterQuotaReset` uses entirely synthetic text and Responses SSE, reproducing the retained shape without reading live text. It proves all 954 saved translations survive; exhausted same-day quota sends no inference; prior-day quota becomes eligible but does not auto-retry a terminal job; explicit Retry resumes only the 1159 untranslated segments with no refetch or ASR and preserves saved strings. The live job remains failed and unchanged; user must explicitly request any live retry.
