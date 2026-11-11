# Recovery and Strain method v1 research note

## Scope and non-equivalence

Advanced Model v1 is an opt-in calculation preview. It does not replace PersonalFitness' existing displayed Recovery/Strain model, does not use a WHOOP or Bevel score, and is not equivalent to either product. WHOOP and Bevel publish input concepts, not complete public weights, transformations, artifact handling, calibration, or proprietary illness models. This document specifies a transparent local heuristic only; it does not diagnose illness, certify readiness, predict injury, or prescribe a safe load.

## Public sources and what they establish

- WHOOP publicly lists overnight HRV, RHR, sleep, respiratory rate, skin temperature and SpO2 as Recovery inputs, says HRV is compared to a 30-day baseline, and describes Sleep Performance concepts. It does **not** publish a reproducible complete score equation.
- Bevel publicly states that its Recovery needs sleep, HRV, RHR, and sufficient baseline data. Its weighting/transformations are not public.
- Apple HealthKit identifies `heartRateVariabilitySDNN`, `restingHeartRate`, `respiratoryRate`, `oxygenSaturation`, and heartbeat-series data. Existing PersonalFitness consent reads only SDNN and RHR. SDNN is a standard deviation of NN intervals; it is not RMSSD and is never converted to RMSSD here.
- Applied HRV literature supports within-person, repeated, consistent-context interpretation and warns against isolated readings and unreported artifact processing. This supports the model's same-source, robust-baseline and missing-data gates, not clinical validity.

## Existing model audit

The existing Recovery implementation has reusable strengths: 28-day same-source baseline selection; median/MAD outlier gates; duplicate/conflict rejection; minimum distinct baseline/recent day gates; SDNN/RHR/sleep/recent-load contributions with renormalized weights; explicit local-day windows; and an independent Health consent flow. Existing Strain reconciles overlapping manual/Health workouts and uses one homogeneous fallback unit at a time. It intentionally avoids mixing session-RPE, minutes, active calories, and steps.

Gaps: it does not have authorized HR-series coverage, HR zones, respiratory rate, wrist temperature, oxygen saturation, stage-quality scoring, or an explicitly separated advanced comparison view. Current Health access cannot supply those missing signals.

## Advanced Recovery preview formula

For each available vital, derive one median per local day from a single selected source. Let `m` be the median of eligible prior daily values and `MAD = median(|x - m|)`. Require at least 14 prior days from one source. For today's value `x`, use `s = max(1, 1.4826 × MAD, 0.05 × |m|)` and `z = (x - m)/s`.

- SDNN: `score = clamp(50 + 15z, 0, 100)`.
- RHR: `score = clamp(50 - 15z, 0, 100)`.
- Other vitals are deliberately unavailable until separately authorized and validated; they are never filled with a population default.
- Combine eligible contributions by `sum(score_i × weight_i) / sum(weight_i)`. Default candidate weights are SDNN 35, RHR 25, sleep duration 25, recent-load context 15. Missing inputs are omitted and the effective weights renormalize. Confidence is eligible weight / configured total weight.

The legacy model remains the regression comparator. A score should say “heuristic” and show raw current/baseline values, source, windows, sample counts, excluded data and confidence.

## Advanced cardiovascular strain preview

Only with explicit resting and maximum-HR assumptions and one coherent source: for adjacent samples no more than 120 seconds apart, `r = clamp((HR - RHR)/(HRmax - RHR), 0, 1)` and `TRIMP += Δminutes × r × exp(1.92r)`. Time is also recorded in five reserve zones. Coverage is observed interval seconds / workout duration; below 50%, TRIMP is unavailable. This nonlinear exposure is not added to strength tonnage, session-RPE, active calories, or steps.

Strength stays a separate model: external volume, reps, completed sets and optional session-RPE are useful for within-exercise/progression reporting but have incompatible units. Any future combined recommendation must normalize each modality against its own observed baseline before weighting and disclose every assumption.

## Coaching guardrails

Any future suggested range should be described as a training-planning prompt, not medical or injury guidance. It should require adequate Recovery confidence and a homogeneous recent-load baseline; otherwise show a setup/insufficient-data state. The recommendation should expose its recovery score, acute and baseline load, coverage and whether it is observed versus assumed.

## Authorization gate

Adding heart-rate series, respiratory-rate, oxygen-saturation or wrist-temperature reads would add HealthKit authorization scope. No request code, entitlement, or privacy prompt was changed. Implementing authorization-independent pure code is complete; connecting these inputs or making the preview selectable requires owner approval followed by explicit HealthKit integration, migration/compatibility review, and simulator/device-independent tests.

## Synthetic checks

`WellnessScoringTests` covers an elevated same-source SDNN input, absent oxygen saturation, explicit HR assumptions, dense HR coverage and sparse-coverage rejection. Existing tests already cover normal/missing/outlier/duplicate/inconsistent-source/partial-day/DST legacy behavior. No user measurement was used.
