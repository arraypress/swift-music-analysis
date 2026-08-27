//
//  TempoSnapping.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//
//  Tempo-octave correction. Beat trackers can't tell 128 BPM from a
//  half-time hearing of 64 — both are valid pulses of the same audio — so
//  callers who know the plausible range for their material can declare it,
//  and detections that are a musical ratio outside it snap in.
//

import Foundation

extension Rhythm {

    /// The correction factors tried, smallest correction first. Within each
    /// pair the speed-up comes before the slow-down, because sparse melodic
    /// material is under-detected far more often than over-detected.
    private static let multipliers: [Double] = [
        1, 4 / 3, 3 / 4, 3 / 2, 2 / 3, 2, 1 / 2, 3, 1 / 3, 4, 1 / 4,
    ]

    /// The tempo, snapped into a plausible range by a musical ratio.
    ///
    /// Every mishear a beat tracker makes is a clean ratio of the truth —
    /// half-time, two-thirds, three-quarters — so when the caller knows the
    /// material's range (a tech-house pack lives around 120–135), the
    /// detection can be corrected honestly: multiply by the smallest musical
    /// ratio that lands inside.
    ///
    /// ```swift
    /// rhythm.beatsPerMinute              // 64.0 — half-time mishear
    /// rhythm.beatsPerMinute(in: 120...135)   // 128.0
    /// ```
    ///
    /// This is a declared prior, not a guess: nothing happens unless the
    /// caller supplies the range, a value already inside is returned
    /// untouched, and a detection no ratio can bring inside is returned
    /// as-is rather than forced.
    ///
    /// - Parameter range: Where this material's tempo plausibly lives.
    /// - Returns: The snapped tempo, or the raw detection when it is already
    ///   inside the range or cannot be brought inside; `nil` when no tempo
    ///   was detected at all.
    public func beatsPerMinute(in range: ClosedRange<Double>) -> Double? {
        guard let bpm = beatsPerMinute else { return nil }
        for multiplier in Self.multipliers where range.contains(bpm * multiplier) {
            return bpm * multiplier
        }
        return bpm
    }
}

extension AudioAnalysis {

    /// The tempo, snapped into a plausible range. See
    /// ``Rhythm/beatsPerMinute(in:)``.
    ///
    /// - Parameter range: Where the tempo plausibly lives, or `nil` for the
    ///   raw detection.
    public func bpm(in range: ClosedRange<Double>?) -> Double? {
        guard let range else { return bpm }
        return rhythm?.beatsPerMinute(in: range)
    }
}
