# Scoring and energy review captures — October 20, 2026

These are **actual simulator screenshots**, not design mockups or the owner's health data. UI tests use a unique temporary disk store/preferences suite and explicitly disable local Health request-completion flags. No physical iPhone was installed or launched in this milestone.

- [Energy progress](energy-progress-synthetic.png): the test entered a synthetic 1,500 kcal food entry and an explicit independent 2,000 kcal expenditure estimate for a closed historical day. The arc is 75% intake/expenditure, center −500 kcal. Zero macros belong only to this deliberately simplified test fixture; they are not nutritional claims about a real food. No calorie-intake goal was configured. Empty Strain/Recovery tracks correctly show setup actions.
- [Energy detail](energy-details-synthetic.png): the same test opens the signed balance, actual input values, missing Health inputs, preserved estimate, calculation time and ratio explanation. The rest of the source/assumption text is scrollable.

Both attachments are retained by `ScoringFlowTests.testEnergyProgressUsesLoggedIntakeOverPreservedHistoricalExpenditure` in the successful `work/scoring-review/EnergyFocused.xcresult` run: **204/204 passed (203 unit + 1 UI), zero failures/skips/runtime warnings**. The UI case also verifies the ratio after app relaunch.

[Implementation review](../../IMPLEMENTATION_REVIEW_REPORT.md) contains formulas, source selection, historical rules, exact verification receipts, limitations and the approval gate. [Changed files](CHANGED_FILES.txt) compares this milestone with the preserved pre-task source archive, including earlier uncommitted work. [Build/test input hashes](SOURCE_HASHES.txt) identify the source used for verification; ignored local signing configuration is excluded.

The final complete scheme also passed **221/221 (203 unit + 18 UI), zero failures/skips/runtime warnings** in `EnergyComplete.xcresult`, with unchanged hashed source. [Strain progress](strain-progress-synthetic.png) and [Strain detail](strain-details-synthetic.png) are actual final-run captures: a 10-minute cardio log with explicit RPE 6 produces 60 load units / provisional 300-unit target = **20/100**. These are separate isolated synthetic scenarios, not personal measurements.
