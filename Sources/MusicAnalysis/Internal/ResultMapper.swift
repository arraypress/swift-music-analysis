//
//  ResultMapper.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//
//  Translates the framework's result tree — CMTime everywhere, enum tonics,
//  `-inf` for silence — into ``AudioAnalysis``.
//

import CoreMedia
import Foundation
import MusicUnderstanding

enum ResultMapper {

    /// Maps a session result into the public model.
    ///
    /// - Parameters:
    ///   - result: What the framework returned.
    ///   - duration: The asset's duration in seconds, measured separately
    ///     because the framework does not report it.
    static func map(
        _ result: MusicUnderstandingSession.SessionResult,
        duration: Double?
    ) -> AudioAnalysis {
        AudioAnalysis(
            duration: duration,
            rhythm: result.rhythm.map(mapRhythm),
            key: result.key.map(mapKey) ?? [],
            structure: result.structure.map(mapStructure),
            pace: result.pace.map(mapPace) ?? [],
            loudness: result.loudness.map(mapLoudness),
            instruments: result.instrumentActivity.map(mapInstruments) ?? []
        )
    }

    // MARK: Dimensions

    private static func mapRhythm(_ rhythm: RhythmResult) -> Rhythm {
        Rhythm(
            beatsPerMinute: rhythm.beatsPerMinute.map(Double.init),
            beats: rhythm.beats.map(\.seconds),
            bars: rhythm.bars.map(\.seconds)
        )
    }

    private static func mapKey(_ key: KeyResult) -> [KeySegment] {
        key.ranges.map { ranged in
            KeySegment(
                tonic: noteName(for: ranged.value.tonic),
                mode: ranged.value.mode.rawValue,
                start: ranged.range.start.seconds,
                end: ranged.range.end.seconds
            )
        }
    }

    private static func mapStructure(_ structure: StructureResult) -> Structure {
        Structure(
            sections: structure.sections.map(span),
            segments: structure.segments.map(span),
            phrases: structure.phrases.map(span)
        )
    }

    private static func mapPace(_ pace: PaceResult) -> [PaceSegment] {
        pace.ranges.compactMap { ranged in
            guard ranged.value.isFinite else { return nil }
            return PaceSegment(
                start: ranged.range.start.seconds,
                end: ranged.range.end.seconds,
                eventsPerMinute: ranged.value
            )
        }
    }

    private static func mapLoudness(_ loudness: LoudnessResult) -> Loudness {
        // Silence measures as -inf LUFS, which JSONEncoder refuses to encode.
        // Scalars become nil; series samples are dropped.
        Loudness(
            integratedLUFS: finite(loudness.integrated.value),
            peakDecibels: finite(loudness.peak.value),
            peakTime: loudness.peak.value.isFinite ? loudness.peak.time.seconds : nil,
            momentary: loudness.momentary.compactMap(sample),
            shortTerm: loudness.shortTerm.compactMap(sample)
        )
    }

    private static func mapInstruments(_ result: InstrumentActivityResult) -> [InstrumentPresence] {
        // Union of both dictionaries: an instrument can have activity samples
        // without ever crossing the threshold that earns it an active range.
        let names = Set(result.ranges.keys).union(result.activity.keys)
        return names.map { instrument in
            let samples = (result.activity[instrument] ?? []).compactMap { timed -> ActivitySample? in
                guard timed.value.isFinite else { return nil }
                return ActivitySample(time: timed.time.seconds, level: Double(timed.value))
            }
            let levels = samples.map(\.level)
            return InstrumentPresence(
                instrument: instrument.rawValue,
                activeRanges: (result.ranges[instrument] ?? []).map(span),
                peakActivity: levels.max() ?? 0,
                meanActivity: levels.isEmpty ? 0 : levels.reduce(0, +) / Double(levels.count),
                activity: samples
            )
        }
        .sorted { order($0.instrument) < order($1.instrument) }
    }

    // MARK: Helpers

    /// Display order: the framework's four known instruments first, anything
    /// a future OS adds after them alphabetically.
    private static func order(_ instrument: String) -> String {
        switch instrument {
        case "vocal": return "0"
        case "drum": return "1"
        case "bass": return "2"
        case "other": return "3"
        default: return "4\(instrument)"
        }
    }

    private static func span(_ range: CMTimeRange) -> TimeSpan {
        TimeSpan(start: range.start.seconds, end: range.end.seconds)
    }

    private static func sample(
        _ timed: MusicUnderstandingSession.TimedValue<Float>
    ) -> LoudnessSample? {
        guard timed.value.isFinite else { return nil }
        return LoudnessSample(time: timed.time.seconds, lufs: Double(timed.value))
    }

    private static func finite(_ value: Float) -> Double? {
        value.isFinite ? Double(value) : nil
    }

    /// The tonic as a note name, using the framework's enharmonic spelling.
    static func noteName(for tonic: KeyResult.Tonic) -> String {
        switch tonic {
        case .a: return "A"
        case .aSharp: return "A#"
        case .aFlat: return "Ab"
        case .b: return "B"
        case .bFlat: return "Bb"
        case .c: return "C"
        case .cSharp: return "C#"
        case .d: return "D"
        case .dSharp: return "D#"
        case .dFlat: return "Db"
        case .e: return "E"
        case .eFlat: return "Eb"
        case .f: return "F"
        case .fSharp: return "F#"
        case .g: return "G"
        case .gSharp: return "G#"
        case .gFlat: return "Gb"
        @unknown default: return tonic.rawValue
        }
    }
}
