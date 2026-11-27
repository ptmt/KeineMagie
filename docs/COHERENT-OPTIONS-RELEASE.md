# Coherent Dictation / activity release — 27 November 2026

## Scope and verification before publication

Isolated integration of durable paid-attempt prevention `990040f`, new-attempt three-reading defaults `251cd9a`, complete web/native timeline `5961f8d`, and weekly Coach activity / Profile month `0a65989`. Original working directory's 304-file manifest remains byte-identical.

Web attempt options are now a large persistent native HTML dialog, separate from the replaced practice subtree. Playback and settings updates preserve its open state; explicit Close/Escape dismiss it. Native inert background, keyboard focus containment/return, translated heading/close, grouped settings/assistance/destructive actions and mobile viewport scrolling are retained. Show original and Delete keep their confirmations. Opening options does not prepare audio. Saved explicit repeat/gap choices survive reload; only new attempts default to three.

Executed on the integrated tree:
- Original disappearing-speed regression reproduced RED during real Chromium media playback, then GREEN.
- Chromium and Playwright WebKit: natural synthetic-WAV playback completion while dialog stays open; speed change; saved 2×/8-second settings and reload; five locales, 390/1100 widths, both themes; outside click, keyboard loop, Escape/Close and canceled reveal/delete. WebKit uses a synthetic bearer bridge, not a browser-cookie authentication claim.
- Full timeline real-media suite and 60 saved-state cases; manual Next, 2/3 repeats, gaps, extra replay, lost Stop acknowledgement/reload, draft and assessment assistance. All passed. Old transient-menu test navigation was adapted to explicit modal closing without removing behavior assertions.
- Profile placement and late-response lifecycle browser suites passed in Chromium/WebKit.
- Node: 201 tests, 200 passes, one existing opt-in skip, zero failures. Go suite and vet passed.
- Swift Core passed; native CI discovery 74 tests, one environment-dependent skip. Native Release full-timeline UI test passed 1/1 on reused iPhone 17 simulator `93E1113F-6736-4CCB-827D-0E2F1C3876EA`, with no clones; device is shut down. Existing main-thread audio-session warning remains.

Native ships the implemented complete timeline and receives new-attempt server defaults. **Native options remain the existing SwiftUI menu, not the new web modal.** No native modal parity, full native UI matrix, physical device, live owner inference, Apple processing or tester availability is claimed.

## Publication

**Web/backend deployed; iOS uploaded to Apple.** Release source `c3334db432e18ee81c50723fe2e0d312494124bb` was pushed normally from the isolated release tree, remote ref read back.

- Server CI **46070502476** succeeded. Exact ARM64 registry/live image: `sha256:57498133cac0543e10628184bec345446978556fa3a91d4a08e6d8c40a2dd0e1`.
- Deployment verified **2026-11-27 21:30:47 UTC**. Fresh idle/store/account checks, locked backup and final hashes preserved **all 76 non-runtime durable files byte-for-byte**, worker/unrelated IDs, full configuration, mounts, resources, routing and networks. Only backend image changed. Established Compose workaround retained; this is not automatic tinyserve deployment.
- HTTPS `/health` **200**, private Dictation/session **401**. **33 public assets** matched exact committed bytes and expected cache headers. Real guest browser inspected. Live HTTPS modules with fully intercepted synthetic Go APIs passed modal playback/settings/locale/keyboard checks and successful reveal → New attempt (3×) → confirmed delete; no production owner action or paid provider call.
- Native UPLOAD run **46070865447**, exact same source, **success**: validate job **140748662289**, upload job **140750797741**. Version **1.0**, archived build **2860.1.40**; signed archive/export succeeded, Apple **`UPLOAD SUCCEEDED with no errors, 1 warning` at 21:46:59 UTC**. Processing, tester availability and installation are not verified.
- Apple warning **90725** remains: move hosted build to iOS 27 SDK / Xcode 27 before April 2027. Existing local main-thread audio-session runtime warning also remains. Neither blocks this accepted upload.
- Private backup/forward-recovery pin: service deployment `coherent-release-20261127T213043Z/`. Use its `compose.policy-safe-recovery.yml` only with the documented base; old pre-policy writer is forensic-only and its restart was disabled before replacement. Never restore historical data or rerun the prior reserve release.

Receipts and inspected runtime previews: `docs/coherent-options-evidence/`. Original 304-file manifest was checked unchanged again. Prior candidate documents remain historical local-stage reports, superseded by this release receipt.

Deployment must retain current user activity, all durable data and the existing $10 cap / prior unknown-cost reservation recovery. No extra releases, cap increase, paid test or old-writer rollback is authorized. Use the documented base + durable override and strict idle/store/account locks; preserve private worker and unrelated containers.
