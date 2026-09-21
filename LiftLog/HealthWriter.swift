import Foundation
import HealthKit

/// Today's lifting as one workout in Apple Health, so it counts in Fitness:
/// a traditional strength training session from the first set to the last
/// lift finished, saved when a lift is finished and replaced as the day
/// grows. Nothing is read from Health; the log stays the record.
@MainActor
enum HealthWriter {
    private static let health = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The switch in Settings ▸ Apple Health. Off until the lifter turns it
    /// on, since the first save asks Health's own permission.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Prefs.healthEnabled) }

    static var status: HKAuthorizationStatus { health.authorizationStatus(for: .workoutType()) }

    /// Health was asked and said no. A Bool, so no screen needs HealthKit's
    /// own types: the project keeps member lookups to modules it imports.
    static var isDenied: Bool { status == .sharingDenied }

    /// Ask to write workouts, and only that. True when allowed.
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        } catch {
            return false
        }
        return status == .sharingAuthorized
    }

    /// Save the day as a workout from its first set to now; a day saved
    /// already is replaced, so a session that grows is one workout, not
    /// three. Only a day with a clock — today's, from the Log tab — is
    /// saved: an older day corrected in History has no start to give.
    static func sync(_ session: Session, store: Store) async {
        guard isEnabled, isAvailable, status == .sharingAuthorized,
              let start = store.sessionStart(on: session.date) else { return }
        let end = Date()
        guard end.timeIntervalSince(start) >= 60 else { return }
        do {
            if let saved = store.healthWorkout(on: session.date), let uuid = UUID(uuidString: saved) {
                try await delete(uuid)
            }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let builder = HKWorkoutBuilder(healthStore: health, configuration: configuration, device: .local())
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Grepp",
                                           HKMetadataKeyIndoorWorkout: true])
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout() {
                store.setHealthWorkout(workout.uuid.uuidString, on: session.date)
            }
        } catch {
            // Health is a mirror of the log, not the log: a save that fails
            // is tried again at the next lift, and the file is unaffected.
        }
    }

    private static func delete(_ uuid: UUID) async throws {
        let predicate = HKQuery.predicateForObject(with: uuid)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            health.execute(query)
        }
        for sample in samples {
            try await health.delete(sample)
        }
    }
}
