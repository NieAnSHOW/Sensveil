# macOS Blur PoC

This isolated Swift 6 experiment targets macOS 14 or later. It has no third-party dependencies. `PoCCore` contains deterministic window matching and protection intent logic. `SensveilPoC` is the diagnostic application; `SensveilFixture` is a separate foreground application containing synthetic data only.

## Build

From the repository root:

```sh
bash experiments/macos-blur-poc/scripts/build-apps.sh
```

The script performs a release build and wraps the current SwiftPM binaries in `.build/apps/SensveilPoC.app` and `.build/apps/SensveilFixture.app`. Both bundles are ad-hoc signed and verified. Their fixed experiment identifiers are `com.nieanshow.sensveil.poc` and `com.nieanshow.sensveil.fixture`; neither is the future product identity. Ad-hoc signing is not Developer ID signing, notarization, production TCC identity stability, or trust across machines. Rebuilds may change TCC behavior. Record such changes; do not reset permissions automatically.

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
| macOS SDK | 26.2 |
| Host | macOS 27.0.1, build 26A434 |
| CPU / output | arm64 / Mach-O thin arm64 |
| Binary minimum OS | 14.0, verified with `xcrun vtool -show-build` |

Release build, plist lint, and strict ad-hoc signature verification passed for both bundles. The existing 15 core tests passed with zero failures. Swift 6 requires the legacy Accessibility import to use `@preconcurrency` for its imported `kAXTrustedCheckOptionPrompt` global; permission operations remain main-actor isolated.

The parent manual GUI pass confirmed app launch, synthetic fixture content, sheet open/close, and initial disabled experiment state with Accessibility ungranted. Permission grant, denial, revocation, moving/resizing/minimizing/reopening, and overlapping duplicate behavior still require additional GUI evidence. The Screen Recording probe awaits an independent GUI pass and requests authorization only through its explicit Request button.
