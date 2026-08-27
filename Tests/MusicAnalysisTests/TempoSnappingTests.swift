//
//  TempoSnappingTests.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//
//  Every case here is a mishear observed on real pack material.
//

import Testing
@testable import MusicAnalysis

struct TempoSnappingTests {

    private func rhythm(_ bpm: Double?) -> Rhythm {
        Rhythm(beatsPerMinute: bpm, beats: [], bars: [])
    }

    @Test func valueInsideRangeIsUntouched() {
        #expect(rhythm(128).beatsPerMinute(in: 120...135) == 128)
    }

    @Test func halfTimeDoubles() {
        // 003_130_lead_synth_loop: 130 heard as 65.
        #expect(rhythm(65).beatsPerMinute(in: 120...135) == 130)
    }

    @Test func twoThirdsSnapsByThreeHalves() {
        // 047_128_drum_loop_no_kick: 128 heard as 85.4.
        #expect(abs(rhythm(85.4).beatsPerMinute(in: 120...135)! - 128.1) < 0.01)
    }

    @Test func threeQuartersSnapsByFourThirds() {
        // 017_128_drum_top_loop_hype: 128 heard as 96.
        #expect(rhythm(96).beatsPerMinute(in: 120...135) == 128)
    }

    @Test func thirdTimeTriples() {
        // 048_129_drum_top_loop_good: 129 heard as 43.
        #expect(rhythm(43).beatsPerMinute(in: 120...135) == 129)
    }

    @Test func tooFastHalves() {
        #expect(rhythm(250).beatsPerMinute(in: 120...135) == 125)
    }

    @Test func unsnappableStaysRaw() {
        // 017_128_bass_synth_loop_hype: 105.9 is no musical ratio away from
        // the range — forcing it would trade one wrong answer for another.
        #expect(rhythm(105.9).beatsPerMinute(in: 120...135) == 105.9)
    }

    @Test func smallestCorrectionWinsInWideRanges() {
        // A range wide enough to admit several ratios keeps the detection.
        #expect(rhythm(65).beatsPerMinute(in: 60...135) == 65)
    }

    @Test func nilStaysNil() {
        #expect(rhythm(nil).beatsPerMinute(in: 120...135) == nil)
        #expect(AudioAnalysis().bpm(in: 120...135) == nil)
    }

    @Test func analysisConvenienceHonoursNilRange() {
        let analysis = AudioAnalysis(rhythm: rhythm(64))
        #expect(analysis.bpm(in: nil) == 64)
        #expect(analysis.bpm(in: 120...135) == 128)
    }
}
