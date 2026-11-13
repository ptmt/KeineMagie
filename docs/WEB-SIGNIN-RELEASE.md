# Web sign-in feedback

## Scope

Signed-out header and sign-in dialog no longer show interface-language settings. Both controls start semantically hidden before JavaScript/session discovery; verified authenticated settings remain available. Saved/browser locale, translated labels and the five original Apple PNGs remain intact. Translation direction is not an interface-language setting and is unchanged.

Apple buttons in Translator, Podcasts and the account dialog now start one attempt immediately. The dialog shows an adjacent animated indicator and localized status before the first bootstrap fetch, preserves Apple's unmodified artwork/name, and disables duplicate Apple/pairing actions. Reduced motion keeps visible status without rotation. The top-right generic Sign in still opens choices without starting OAuth.

Attempts are bounded to 15 seconds including redirect loading. Close/Escape, identity loss, errors, timeout and page restoration clear pending; AbortController and attempt identity fence stale bootstrap/start responses. Cancel/timeout stops a pending navigation with `window.stop()`; real pagehide does not stop the intended navigation. No automatic retry. OAuth origin/path validation, CSRF POST, cookies, backend auth, and worker are unchanged.

Native scope inspection: `LoginGate` already has preparing/authorizing/exchanging ProgressView states and `SessionController.prepareLogin` switches phase before awaiting the challenge, with duplicate phase guard/cancel generation. No native code or TestFlight release is included.

## Verification

`web/tests/signin_browser.py` runs actual shipped HTTP assets with explicitly synthetic API/Apple destinations; it never signs into Apple. RED witnessed guest language visibility, missing synchronous progress, cancel/reopen disabled state, and the two public Apple entry points. GREEN covers five locales × 320/390/768/1440 widths, saved locale, authenticated language settings/logout, keyboard activation, Apple artwork dimensions, pending copy, animation/reduced motion, error/network recovery, coalesced POST with CSRF, stale canceled responses, Back and synthetic persisted-pageshow recovery. Actual held navigation samples prove pending persists until leaving. Releasing the delayed destination after timeout stays on the app.

Independent Codex review (explicit available `gpt-6-astra`) found two lifecycle issues: pending navigation survived fetch abort, and a newly restored authenticated identity could leave its timer inactive. Browser RED tests reproduced both; navigation stop and cancel-before-session-assignment fixed them. Final independent review reported no remaining concrete logic/security blockers. The first CLI launch used an unsupported configured model and failed; no result was claimed from it.

Final local suite: **205 browser checks**, **70 Node**, full Go tests/race/vet, HTTP i18n **24** checks and bootstrap fallback passed. Actual native simulator was an existing signed-in synthetic Translator surface, not the LoginGate; only native sign-in source was inspected and no native parity claim is made. BFCache cache-hit verification is separate from the synthetic persisted-pageshow and real Back tests.

Local baseline regression: 70 Node tests; full Go tests and vet; HTTP i18n 24 checks and bootstrap fallback suite. Screenshots live in scratch `km-signin-evidence/` (all five locales/four widths plus Russian dark mobile); inspected actual desktop/mobile/dark pending renders. These are synthetic identity tests, not live consent/provider validation. No owner cookies, credentials or inference used.

Apple references: https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple and https://developer.apple.com/documentation/signinwithapple/incorporating-sign-in-with-apple-into-other-platforms (official documentation JSON read). Existing generated official PNGs unchanged.

## Release

Pending exact source/CI/image and public readback verification. Existing local Compose deployment workaround must retain original base plus durable override; change backend image only, lock stores, verify idle state, back up privately and compare nonruntime bytes. Do not reset data, regenerate infrastructure or replace worker.
