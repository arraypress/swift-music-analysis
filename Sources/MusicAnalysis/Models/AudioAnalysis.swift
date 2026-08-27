//
//  AudioAnalysis.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//
//  The friendly shape of a MusicUnderstanding analysis: seconds instead of
//  CMTime dictionaries, note names instead of enum cases, and no value that
//  JSONEncoder refuses to serialise.
//

import Foundation

/// Everything one analysis pass learned about an audio file.
///
/// Each dimension is optional because each can be skipped at request time, and
/// because the framework itself returns nothing for dimensions it could not
/// measure — a one-shot has no bars, an atonal FX sweep may have no key.
///
/// The whole tree is `Codable`, and unlike the framework's own result types it
/// serialises cleanly: silent windows come back from the framework as `-inf`
/// LUFS, which `JSONEncoder` rejects, so non-finite values are dropped during
/// mapping rather than left to crash the caller's encode.
public struct AudioAnalysis: Codable, Sendable, Equatable {

    /// Total length of the audio, in seconds.
    public let duration: Double?

    /// Beat grid and tempo. `nil` when rhythm analysis was skipped.
    public let rhythm: Rhythm?

    /// Detected keys, in time order. Empty when no key was found — but note
    /// the framework also *invents* keys for purely percussive material, so an
    /// entry here is not proof the audio is tonal.
    public let key: [KeySegment]

    /// Musical form: sections ⊃ segments ⊃ phrases. `nil` when skipped.
    public let structure: Structure?

    /// Perceived energy over time, as events per minute. Independent of BPM.
    public let pace: [PaceSegment]

    /// LUFS loudness and peak level. `nil` when skipped.
    public let loudness: Loudness?

    /// Per-instrument presence, in a stable order (vocal, drum, bass, other).
    public let instruments: [InstrumentPresence]

    public init(
        duration: Double? = nil,
        rhythm: Rhythm? = nil,
        key: [KeySegment] = [],
        structure: Structure? = nil,
        pace: [PaceSegment] = [],
        loudness: Loudness? = nil,
        instruments: [InstrumentPresence] = []
    ) {
        self.duration = duration
        self.rhythm = rhythm
        self.key = key
        self.structure = structure
        self.pace = pace
        self.loudness = loudness
        self.instruments = instruments
    }

    // MARK: Conveniences

    /// The tempo, if one was found. Shorthand for `rhythm?.beatsPerMinute`.
    public var bpm: Double? { rhythm?.beatsPerMinute }

    /// The key that covers the most time — what a sample-library tag wants.
    ///
    /// A track that modulates reports every key in ``key``; this is the one
    /// to file it under.
    public var primaryKey: KeySegment? {
        key.max { ($0.end - $0.start) < ($1.end - $1.start) }
    }

    /// The instrument with the highest peak activity, if any was active.
    public var dominantInstrument: InstrumentPresence? {
        instruments.filter { $0.peakActivity > 0 }.max { $0.peakActivity < $1.peakActivity }
    }
}

// MARK: - Rhythm

/// The beat grid: where the beats and bars fall, and how fast.
public struct Rhythm: Codable, Sendable, Equatable {

    /// Global tempo in beats per minute.
    ///
    /// `nil` until the framework has found at least two beats — which means
    /// every one-shot, by definition. On sustained material longer than a few
    /// seconds the framework sometimes derives a slow phantom tempo from the
    /// decay envelope instead; treat a BPM built on fewer than ~8 beats with
    /// suspicion.
    public let beatsPerMinute: Double?

    /// Each beat's position, in seconds from the start.
    public let beats: [Double]

    /// Each bar line's position, in seconds from the start.
    public let bars: [Double]

    public init(beatsPerMinute: Double?, beats: [Double], bars: [Double]) {
        self.beatsPerMinute = beatsPerMinute
        self.beats = beats
        self.bars = bars
    }
}

// MARK: - Key

/// One detected key, over the span it applies to.
public struct KeySegment: Codable, Sendable, Equatable {

    /// The tonic as a note name: `"C"`, `"F#"`, `"Eb"`. Enharmonic spelling
    /// follows the framework's choice.
    public let tonic: String

    /// `"major"` or `"minor"`.
    public let mode: String

    /// Start of the span, in seconds.
    public let start: Double

    /// End of the span, in seconds.
    public let end: Double

    public init(tonic: String, mode: String, start: Double, end: Double) {
        self.tonic = tonic
        self.mode = mode
        self.start = start
        self.end = end
    }

    /// The key as a person writes it: `"F# minor"`.
    public var name: String { "\(tonic) \(mode)" }
}

// MARK: - Structure

/// Musical form as three nested granularities over the same timeline.
public struct Structure: Codable, Sendable, Equatable {

    /// The broadest divisions — intro, drop, breakdown.
    public let sections: [TimeSpan]

    /// Mid-level divisions within sections.
    public let segments: [TimeSpan]

    /// The finest divisions within segments.
    public let phrases: [TimeSpan]

    public init(sections: [TimeSpan], segments: [TimeSpan], phrases: [TimeSpan]) {
        self.sections = sections
        self.segments = segments
        self.phrases = phrases
    }
}

/// A span of time within the audio, in seconds.
public struct TimeSpan: Codable, Sendable, Equatable {

    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    /// The span's length in seconds.
    public var duration: Double { end - start }
}

// MARK: - Pace

/// Perceived momentum over one span, as musical events per minute.
///
/// Distinct from BPM: a track can hold a steady 128 BPM while its pace rises
/// through a build and falls in the breakdown.
public struct PaceSegment: Codable, Sendable, Equatable {

    public let start: Double
    public let end: Double

    /// Events per minute across this span.
    public let eventsPerMinute: Double

    public init(start: Double, end: Double, eventsPerMinute: Double) {
        self.start = start
        self.end = end
        self.eventsPerMinute = eventsPerMinute
    }
}

// MARK: - Loudness

/// Loudness in LUFS, plus the true peak.
public struct Loudness: Codable, Sendable, Equatable {

    /// Integrated (whole-file) loudness in LUFS. `nil` when the framework
    /// reported a non-finite value, which is what silence measures as.
    public let integratedLUFS: Double?

    /// The loudest instant, in decibels.
    public let peakDecibels: Double?

    /// When the peak occurs, in seconds.
    public let peakTime: Double?

    /// Momentary loudness (400 ms window) sampled every 100 ms. Silent
    /// windows, which measure as `-inf`, are omitted.
    public let momentary: [LoudnessSample]

    /// Short-term loudness (3 s window) sampled every 100 ms. Empty on audio
    /// shorter than the window. Silent windows are omitted.
    public let shortTerm: [LoudnessSample]

    public init(
        integratedLUFS: Double?,
        peakDecibels: Double?,
        peakTime: Double?,
        momentary: [LoudnessSample] = [],
        shortTerm: [LoudnessSample] = []
    ) {
        self.integratedLUFS = integratedLUFS
        self.peakDecibels = peakDecibels
        self.peakTime = peakTime
        self.momentary = momentary
        self.shortTerm = shortTerm
    }
}

/// One loudness measurement at one moment.
public struct LoudnessSample: Codable, Sendable, Equatable {

    /// Seconds from the start.
    public let time: Double

    /// Loudness in LUFS. Always finite.
    public let lufs: Double

    public init(time: Double, lufs: Double) {
        self.time = time
        self.lufs = lufs
    }
}

// MARK: - Instruments

/// One instrument's presence across the audio.
///
/// The framework currently distinguishes four: `vocal`, `drum`, `bass`, and
/// `other` (everything melodic or harmonic that is not the first three). The
/// name is kept as a string so new instruments arriving in a later OS pass
/// through untouched.
public struct InstrumentPresence: Codable, Sendable, Equatable {

    /// The instrument: `"vocal"`, `"drum"`, `"bass"`, or `"other"`.
    public let instrument: String

    /// Spans where the instrument is audibly active.
    public let activeRanges: [TimeSpan]

    /// The highest activity reached, 0–1.
    public let peakActivity: Double

    /// Activity averaged over the whole file, 0–1.
    public let meanActivity: Double

    /// Activity over time, 0–1, sampled every 50 ms.
    public let activity: [ActivitySample]

    public init(
        instrument: String,
        activeRanges: [TimeSpan] = [],
        peakActivity: Double = 0,
        meanActivity: Double = 0,
        activity: [ActivitySample] = []
    ) {
        self.instrument = instrument
        self.activeRanges = activeRanges
        self.peakActivity = peakActivity
        self.meanActivity = meanActivity
        self.activity = activity
    }
}

/// One instrument-activity measurement at one moment.
public struct ActivitySample: Codable, Sendable, Equatable {

    /// Seconds from the start.
    public let time: Double

    /// Activity level, 0–1.
    public let level: Double

    public init(time: Double, level: Double) {
        self.time = time
        self.level = level
    }
}
