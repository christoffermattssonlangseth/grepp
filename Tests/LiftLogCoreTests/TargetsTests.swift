import XCTest
@testable import LiftLogCore

final class TargetsTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = Session.dateFormatter.timeZone
        return c
    }
    private func day(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }

    func testTargetsAreReadOutOfProseForLiftsTheLogKnows() {
        let goals = """
        # Goals

        - 140 kg squat by June. Currently 120.
        - Bench press 100 kg by 1 Dec 2026
        - chin-ups 12 reps
        - Lose 3 kg by summer.
        - romanian deadlift 120 kg
        """
        let targets = Targets.parse(goals, lifts: ["squat", "bench", "chin-ups", "deadlift", "romanian-deadlift"],
                                    today: day("2026-09-21"), calendar: utc)
        XCTAssertEqual(targets.map(\.lift), ["squat", "bench-press", "chin-ups", "romanian-deadlift"])
        XCTAssertEqual(targets.map(\.value), [140, 100, 12, 120])
        XCTAssertEqual(targets.map(\.kind), [.topSet, .topSet, .reps, .topSet])
        XCTAssertEqual(targets[0].by, day("2027-06-30"), "a month alone is the end of its next occurrence")
        XCTAssertEqual(targets[1].by, day("2026-12-01"))
        XCTAssertNil(targets[2].by)
    }

    func testProseHeadingsAndBareNumbersAreReadToo() {
        let goals = """
        # Goals

        Squat 140 and bench press 100 kg until June 2027; deadlift 180 kg before christmas.

        ## Chin-ups
        Target: 15 reps by March.
        Currently 11.

        **Over head press**
        - 60 kg. Was 52.5 in August.
        - 3x5 at 55 kg first
        """
        let lifts = ["squat", "bench-press", "deadlift", "chin-ups", "over-head-press"]
        let targets = Targets.parse(goals, lifts: lifts, today: day("2026-09-21"), calendar: utc)
        XCTAssertEqual(targets.map(\.lift), ["squat", "bench-press", "deadlift", "chin-ups", "over-head-press"])
        XCTAssertEqual(targets.map(\.value), [140, 100, 180, 15, 60])
        XCTAssertEqual(targets.map(\.kind), [.topSet, .topSet, .topSet, .reps, .topSet])
        XCTAssertEqual(targets[0].by, day("2027-06-30"), "one date for the sentence")
        XCTAssertEqual(targets[1].by, day("2027-06-30"))
        XCTAssertNil(targets[2].by, "christmas is not a date")
        XCTAssertEqual(targets[3].by, day("2027-03-31"))
        XCTAssertNil(targets[4].by)
        XCTAssertEqual(Targets.number(in: "3x5 at 55")?.value, 55, "a scheme is not a load")
        XCTAssertNil(Targets.number(in: "3x5 for 6 weeks"))
        XCTAssertNil(Targets.number(in: "2026 is the year"))
    }

    func testOneRepMaxGoalsAreMaxesByLineOrBySection() {
        let goals = """
        # 1RM goals
        - Squat 140 kg by June
        - Bench 100

        ## Other
        - deadlift 180 kg
        - Over head press one rep max 70 kg
        - chin-ups 15 reps
        """
        let targets = Targets.parse(goals, lifts: ["squat", "bench-press", "deadlift", "over-head-press", "chin-ups"],
                                    today: day("2026-09-21"), calendar: utc)
        XCTAssertEqual(targets.map(\.lift), ["squat", "bench-press", "deadlift", "over-head-press", "chin-ups"])
        XCTAssertEqual(targets.map(\.kind), [.oneRepMax, .oneRepMax, .topSet, .oneRepMax, .reps])
        XCTAssertEqual(targets[0].kind.metric, .oneRepMax)
        XCTAssertTrue(Targets.isMax("e1RM 140"))
        XCTAssertTrue(Targets.isMax("1 rm"))
        XCTAssertFalse(Targets.isMax("3x5 at 100 kg"))
    }

    func testIncrementsAreNotTheTargetAndTheLargestLoadIs() {
        let goals = """
        - Deadlift: +5 kg per month, to 160 kg by December
        - Squat 140 kg, add 2.5 kg a week
        - Bench 100 kg (currently 80, up 5 kg since June)
        - chin-ups 15 reps, adding 1 rep each week
        """
        let targets = Targets.parse(goals, lifts: ["deadlift", "squat", "bench-press", "chin-ups"],
                                    today: day("2026-09-21"), calendar: utc)
        XCTAssertEqual(targets.map(\.lift), ["deadlift", "squat", "bench-press", "chin-ups"])
        XCTAssertEqual(targets.map(\.value), [160, 140, 100, 15])
        XCTAssertEqual(targets[0].by, day("2026-12-31"))
        XCTAssertEqual(Targets.number(in: "add 5 kg to the 120 kg")?.value, 120)
        XCTAssertNil(Targets.number(in: "5 kg a month"))
    }

    func testDatesWithoutAYearRollForwardAndISOIsRead() {
        XCTAssertEqual(Targets.date(after: "by", in: "squat 140 kg by 2026-12-24", today: day("2026-09-21"), calendar: utc), day("2026-12-24"))
        XCTAssertEqual(Targets.date(after: "by", in: "squat 140 kg by 1 march", today: day("2026-09-21"), calendar: utc), day("2027-03-01"))
        XCTAssertEqual(Targets.date(after: "by", in: "squat 140 kg by october, then deload", today: day("2026-09-21"), calendar: utc), day("2026-10-31"))
        XCTAssertEqual(Targets.date(after: "by", in: "squat 140 kg by end of sept", today: day("2026-09-21"), calendar: utc), day("2026-09-30"))
        XCTAssertNil(Targets.date(after: "by", in: "squat 140 kg by christmas", today: day("2026-09-21"), calendar: utc))
    }

    func testTheLineTheAppWritesIsOneItReads() {
        let line = Targets.line(lift: "bench-press", value: 100, kind: .topSet, by: day("2026-12-01"))
        XCTAssertEqual(line, "- bench press 100 kg by 1 Dec 2026")
        let max = Targets.line(lift: "squat", value: 140, kind: .oneRepMax, by: nil)
        XCTAssertEqual(max, "- squat 1RM 140 kg")
        XCTAssertEqual(Targets.parse(max, lifts: ["squat"], today: day("2026-09-21"), calendar: utc).first?.kind, .oneRepMax)
        let back = Targets.parse(line, lifts: ["bench-press"], today: day("2026-09-21"), calendar: utc)
        XCTAssertEqual(back.first?.value, 100)
        XCTAssertEqual(back.first?.by, day("2026-12-01"))
    }

    func testBodyweightLiftsTakeAddedLoadAndRepsTargets() {
        let chins = { (sets: [WorkSet]) in
            Session(date: self.day("2026-09-01"), exercises: [ExerciseEntry(name: "chin-ups", sets: sets)])
        }
        let loaded = [chins([WorkSet(weight: nil, added: 10, reps: 5), WorkSet(weight: nil, added: nil, reps: 8)])]

        // "chin-ups 20 kg" on a bodyweight lift is load hung on the lifter.
        let plain = Targets.parse("- chin-ups 20 kg", lifts: ["chin-ups"], today: day("2026-09-21"), calendar: utc)
        XCTAssertEqual(plain.first?.kind, .topSet)
        let resolved = Targets.target(for: "chin-ups", in: plain, sessions: loaded)
        XCTAssertEqual(resolved?.kind, .addedLoad)
        XCTAssertEqual(resolved?.kind.metric, .addedLoad)
        XCTAssertEqual(Analytics.series("chin-ups", metric: resolved!.kind.metric, in: loaded).last?.value, 10,
                       "a series to project from")

        // A reps target still shows once bw+X sets exist.
        let reps = Targets.parse("- chin-ups 15 reps", lifts: ["chin-ups"], today: day("2026-09-21"), calendar: utc)
        XCTAssertEqual(Targets.target(for: "chin-ups", in: reps, sessions: loaded)?.kind, .reps)
        XCTAssertNil(Targets.target(for: "chin-ups", in: reps, sessions: [Session(date: day("2026-09-01"), exercises: [
            ExerciseEntry(name: "chin-ups", sets: [WorkSet(weight: 20, added: nil, reps: 5)])])]),
            "a weighted lift's target is a load")

        // The line the app writes reads back as added load, small plates too.
        let line = Targets.line(lift: "chin-ups", value: 2.5, kind: .addedLoad, by: day("2026-12-01"))
        XCTAssertEqual(line, "- chin ups 2.5 kg added by 1 Dec 2026")
        let back = Targets.parse(line, lifts: ["chin-ups"], today: day("2026-09-21"), calendar: utc).first
        XCTAssertEqual(back?.kind, .addedLoad)
        XCTAssertEqual(back?.value, 2.5)
        XCTAssertEqual(back?.by, day("2026-12-01"))
        XCTAssertEqual(Targets.parse("- weighted chin-ups 20 kg; dips bw+5 kg", lifts: ["chin-ups", "dips"],
                                     today: day("2026-09-21"), calendar: utc).map(\.kind), [.addedLoad, .addedLoad])
        XCTAssertEqual(Targets.parse("- dips bw+5 kg", lifts: ["dips"], today: day("2026-09-21"), calendar: utc).first?.value, 5,
                       "bw+ is a load, not an increment")
    }

    func testProjectionCarriesTheRecentSlopeForward() {
        // 2.5 kg a week for four weeks: 100 → 107.5, so 120 is five more weeks out.
        let series = [("2026-08-24", 100.0), ("2026-08-31", 102.5), ("2026-09-07", 105.0), ("2026-09-14", 107.5)]
            .map { TrendPoint(date: day($0.0), value: $0.1) }
        let p = Analytics.projection(series, to: 120, now: day("2026-09-21"), calendar: utc)!
        XCTAssertEqual(p.current, 107.5)
        XCTAssertEqual(p.perDay!, 2.5 / 7, accuracy: 0.0001)
        XCTAssertEqual(p.date.map { Session.dateFormatter.string(from: $0) }, "2026-10-19")
        XCTAssertFalse(p.isMet)
    }

    func testProjectionIsMetOrFlat() {
        let flat = [("2026-08-24", 100.0), ("2026-09-07", 100.0), ("2026-09-14", 100.0)]
            .map { TrendPoint(date: day($0.0), value: $0.1) }
        let p = Analytics.projection(flat, to: 120, now: day("2026-09-21"), calendar: utc)!
        XCTAssertNil(p.date)
        XCTAssertNil(p.perDay)
        let met = Analytics.projection(flat, to: 100, now: day("2026-09-21"), calendar: utc)!
        XCTAssertTrue(met.isMet)
        XCTAssertNil(met.date)
        XCTAssertNil(Analytics.projection([flat[0]], to: 120, now: day("2026-09-21"), calendar: utc))
    }
}
