import HealthKit

enum HealthAvailability {
    // Availability is not permission. No authorization or query runs at launch.
    static var isSupported: Bool { HKHealthStore.isHealthDataAvailable() }
}
