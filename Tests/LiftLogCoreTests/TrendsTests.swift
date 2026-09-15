import XCTest
@testable import LiftLogCore

/// The numbers behind the Trends tab: one lift is one lift whatever the log
/// calls it, windows are measured from today, and the verdict reads like a
/// coach would.
final class TrendsTests: XCTestCase {

    private var calendar: Calendar { Session.calendar }
    private func day(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }
    private func lift(_ name: String, _ tokens: String) -> ExerciseEntry {
        ExerciseEntry(name: name, sets: tokens.split(separator: " ").map { WorkoutParser.parseSet(String($0))! })
    }
    private func session(_ d: String, _ lifts: [ExerciseEntry]) -> Session {
        Session(date: day(d), exercises: lifts)
    }

    // MARK: - one lift, whatever the log calls it

    func testSeriesReadsEveryLineOfALiftOnOneDay() {
        let sessions = [session("2026-09-01", [lift("squat", "100x5 100x5"), lift("squat", "120x3")])]
        let series = Analytics.series("squat", metric: .topSet, in: sessions)
        XCTAssertEqual(series.map(\.value), [120])
        XCTAssertEqual(series.first?.tokens, "100x5 100x5 120x3")
    }

    func testSpellingsAndAliasesAreOneLift() {
        let sessions = [
            session("2026-08-03", [lift("bench", "80x5")]),
            session("2026-08-10", [lift("Bench press", "82.5x5")]),
            session("2026-08-17", [lift("bench-press", "85x5")]),
        ]
        XCTAssertEqual(Analytics.series("bench", metric: .topSet, in: sessions).map(\.value), [80, 82.5, 85])
        XCTAssertEqual(Analytics.series("bench-press", metric: .topSet, in: sessions).count, 3)
        XCTAssertEqual(Analytics.allSets("BENCH", in: sessions).count, 3)
        XCTAssertEqual(Analytics.record(for: WorkSet(weight: 90, added: nil, reps: 1), exercise: "bench", in: sessions), .load,
                       "a record on one spelling is judged against every spelling")
        let board = Analytics.liftSummaries(in: sessions, today: day("2026-08-20"), calendar: calendar)
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.first?.name, "bench-press", "the spelling the log used last")
        XCTAssertEqual(board.first?.sessionsEver, 3)
    }

    func testAStrayWeightedLineDoesNotEraseABodyweightLift() {
        var sessions = (0..<10).map { i in
            session("2026-06-\(String(format: "%02d", i + 1))", [lift("chin-ups", "bwx8 bwx7")])
        }
        sessions.append(session("2026-06-20", [lift("chin-ups", "10x6")]))   // meant bw+10x6
        XCTAssertTrue(Analytics.isBodyweight("chin-ups", in: sessions))
        XCTAssertEqual(Analytics.availableMetrics("chin-ups", in: sessions), [.addedLoad, .maxReps])
        let reps = Analytics.series("chin-ups", metric: .maxReps, in: sessions)
        XCTAssertEqual(reps.count, 11)
        let added = Analytics.series("chin-ups", metric: .addedLoad, in: sessions)
        XCTAssertEqual(added.last?.value, 10, "a plain weight on a bodyweight lift reads as added load")
    }

    func testALineDatedInTheFutureStaysOffTheChart() {
        let sessions = [
            session("2026-09-08", [lift("squat", "120x5")]),
            session("2027-09-08", [lift("squat", "60x5")]),
        ]
        let series = Analytics.series("squat", metric: .topSet, in: sessions, through: day("2026-09-15"))
        XCTAssertEqual(series.map(\.value), [120])
        XCTAssertEqual(Analytics.liftSummaries(in: sessions, today: day("2026-09-15"), calendar: calendar).first?.sessionsEver, 1)
    }

    // MARK: - windows

    func testShortTermChangeIsMeasuredFromToday() {
        let sessions = [
            session("2026-01-01", [lift("squat", "100x5")]),
            session("2026-01-15", [lift("squat", "110x5")]),
        ]
        let series = Analytics.series("squat", metric: .topSet, in: sessions)
        XCTAssertNil(Analytics.change(series, sinceDays: 21, now: day("2026-09-15"), calendar: calendar),
                     "a lift left in January has no change in the last three weeks of September")
        XCTAssertEqual(Analytics.change(series, sinceDays: 21, now: day("2026-01-20"), calendar: calendar)?.delta, 10)
        XCTAssertEqual(Analytics.change(series)?.delta, 10)
    }

    func testPercentIsNilOnAZeroBaseline() {
        let sessions = [
            session("2026-08-01", [lift("chin-ups", "bwx8")]),
            session("2026-08-08", [lift("chin-ups", "bw+10x6")]),
        ]
        let change = Analytics.change(Analytics.series("chin-ups", metric: .addedLoad, in: sessions))
        XCTAssertEqual(change?.delta, 10)
        XCTAssertNil(change?.percent)
        XCTAssertFalse(TrendChange(delta: 0, percent: nil).isUp)
        XCTAssertTrue(TrendChange(delta: 0, percent: nil).isFlat)
    }

    func testEpleyIsCappedAtADozenRepsAndASingleIsItsOwnMax() {
        XCTAssertEqual(Analytics.epley(weight: 140, reps: 1), 140)
        XCTAssertEqual(Analytics.epley(weight: 70, reps: 25), Analytics.epley(weight: 70, reps: 12))
        XCTAssertLessThan(Analytics.epley(weight: 70, reps: 25), Analytics.epley(weight: 100, reps: 5))
    }

    func testNegativeOrZeroRepsAreUnreadable() {
        XCTAssertNil(WorkoutParser.parseSet("100x-5"))
        XCTAssertNil(WorkoutParser.parseSet("100x0"))
        XCTAssertEqual(WorkoutParser.unreadableLines(in: "2026-09-01 squat 100x-5\n").map(\.number), [1])
    }

    // MARK: - every lift

    func testLiftSummariesNameTheBestAndWhenItWasFirstHit() {
        let sessions = [
            session("2026-08-20", [lift("squat", "110x3 100x5"), lift("chin-ups", "bw+10x5")]),
            session("2026-09-01", [lift("squat", "100x5 100x5 100x5")]),
            session("2026-09-08", [lift("squat", "110x3"), lift("chin-ups", "bwx8 bw+5x6")]),
        ]
        let board = Analytics.liftSummaries(in: sessions, today: day("2026-09-11"), calendar: calendar)
        XCTAssertEqual(board.map(\.name), ["squat", "chin-ups"], "last done first; same day in the order done")
        let squat = board[0]
        XCTAssertEqual(squat.best?.token, "110x3")
        XCTAssertEqual(squat.bestDate, day("2026-08-20"), "the day the standing best was first lifted, not repeated")
        XCTAssertEqual(squat.daysSinceBest(today: day("2026-09-11"), calendar: calendar), 22)
        XCTAssertEqual(squat.daysSinceLast(today: day("2026-09-11"), calendar: calendar), 3)
        XCTAssertEqual(squat.sessionsInFourWeeks, 3)
        XCTAssertEqual(board[1].best?.token, "bw+10x5")
        XCTAssertEqual(board[1].lastTokens, "bwx8 bw+5x6")
    }

    func testDigestCarriesTheDoseReadingWhenGivenOne() {
        let sessions = [session("2026-09-08", [lift("squat", "100x5")])]
        let digest = CoachContext.liftDigest(from: sessions, today: day("2026-09-11"), calendar: calendar,
                                             dose: { $0.name == "squat" ? "Flat for 3 weeks at 3 squat sets a week." : nil })!
        XCTAssertTrue(digest.contains("- squat: last 2026-09-08 (3 days ago) 100x5 · best 100x5 on 2026-09-08 · 1 session in the last 4 weeks, 1 ever · dose: Flat for 3 weeks"), digest)
    }

    // MARK: - the verdict

    private func squatDay(_ d: String, _ kg: Double) -> Session {
        session(d, [lift("squat", "\(WorkSet.formatWeight(kg))x5 \(WorkSet.formatWeight(kg))x5 \(WorkSet.formatWeight(kg))x5")])
    }

    func testOneBadWeekAfterARecordIsNotAStall() {
        let sessions = [squatDay("2026-08-04", 100), squatDay("2026-08-11", 102.5),
                        squatDay("2026-08-18", 107.5), squatDay("2026-08-25", 105)]
        let dose = DoseResponse.make(for: "squat", in: sessions, map: MuscleMap(), endingOn: day("2026-09-06"), calendar: calendar)!
        guard case .progressing(let delta, _, _) = dose.verdict else { return XCTFail("\(dose.verdict)") }
        XCTAssertEqual(delta, 7.5)
        XCTAssertTrue(dose.summary.hasSuffix("Done once a week."), dose.summary)
        XCTAssertEqual(dose.sessionsPerWeek, 1)
    }

    func testAStallIsCountedInCalendarWeeks() {
        // Every third week, never moving: flat for six weeks, not two.
        let sessions = [squatDay("2026-07-20", 100), squatDay("2026-08-10", 100), squatDay("2026-08-31", 100)]
        let dose = DoseResponse.make(for: "squat", in: sessions, map: MuscleMap(), endingOn: day("2026-09-06"), calendar: calendar)!
        guard case .stalledLow(let weeks, _, _) = dose.verdict else { return XCTFail("\(dose.verdict)") }
        XCTAssertEqual(weeks, 6)
        XCTAssertTrue(dose.summary.hasPrefix("Flat for 6 weeks"), dose.summary)
    }

    func testTheCoachQuestionCarriesTheVerdictAndTheWeeks() {
        let sessions = [squatDay("2026-08-04", 100), squatDay("2026-08-11", 100),
                        squatDay("2026-08-18", 100), squatDay("2026-08-25", 100)]
        let dose = DoseResponse.make(for: "squat", in: sessions, map: MuscleMap(), endingOn: day("2026-09-06"), calendar: calendar)!
        let question = dose.coachQuestion(today: day("2026-09-06"), calendar: calendar)
        XCTAssertTrue(question.hasPrefix("Trends reads my squat as: Flat for 3 weeks"), question)
        XCTAssertTrue(question.contains("- week of 2026-08-24: 3 squat sets over 1 day, 3 quads sets in all, best 100 kg"), question)
        XCTAssertTrue(question.contains("- week of 2026-07-13: 0 squat sets over 0 days, 0 quads sets in all, not done"), question)
    }

    // MARK: - muscle overrides follow the lift, not the spelling

    func testAnOverrideOnOneSpellingCountsForEverySpelling() {
        var map = MuscleMap()
        map.set(.lift(.chest, half: .triceps, .frontDelts), for: "bench")
        XCTAssertTrue(map.isOverridden("bench-press"))
        XCTAssertTrue(map.isOverridden("Bench"))
        XCTAssertEqual(map.share(for: "bench-press"), map.share(for: "bench"))
        map.set(nil as MuscleMap.Share?, for: "bench-press")
        XCTAssertFalse(map.isOverridden("bench"))
    }
}
