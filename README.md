# Swift Music Analysis

A Swift library for on-device musical analysis of local audio files — BPM, key, structure, pace, instrument activity, and loudness — built on Apple's MusicUnderstanding framework. No API key, no network: audio never leaves the machine.

## Features

- 🎯 **Simple API** — one async call per file, all six dimensions or just the ones you need
- 🥁 **Rhythm** — global BPM plus every beat and bar position in seconds
- 🎹 **Key** — tonic and mode over time, as note names (`"F# minor"`), with key changes captured
- 🏗️ **Structure** — sections ⊃ segments ⊃ phrases as plain time spans
- 🏃 **Pace** — perceived events-per-minute over time, independent of BPM
- 🎸 **Instrument activity** — vocal / drum / bass / other presence, peak and mean levels, active ranges
- 🔊 **Loudness** — integrated LUFS, true peak, and the momentary / short-term series
- 📦 **Serialisable results** — everything `Codable`, with the framework's `-inf` silence values sanitised so `JSONEncoder` cannot fail
- 🔒 **On-device** — Apple's models, no audio uploaded, works offline
- ⚡ **Async/await** native — built for modern Swift concurrency
- 🛡️ **Typed error handling** — specific errors for every failure case

## Requirements

- macOS 27.0+ / iOS 27.0+ / tvOS 27.0+ / watchOS 27.0+ / visionOS 27.0+
- Swift 6.0+
- Xcode 27.0+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-music-analysis.git", from: "0.1.0")
]
```

## Usage

### Analyze a file

```swift
import MusicAnalysis

let analysis = try await MusicAnalysis.analyze("~/Samples/loop.wav")

analysis.bpm                    // 128.0
analysis.primaryKey?.name       // "F# minor"
analysis.duration               // 15.0
analysis.loudness?.integratedLUFS   // -6.2
analysis.dominantInstrument?.instrument  // "drum"
```

### Only the dimensions you need

Skipping dimensions skips their models, which is faster:

```swift
let analysis = try await MusicAnalysis.analyze("track.mp3", only: [.rhythm, .key])
```

### Beat grid for slicing

```swift
let rhythm = analysis.rhythm!
rhythm.beats   // [0.01, 0.5, 1.0, 1.5, ...] seconds
rhythm.bars    // [0.01, 2.0, 4.0, ...]
```

### Snap tempo-octave mishears

Beat trackers can't distinguish 128 BPM from a half-time hearing of 64 — both are valid. When you know the material's plausible range, declare it and mishears snap in by musical ratios only (×2, ×3/2, ×4/3…):

```swift
analysis.bpm                    // 64.0 — half-time mishear
analysis.bpm(in: 120...135)     // 128.0
```

Values already in range are untouched; a detection no ratio can bring inside is returned as-is. Measured on a 295-loop pack: 91% → 99% exact against filename BPMs.

### Serialise it

```swift
let json = try JSONEncoder().encode(analysis)   // cannot fail on silence
```

## What to trust, measured

Validated against a commercial sample pack with BPM and key in the filenames:

- **Loops**: BPM typically exact to ±0.1; occasional ⅔- or ¾-tempo mishears. Key is reliable on isolated bass/synth loops, less so on busy full mixes.
- **One-shots**: BPM is `nil` under ~1s by design (needs two beats); longer one-shots can report a phantom tempo derived from the decay. Treat any BPM built on fewer than ~8 beats with suspicion.
- **Percussive material**: the framework reports keys for drum loops and hits, and provides **no confidence value** to filter them by. A key on a snare is noise.
- **DRM**: Apple Music downloads cannot be analyzed (`protectedContent`).

## Error Handling

```swift
do {
    let analysis = try await MusicAnalysis.analyze(path)
} catch MusicAnalysisError.protectedContent {
    // Apple Music download — can't be decoded
} catch MusicAnalysisError.invalidAsset {
    // not decodable audio
}
```

## License

MIT
