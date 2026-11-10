# Translation styles and saved shortcuts

`POST /v1/translations` accepts an optional `instructions` JSON string on both
account and legacy token routes. Omit it (or send an empty string) for the existing
translation behavior. The maximum is **1,000 Unicode code points**, not UTF-8
bytes or UTF-16 code units. `null`, nonstrings, oversized instructions, unknown
fields, malformed JSON and additional JSON values are rejected with HTTP 400.
The existing source text and language limits still apply.

```json
{"text":"Hallo","source_language":"de","target_language":"ru","instructions":"Use a formal, professional tone."}
```

Instructions are user-level **translation style preferences**. Trusted provider
instructions limit them to tone/register/wording/formatting while preserving
meaning, the translation task and the strict output schema. Source text remains
data, never instructions. This is prompt-level containment, not a guarantee that
an upstream model can never misbehave. Account-provider Responses still decode exactly
one strict `{"text": "..."}` envelope; literal translated JSON is never recursively
unwrapped. The legacy provider retains its existing enriched translation schema.

The exact instructions string is saved with the resulting history record and
returned on POST/GET for reproducibility. No extra style-name/ID API fields are
required. Empty instructions are omitted. Old history is unchanged and clients
that ignore unknown JSON fields remain compatible. Editing/deleting a shortcut
does not mutate previous history; web reopening restores the saved snapshot,
including an “Aus Verlauf” chip when no current shortcut matches.

## Local shortcut storage

The web translator provides Standard, Freundlich, Formell and named custom styles
with add/edit/delete. Only `{id,name,instructions}` user text is serialized to
`keinemagie:translation-prompts:v1:<encoded owner ID>` in localStorage. The owner ID
comes from authenticated `GET /v1/web/session` → `user.id`, backed by the server's
stable account identity; neither email nor bearer/session tokens are storage keys.
The store does not receive or serialize credentials or CSRF tokens. Names are
limited to 60 Unicode code points, instructions to 1,000, and custom entries to 50.
Storage errors produce visible save/delete errors; built-in styles still work.

Logout, session expiry and owner changes clear selected style, custom chip DOM,
editor contents, input/result/history and any open editor. Per-owner saved text
remains in this browser for that same account's next session. This is namespace
isolation, **not encryption or protection from someone with local browser access**.
Do not store secrets in shortcut text. The selected instructions are sent to the
translation provider and saved in server history only when translating.

Native clients use their own local same-device store. Web/native custom shortcuts
are not synchronized initially. Server history does retain the actual instructions
used across clients; this is not shortcut-library synchronization.

## Verification

- `cd server && go test ./...` (including request validation, prompt boundaries,
  structured output, legacy route compatibility, owner history restart/readback).
- `node --test web/tests/*.test.mjs` (Unicode contract, safe persistence, CRUD,
  cross-account UI clearing, historical snapshots and existing model gating).
- `web/tests/styles_browser.py` is an explicitly synthetic browser fixture for
  UI and screenshot checks, not proof of live consent or provider inference.
