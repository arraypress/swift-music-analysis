//
//  SampleClassifier.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//
//  Fine-grained sample classification: a CLAP audio encoder running through
//  Apple's Core AI runtime, a small trained head, and the mel-spectrogram
//  front end that matches CLAP's Python preprocessing bit-for-bit.
//

import Accelerate
import AVFAudio
import CoreAI
import Foundation

/// Classifies audio into fine-grained sample types (kick, pluck, reese bass…)
/// using a CLAP audio encoder converted to a Core AI `.aimodel` plus a small
/// trained classification head.
///
/// Two layouts of the model directory are read. Version 2, preferred when present:
/// - `muse-sample-types.aimodel` — CLAP with both heads inside, entry point
///   `classify`: mel in; `types`, `gate` (atonal, tonal) and `embedding` out
/// - `types.txt`, `gate.txt` — the labels of the two outputs
/// - `mel-filters.f32` — the 513×64 slaney mel filterbank, row-major floats
///
/// Version 1: `clap-audio.aimodel` (entry point `embed`), `mel-filters.f32`,
/// `head-w1.f32`, `head-b1.f32`, `head-w2.f32`, `head-b2.f32` and
/// `head-labels.txt` — the head run here with vDSP, and no tonal answer.
///
/// Preprocessing matches `ClapFeatureExtractor` exactly: 48 kHz mono,
/// repeat-padded to 10 s (audio longer than 10 s uses the leading window),
/// 1024-point hann STFT at hop 480, slaney mel, dB with a 1e-10 floor.
public final class SampleClassifier: @unchecked Sendable {

    /// The network: the encoder with the head run here (v1), or one asset
    /// with both heads inside it (v2).
    private enum Network {
        case encoderAndHead(InferenceFunction, w1: [Float], b1: [Float], w2: [Float], b2: [Float])
        case combined(InferenceFunction, gateLabels: [String])
    }

    private let network: Network
    private let filters: [Float]                       // [513][64]
    private let labels: [String]

    /// The combined (v2) asset's file name.
    public static let combinedAssetName = "muse-sample-types.aimodel"

    /// Whether this classifier also answers tonal / atonal (v2).
    public var hasGate: Bool {
        if case .combined = network { return true }
        return false
    }

    /// One file's classification.
    public struct Verdict: Sendable {
        /// The winning label.
        public let label: String
        /// Softmax probability of the winning label, 0–1.
        public let confidence: Double
        /// All labels with their probabilities, best first.
        public let ranking: [(label: String, probability: Double)]
        /// The probability that a key signature means something here — the
        /// tonal gate's answer, v2 only.
        public let tonal: Double?
    }

    /// Loads the classifier from a model directory, v2 when it is there.
    public init(directory: URL) async throws {
        func floats(_ name: String) throws -> [Float] {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw MusicAnalysisError.fileNotFound(url.path)
            }
            let data = try Data(contentsOf: url)
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        func lines(_ name: String) throws -> [String] {
            try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
                .split(separator: "\n").map(String.init)
        }
        func function(_ asset: String, _ name: String) async throws -> InferenceFunction {
            let url = directory.appendingPathComponent(asset)
            guard FileManager.default.fileExists(atPath: url.path) else { throw MusicAnalysisError.fileNotFound(url.path) }
            guard let function = try await AIModel(contentsOf: url).loadFunction(named: name) else {
                throw MusicAnalysisError.analysisFailed("\(asset) has no '\(name)' function")
            }
            return function
        }
        filters = try floats("mel-filters.f32")
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.combinedAssetName).path) {
            labels = try lines("types.txt")
            network = .combined(try await function(Self.combinedAssetName, "classify"), gateLabels: try lines("gate.txt"))
        } else {
            let (w1, b1, w2, b2) = (try floats("head-w1.f32"), try floats("head-b1.f32"), try floats("head-w2.f32"), try floats("head-b2.f32"))
            labels = try lines("head-labels.txt")
            guard b2.count == labels.count else {
                throw MusicAnalysisError.analysisFailed("head has \(b2.count) outputs but \(labels.count) labels")
            }
            network = .encoderAndHead(try await function("clap-audio.aimodel", "embed"), w1: w1, b1: b1, w2: w2, b2: b2)
        }
    }

    // MARK: - Classification

    /// Classifies one audio file.
    public func classify(url: URL) async throws -> Verdict {
        let mel = try Self.melSpectrogram(of: try Self.load48kMono(url), filters: filters)
        let input = ["input_features": NDArray(scalars: mel, shape: [1, 1, Self.frames, Self.mels])]
        switch network {
        case .encoderAndHead(let encode, let w1, let b1, let w2, let b2):
            var outputs = try await encode.run(inputs: input)
            let embedding = try Self.vector(&outputs, "embedding", count: 512)
            return verdict(probabilities: Self.head(embedding, w1: w1, b1: b1, w2: w2, b2: b2, outputs: labels.count), tonal: nil)
        case .combined(let classify, let gateLabels):
            var outputs = try await classify.run(inputs: input)
            let types = try Self.vector(&outputs, "types", count: labels.count).map(Double.init)
            let gate = try Self.vector(&outputs, "gate", count: gateLabels.count)
            let tonal = gateLabels.firstIndex(of: "tonal").map { Double(gate[$0]) }
            return verdict(probabilities: types, tonal: tonal)
        }
    }

    /// The first `count` floats of a `[1, count]` output.
    private static func vector(_ outputs: inout InferenceFunction.Outputs, _ name: String, count: Int) throws -> [Float] {
        guard let array = outputs.remove(name)?.ndArray else { throw MusicAnalysisError.analysisFailed("model produced no \(name)") }
        let view = array.view(as: Float.self)
        return (0..<count).map { view[scalarAt: [0, $0]] }
    }

    private func verdict(probabilities: [Double], tonal: Double?) -> Verdict {
        let ranking = zip(labels, probabilities).map { (label: $0.0, probability: $0.1) }
            .sorted { $0.probability > $1.probability }
        return Verdict(label: ranking[0].label, confidence: ranking[0].probability, ranking: ranking, tonal: tonal)
    }

    /// The v1 head on a raw embedding: L2-normalise, 512 → 512 GELU → labels, softmax.
    private static func head(_ embedding: [Float], w1: [Float], b1: [Float], w2: [Float], b2: [Float], outputs: Int) -> [Double] {
        let norm = sqrt(embedding.reduce(Float(0)) { $0 + $1 * $1 })
        let x = embedding.map { $0 / max(norm, .leastNormalMagnitude) }
        let width = b1.count
        var hidden = [Float](repeating: 0, count: width)
        vDSP_mmul(w1, 1, x, 1, &hidden, 1, vDSP_Length(width), 1, 512)
        for i in 0..<width {
            let v = hidden[i] + b1[i]
            hidden[i] = 0.5 * v * (1 + erf(v / sqrt(Float(2))))    // torch's exact GELU
        }
        var logits = [Float](repeating: 0, count: outputs)
        vDSP_mmul(w2, 1, hidden, 1, &logits, 1, vDSP_Length(outputs), 1, vDSP_Length(width))
        for i in 0..<outputs { logits[i] += b2[i] }
        let peak = logits.max() ?? 0
        let exps = logits.map { exp(Double($0 - peak)) }
        let total = exps.reduce(0, +)
        return exps.map { $0 / total }
    }

    // MARK: - Audio loading

    /// Reads any decodable audio file as 48 kHz mono floats.
    static func load48kMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw MusicAnalysisError.invalidAsset
        }
        let sourceCapacity = AVAudioFrameCount(16_384)
        let ratio = 48_000 / file.processingFormat.sampleRate
        var samples: [Float] = []
        var reachedEnd = false
        while !reachedEnd {
            let out = AVAudioPCMBuffer(
                pcmFormat: target,
                frameCapacity: AVAudioFrameCount(Double(sourceCapacity) * ratio) + 64
            )!
            var conversionError: NSError?
            let status = converter.convert(to: out, error: &conversionError) { count, statusOut in
                guard !reachedEnd else { statusOut.pointee = .endOfStream; return nil }
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: sourceCapacity)!
                do {
                    try file.read(into: buffer, frameCount: sourceCapacity)
                } catch {
                    statusOut.pointee = .endOfStream; reachedEnd = true; return nil
                }
                if buffer.frameLength == 0 { statusOut.pointee = .endOfStream; reachedEnd = true; return nil }
                statusOut.pointee = .haveData
                return buffer
            }
            if let conversionError {
                throw MusicAnalysisError.analysisFailed(conversionError.localizedDescription)
            }
            if out.frameLength > 0, let channel = out.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
            }
            if status == .endOfStream { break }
        }
        guard !samples.isEmpty else { throw MusicAnalysisError.invalidAsset }
        return samples
    }

    // MARK: - Mel spectrogram (matches ClapFeatureExtractor)

    static let nFFT = 1024, hop = 480, bins = 513, mels = 64
    static let maxSamples = 480_000, frames = 1001

    static func melSpectrogram(of input: [Float], filters: [Float]) throws -> [Float] {
        guard filters.count == bins * mels else {
            throw MusicAnalysisError.analysisFailed("mel filterbank has wrong shape")
        }
        // repeatpad below 10 s; leading 10 s window above it (deterministic,
        // where training used a random crop).
        var wav: [Float]
        if input.count >= maxSamples {
            wav = Array(input[0..<maxSamples])
        } else {
            wav = []
            wav.reserveCapacity(maxSamples)
            for _ in 0..<max(maxSamples / input.count, 1) { wav.append(contentsOf: input) }
            if wav.count > maxSamples { wav = Array(wav[0..<maxSamples]) }
            wav.append(contentsOf: [Float](repeating: 0, count: maxSamples - wav.count))
        }

        let half = nFFT / 2
        var padded = [Float]()
        padded.reserveCapacity(wav.count + nFFT)
        padded.append(contentsOf: (1...half).reversed().map { wav[$0] })
        padded.append(contentsOf: wav)
        padded.append(contentsOf: (2...(half + 1)).map { wav[wav.count - $0] })

        let window = (0..<nFFT).map { 0.5 * (1 - cos(2 * .pi * Float($0) / Float(nFFT))) }
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD) else {
            throw MusicAnalysisError.analysisFailed("could not create DFT setup")
        }
        defer { vDSP_DFT_DestroySetup(setup) }

        var inRe = [Float](repeating: 0, count: nFFT)
        let inIm = [Float](repeating: 0, count: nFFT)
        var outRe = [Float](repeating: 0, count: nFFT)
        var outIm = [Float](repeating: 0, count: nFFT)
        var power = [Float](repeating: 0, count: frames * bins)

        for f in 0..<frames {
            let start = f * hop
            for i in 0..<nFFT { inRe[i] = padded[start + i] * window[i] }
            vDSP_DFT_Execute(setup, inRe, inIm, &outRe, &outIm)
            for b in 0..<bins {
                power[f * bins + b] = outRe[b] * outRe[b] + outIm[b] * outIm[b]
            }
        }

        var mel = [Float](repeating: 0, count: frames * mels)
        vDSP_mmul(power, 1, filters, 1, &mel, 1,
                  vDSP_Length(frames), vDSP_Length(mels), vDSP_Length(bins))
        for i in 0..<mel.count {
            mel[i] = 10 * log10(max(mel[i], 1e-10))
        }
        return mel
    }
}
