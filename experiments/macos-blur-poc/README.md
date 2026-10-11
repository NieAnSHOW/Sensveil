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

The diagnostic panel preflights Accessibility at startup without requesting authorization. The Accessibility request button is an explicit user action. Screen Recording is intentionally deferred until a later conditional capture path exists. Refresh checks the actual authorization state; a displayed prompt is not evidence of permission. Denied permission leaves diagnostics usable. The panel says the experiment is unvalidated, and this shell does not claim protection or install overlays.

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

The parent manual GUI pass confirmed app launch, synthetic fixture content, sheet open/close, and initial disabled experiment state with Accessibility ungranted. Permission grant, denial, revocation, moving/resizing/minimizing/reopening, and overlapping duplicate behavior still require additional GUI evidence. No capture permission is requested by this stage.
