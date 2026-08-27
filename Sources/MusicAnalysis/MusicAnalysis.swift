//
//  MusicAnalysis.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//
//  A friendly wrapper around Apple's MusicUnderstanding framework: on-device
//  musical analysis — BPM, key, structure, pace, instruments, loudness — with
//  results in plain seconds and note names rather than CMTime and enum cases.
//
//  ```swift
//  let analysis = try await MusicAnalysis.analyze("~/Samples/loop.wav")
//  print(analysis.bpm ?? 0)                  // 128.0
//  print(analysis.primaryKey?.name ?? "-")   // "F# minor"
//  ```
//

import AVFoundation
import Foundation
import MusicUnderstanding

/// On-device musical analysis of local audio files.
///
/// Wraps `MusicUnderstandingSession` with three conveniences the raw
/// framework leaves to the caller:
///
/// - **Serialisable results.** The framework reports silence as `-inf` LUFS,
///   which `JSONEncoder` refuses; ``AudioAnalysis`` carries only finite
///   values, so encoding cannot fail.
/// - **Human units.** Seconds instead of `CMTime`, `"F#"` instead of
///   `.fSharp`, one type per concept.
/// - **One call per file.** The framework allows a single `analyze()` per
///   session; this wrapper creates the session for you, so the constraint
///   cannot be tripped over.
///
/// What the framework can measure — and where it guesses — varies sharply
/// with the material. On loops it is strong: BPM is typically exact and key
/// is reliable on isolated melodic or bass content. On one-shots BPM is `nil`
/// by design (it needs two beats), and key output on percussive material is
/// noise with no confidence value to filter it by. See ``AudioAnalysis`` for
/// the per-field caveats.
public enum MusicAnalysis {

    /// Analyzes an audio file at a path.
    ///
    /// ```swift
    /// let analysis = try await MusicAnalysis.analyze("~/Samples/loop.wav")
    /// ```
    ///
    /// - Parameters:
    ///   - path: The audio file. Tilde is expanded.
    ///   - analyses: The dimensions to run. Defaults to all six; requesting
    ///     fewer skips the models the caller does not need.
    /// - Returns: The analysis, with every requested dimension populated
    ///   where the framework found anything to report.
    public static func analyze(
        _ path: String,
        only analyses: Set<Analysis> = Set(Analysis.allCases)
    ) async throws -> AudioAnalysis {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw MusicAnalysisError.fileNotFound(path)
        }
        return try await analyze(url: URL(fileURLWithPath: expanded), only: analyses)
    }

    /// Analyzes an audio file at a URL.
    ///
    /// - Parameters:
    ///   - url: A local file URL. Remote URLs are not supported by the
    ///     framework.
    ///   - analyses: The dimensions to run. Defaults to all six.
    public static func analyze(
        url: URL,
        only analyses: Set<Analysis> = Set(Analysis.allCases)
    ) async throws -> AudioAnalysis {
        guard !analyses.isEmpty else { throw MusicAnalysisError.emptyAnalysisSet }

        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        // Checked here rather than left to the session so the error is ours
        // and carries a message worth showing.
        if (try? await asset.load(.hasProtectedContent)) == true {
            throw MusicAnalysisError.protectedContent
        }

        let duration = try? await asset.load(.duration).seconds

        do {
            let session = try await MusicUnderstandingSession(asset: asset)
            let result = try await session.analyze(
                for: Set(analyses.map(\.frameworkType))
            )
            return ResultMapper.map(result, duration: duration)
        } catch let error as MusicUnderstandingError {
            switch error {
            case .invalidAsset:
                throw MusicAnalysisError.invalidAsset
            case .hasProtectedContent:
                throw MusicAnalysisError.protectedContent
            case .emptyAnalysisSet:
                throw MusicAnalysisError.emptyAnalysisSet
            case .sessionInProgress, .internalError:
                throw MusicAnalysisError.analysisFailed(String(describing: error))
            @unknown default:
                throw MusicAnalysisError.analysisFailed(String(describing: error))
            }
        }
    }

    /// Analyzes an audio file and returns the framework's own result type,
    /// untranslated.
    ///
    /// For callers who want the raw `CMTime` tree — note that encoding it
    /// with `JSONEncoder` fails on silent audio unless a non-conforming
    /// float strategy is set.
    public static func analyzeRaw(
        url: URL,
        only analyses: Set<Analysis> = Set(Analysis.allCases)
    ) async throws -> MusicUnderstandingSession.SessionResult {
        guard !analyses.isEmpty else { throw MusicAnalysisError.emptyAnalysisSet }
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let session = try await MusicUnderstandingSession(asset: asset)
        return try await session.analyze(for: Set(analyses.map(\.frameworkType)))
    }
}
