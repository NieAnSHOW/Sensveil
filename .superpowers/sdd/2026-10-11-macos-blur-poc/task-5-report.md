# Task 5 report: evidence and conditional gate

## Scope and decision

Updated POC_RESULTS, DEVELOPMENT, root README, AGENTS, the experiment README validation record, and the plan execution-status section. Existing permission-diagnostic exception edits were preserved. No product code, capture code, requirements, prices, license rules, or API thresholds were changed.

Conclusion: **未具备放行证据**. The material gate remains **UNMEASURED** because Accessibility has not actually preflighted as granted. F-03/F-04/F-05 are unmeasured, so conditional ScreenCaptureKit implementation is not allowed. This is neither material-route success nor evidence that the public API route fails.

## Evidence received from implementation and GUI lanes

- Core tests: 19 XCTest tests passed, 0 failures. These cover deterministic rule logic, not 19 visual/compositor tests.
- Release apps: build, both plist lints and strict ad-hoc signature verification passed; Mach-O minimum OS is 14.0 on the current macOS 27.0.1 arm64 host. macOS 14 and Intel runtime remain unmeasured. SDK alias metadata discrepancy is preserved.
- Coordinator GUI: three synthetic fixture windows with 12/24/48pt text; sheet open/close; experiment initially disabled.
- Experiment enabled with AX unavailable: Cannot protect, 0 CG/AX window counts and 0 overlay requests. That establishes the unavailable-permission branch only, not successful real enumeration or overlay removal.
- User reported Accessibility granted, with Settings toggle enabled, but refresh and full quit/relaunch still left app preflight not granted. Revocation/restoration has not been tested and TCC cause remains unresolved.
- The user explicitly requested the independent Screen Recording probe. Request was clicked; system authentication was completed by the user; the pre-identity-change probe showed Screen Recording Granted and Accessibility Not Granted. No pixel capture occurred.
- User subsequently allowed local developer signing of ignored app artifacts for TCC diagnosis. Strict signature/designated-requirement verification passed; after complete quit/relaunch under the changed identity, both permissions were Not Granted and a one-time user grant is pending. No personal certificate information is recorded.

F-07 and AC-06 are partial only. Sheet/relaunch observations are a partial F-08 fixture subset, not overlay lifecycle proof. No full F row is marked passed. F-02 and AC-01 lack 100-switch statistics and actual-presentation samples; API request timestamps cannot substitute for visible presentation. F-14 lacks a 10-window resource sample. Independent readability evaluators: 0.

## Task 5 step disposition

| Step | Disposition |
| --- | --- |
| 1 | Gate reviewed and recorded as UNMEASURED; no route outcome inferred |
| 2–3 | Conditional capture implementation and capture experiments not executed; explicit permission probe is a separate user-authorized diagnostic exception |
| 4 | Available fixture/permission observations recorded; complete F-01–F-16 matrix remains incomplete |
| 5 | No timing/resource measurements fabricated; required samples remain unmeasured |
| 6 | Existing implementation-lane core test/build/availability evidence recorded; no new artifact resigning/build done in this docs lane |
| 7 | Evidence-based incomplete conclusion recorded without lowering PRD thresholds |
| 8 | Parent coordinator owns independent whole-branch review; author has not self-approved |

## Documentation verification

Fresh `git diff --check` and `bash -n experiments/macos-blur-poc/scripts/build-apps.sh` exited 0. Local documentation targets were checked to exist; the staged name list will be checked before the scoped commit. The parent will supply a separate independent review. No code tests or app builds were rerun in this documentation lane; their dated evidence above comes from the implementation/coordinator lanes. Build artifacts were not modified by this lane, avoiding interference with active permission diagnosis. No push is requested or performed.
