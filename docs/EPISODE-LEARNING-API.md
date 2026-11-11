# Episode learning API

Server contract for native and web clients. All routes are owner scoped. Browser requests use the existing session cookie; mutations require the configured same Origin and `X-CSRF-Token`. Native clients use their session bearer without Origin. No shared API key fallback. GET never invokes inference.

## Profile and actual progress

- `GET /v1/learning/profiles/de` (also `ru`): `{language,cefr,self_assessments,progress}`. Default `cefr` is `unknown`. `progress` contains `saved`, `learning`, `known`, `favorites` counts from actual vocabulary state, not inferred proficiency.
- `PUT /v1/learning/profiles/de` body `{"cefr":"B1"}`: explicit self-assessment, allowed `unknown,A1,A2,B1,B2,C1,C2`. Returns profile with append-only `self_assessments:[{cefr,assessed_at}]` (server UTC timestamps). Vocabulary actions never automatically promote CEFR.

## Saved words / idioms

- `GET /v1/learning/vocabulary?language=de&job_id=...`: `{items:[...]}`; optional filters.
- `POST /v1/learning/vocabulary`: `{job_id,segment_id,quote,term,kind,translation,notes,favorite,status}`. `segment_id` is the stable **zero-based episode segment index**, matching the transcript array. `kind` is `word` or `idiom`; `status` is `saved`, `learning`, or `known`. `quote` must be an exact nonempty substring of that owner's job segment; `term` must occur in the quote (case insensitive). Do not send timestamps or language: server derives both.
- `PATCH /v1/learning/vocabulary/{id}`: any subset of `{translation,notes,favorite,status}`; source citation is immutable. Changes to status append `{status,at}` to `history`.
- `DELETE /v1/learning/vocabulary/{id}`: 204.

Items include `id,job_id,language,segment_id,quote,term,kind,translation,notes,favorite,status,start,end,created_at,updated_at,history`. Times `start/end` are copied from the source segment, never model generated. Favorite is independent of learning state. User translations/notes are annotations, not validated provider translations.

## Detailed full-episode analysis (explicit, resumable)

- `GET /v1/learning/episodes/{job_id}/analysis`: cached/checkpoint state and cost estimate; no upstream requests.
- `POST /v1/learning/episodes/{job_id}/analysis` body `{}`: **explicit consent for at most one personal ChatGPT Responses request**. On first call or retry, preflights the remaining request plan against the same account daily translation budget (default 100/day), and consumes only the request actually attempted. Requires the complete ASR transcript (translation may still be in progress). Does not block/change the ASR/translation job.
- Response 202: one checkpoint completed, more work remains. The web Generate/Resume action explicitly authorizes the displayed remaining request-count plan and continues sequentially while the reader remains visible; every POST still permits at most one inference request. Cancel, navigation, hiding the page, or account changes abort the current request and stop further POSTs. Opening/reopening the reader only performs GETs; Resume is always explicit. A changed plan cannot exceed the originally displayed request-count bound. Network failure returns an error; completed checkpoints remain durable. A restart needs no background worker: POST resumes the next uncompleted step. A lost in-flight response may cost a retry; never replay a durably completed step.
- Response 200: complete cached result; repeated POST is a cache hit and spends nothing.

State shape: `{state,job_id,transcript_hash,cefr,recommendations_available,profile_required,completed_steps,estimate,result}`. `state` is `pending` or `completed`. `result` is null until **all** transcript chunks and hierarchical reductions are validated and saved. `estimate` contains `total_requests,completed_requests,remaining_requests,transcript_characters,max_requests_per_post` (1). This is a request-count estimate, not a dollar/token quote. Large transcripts (including 216k characters) are chunked, never silently excerpted. Reads are not a claim of inference completion.

`result` shape:

```json
{
  "narrative": [{"text":"...","citations":[{"segment_id":0,"quote":"exact source text","start":0,"end":12}]}],
  "topics": [{"title":"...","key_points":[{"text":"...","citations":[{"segment_id":0,"quote":"exact source text","start":0,"end":12}]}]}],
  "recommendations": [{"kind":"word","term":"...","translation":"...","reason":"...","cefr":"B1","citation":{"segment_id":0,"quote":"exact source text","start":0,"end":12}}]
}
```

Narrative and topic key points carry source citations. Recommendations are based on the stored self-assessed source-language CEFR and actual saved/learning/known vocabulary; known terms are excluded. With `unknown`, summaries remain available but recommendations are empty and `profile_required:true` asks the user to select CEFR. Recommendation levels are advisory model labels, never changes to the profile. Citations validate exact quote presence and stable IDs; timestamps are server-derived. Grounded citations do not prove the semantic correctness of generated prose.

Cache identity includes owner, job, complete transcript digest, source/target languages, CEFR and actual vocabulary progress. Updating profile/progress invalidates the analysis view; earlier generation checkpoints are retained for their exact input snapshot. Models receive transcript as untrusted data, structured strict schemas, and no authority to call tools. Only a strict `response.completed` SSE output with schema-valid grounded data can become a checkpoint. Unfinished/refused/invalid outputs are never ready.

Errors use `{error:"..."}`: 400 invalid input, 401 authentication, 403 browser CSRF/Origin, 404 foreign/missing source, 409 incomplete transcript, 429 budget/account busy, 502 personal provider failed/incomplete/invalid, 503 durable storage/provider unavailable. Analysis does not call shared providers and does not run implicitly on import, playback, GET, or profile changes.
