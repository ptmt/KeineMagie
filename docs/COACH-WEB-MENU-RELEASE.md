# Coach web composer menu

Owner-authorized web-only follow-up to native Coach source `cff9deeefd51f5746afdfe69e9913b94f108c017`. Native TestFlight run `44718914653` remains the only upload; this follow-up does not change native, server, Dictation or budget code.

- Plus menu inside the composer replaces the separate quick-action row. Every available action remains; Progress has a concise label while its original My progress payload is unchanged.
- Semantic menu/menuitem roles, 44px targets, arrow/Home/End/Tab/Escape navigation, outside dismissal, focused editor/caret restoration, busy/guest disabling and owner fencing. Opening/dismissal sends no action; existing authenticated daily-entry behavior is unchanged.
- Actual Chromium synthetic-owner test passed: five locales × 390/1280px, original Hint and Progress payloads, no duplicate action, preserved draft/selection, no overflow/JS errors. Actual screenshots retained in `docs/evidence/coach-web-menu`.
- Full Node suite passed; two additional mounted-controller tests passed for all commands, no menu-open action, disabled busy commands and stale-owner rejection. Existing browser selectors migrated to menu semantics without dropping behavioral assertions.
- Public rollout/health and exact asset receipt will be recorded after registry CI and guarded backend-only replacement. No production AI smoke call or historical-ledger change is authorized.
