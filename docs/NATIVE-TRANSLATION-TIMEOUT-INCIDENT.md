# Native translation timeout incident — local candidate

Base: exact deployed application revision `78e2ebf589cbee9f574b497892319afa255de121`.
Isolated worktree: `/Users/tinyserve/Projects/KeineMagie-translate-incident`.
No push, deployment, TestFlight upload, provider inference, queue replay/reset, credential rotation or private draft mutation.

## Read-only production evidence (2026-11-19)

- Backend image `sha256:c7ee5112434d3d133d3803d9a0f7e6ca7eb212062a2c467ff96dcc0f8a57f1cc`; OCI revision matches the base; started `2026-11-17T21:01:09.829757208Z`.
- Certificate-validated public IPv4 `/health`: 200.
- Allowlisted reverse-proxy access-log fields: at `08:14:58 UTC`, GET `/v1/auth/session`, `/v1/translations`, `/v1/provider` each returned 200. POST `/v1/translations` began `08:15:06 UTC`, ended with 499 (client disconnected). Backend completion logged `08:15:14.906250294Z`, duration `8.788678916s`.
- Backend translation logs do not retain HTTP status, request correlation IDs or upstream error classification. Proxy status is independently available. No upstream response body/status can be reconstructed from these logs. Provider GET 200 is not proof of upstream credential acceptance.
- Aggregate persisted read in memory: 18 completed translation receipts, one incomplete receipt timestamped `08:15:06 UTC`; 43 history records, newest `2026-11-17T06:37:43.540913964Z`; one encrypted provider record. No credential was decrypted, extracted or replayed. No private text, identity or receipt key was printed.
- Private worker readiness `/internal/podcast/ready`: authenticated 200, ready true, capacity 1, version 1. Initial `/health` probe was a wrong route (404), corrected from worker source; worker was not restarted or used for inference.

## Diagnosis

`MainTabsView` maps the exclamation bubble to unresolved outbox `.failed` or `.needsDecision`, not provider disconnection. `APIClient` requests already specify 90 seconds, but `AuthClient.network` applied an unconditional eight-second URLSession **resource** timeout. Thus valid slow translations were canceled despite their declared 90-second deadline. `AppModel` correctly retains timeout outcomes as uncertain; repeated identical submissions coalesce rather than spending again. This explains why tapping Translate again does not create another request.

The deployed 499 timing and incomplete receipt strongly match the deterministic transport defect; no device diagnostic was extracted, so the precise device NSError is not claimed as observed. The synthetic regression obtains actual NSURLErrorDomain -1001 after 8.654 seconds. No evidence justifies asking the user to reconnect ChatGPT.

## Minimal fix

Honor the request's declared deadline for both URLSession request/resource timeouts. Explicitly retain eight seconds for Apple challenge/sign-in (session/logout already set eight). Redirect refusal, cancellation, connectivity policy, receipt identity, immutable snapshots, retry/admission policy and all production UI remain unchanged. This shared transport now honors existing feature-specific deadlines rather than truncating them to eight seconds.

Simulator-only fixture uses actual loopback TCP/HTTP and the production URLSession path; it returns a clearly synthetic translation after ten seconds. No mocked transport delay is substituted for real URLSession timeout behavior. The source value is `сплетни`, direction ru→de. Fixture has synthetic history/default styles; it intentionally does not reproduce the user's custom bike style and shows an unrelated synthetic profile-sync notice. No personal history was copied.

## RED/GREEN and validation

- Core real-HTTP regression: RED -1001 at 8.654 seconds with released cap; GREEN successful result at 10.756 seconds. Initial harness port-zero readiness error was corrected before accepting RED.
- Authentication deadline regression: RED challenge/sign-in request defaults 60, GREEN explicit eight seconds; session/logout remain eight.
- Swift package: 81 tests passed.
- Actual AppModel lifecycle/ownership/outbox synthetic harness: 113 tests passed (includes uncertain lookup-only handling, explicit retries, immutable snapshots, 401 isolation and late-response fencing).
- Native Python CI discovery: 58 tests run, OK, one skipped; includes the 113-test lifecycle harness.
- Actual iOS simulator `93E1113F-6736-4CCB-827D-0E2F1C3876EA`: four UI tests passed (new real-network deadline case plus all three TranslationOutboxUITests).
- UI differential check: temporarily restored released eight-second cap; same new UI test failed with missing result, missing output text and present attention bubble. Reinstated fix, same UI test passed again. RED and GREEN exported screenshots inspected visually; RED matches empty result and attention symbol, GREEN shows Gerüchte and no attention symbol.
- Evidence: scratch `km-translate-core-tests.log`, `km-translate-lifecycle-tests.log`, `km-translate-python-tests.log`; `km-translate-red.xcresult`, `km-translate-green.xcresult`, `km-translate-final.xcresult`; corresponding exported red/green attachments.

## Recovery / release gates

This is a **local candidate**, not a shipped repair. An existing uncertain receipt must not be automatically resent or removed. The attention sheet's **Check result** performs GET-only history lookup. At audit no new result was saved; the fix does not resurrect this already interrupted provider attempt. A genuinely new attempt requires an explicit informed user decision after the fixed build is delivered; it may spend again. Do not describe repeated Translate or a code update as recovery of the old result.

Protected unpublished native player `6cbfb1cf891d8302178e19cfaa918cb737299bdd` and web cards `dfb3dc729d5f29a6afcb711ae0e6dd2aba9b8578` remain unchanged and clean. Original main remains `df309d46d8760c61442220d10aac78049fe5e59c` with 59 existing status entries. No writes were made there or to AnyProgress. A pre-task 304-file hash manifest was not provided or independently regenerated; do not claim a hash comparison that was not performed.
