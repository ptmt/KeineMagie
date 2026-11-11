# Local resumable recognition candidate — not deployed

Candidate tag: `keinemagie-podcast-worker:resume-candidate`

Pinned Linux image ID:
`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`

Image `/app/worker.py` SHA256, independently compared to current source:
`bc89f04c9d766a85f30304ff3b7455d3620010c530e4432bb15cd03cefa7ab60`

## Reproduce

From `server/podcast-worker` on this Mac:

```sh
python3 -m unittest test_worker -v
docker build -t keinemagie-podcast-worker:resume-candidate .
python3 verify_resume_container.py
PODCAST_WORKER_TEST_IMAGE=keinemagie-podcast-worker:resume-candidate python3 verify_container.py
```

17 Python tests passed. Real subprocess tests exercise incremental stdout, line-size cap, deadline/process-group killing and disconnected sockets. HTTP tests exercise strict pre-upload offsets, beyond-duration rejection, EOF framing, sanitized post-header error and equal-duration completion.

## Real container evidence

`verify_resume_container.py` passed on the exact pinned image under read-only root, noexec 512 MiB tmpfs, 2 GiB/no swap, two CPUs, dropped capabilities except SETUID/SETGID/CHOWN/KILL, UID-1001 recognition, internal-only network and no published ports.

- Real generated 660-second 16 kHz mono WAV, German opening and final speech beginning at 650 seconds. SHA256 `39b74b1ba4a808cb8589de187f10440f2fa31ec1ed84af57ae240ca0a3d3643f`.
- Unmodified image/server emitted checkpoint 0 at endpoint 600, checkpoint 1 at endpoint 660, then complete. Checkpoint 0 arrived **1.357 seconds before checkpoint 1**.
- Separate deterministic cancellation run injected a fixture-only Python launcher wrapper around the second real Whisper invocation. It paused that invocation, never fabricated recognition output. Hook source was mounted read-only only in that disposable run; it is absent from the image and no production configuration switch was added.
- HTTP client received checkpoint 0, fsynced it outside worker storage, and disconnected. The second invocation was observed paused, and its real recognizer PID 25 was confirmed dead/zombie after disconnect. Process group cleanup is independently covered by real supervisor/descendant tests.
- Destroyed that worker container and its entire ephemeral tmpfs, then started a fresh **unmodified** image with only a disposable secret volume. Reuploaded original full media with `X-Resume-Offset: 600`.
- New HTTP response contained only checkpoint index 1 and complete; no initial German opening was repeated. Real Whisper recognized the final marker at **649.8–656.4941875**: “Zum Abschluss sprechen wir über die Bibliothek, in der Bibliothek lesen wir deutsche Bücher, auf Wiedersehen.”
- Fresh resumed container peak memory **710631424 bytes**; memory max/OOM/OOM-kill counters all zero. No worker transcripts/auth appeared in container logs.
- `resume-verification.json` contains exact persisted checkpoint, resumed events, image/source/fixture digests and observed resource counters.

Existing unchanged `verify_container.py` also passed on this image: short German recognition, exactly 300 MiB upload with real 660-second duration, long final marker at 649.8–656.4941875, legacy JSON schema, auth, oversized header, manifest rejection, contention, disconnect cancellation, blocked internet, decoder secret isolation, supervisor deadline/grandchild cancellation, and existing Linux Go `TestPodcastRemoteRealContainer` (real recognition with synthetic owner translation). Long legacy request took **4.67 seconds**, peak **1097342976 bytes**, zero OOM events. Entire legacy verifier took **20.67 seconds**.

## Scope and limitations

No production container was replaced, no registry push or Git commit occurred, and no files outside `server/podcast-worker` were changed by this implementation. The running production worker remains its prior image. Parent/sibling own Go persistence/recovery integration and rollout.

This is a real worker disconnect plus whole-container replacement/resume test, **not** evidence that backend persisted jobs survive SIGKILL; backend crash-recovery acceptance is a separate Go-owned gate. The fixture is 11 minutes of speech/silence bookends, not continuous 11-minute or 3-hour inference. Perfect word recognition across a chunk boundary is not guaranteed. No persistent worker audio/model-state volume is required; Go must retain the original encoded media and checkpoints. A final partial checkpoint endpoint is not a valid nonmultiple resume header; backend must recognize its already-complete durable transcript or replay that final window according to its contract.
