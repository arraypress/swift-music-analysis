//
//  AudioClassifier.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//
//  Runs a Core ML sound-classification model over an audio file and
//  aggregates the per-window results into one file-level answer.
//

import AVFAudio
import CoreML
import Foundation
import SoundAnalysis

/// A Core ML sound classifier applied to whole files.
///
/// Sound-classification models judge ~1-second windows; a file-level answer
/// needs those windows aggregated. This wrapper runs the model across the
/// file and averages the per-label confidences, so a 15-second loop is
/// judged by all of it rather than its first second.
///
/// Works with any Create ML `MLSoundClassifier` model. Compilation of the
/// `.mlmodel` is cached, so only the first run of a new model pays it.
///
/// ```swift
/// let gate = try AudioClassifier(modelAt: gateURL)
/// let verdict = try await gate.classify(url: sampleURL)
/// verdict.label        // "tonal"
/// verdict.confidence   // 0.94
/// ```
public final class AudioClassifier: @unchecked Sendable {

    private let model: MLModel

    /// Loads a classifier model, compiling and caching it when needed.
    ///
    /// - Parameter url: A `.mlmodel` (compiled on first use, cached) or an
    ///   already-compiled `.mlmodelc`.
    public init(modelAt url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MusicAnalysisError.fileNotFound(url.path)
        }
        if url.pathExtension == "mlmodelc" {
            model = try MLModel(contentsOf: url)
        } else {
            model = try MLModel(contentsOf: try Self.compiled(url))
        }
    }

    // MARK: - Classification

    /// One file's classification.
    public struct Verdict: Sendable {

        /// The winning label.
        public let label: String

        /// The winning label's mean confidence across windows, 0–1.
        public let confidence: Double

        /// Mean confidence per label across all windows.
        public let distribution: [String: Double]

        /// How many analysis windows contributed.
        public let windows: Int
    }

    /// Audio shorter than this is zero-padded before analysis, because a
    /// file shorter than the model's window produces no windows at all —
    /// and one-shots are shorter than the window by nature.
    private static let minimumSeconds = 1.1

    /// Classifies an audio file, averaging all analysis windows.
    ///
    /// - Parameter url: A local audio file. One-shots shorter than the
    ///   model's analysis window are zero-padded rather than skipped.
    /// - Returns: The aggregated verdict.
    public func classify(url: URL) async throws -> Verdict {
        let request = try SNClassifySoundRequest(mlModel: model)
        let observer = Collector()

        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        if seconds < Self.minimumSeconds {
            return try classifyPadded(file: file, request: request, observer: observer)
        }

        let analyzer = try SNAudioFileAnalyzer(url: url)
        try analyzer.add(request, withObserver: observer)
        return try await withCheckedThrowingContinuation { continuation in
            analyzer.analyze { _ in
                continuation.resume(with: observer.verdict())
            }
        }
    }

    /// Streams a short file into the analyzer with a zero tail.
    private func classifyPadded(
        file: AVAudioFile,
        request: SNClassifySoundRequest,
        observer: Collector
    ) throws -> Verdict {
        let format = file.processingFormat
        let padded = AVAudioFrameCount(format.sampleRate * Self.minimumSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: padded) else {
            throw MusicAnalysisError.analysisFailed("could not allocate analysis buffer")
        }
        try file.read(into: buffer)
        // Zero the tail explicitly — freshly allocated buffers make no
        // silence guarantee — then claim the padded length.
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                let tail = channels[channel].advanced(by: Int(buffer.frameLength))
                tail.update(repeating: 0, count: Int(padded - buffer.frameLength))
            }
        }
        buffer.frameLength = padded

        let analyzer = SNAudioStreamAnalyzer(format: format)
        try analyzer.add(request, withObserver: observer)
        analyzer.analyze(buffer, atAudioFramePosition: 0)
        analyzer.completeAnalysis()
        return try observer.verdict().get()
    }

    /// Accumulates per-window classifications.
    private final class Collector: NSObject, SNResultsObserving, @unchecked Sendable {
        private var sums: [String: Double] = [:]
        private var windows = 0
        private var failure: Error?

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            windows += 1
            for c in result.classifications {
                sums[c.identifier, default: 0] += c.confidence
            }
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {
            failure = error
        }

        func verdict() -> Result<Verdict, Error> {
            if let failure {
                return .failure(MusicAnalysisError.analysisFailed(failure.localizedDescription))
            }
            guard windows > 0 else {
                return .failure(MusicAnalysisError.analysisFailed("no analysis windows produced — file may be shorter than the model's window"))
            }
            let distribution = sums.mapValues { $0 / Double(windows) }
            let best = distribution.max { $0.value < $1.value }!
            return .success(Verdict(
                label: best.key,
                confidence: best.value,
                distribution: distribution,
                windows: windows
            ))
        }
    }

    // MARK: - Compilation cache

    /// Compiles a `.mlmodel`, caching the result keyed by name and mtime so
    /// recompilation only happens when the model file actually changes.
    private static func compiled(_ url: URL) throws -> URL {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("music-analysis/models", isDirectory: true)
        let cached = cacheDir.appendingPathComponent(
            "\(url.deletingPathExtension().lastPathComponent)-\(Int(mtime)).mlmodelc"
        )
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let compiled = try MLModel.compileModel(at: url)
        // Replace any stale compilation of the same model.
        try? FileManager.default.removeItem(at: cached)
        try FileManager.default.moveItem(at: compiled, to: cached)
        return cached
    }
}
