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

Pending at this source commit. Update with exact image/CI/deployment and Apple upload receipts after actual publication. Do not infer deployment from image CI.

Deployment must retain current user activity, all durable data and the existing $10 cap / prior unknown-cost reservation recovery. No extra releases, cap increase, paid test or old-writer rollback is authorized. Use the documented base + durable override and strict idle/store/account locks; preserve private worker and unrelated containers.
