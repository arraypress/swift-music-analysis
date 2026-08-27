//
//  ResultMapperTests.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//

import CoreMedia
import Foundation
import Testing
@testable import MusicAnalysis
import MusicUnderstanding

struct ResultMapperTests {

    // MARK: Fixtures

    /// Decodes a framework result from fixture JSON — the only way to build
    /// one, since the framework's types expose no memberwise initializers.
    /// Non-finite floats travel as strings, matching how the framework's own
    /// values fail to round-trip without the strategy.
    private func decodeResult(_ json: String) throws -> MusicUnderstandingSession.SessionResult {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        return try decoder.decode(
            MusicUnderstandingSession.SessionResult.self,
            from: Data(json.utf8)
        )
    }

    private func time(_ seconds: Double, timescale: Int32 = 44100) -> String {
        """
        {"value": \(Int(seconds * Double(timescale))), "timescale": \(timescale), "epoch": 0, "flags": 1}
        """
    }

    private func range(_ start: Double, _ duration: Double) -> String {
        """
        {"start": \(time(start)), "duration": \(time(duration))}
        """
    }

    // MARK: Rhythm

    @Test func rhythmConvertsToSeconds() throws {
        let result = try decodeResult("""
        {"rhythm": {
            "beats": [\(time(0.5)), \(time(1.0))],
            "bars": [\(time(0.5))],
            "beatsPerMinute": 120.5
        }}
        """)
        let mapped = ResultMapper.map(result, duration: 16)

        let rhythm = try #require(mapped.rhythm)
        #expect(rhythm.beatsPerMinute == 120.5)
        #expect(rhythm.beats == [0.5, 1.0])
        #expect(rhythm.bars == [0.5])
        #expect(mapped.bpm == 120.5)
        #expect(mapped.duration == 16)
    }

    @Test func missingBPMStaysNil() throws {
        let result = try decodeResult("""
        {"rhythm": {"beats": [\(time(0.1))], "bars": [], "beatsPerMinute": null}}
        """)
        #expect(ResultMapper.map(result, duration: nil).rhythm?.beatsPerMinute == nil)
    }

    // MARK: Key

    @Test func keyUsesNoteNamesAndPrimaryKeyPicksLongest() throws {
        let result = try decodeResult("""
        {"key": {"ranges": [
            {"range": \(range(0, 4)), "value": {"tonic": "fSharp", "mode": "minor"}},
            {"range": \(range(4, 12)), "value": {"tonic": "eFlat", "mode": "major"}}
        ]}}
        """)
        let mapped = ResultMapper.map(result, duration: nil)

        #expect(mapped.key.count == 2)
        #expect(mapped.key[0].name == "F# minor")
        #expect(mapped.key[1].tonic == "Eb")
        #expect(mapped.primaryKey?.name == "Eb major")
    }

    // MARK: Loudness

    @Test func nonFiniteLoudnessIsDropped() throws {
        let result = try decodeResult("""
        {"loudness": {
            "integrated": {"time": \(time(0)), "value": "-inf"},
            "peak": {"time": \(time(3.2)), "value": -0.4},
            "momentary": [
                {"time": \(time(0)), "value": "-inf"},
                {"time": \(time(0.1)), "value": -18.5}
            ],
            "shortTerm": []
        }}
        """)
        let mapped = ResultMapper.map(result, duration: nil)

        let loudness = try #require(mapped.loudness)
        #expect(loudness.integratedLUFS == nil)
        // Framework values are Float; a Double comparison needs a tolerance.
        #expect(abs((loudness.peakDecibels ?? 0) - -0.4) < 0.0001)
        #expect(loudness.peakTime != nil)
        #expect(loudness.momentary.count == 1)
        #expect(abs(loudness.momentary[0].lufs - -18.5) < 0.0001)

        // The whole point: the mapped tree must encode without a strategy.
        #expect(throws: Never.self) { try JSONEncoder().encode(mapped) }
    }

    // MARK: Instruments

    @Test func instrumentsAggregateAndKeepStableOrder() throws {
        let result = try decodeResult("""
        {"instrumentActivity": {
            "ranges": {"drum": [\(range(0, 8))]},
            "activity": {
                "drum": [
                    {"time": \(time(0)), "value": 0.9},
                    {"time": \(time(0.05)), "value": 0.5}
                ],
                "vocal": [{"time": \(time(0)), "value": 0.0}]
            }
        }}
        """)
        let mapped = ResultMapper.map(result, duration: nil)

        #expect(mapped.instruments.map(\.instrument) == ["vocal", "drum"])
        let drum = try #require(mapped.instruments.last)
        #expect(abs(drum.peakActivity - 0.9) < 0.0001)
        #expect(abs(drum.meanActivity - 0.7) < 0.0001)
        #expect(drum.activeRanges == [TimeSpan(start: 0, end: 8)])
        #expect(mapped.dominantInstrument?.instrument == "drum")
    }

    // MARK: Note names

    @Test func everyTonicHasANoteName() {
        for tonic in [KeyResult.Tonic.aFlat, .aSharp, .a, .bFlat, .b, .c, .cSharp,
                      .d, .dFlat, .dSharp, .eFlat, .e, .f, .fSharp, .g, .gFlat, .gSharp] {
            let name = ResultMapper.noteName(for: tonic)
            #expect(!name.isEmpty)
            #expect(name.first?.isUppercase == true)
        }
        #expect(ResultMapper.noteName(for: .dSharp) == "D#")
        #expect(ResultMapper.noteName(for: .aFlat) == "Ab")
    }
}
