import XCTest
@testable import LiftLogCore

final class VelocityTests: XCTestCase {

    private func url(_ s: String) -> URL { URL(string: s)! }

    func testReadsBarVeloHandoff() throws {
        let v = try XCTUnwrap(VelocitySet(url: url(
            "grepp://velocity?lift=Back%20Squat&load=100&mcv=0.52,0.50,0.41&peak=0.71,0.66,0.55&rom=0.68,0.70,0.69&date=2026-11-05")))
        XCTAssertEqual(v.lift, "back-squat")
        XCTAssertEqual(v.load, 100)
        XCTAssertEqual(v.reps, 3)
        XCTAssertEqual(v.peak.count, 3)
        XCTAssertEqual(Session.dateFormatter.string(from: v.date), "2026-11-05")
        XCTAssertEqual(v.loss!, 0.2115, accuracy: 0.001)
        XCTAssertEqual(v.line, "2026-11-05 back-squat 100x3 mcv 0.52 0.50 0.41 loss 21%")
        XCTAssertEqual(v.summary, "0.52 → 0.41 m/s · loss 21%")
    }

    func testBodyweightAndMissingOptionalFields() throws {
        let v = try XCTUnwrap(VelocitySet(url: url("grepp://velocity?lift=chin-ups&mcv=0.6,0.5")))
        XCTAssertNil(v.load)
        XCTAssertEqual(v.token, "bwx2")
        XCTAssertEqual(v.peak, [])
    }

    func testRefusesAnythingHalfRead() {
        XCTAssertNil(VelocitySet(url: url("grepp://log")))
        XCTAssertNil(VelocitySet(url: url("grepp://velocity?lift=squat")))                  // no reps
        XCTAssertNil(VelocitySet(url: url("grepp://velocity?mcv=0.5")))                      // no lift
        XCTAssertNil(VelocitySet(url: url("grepp://velocity?lift=squat&mcv=0.5,abc")))       // garbage speed
        XCTAssertNil(VelocitySet(url: url("grepp://velocity?lift=squat&load=-5&mcv=0.5")))   // bad load
        XCTAssertNil(VelocitySet(url: url("barvelo://velocity?lift=squat&mcv=0.5")))         // wrong app
    }

    func testMeasureURLRoundTripsTheLift() throws {
        let u = VelocitySet.measureURL(lift: "bench-press", load: 82.5, reps: 5)
        XCTAssertEqual(u.scheme, "barvelo")
        XCTAssertEqual(u.host, "measure")
        let items = try XCTUnwrap(URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "lift" }?.value, "bench-press")
        XCTAssertEqual(items.first { $0.name == "load" }?.value, "82.5")
        XCTAssertEqual(items.first { $0.name == "reps" }?.value, "5")
        XCTAssertEqual(items.first { $0.name == "return" }?.value, "grepp")
    }

    private let day = Session.dateFormatter.date(from: "2026-11-06")!
    private func line(_ n: Int, _ w: Double, _ r: Int) -> ExerciseEntry {
        ExerciseEntry(name: "squat", sets: Array(repeating: WorkSet(weight: w, added: nil, reps: r), count: n))
    }

    func testLandedSetIsNumberedAndSpelledAsLogged() {
        let measured = VelocitySet(date: day, lift: "squat", load: 100, mcv: [0.52, 0.50, 0.47, 0.45, 0.41])
        // Three identical sets: the third one was filmed.
        let v = measured.landed(as: WorkSet(weight: 100, added: nil, reps: 5), number: 3, lift: "squat", on: day)
        XCTAssertEqual(v.line, "2026-11-06 squat set 3 100x5 mcv 0.52 0.50 0.47 0.45 0.41 loss 21%")
    }

    func testLoggedRepsWinTheTokenSpeedsStayAsMeasured() {
        // BarVelo missed a rep: five speeds, six reps logged.
        let measured = VelocitySet(date: day, lift: "squat", load: 100, mcv: [0.52, 0.50, 0.47, 0.45, 0.41])
        let v = measured.landed(as: WorkSet(weight: 102.5, added: nil, reps: 6), number: 1, lift: "back-squat", on: day)
        XCTAssertEqual(v.line, "2026-11-06 back-squat set 1 102.5x6 mcv 0.52 0.50 0.47 0.45 0.41 loss 21%")
        XCTAssertEqual(v.mcv.count, 5)
    }

    func testUnlandedSpeedsHaveNoSetNumber() {
        let v = VelocitySet(date: day, lift: "squat", load: 100, mcv: [0.5])
        XCTAssertEqual(v.line, "2026-11-06 squat 100x1 mcv 0.50 loss 0%")
    }

    func testSetNumberCountsAlongTheDaysLinesOfTheLift() {
        // Nothing logged yet: the first set landed is set 1.
        XCTAssertEqual(VelocitySet.setNumber(dayLinesOfLift: [], editingOccurrence: nil, inHand: 1), 1)
        // The day's squat line (2 sets) loaded back and a third set landed: set 3.
        XCTAssertEqual(VelocitySet.setNumber(dayLinesOfLift: [line(2, 100, 5)], editingOccurrence: 0, inHand: 3), 3)
        // Squats twice in a day: a new, second line's first set follows the first line's 3.
        XCTAssertEqual(VelocitySet.setNumber(dayLinesOfLift: [line(3, 100, 5)], editingOccurrence: nil, inHand: 1), 4)
        // Editing the second of two lines: the first line's sets come first.
        XCTAssertEqual(VelocitySet.setNumber(dayLinesOfLift: [line(3, 100, 5), line(2, 80, 8)], editingOccurrence: 1, inHand: 3), 6)
    }

    func testFileGetsAHeaderOnceAndLinesAppend() {
        let a = VelocitySet(date: Session.dateFormatter.date(from: "2026-11-04")!, lift: "squat", load: 100, mcv: [0.5, 0.5])
        let b = VelocitySet(date: Session.dateFormatter.date(from: "2026-11-05")!, lift: "squat", load: 105, mcv: [0.45])
        let file = VelocitySet.appending(b, to: VelocitySet.appending(a, to: ""))
        XCTAssertEqual(file.components(separatedBy: "# Bar speed").count, 2)
        XCTAssertEqual(VelocitySet.recentLines(file), [
            "2026-11-04 squat 100x2 mcv 0.50 0.50 loss 0%",
            "2026-11-05 squat 105x1 mcv 0.45 loss 0%",
        ])
        XCTAssertEqual(VelocitySet.recentLines(file, limit: 1).count, 1)
    }
}

final class VelocityCoachTests: XCTestCase {
    func testCoachSeesMeasuredSetsOnlyWhenThereAreSome() {
        XCTAssertEqual(CoachContext.barSpeedBrief(""), "")
        XCTAssertEqual(CoachContext.barSpeedBrief("# Bar speed\n\nprose only\n"), "")

        let file = "# Bar speed\n\n2026-11-05 squat 100x5 mcv 0.52 0.50 0.47 0.45 0.41 loss 21%\n"
        let excerpt = CoachContext.excerpt(from: [Session(date: Session.dateFormatter.date(from: "2026-11-05")!,
                                                         exercises: [ExerciseEntry(name: "squat", sets: [WorkSet(weight: 100, added: nil, reps: 5)])])])
        let prompt = CoachContext.systemPrompt(for: excerpt, brief: CoachContext.Brief(velocity: file))
        XCTAssertTrue(prompt.contains("<bar-speed>\n2026-11-05 squat 100x5 mcv 0.52"), prompt)
        XCTAssertFalse(CoachContext.systemPrompt(for: excerpt, brief: .none).contains("<bar-speed>"))
        // The coach is told how to join a line to its set.
        XCTAssertTrue(prompt.contains("Join a line to the log by day, lift and set number"), prompt)
        XCTAssertFalse(prompt.contains("LiDAR"))
    }
}
