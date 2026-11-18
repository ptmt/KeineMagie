# Minimal global Dictation player — local preview

Base verified clean: `4cf23d02b138c6c38dda19981e52b285772059d0`.

The latest supplied Apple Music image explicitly supersedes the earlier centered-title/full-width-timeline design. The reference was inspected directly; it is a visual reference, not permission to add music-style pause or skip behavior.

## Current presentation

- One horizontal 44pt content row inside the existing native accessory glass: quiet headphones SF Symbol, left-aligned title, separate 44×44pt trailing transport/status.
- No progress line, elapsed/remaining clocks, info button, permanent speed, duplicate subtitle/badges, invented cover art, extra blur/material or fake pill.
- Playback uses the existing disabled waveform status while active. Play/Continue and preparation cancellation retain their existing state-machine actions. No pause/seek/skip or listening-policy changes.
- Body tap opens the exact attempt at all text sizes without admission, autoplay or draft replacement. Existing long-press speed and Audio details remain secondary.
- The separate native detail sheet still exposes full title, real timing and speed at the actual requested accessibility size. The compact native host retains its existing type cap.

Only `DictationPracticeComponents.swift` changes shipping presentation. Coordinator, controller, journal/privacy/owner handling, camera/OCR, navigation root and background policy are unchanged. A simulator-only, explicitly opted-in accessibility value samples the real coordinator clock for UI verification; no probe or synthetic clock is included in device builds, and no clock text is rendered in the mini-player.

## Verified evidence

- Structural RED caught the old compact ProgressView; GREEN: **4/4**.
- Final Release normal simulator: **6/6**, zero failures/skips.
- Final Release small simulator: **3/3**, zero failures/skips.
- Reused `93E1113F-6736-4CCB-827D-0E2F1C3876EA` and `56A70197-59DE-4410-9E76-25272244E9C8` sequentially with parallel testing disabled. Both shut down after export; no new/cloned/deleted devices.
- Native captures cover light/dark, normal/small, ready/playing and maximum accessibility text, including separate readable details. Sixteen exported PNGs are copied byte-for-byte with source attachment mappings and hashes in `dictation-player-minimal-receipt.json`.
- Tests assert absence of mini progress/time, a single-row fit and separate 44pt transport. SwiftUI merges icon and label accessibility frames, so the initial naive glyph-frame assertion failed. The corrected geometry guard checks actual screenshot title ink starts beside the source icon, rather than weakening the requirement to accept centered text.
- Generated eight-second PCM WAV playback advances through all four tabs, with stable listening counts and exact draft/attempt restoration. Tests also exercise background interruption/Continue, Back/swipe, keyboard non-overlap, long-press speed without admission, and maximum-font body navigation/details/dismissal.
- Original worktree: **304 protected file hashes** and complete status unchanged. No server/web/AnyProgress changes, push, release, production account mutation or paid provider request.

## Evidence and limits

`docs/screenshots/dictation-player-minimal/` contains current previews. The former timeline receipts remain historical. Raw xcresults, exported attachments, structural RED output and run commands are under `/Users/tinyserve/.hermes/cache/scratch/dictation-player-minimal/` (RED text is the sibling `minimal-player-red.txt`).

This is simulator/local-fixture acceptance, not physical-camera, spoken VoiceOver, older-iOS or live-provider verification. Existing unrelated test-target actor-isolation warnings and simulator runtime warnings remain; no controller/security changes were made to suppress them. No full unrelated suite was rerun for this presentation-only revision.
