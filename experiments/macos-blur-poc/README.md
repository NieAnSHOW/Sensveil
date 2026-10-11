# macOS Blur PoC

This isolated Swift 6 experiment targets macOS 14 or later. It has no third-party dependencies. `PoCCore` contains deterministic window matching and protection intent logic. `SensveilPoC` is the diagnostic application; `SensveilFixture` is a separate foreground application containing synthetic data only.

## Build

From the repository root:

```sh
swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
```

The script performs a release build and wraps the current SwiftPM binaries in `.build/apps/Sensveil.app`, `.build/apps/SensveilPoC.app` and `.build/apps/SensveilFixture.app`. Sensveil is the menu bar product shell (`LSUIElement=true`) and keeps running when its management window closes. All bundles are ad-hoc signed and verified. The product bundle identifier is `com.nieanshow.sensveil`; the two fixed experiment identifiers are `com.nieanshow.sensveil.poc` and `com.nieanshow.sensveil.fixture`. Ad-hoc signing is not Developer ID signing, notarization, production TCC identity stability, or trust across machines. Rebuilds may change TCC behavior. Record such changes; do not reset permissions automatically.

The product shell is Chinese-first and keeps protection fail-closed: a submitted material request is shown as “无法保护” until visual blur evidence is verified. Accessibility requests are initiated only by the management window button. Screen Recording is an optional diagnostic probe and is not required for protection. Login launch remains visibly disabled in this first release.

The default signing identity is ad-hoc (`-`). For a user-authorized local TCC identity check only, set `SENSVEIL_SIGNING_IDENTITY` in the shell before running the same script. Keep certificate names and identifiers out of source control. A local development signature is not Developer ID signing, notarization, or public distribution evidence.

## Safe experiment

Launch the fixture and then the PoC app manually. The experiment starts off. Select the running fixture explicitly. This stage only accepts one verified foreground fixture process with a bundle executable matching its declared main executable. Other apps, helpers, missing identifiers, and SensveilPoC itself are rejected.

The diagnostic panel separately preflights Accessibility and Screen Recording at startup without requesting authorization. Each permission has explicit Request and Refresh controls. Screen Recording is an exploratory permission probe only: it uses `CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess`, without ScreenCaptureKit or pixel capture. Request may return before settings change; manual refresh and the one-second permission poll check actual authorization rather than treating a prompt as permission. Denied permission leaves diagnostics usable. Granting either permission does not validate blur or protection; material overlays remain experimental.

The fixture opens three normal, resizable windows. Controls move, resize, minimize, reopen the three windows, open a closable sheet, and create two identical overlapping windows. The Fixture menu also reopens windows after all are closed. All displayed account data is synthetic, including the invalid phone number and fictional balances. The diagnostic panel is itself a normal foreground window usable as an occluder.

## Validation record

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
