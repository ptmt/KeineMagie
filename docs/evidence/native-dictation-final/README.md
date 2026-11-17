# Final native acceptance evidence

Application/test source: `04e84f61096d3bcc7b63ad0866776eb2d0a10341`.
See `../../NATIVE-DICTATION-POLICY.md` for scope, limits, findings and release handoff.

## Accepted final-code runs

- `reviewed-summary.json`: coherent Release UI, 33 passed, 0 failed, 0 skipped.
- `small-reviewed-summary.json`: reused SE, same Release build, 6 passed, 0 failed, 0 skipped.
- `coherent-command.json`, `small-command.json`: exact serial commands, existing simulator UUIDs, parallel testing disabled.
- `reviewed-attachments/`, `small-reviewed-attachments/`: selected actual XCTest captures from those final-code runs.
- `final-screenshot-index.json`: 189 original PNGs with hashes and exact source paths/revisions; 24 included native PNGs across final runs and the explicitly labeled supplementary dark run.
- `final-receipt-hashes.json`: hashes/paths for non-UI test logs retained in scratch. Overlapping AppModel harness runs must not be added as distinct cases.
- `web-parity/`: four actual browser captures of the production web module mounted with clearly marked synthetic read-only data. These are not production authenticated-session evidence.

## Diagnostic / supplementary evidence, not final-code acceptance

- `keyboard-red-summary.json`: strengthened maximum Dynamic Type keyboard assertion failed before the fix (typed bottom 616 > allowed 582).
- `keyboard-focus-summary.json`: the same focused regression passed after focus-aware scrolling.
- `normal-dark-summary.json`, `normal-dark-attachments/`: 3/3 supplementary system-dark checks before the keyboard fix; source revision is recorded in the final index. Final keyboard evidence is in the reviewed directories, not here.
- `coherent-summary.json`, `small-verified-summary.json`, `recovery-attachments/`, `small-verified-attachments/`, `screenshot-index.json`, `receipt-hashes.json`: earlier recovery evidence, retained rather than mislabeled as final-source evidence.
- `small-summary.json`: initial unsuccessful small-device recovery; retained for diagnosis.

Full `.xcresult` bundles, all exported attachments, logs, commands and fixture archives remain at `/Users/tinyserve/.hermes/cache/scratch/dictation-final/`. Only regenerable build/cache directories were cleaned. The earlier disk-interrupted `coherent-release-final.xcresult` is invalid and is never counted as a pass.
