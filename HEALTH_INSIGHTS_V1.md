# Health insights v1

## What it does

Health Insights v1 is a local, deterministic presentation layer over the existing Recovery, Strain/activity-load, and sleep engines. It adds no HealthKit reads, writes, model entities, exports, or changes to existing scores. The Today dashboard shows at most four concise cards, each expandable to reveal its exact input description.

## Rules

1. If the selected day is current, the score is provisional, or scoring/sleep is loading, show only “Today is still updating.” No forecast is called a measurement.
2. If Recovery has an eligible score, show its rounded score and the highest weighted eligible contribution. The detail is the pre-existing component's source/window/coverage explanation.
3. If Recovery lacks eligible coverage, show a setup explanation assembled from each missing component. This never treats missing records as zero.
4. If Strain has a compatible observed load, show its score, observed quantity and unit, plus original reconciliation notes. Otherwise show the unavailable explanation.
5. A training-context sentence uses only the displayed heuristic scores. It says neither safe nor unsafe, makes no injury/illness/overtraining claim, and does not attribute a score change to a behavior.
6. A sleep insight is shown only when the existing sleep analysis produces an observation. It explicitly describes a trend, not a cause of Recovery.

## Visibility and notifications

`personalFitness.insights.v1` stores one validated boolean: show/hide the Today insight card. It does not affect records or scores. Notifications are explicitly off: no permission, schedule, background work, or repeated notification behavior exists in this version.

## Limitations

Insights reflect the coverage and limits of their upstream engines. Health read authorization can be unavailable even after a request, Apple Health can sync later, and a historical day does not prove complete coverage. They are coaching context, not medical assessment, physiological certification, causal attribution, injury prediction, or generic encouragement.

## Validation

Pure tests verify deterministic selection, missing Recovery/load, partial-day suppression and supported training-context wording. Existing tests continue to cover outliers, duplicate and conflicting signals, source changes, DST, missing data, and unchanged legacy scoring. Hosted UI verification is pending a functioning CoreSimulator runtime.
