import XCTest
import AVFoundation
@testable import KeineMagieCore

final class DictationWAVTimingTests: XCTestCase {
    /// Actual RIFF PCM bytes; AVAudioPlayer decodes these rather than a mocked duration.
    private func wav(seconds: Double) -> Data {
        let sampleRate = 8000
        let samples = Int(seconds * Double(sampleRate))
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + samples * 2)); ascii("WAVEfmt ")
        u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        ascii("data"); u32(UInt32(samples * 2)); data.append(Data(repeating: 0, count: samples * 2))
        return data
    }
    func testDecodedDurationsIncludeEachDistinctAssetRepeatAndOnlyInternalGaps() throws {
        let durations = try [0: 4.0, 1: 1.25, 2: 2.5].mapValues { try AVAudioPlayer(data: wav(seconds: $0)).duration }
        XCTAssertEqual(try XCTUnwrap(durations[1]), 1.25, accuracy: 0.001)
        let track = DictationTimingTrack(assets: [1, 1, 2, 2])
        let end = track.snapshot(durations: durations, index: 3, position: 2.5, completed: true)
        XCTAssertEqual(end.duration, 16.5)
        XCTAssertEqual(end.remaining, 0)
        XCTAssertEqual(DictationTimingTrack(assets: [0]).snapshot(durations: durations, index: 0, position: 0).duration, 4)
    }
}
