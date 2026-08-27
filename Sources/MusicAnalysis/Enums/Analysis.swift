//
//  Analysis.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//

import Foundation
import MusicUnderstanding

/// The dimensions an analysis can cover.
///
/// Mirrors the framework's `AnalysisType` as a `CaseIterable` enum so callers
/// can enumerate, parse from strings (`muse analyze --only rhythm,key`), and
/// encode without touching the framework type.
public enum Analysis: String, Codable, Sendable, CaseIterable {

    /// Beats, bars, and BPM.
    case rhythm

    /// Tonic and mode over time.
    case key

    /// Sections, segments, and phrases.
    case structure

    /// Perceived events-per-minute over time.
    case pace

    /// Which of vocal, drum, bass, other is playing, and how hard.
    case instrumentActivity

    /// LUFS loudness and peak.
    case loudness

    /// The framework's equivalent of this case.
    var frameworkType: AnalysisType {
        switch self {
        case .rhythm: return .rhythm
        case .key: return .key
        case .structure: return .structure
        case .pace: return .pace
        case .instrumentActivity: return .instrumentActivity
        case .loudness: return .loudness
        }
    }
}
