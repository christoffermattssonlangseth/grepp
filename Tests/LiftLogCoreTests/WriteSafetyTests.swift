import XCTest
@testable import LiftLogCore

/// The file is the lifter's. A save changes the line it means to and no other.
final class WriteSafetyTests: XCTestCase {

    private func date(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }
    private func entry(_ name: String, _ tokens: String) -> ExerciseEntry {
        ExerciseEntry(name: name, sets: tokens.split(separator: " ").map { WorkoutParser.parseSet(String($0))! })
    }

    private let file = "2026-08-30 bench press 60x5  60x5\n2026-08-30 Squat 100x5\n\n2026-09-01 chin-ups bwx8\n"

    func testUntouchedLinesComeBackByteForByte() {
        let sessions = WorkoutParser.parse(file)
        XCTAssertEqual(WorkoutParser.serialize(sessions), file, "the spacing, the casing, the two-word name: all as written")
        XCTAssertEqual(sessions[0].exercises[0].name, "bench-press", "read as one lift all the same")
    }

    func testOnlyTheLineThatWasSavedIsRewritten() {
        var sessions = WorkoutParser.parse(file)
        WorkoutParser.merge(entry("squat", "105x5 105x5"), on: date("2026-08-30"), into: &sessions)
        XCTAssertEqual(WorkoutParser.serialize(sessions),
                       "2026-08-30 bench press 60x5  60x5\n2026-08-30 squat 105x5 105x5\n\n2026-09-01 chin-ups bwx8\n",
                       "Squat matched and replaced; the bench line untouched")
    }

    func testAMovedLineIsRewrittenWithItsNewDate() {
        var sessions = WorkoutParser.parse(file)
        WorkoutParser.move("squat", on: date("2026-08-30"), to: date("2026-08-31"), in: &sessions)
        XCTAssertEqual(WorkoutParser.serialize(sessions),
                       "2026-08-30 bench press 60x5  60x5\n\n2026-08-31 Squat 100x5\n\n2026-09-01 chin-ups bwx8\n")
    }

    func testOneLiftIsOneLineWhateverItIsCalled() {
        var sessions = WorkoutParser.parse("2026-09-01 bench-press 80x5\n")
        WorkoutParser.merge(entry("bench", "82.5x5"), on: date("2026-09-01"), into: &sessions)
        XCTAssertEqual(sessions[0].exercises.count, 1, "bench is bench-press: replaced, not a second line")
        XCTAssertEqual(WorkoutParser.serialize(sessions), "2026-09-01 bench 82.5x5\n")
        WorkoutParser.remove("Bench Press", on: date("2026-09-01"), from: &sessions)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testAnOverrideSavedUnderAnOldSpellingIsTheLiftsNow() {
        var map = MuscleMap(rawValue: "bench=chest:1+triceps:1")!
        XCTAssertTrue(map.isOverridden("bench-press"))
        XCTAssertEqual(map.share(for: "bench"), map.share(for: "bench-press"))
        XCTAssertTrue(map.rawValue.hasPrefix("bench-press="), map.rawValue)
        map.set(nil as MuscleMap.Share?, for: "bench-press")
        XCTAssertFalse(map.isOverridden("bench"))
        XCTAssertEqual(map.share(for: "bench"), MuscleMap.builtInShare(for: "bench-press"))
    }
}
