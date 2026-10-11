# Task 3 report: multi-target focus, windows, and material coordination

Implemented the product-side adapters and coordinator in `Sources/Sensveil` while retaining `SensveilPoC` as the regression reference. The product target now depends on `PoCCore`.

## Behavior covered

- Process identity is bound through shared `ProcessRegistry` PID generations and `launchDate`.
- All unique normal top-level windows for a configured bundle share application-level foreground behavior. A foreground instance removes overlays for every instance of that bundle.
- AX/CG matching remains conservative; only visible layer-0 windows with unique mappings reach the material adapter.
- Material panels remain transparent, nonactivating, mouse-ignoring `NSVisualEffectView` panels using `behindWindow`; no opaque fallback is created.
- `requestSubmitted` remains unverified and maps to `cannotProtect`/`partialFailure`, never `protected`.
- Permission, geometry, metadata, lifecycle, display, Space, sleep, and PID-generation changes invalidate overlay evidence and trigger safe reconciliation.
- Failure summaries are structured by sanitized issue kind and do not include window titles or pixels.

## Verification

- Red test run: `swift test --package-path experiments/macos-blur-poc --filter WindowProtectionCoordinatorTests` failed before coordinator/runtime implementation with missing `WindowProtectionCoordinator` and runtime types.
- Focused green run: `swift test --package-path experiments/macos-blur-poc --filter WindowProtectionCoordinatorTests` — 7 tests passed.
- Full suite: `swift test --package-path experiments/macos-blur-poc` — 41 tests passed.
- `git diff --check` — passed.

The coordinator intentionally does not report `.protected` because public AppKit material APIs provide no visual unreadability proof. A future evidence adapter can add that state only after validated visual measurement.
