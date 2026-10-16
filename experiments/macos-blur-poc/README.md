# macOS Blur PoC

This isolated Swift 6 experiment targets macOS 14 or later. It has no third-party dependencies. `PoCCore` contains deterministic window matching and protection intent logic. `SensveilPoC` is the diagnostic application; `SensveilFixture` is a separate foreground application containing synthetic data only.

## Current product baseline (2026-10-14)

Sensveil is fully free with no configured-app limit, trial clock, purchase, activation or device binding. Core protection and configuration run offline; old commercial state does not affect app selection or protection. Historical quota/trial/license checks in older plans and reports are obsolete. Since 2026-10-16, the repository is open source under the [MIT License](../../LICENSE); source availability does not certify release readiness or compatibility.

The native macOS management window uses a sidebar and detail pages: 防窥应用, 防窥设置, 权限, 通用 and 关于. 防窥设置 combines effects and schedules in one scrollable form with a floating save/discard bar; both groups are saved together, and validation failure preserves the entire draft. Login launch remains explicitly unimplemented; transition selection remains hidden. About reads the marketing version and build number from `Bundle.main` (currently `0.1.0 (1)`) and offers the [project](https://github.com/NieAnSHOW/Sensveil) and [author](https://github.com/NieAnSHOW) links, opened only on a user click. Current requirements are in [TASK](../../TASK.md); the historical validation records below do not certify this UI change.

Multi-display fix (2026-10-14): material placement now checks each window's expanded coverage against one uniquely containing display and permits normal 1x/2x panel scale. Connecting another display no longer rejects every window. Cross-display/incomplete coverage remains unsupported; changed layouts invalidate old placement evidence. All 220 tests passed, and the synthetic guard validation passed 33 checks on each of the two actual displays (1x and 2x). This verifies runtime placement and labels, not pixel privacy strength on new displays. See [multi-display validation](../../docs/engineering/MULTI_DISPLAY_VALIDATION.md).

## Build

From the repository root:

```sh
swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
```

The script performs a release build, wraps the current SwiftPM binaries in `.build/apps/Sensveil.app`, `.build/apps/SensveilPoC.app` and `.build/apps/SensveilFixture.app`, then installs and launches only the product at `/Applications/Sensveil.app` if macOS execution assessment succeeds. Set `SENSVEIL_INSTALL=0` to build without installing. `SENSVEIL_INSTALL_DESTINATION` may choose an absolute path ending in `Sensveil.app` with an existing parent directory. The installer refuses symlinks or unrelated existing bundles, stages and backs up in the same parent directory, and restores the previous bundle if launch verification fails. It stops only processes whose executable matches the installation path, preserves configuration and permissions, and never uses `sudo`. Sensveil is the menu bar product shell (`LSUIElement=true`) and keeps running when its management window closes. The product bundle identifier is `com.nieanshow.sensveil`; the two fixed experiment identifiers are `com.nieanshow.sensveil.poc` and `com.nieanshow.sensveil.fixture`.

The product shell is Chinese-first and keeps protection fail-closed: a submitted material request is shown as “无法保护” until visual blur evidence is verified. Accessibility requests are initiated only by the management window button. Screen Recording is an optional diagnostic probe and is not required for protection. Login launch remains visibly disabled in this first release.

The default signing identity is ad-hoc (`-`); rebuilds may require Accessibility permission again. After user authorization for the intended use, set `SENSVEIL_SIGNING_IDENTITY` explicitly to a valid identity. The script does not automatically select certificates or fall back when an explicit identity fails. All bundles receive strict signature verification; this alone cannot establish certificate validity or permission to execute. The installer also requires `spctl --assess --type execute` to accept the product before and after replacement, stops on revocation or rejection, and verifies the actual installed process remains alive after launch. It never changes Gatekeeper settings, clears quarantine, or resets TCC. Ad-hoc builds may be rejected under normal security policy. A local development signature is not Developer ID signing, notarization, or public distribution evidence. Keep certificate names and identifiers out of source control.

## Bundled holiday data

`Sources/Sensveil/Resources/mainland-holidays.json` ships the official annual arrangements offline; the Sensveil target registers it with `.process("Resources")` and `build-apps.sh` copies the built `SensveilBlurPoC_Sensveil.bundle` into `Contents/Resources` before signing, so `MainlandHolidayCalendar.loadBundled()` reads the same data under `swift test` (`Bundle.module`) and in the installed app. Only exception days are stored: rest days (放假) and makeup workdays (调休上班); all other days follow the weekly schedule, and an unpublished year falls back to the weekly rules with a warning instead of reusing an old arrangement. Current content: 2026, 国办发明电〔2025〕7号, retrieved 2026-10-13 from <https://www.gov.cn/gongbao/2025/issue_12406/202511/content_7048922.html>. Data updates only with an application version.

## Safe experiment

Launch the fixture and then the PoC app manually. The experiment starts off. Select the running fixture explicitly. This stage only accepts one verified foreground fixture process with a bundle executable matching its declared main executable. Other apps, helpers, missing identifiers, and SensveilPoC itself are rejected.

The diagnostic panel separately preflights Accessibility and Screen Recording at startup without requesting authorization. Each permission has explicit Request and Refresh controls. Granting permission does not validate protection. The separately authorized contour study uses one-shot ScreenCaptureKit capture of a verified synthetic fixture window; original RGB and alpha stay in memory, and only a neutral filled silhouette and statistics can be shown. Request may return before settings change; manual refresh and the one-second permission poll check actual authorization. Denied permission leaves diagnostics usable; material overlays remain experimental.

The fixture opens three normal, resizable windows. Controls move, resize, minimize, reopen the three windows, open a closable sheet, and create two identical overlapping windows. The Fixture menu also reopens windows after all are closed. All displayed account data is synthetic, including the invalid phone number and fictional balances. The diagnostic panel is itself a normal foreground window usable as an occluder.

### Finite contour and ordering checks

2026-10-14 update: the product and PoC now use a 20pt circular rounded mask with 8pt outward padding on every edge. Target identity bounds and expanded coverage bounds remain separate; intervening windows intersecting only the padding are also rejected. This is a Sensveil appearance choice, not an Apple per-OS standard radius. `--validate-ordering` now checks four poses, including a margin-only conflict. The latest full suite passed 161 tests. [Expanded coverage evidence](../../docs/engineering/EXPANDED_OVERLAY_VALIDATION.md) records raster containment and the remaining visual gates; the contour research below is retained as historical evidence and no longer blocks this geometry implementation.

After `swift test` builds the debug executables, run from the repository root:

```sh
experiments/macos-blur-poc/.build/debug/SensveilPoC --validate-ordering
experiments/macos-blur-poc/.build/debug/SensveilFixture --validate-contours
```

The ordering check creates three nonactivating synthetic panels and checks actual CG order and intersections outside, overlapping, and outside again. It never reads pixels or requests permission. The contour check creates a titled and a known drawn rounded window, compares static/moved/resized single-window candidates against local drawing and a display-filtered whitelist containing only the same window, then exits. It uses only existing Screen Recording authorization, never saves images, and never approves product protection. A contour process exit of zero means the finite run ended; inspect skipped captures, differences and `UNVALIDATED` output before interpreting it. Latest evidence: 153 XCTest tests passed; real ordering 3/3 matched expectations; all six SCK crosschecks had zero differences, while the independent rounded drawing had 32 low-alpha differences after resize and the titled drawing reference was invalid for compositor corners. [The full record](../../docs/engineering/CONTOUR_ORDERING_VALIDATION.md) retains the Task 8 gate and remaining limits.

## Validation record

Current transition policy: after negative visual feedback, the product hides the duration controls and always runs at 200ms. Four-choice code, schema 3 values and experiments remain available in source; stored 500ms/800ms/Off values are preserved but do not affect production. Saving other settings retains the historical choice. All 199 tests passed, the release product was installed and its settings view has no transition selector. This scope change does not claim improved or accepted visual quality.

Latest duration update: transition settings now offer 200ms, 500ms, 800ms and Off, defaulting to 200ms. Schema 3 persists the selection; schema 1/2 retain prior settings and default to 200ms without rewriting on load. Saving a new duration cancels old entry/exit work; reduced motion overrides all choices. Full tests passed 199 cases and the synthetic production-panel check passed 33/33 across all choices; installed GUI selection/discard was observed. [Four-choice validation](../../docs/engineering/PROTECTION_TRANSITION_VALIDATION.md) retains the remaining visual privacy and smoothness limits.

Latest transition update: after guard-label acceptance, the product implements fixed 200ms entry from the accepted strongest material combination and a foreground-only whole-panel fade-out. Failure, changed geometry, unknown focus and reduced motion clear immediately; generation checks cancel stale entry/exit completions. The full suite passed 192 tests, and the synthetic production-panel check passed 21/21. [Transition evidence](../../docs/engineering/PROTECTION_TRANSITION_VALIDATION.md) retains unmeasured intermediate-frame privacy, external visual smoothness and presentation timing; the installed build currently needs Accessibility authorization for external-window acceptance.

Latest 2026-10-14 update: after the user's acceptance of the corrected tiers, the guard label is connected for the accepted local profile (macOS 27.0.1/26A434, arm64, one display, 2x, fully contained normal window, standard transparency/contrast). A new panel only submits a request; a later matching natural CG snapshot and live panel placement can issue current key/bounds/tier/revision evidence. Stale, missing, conflicting or unsupported conditions cannot report protected. Full tests passed 186 cases; the self-owned production-panel check `SensveilApp --validate-guard-label` passed 16/16 without pixel capture or user configuration access. [Latest label evidence](../../docs/engineering/BLUR_LABEL_INTEGRATION.md) documents runtime behavior, local scope and the remaining animation/platform limits. The installed product currently needs Accessibility authorization before it can display labels for external apps.

2026-10-14: the product now forwards saved blur/label settings to existing material panels without removing them. The user accepted tier implementation and reported enhanced visually stronger than strongest, so the selected-material order is now hudWindow / popover / underWindowBackground. The physical popover anchor remains unchanged to preserve the observed combinations; it is not asserted to be the strongest material or a validated safe transition baseline. Centered label layout, small-window hiding and click-through are implemented, but production labels remain hidden while material protection is unverified; no new protected status is issued. The full suite passed 171 tests and the product was installed. [Integration evidence and limits](../../docs/engineering/BLUR_LABEL_INTEGRATION.md) distinguish settings/geometry tests from privacy validation.

Current MVP validation (2026-10-12, implementation baseline `d505e43`): all 59 XCTest tests passed; the release script built all three bundles and passed plist and strict ad-hoc signature verification. Explicit product plist lint and strict signature verification also exited 0. These results validate rules and local build integrity, not rendered blur. The product search/add UI has a partial manual observation; 20 focus switches, lifecycle, permission revocation/restoration, multi-screen, Spaces, Intel and macOS 14 remain unmeasured. Product material requests remain “无法保护” while visual evidence is unavailable. See [MVP_VALIDATION](../../docs/engineering/MVP_VALIDATION.md) for commands, the manual matrix and the release boundary. The following older observations belong to the diagnostic PoC and do not establish current product permission or protection results.

Observed build environment on 2026-10-11:

| Field | Observed value |
| --- | --- |
| Swift | Apple Swift 6.2.3, swift-driver 1.127.14.1 |
| Xcode | 26.2, build 17C52 |
| SDK metadata | Mach-O records 26.2; active SDK alias SDKSettings declares 27.0, discrepancy unresolved; current xcrun SDK query fails |
| Host | macOS 27.0.1, build 26A434 |
| CPU / output | arm64 / Mach-O thin arm64 |
| Binary minimum OS | 14.0, verified with `xcrun vtool -show-build` |

Release build, plist lint, and strict ad-hoc signature verification passed for both bundles. The existing 19 core tests passed with zero failures; these are deterministic rule tests, not compositor or visual tests. macOS 14 and Intel runtime validation remains unmeasured. Swift 6 requires the legacy Accessibility import to use `@preconcurrency` for its imported `kAXTrustedCheckOptionPrompt` global; permission operations remain main-actor isolated.

The coordinator's manual GUI pass confirmed app launch, three synthetic fixture windows with 12/24/48pt text, sheet open/close, and the initial disabled experiment state. With the experiment enabled and Accessibility unavailable, diagnostics showed Cannot protect, zero CG/AX windows and zero overlay requests. The earlier ineffective grant was traced to TCC's stored legacy code requirement not matching the current development-signing identity.

The user explicitly requested the separate Screen Recording probe and then authorized local development signing. The development-signed build and strict signature checks passed. The user explicitly authorized a targeted `tccutil reset` for only this PoC's Accessibility and ScreenCapture services, then granted both requests under the stable identity. The latest GUI showed both permissions Granted. This was a one-time authorized diagnosis, not an automatic reset policy; no certificate information or system logs are stored in the repository.

After selecting the fixture, diagnostics showed Matched 3 / CG 4 / AX 4 and two issues: a nonstandard AXWindow and a visible CG window without a validated AX counterpart. Enabling the experiment still showed Cannot protect with revalidation required and zero overlay requests. The unique-match subset of F-01 and permission-restoration subset of F-07 have evidence; duplicate ambiguity and complete rejection/revocation behavior remain unmeasured. No pixel capture was performed. Relative layering, click-through, material readability and system-space behavior remain unmeasured. The material gate is UNMEASURED, so no ScreenCaptureKit capture experiment is allowed yet. See [the evidence matrix and decision](../../docs/engineering/POC_RESULTS.md).
