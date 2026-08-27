//
//  MusicAnalysisError.swift
//  MusicAnalysis
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Every way an analysis can fail, with a message worth showing a person.
public enum MusicAnalysisError: Error, LocalizedError, Equatable {

    /// The path does not exist.
    case fileNotFound(String)

    /// The file is DRM-protected — an Apple Music download, typically — and
    /// cannot be decoded for analysis.
    case protectedContent

    /// The file exists but is not decodable audio.
    case invalidAsset

    /// The analysis-type set was empty.
    case emptyAnalysisSet

    /// The framework failed internally. The string is the underlying error's
    /// description, kept for the log rather than the user.
    case analysisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "No such file: \(path)"
        case .protectedContent:
            return "The file is DRM-protected and can't be decoded. Apple Music downloads can't be analyzed."
        case .invalidAsset:
            return "The file isn't decodable audio. Supported containers include WAV, AIFF, CAF, MP3, M4A and FLAC."
        case .emptyAnalysisSet:
            return "No analysis types were requested."
        case .analysisFailed(let reason):
            return "Analysis failed: \(reason)"
        }
    }
}
