# Resume contract — backend ACK

Backend implementation owns persistent encoded media and transcript checkpoint storage. Python worker counterpart must implement this exact opt-in protocol; no worker cache/volume is necessary. Parent: please coordinate the Python child against this file now.

POST /internal/podcast/transcribe retains Authorization Bearer and X-Podcast-Version: 1, X-Podcast-Language: de|ru, application/octet-stream full original encoded upload with Content-Length. New headers: Accept: application/x-ndjson; X-Resume-Offset: integer seconds (0,600,...,10800); X-Podcast-Job-ID: opaque stable backend ID; X-Media-SHA256: lowercase SHA256 hex of original bytes. IDs/digests are metadata, never filesystem paths. Backend handles identity/config binding; worker is stateless.

Response 200 Content-Type application/x-ndjson, one flushed JSON object per line:

{"type":"checkpoint","chunk_index":0,"end_seconds":600,"segments":[{"start":0.0,"end":2.0,"text":"speech"}]}
{"type":"checkpoint","chunk_index":1,"end_seconds":660.0,"segments":[{"start":650.0,"end":652.0,"text":"last marker"}]}
{"type":"complete","duration_seconds":660.0,"language":"de"}

chunk_index is absolute zero-based 600-second window index; first equals resume_offset/600. end_seconds is absolute actual consumed endpoint (full windows 600 multiples; final short window may be fractional). All segment timestamps absolute, bounded by window, ordered/nonoverlapping; empty chunks allowed. Emit checkpoint only once recognition of that chunk succeeded. Backend atomically fsyncs full accumulated segments + cursor in one durable store update before reading further. Resume reuploads original media once, skips recognized windows, and repeats only interrupted/unpersisted chunk. Worker seeks/skips decoding from requested offset and must emit complete even when offset equals exact duration. Final partial checkpoint is durable and backend retains its endpoint; on stream break before complete backend may retranscribe that final partial window (never duplicate published segments).

Post-header failures: {"type":"error","code":"recognition_failed"} then close (safe bounded codes only). No completion means incomplete. Nonstreaming legacy JSON requests remain unchanged at offset zero. Limits unchanged: <=300 MiB encoded, <=10800 seconds, <=600 seconds recognition chunk, bounded transcript response. Worker must flush each line promptly. Backend does not translate any partial transcript before complete.
