# Implementation backlog

Priority reflects user impact and evidence quality, not a promise that all work is already complete.

| Priority | Next work | Acceptance evidence |
| --- | --- | --- |
| P1 | Recheck the seven failed iPhone 17e UI flows after the accessibility and safe-area fixes; repair remaining defects. | Focused result bundle, screenshots and a passing rerun. Full pre-fix run was 212/212 unit/integration and 11/18 UI. |
| P1 | Validate Today’s rings-first order and current-day observed/provisional/missing states in simulator. | Synthetic fixture assertions and a new first-viewport screenshot/VoiceOver review. |
| P1 | Reassess data recovery expectations with owner only if a future physical-device task is requested. | Explicit authorization before any install/restore; do not assume old local data exists. |
| P2 | Complete small-screen and Dynamic Type review for Today, Training, Food, Progress, More and primary sheets. | New synthetic screenshots; fix clipping and safe-area issues. |
| P2 | Visually verify the new preferred rest duration in Training, including large text. | Versioned persistence test passed in the full hosted unit run; UI relaunch check pending. |
| P2 | Add nutrition favorites and copy-previous-meal with snapshot/source preservation. | Store integration tests, synthetic UI path and no historical mutation. |
| P2 | Audit exercise/routine organization and workout history editing. | Interaction counts, persistence tests, accessible navigation. |
| P2 | Resolve isolated-settings theme fixture issue and verify dark/light/black/system. | Simulator screenshots and persisted preference test. |
| P3 | Reduce instructional copy on primary screens and polish transitions/haptics. | Visual/accessibility pass, Reduce Motion behavior. |
| Gate | Widget extension and shared snapshots | Owner approval before App Group entitlement/provisioning change. |
| Gate | Any new Health signals, SwiftData schema change or physical deployment | Explicit owner approval before the operation. |

At each checkpoint update `CURRENT_STATE.md` with commands actually run, result paths, unresolved risks and the next safe task. Do not commit or push automatically.
