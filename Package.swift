// swift-tools-version: 5.9
import PackageDescription

// Runs the platform-independent calculation tests without an iOS SDK.
let package = Package(
    name: "PersonalFitnessCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "PersonalFitnessCore", targets: ["PersonalFitnessCore"])],
    targets: [
        .target(name: "PersonalFitnessCore", path: "PersonalFitness",
                exclude: ["App", "Components", "Dashboard", "Food", "Health", "Models", "Navigation", "Persistence", "Resources",
                          "Progress/DataExportView.swift", "Progress/ProgressModel.swift", "Progress/ProgressStore.swift", "Progress/ProgressView.swift", "Progress/ProgressCharts.swift", "Progress/ReportDetailView.swift", "Progress/WeightHistoryView.swift", "Progress/TrainingReportView.swift", "Workouts/SessionRPEField.swift", "Workouts/WorkoutKeyboard.swift", "Workouts/CardioEditor.swift", "Workouts/ExerciseLibraryView.swift", "Workouts/RoutineEditor.swift",
                          "Workouts/StrengthSessionView.swift", "Workouts/WorkoutDaySummary.swift", "Workouts/WorkoutSessionModel.swift", "Workouts/WorkoutsView.swift"],
                sources: ["Nutrition", "Workouts/Core", "Progress/Core"]),
        .testTarget(name: "PersonalFitnessCoreTests", dependencies: ["PersonalFitnessCore"],
                    path: "PersonalFitnessTests/Calculations")
    ]
)
