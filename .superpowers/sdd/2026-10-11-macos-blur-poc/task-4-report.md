# Task 4 implementation report

Implemented the public material experiment, neutral diagnostic states, and initial unmeasured results matrix. Author implementation is ready for the parent's GUI and independent review lanes; material protection has not been approved.

## Verification

- `swift test --package-path experiments/macos-blur-poc`: 19 tests passed, zero failures; all executable sources also compiled. Existing reducer tests cover foreground removal, unknown focus, revalidation, unavailable permissions, process generations and stale windows. No new claim of automated compositor coverage is made.
- `bash experiments/macos-blur-poc/scripts/build-apps.sh`: release build passed, both Info.plists validated, both ad-hoc app signatures verified.
- `git diff --check`: passed.
- SDK header availability: `NSVisualEffectView`, `.behindWindow`, `.active` are macOS 10.10; `.hudWindow` is 10.14; `.fullScreenAuxiliary` is 10.7; `.canJoinAllApplications` is 13.0; `.ignoresCycle` is 10.6; workspace display-options notification and Reduce Transparency are 10.10; `effectiveAppearance` is 10.9. The remaining panel/window style, normal level, geometry, click-through and public order APIs predate target 14. Headers explicitly permit only one of primary/auxiliary/canJoinAllApplications; this candidate uses only canJoinAllApplications from that group.
- Current OS is macOS 27.0.1, arm64, Swift 6.2.3; active SDK alias SDKSettings declares SDK 27.0. The final PoC Mach-O `LC_BUILD_VERSION` records sdk 26.2 and minos 14.0, so the SDK metadata discrepancy is explicitly unresolved. `xcrun --show-sdk-version` fails on this installed SDK alias. Package/script target remains 14.0. No macOS 14 or Intel runtime claim is made.

## Behavior and evidence boundary

`MaterialOverlayCoordinator.reconcile(_:windows:screenLayout:)` returns only `.requestSubmitted` or `.failed(reason:)`. Every panel is borderless/nonactivating, transparent, normal level, mouse-through and cannot become key/main. The full matched titlebar/content geometry is filled with `hudWindow / active / behindWindow`. There is no animation, global floating level, orderFrontRegardless, makeKey, target activation, private API, SCK, capture API, entitlement or billing work.

The first attempt submits public relative-order requests using the CG ID. Subsequent reconciliation reads the public CG ordering list before reordering: missing panel/target, panel below target, or an intervening unrelated window expires the candidate and removes panels. Other owned overlay panels are ignored for adjacency. This check can reject a candidate; it cannot prove final pixels, real blur, readability, input success or WindowServer presentation latency. An ordering failure remains latched until explicit lifecycle/material revalidation or experiment restart. No fallback puts the panel globally on top.

Foreground changes reconcile before fresh enumeration, removing every selected-app panel. Disabled experiment, snapshot invalidation, lifecycle events and stop remove panels. Any tracker issue prevents attempts until a complete fresh snapshot. Display-options notifications and effectiveAppearance KVO remove panels and re-enumerate; Reduce Transparency refuses the candidate outright because an opaque material cannot satisfy this requirement. Notification/KVO observation is stopped during termination. Diagnostic content scrolls and uses only unverified/failed language, with no green protection success state.

Anonymous measurement events add synchronous AppKit API-call duration for order/remove requests. The recorder remains in memory only, bounded at 1,000 entries, and contains no pixels, window titles, raw target identities, device identifiers or paths. There is no presented/protected measurement phase.

## Pending actual-system evidence

No app launch, TCC prompt, permission change, screen recording, osascript or synthetic GUI input occurred in this lane. The parent owns the final-binary GUI experiment. F-01 through F-16 and AC-01 through AC-06 are initialized to unmeasured in `POC_RESULTS.md`, with steps and evidence requirements. Layer/input/multi-display/fullscreen/system-setting experiments, actual visual timing, 10-window resource usage and the three independent readability evaluators remain pending.

Task 5 is not approved by this implementation: layer/input failures block route review; only those passing with material-strength failure permit conditional SCK; a passing material route does not create SCK or request screen recording. The implementation author has not self-approved this code. Independent approval is the parent's separate reviewer lane.

## Scope

Created MaterialOverlayCoordinator and POC_RESULTS; modified controller, diagnostics and measurement recorder. This report is included. Plan and core sources/tests are unchanged. No push.
