import XCTest
@testable import KeineMagieCore

final class DictationTimingTests: XCTestCase {
    func testUnknownDurationsNeverEstimateAndRepeatsCountEveryOccurrence() {
        let track = DictationTimingTrack(assets: [1, 1, 2])
        XCTAssertNil(track.snapshot(durations: [1: 2], index: 0, position: 1).duration)
        XCTAssertEqual(track.snapshot(durations: [1: 2, 2: 5], index: 0, position: 1).duration, 15)
        XCTAssertNil(track.snapshot(durations: [2: 5], index: 2, position: 1).elapsed)
    }
    func testGapAndFinalBoundariesAreClampedAndNonseekable() {
        let track = DictationTimingTrack(assets: [1, 1, 2])
        let durations = [1: 2.0, 2: 5.0]
        let gap = track.snapshot(durations: durations, index: 0, position: 2, gapElapsed: 1.5)
        XCTAssertEqual(gap.elapsed, 3.5)
        XCTAssertEqual(gap.remaining, 11.5)
        XCTAssertEqual(track.snapshot(durations: durations, index: 1, position: 0).elapsed, 5)
        let end = track.snapshot(durations: durations, index: 2, position: 99, completed: true)
        XCTAssertEqual(end.elapsed, 15)
        XCTAssertEqual(end.remaining, 0)
        XCTAssertEqual(end.fraction, 1)
        let final = DictationTimingTrack(assets: [0]).snapshot(durations: [0: 12], index: 0, position: 0)
        XCTAssertEqual(final.duration, 12)
        XCTAssertEqual(final.elapsed, 0)
    }
    func testInvalidDurationsAndPositionsDoNotProduceNaN() {
        let track = DictationTimingTrack(assets: [0])
        XCTAssertNil(track.snapshot(durations: [0: .nan], index: 0, position: .infinity).duration)
        XCTAssertNil(track.snapshot(durations: [0: -1], index: 0, position: 0).remaining)
        XCTAssertEqual(track.snapshot(durations: [0: 3], index: 0, position: -1).elapsed, 0)
    }
}
