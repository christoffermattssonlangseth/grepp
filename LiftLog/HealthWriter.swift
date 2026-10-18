import Foundation
import HealthKit

/// Today's lifting as one workout in Apple Health, so it counts in Fitness:
/// a traditional strength training session from the first set to the last
/// lift finished, saved when a lift is finished and replaced as the day
/// grows. Nothing is read from Health but its own workouts; the log stays
/// the record.
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
        await serialized(session.dateString) { await save(session, store: store) }
    }

    /// One Health job per day at a time. Two lifts finished close together
    /// would otherwise both delete the old workout and both save a new one:
    /// two workouts for one session. Each waits for the one before it, and
    /// reads the saved id only once that one is done.
    private static var running: [String: Task<Void, Never>] = [:]

    private static func serialized(_ day: String, _ job: @escaping @MainActor () async -> Void) async {
        let before = running[day]
        let task = Task { @MainActor in
            await before?.value
            await job()
        }
        running[day] = task
        await task.value
        if running[day] == task { running[day] = nil }
    }

    private static func save(_ session: Session, store: Store) async {
        guard isEnabled, isAvailable, status == .sharingAuthorized,
              let start = store.sessionStart(on: session.date) else { return }
        let now = Date()
        guard now.timeIntervalSince(start) >= 60 else { return }
        // The same length Strava is given: a lift added hours after the
        // session (a forgotten one, logged that evening) must not stretch a
        // morning workout to fourteen hours, so past six it's the hour guess.
        let end = start.addingTimeInterval(StravaPost.elapsed(start: start, end: now))
        do {
            if let saved = store.healthWorkout(on: session.date), let uuid = UUID(uuidString: saved) {
                try await delete(uuid)
            }
            if let id = try await create(start: start, end: end) {
                store.setHealthWorkout(id, on: session.date)
            }
        } catch {
            // Health is a mirror of the log, not the log: a save that fails
            // is tried again at the next lift, and the file is unaffected.
        }
    }

    /// The day left the log (its last lift deleted, or moved elsewhere): its
    /// workout leaves Health too. The mark stays if Health can't be reached,
    /// so a later save of that day still replaces it.
    static func remove(on date: Date, store: Store) async {
        let day = Session.dateFormatter.string(from: date)
        await serialized(day) {
            guard isAvailable, status == .sharingAuthorized,
                  let saved = store.healthWorkout(on: date) else { return }
            do {
                if let uuid = UUID(uuidString: saved) { try await delete(uuid) }
                store.clearHealthWorkout(on: date)
            } catch {}
        }
    }

    /// A whole day moved to another date: its workout moves with it, the
    /// same hours on the new day. Health samples can't be edited, so it's
    /// saved again there and the old one deleted. A day moved onto one that
    /// has its own workout just loses the moved one — one day, one workout.
    static func move(from date: Date, to target: Date, store: Store) async {
        let day = Session.dateFormatter.string(from: date)
        await serialized(day) {
            guard isAvailable, status == .sharingAuthorized,
                  let saved = store.healthWorkout(on: date), let uuid = UUID(uuidString: saved) else { return }
            do {
                let old = try await workout(uuid)
                try await delete(uuid)
                store.clearHealthWorkout(on: date)
                guard let old, store.healthWorkout(on: target) == nil else { return }
                let calendar = Calendar.current
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                                   to: calendar.startOfDay(for: target)).day ?? 0
                guard let start = calendar.date(byAdding: .day, value: days, to: old.startDate),
                      let end = calendar.date(byAdding: .day, value: days, to: old.endDate),
                      let id = try await create(start: start, end: end) else { return }
                store.setHealthWorkout(id, on: target)
            } catch {}
        }
    }

    /// A strength workout from `start` to `end`; its id, or nil if Health
    /// saved nothing.
    private static func create(start: Date, end: Date) async throws -> String? {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: health, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Grepp",
                                       HKMetadataKeyIndoorWorkout: true])
        try await builder.endCollection(at: end)
        return try await builder.finishWorkout()?.uuid.uuidString
    }

    private static func workout(_ uuid: UUID) async throws -> HKSample? {
        try await samples(uuid).first
    }

    private static func delete(_ uuid: UUID) async throws {
        for sample in try await samples(uuid) {
            try await health.delete(sample)
        }
    }

    private static func samples(_ uuid: UUID) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForObject(with: uuid)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            health.execute(query)
        }
    }
}
