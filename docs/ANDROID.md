# Android support

**PersonalFitness cannot currently be installed on Android.** This repository contains a native SwiftUI iOS application. There is no Android project, APK, Android build command or Android installation link. Downloading the source or renaming an iPhone package will not make it run on Android.

An Android edition would require a separate application, for example Kotlin/Jetpack Compose UI, Room local persistence and an authorized Health Connect adapter. Health Connect is Android's framework for sharing health/fitness data; it is not a direct Apple Health/Apple Watch bridge. Available measurements depend on actual supported Android sources and permissions. [Android Health Connect documentation](https://developer.android.com/health-and-fitness/health-connect).

The nutrition rules, snapshot semantics, calendar-day policy and test cases in this project can guide a port, but SwiftUI, SwiftData and HealthKit implementations cannot be reused as an Android binary. A versioned local JSON export now preserves iPhone records, but no Android importer or tested cross-platform transfer exists. An Android port would need to implement and validate those semantics explicitly.

Recommended future milestones:

1. Validate the current iPhone app and add tested local export/import.
2. Define an Android scope and compatible file format without a backend requirement.
3. Implement and test Android nutrition/training first, then Health Connect where supported.
4. Decide on private APK installation versus Play distribution only after an actual Android app exists.

No Android implementation or distribution is part of this documentation update.
