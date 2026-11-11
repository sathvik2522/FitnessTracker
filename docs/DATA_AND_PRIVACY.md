# Data and privacy

`AppPersistence` creates a local SwiftData container with eight entities: FoodEntry, SavedFood, SavedMeal, ExerciseRecord, WorkoutRoutine, StrengthSession, CardioSession and ManualWeight. CloudKit is disabled. Preferences and preserved estimates use local UserDefaults. An unreadable store is not automatically replaced. Food and workout snapshots retain historical values when library definitions change. Schema and Codable migrations require review and tests.

Health samples are read into memory after explicit consent; the app requests no writes. The widget receives a versioned, privacy-controlled snapshot via an App Group; display values default to hidden. Existing group IDs are owner-specific. No app backend, analytics or external food service is required.

JSON export is user initiated and may contain sensitive personal records. There is **no in-app restore**, so an export alone is not a proven migration strategy. Removing the app can erase its local container; reinstalling after expiration without deleting the app is different from uninstalling. Apple Health data is separate. iOS device backup/restore behavior depends on device settings and is not verified as an app-specific restore path. Never commit exports, stores, logs, Health samples or device containers.
