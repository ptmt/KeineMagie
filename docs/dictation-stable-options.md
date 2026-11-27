# Dictation options: partial candidate, not deployed

Base: `0db893ecc3078dc45345482361ecf5c3470e6ff7` (freshly fetched origin/main), including prevention `990040f0f70579aa15b31e600f9f8f07a5857cb1`.

## Verified root causes

`web/tests/dictation_options_browser.py` mounts the production web module, routes to real Go handlers/storage, and plays the fixture's synthetic silent WAV. Chromium RED: opening More options while playing, then selecting 0.75 speed, makes Playback speed invisible immediately.

The attempt details element has a bubbling `change` handler that unconditionally closes it. In addition, full `render()` replaces the practice subtree (including the details element), so playback phase changes, asynchronous accepted records, and localization recreate a closed menu. Ordinary audio `timeupdate` updates a timestamp, not the entire screen; do not blame every timeupdate for the full rerender.

Baseline evidence: `/Users/tinyserve/.hermes/cache/scratch/options-red/playing-options.png` and `speed-result.json`. Screenshot inspected: narrow unlabelled speed, destructives first, info and assistance squeezed into the trailing column.

## Completed slice

New policy-2 creations and New attempt now create three planned readings per fragment, with the original 3-second gap and manual advancement unchanged. The existing 59-fragment acceptance bound is preserved independently of repeats. No saved record migration or budget changes.

New handler regression verifies new defaults and actual plan length, saved explicit two repeats / 8-second gap surviving GET and new-attempt creation, source remaining unchanged, and policy-1 retaining its policy. Existing creation and hybrid assistance integration tests now assert three real planned admissions.

`go test ./...` PASS, log `/Users/tinyserve/.hermes/cache/scratch/options-go-green.log`. The focused regression failed before implementation and passed afterwards.

## Blocker / unfinished work

The proposed modal transformation is NOT applied. Executing a Python transformation through execute_code requested user approval; it was not retried or bypassed. Draft script is `/Users/tinyserve/.hermes/cache/scratch/patch-options.py`. It is only an initial proposal and still needs CSS, localization, focus/async validation and review. Await that approval before executing the gated action.

Native counterpart inspected: `DictationView.swift:295` uses nested SwiftUI Menu, including mode, speed, repeats and information. No native changes made. Native's create/new-attempt calls use the backend-generated policy-2 plan, so the completed server default applies there without saved-record rewriting; explicit upgrade/fallback values remain two until deliberately addressed.

Modal GREEN, Chromium/WebKit locale/theme/responsive acceptance, native sheet implementation/runtime tests, Obsidian update and integration with the concurrent full-timeline worker remain outstanding. No deployment, publication, paid provider call, credential access, original dirty-tree edit, timeline-worker edit, or operator adjustment occurred.
