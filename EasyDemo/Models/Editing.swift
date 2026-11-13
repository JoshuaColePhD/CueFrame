import Foundation
import CoreGraphics

struct MediaRange: Codable, Equatable, Sendable {
    var start: Double
    var end: Double
    var duration: Double { max(0, end - start) }
}

struct ZoomSuggestion: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    /// Normalized coordinates, measured from the source's top left.
    var x: Double
    var y: Double
    var scale: Double
    var reason: String
    var enabled = true

    func amount(at time: Double) -> Double {
        guard enabled, time >= start, time <= end else { return 0 }
        let ramp = min(0.6, (end - start) / 2)
        guard ramp > 0 else { return 0 }
        let t = min(1, min((time - start) / ramp, (end - time) / ramp))
        return t * t * (3 - 2 * t)
    }
}

struct PauseSuggestion: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var enabled = true
    var reason = "Quiet pause with no screen activity"
}

struct EditPlan: Codable, Equatable, Sendable {
    var zooms: [ZoomSuggestion] = []
    var pauses: [PauseSuggestion] = []

    func validated(duration: Double) throws -> EditPlan {
        guard duration.isFinite, duration > 0 else { throw EditingError.invalidPlan }
        let valid = zooms.filter(\.enabled).allSatisfy {
            [$0.start, $0.end, $0.x, $0.y, $0.scale].allSatisfy(\.isFinite) &&
            $0.start >= 0 && $0.end <= duration && $0.end > $0.start &&
            (0...1).contains($0.x) && (0...1).contains($0.y) && (1...2.5).contains($0.scale)
        } && pauses.filter(\.enabled).allSatisfy {
            $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end <= duration && $0.end > $0.start
        }
        guard valid, zooms.count <= 300, pauses.count <= 1000 else { throw EditingError.invalidPlan }
        let sorted = zooms.filter(\.enabled).sorted { $0.start < $1.start }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ $0.end <= $1.start }) else {
            throw EditingError.overlappingZooms
        }
        guard keptRanges(duration: duration).reduce(0, { $0 + $1.duration }) >= min(0.5, duration) else {
            throw EditingError.invalidPlan
        }
        return self
    }

    func keptRanges(duration: Double) -> [MediaRange] {
        var result: [MediaRange] = []
        var cursor = 0.0
        for cut in pauses.filter(\.enabled).sorted(by: { $0.start < $1.start }) {
            let start = max(0, min(duration, cut.start))
            let end = max(start, min(duration, cut.end))
            if start > cursor { result.append(MediaRange(start: cursor, end: start)) }
            cursor = max(cursor, end)
        }
        if cursor < duration { result.append(MediaRange(start: cursor, end: duration)) }
        return result
    }

    static func sourceTime(for outputTime: Double, ranges: [MediaRange]) -> Double {
        var offset = 0.0
        for range in ranges {
            if outputTime < offset + range.duration { return range.start + max(0, outputTime - offset) }
            offset += range.duration
        }
        return ranges.last?.end ?? 0
    }
}

enum EditingError: LocalizedError {
    case invalidPlan, overlappingZooms, noScreen, missingKey, api(String), media(String)
    var errorDescription: String? {
        switch self {
        case .invalidPlan: return "The edit contains invalid times or framing. Check the suggestions and try again."
        case .overlappingZooms: return "Zoom suggestions overlap. Adjust their times or turn one off."
        case .noScreen: return "This project does not have a playable screen recording. Its source files are still preserved."
        case .missingKey: return "Add your OpenAI API key in Settings to generate an AI edit."
        case .api(let message), .media(let message): return message
        }
    }
}

struct ActivitySample: Codable, Sendable {
    var time: Double
    var microphoneDB: Double?
    var systemDB: Double?
    var screenChanged: Bool
}

struct CursorSample: Codable, Sendable {
    var time: Double
    var x: Double
    var y: Double
    var clicked: Bool
}

struct TranscriptChunk: Codable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

enum PauseDetector {
    /// Missing data is not evidence of silence. Keep any interval without complete observations.
    static func suggestions(samples: [ActivitySample], cursor: [CursorSample], duration: Double,
                            microphone: Bool, system: Bool) -> [PauseSuggestion] {
        guard microphone, duration > 2 else { return [] }
        var quietStart: Double?
        var previous = -1.0
        var pauses: [PauseSuggestion] = []
        func finish(at end: Double) {
            if let start = quietStart, end - start > 2 {
                pauses.append(PauseSuggestion(start: start + 0.3, end: end - 0.3))
            }
            quietStart = nil
        }
        for sample in samples.sorted(by: { $0.time < $1.time }) {
            let hasCursorActivity = cursor.contains { abs($0.time - sample.time) <= 0.3 }
            let quiet = (sample.microphoneDB.map { $0 < -45 } ?? false) &&
                (!system || (sample.systemDB.map { $0 < -50 } ?? false)) &&
                !sample.screenChanged && !hasCursorActivity
            if sample.time - previous > 0.6 { finish(at: previous + 0.25) }
            if quiet {
                if quietStart == nil { quietStart = sample.time }
            } else { finish(at: sample.time) }
            previous = sample.time
        }
        finish(at: min(duration, previous + 0.25))
        return pauses
    }
}
