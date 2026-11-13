import Foundation
import SwiftUI
import AppKit

struct SavedBackground: Codable {
    var colors: [[Double]]
    var start: [Double] = [0, 0]
    var end: [Double] = [1, 1]
    var imageURL: URL?
    var bookmark: Data?

    init(_ style: BackgroundStyle) {
        switch style {
        case .solidColor(let color): colors = [Self.components(color)]
        case .gradient(let values, let s, let e):
            colors = values.map(Self.components)
            start = [s.x, s.y]; end = [e.x, e.y]
        case .image(let url):
            colors = []; imageURL = url
            bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    var style: BackgroundStyle {
        if let imageURL {
            var stale = false
            let resolved = bookmark.flatMap { try? URL(resolvingBookmarkData: $0, options: .withSecurityScope,
                                                      bookmarkDataIsStale: &stale) } ?? imageURL
            return .image(resolved)
        }
        let values = colors.filter { $0.count == 4 }.map { Color(.sRGB, red: $0[0], green: $0[1], blue: $0[2], opacity: $0[3]) }
        if values.count >= 2, start.count == 2, end.count == 2 {
            return .gradient(colors: values, startPoint: UnitPoint(x: start[0], y: start[1]), endPoint: UnitPoint(x: end[0], y: end[1]))
        }
        return .solidColor(values.first ?? .black)
    }

    private static func components(_ color: Color) -> [Double] {
        let c = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }
}

struct RecorderPreferences: Codable {
    var webcam = WebcamConfiguration.default
    var audio = AudioConfiguration.default
    var resolution = RecordingConfiguration.Resolution.hd1080
    var codec = RecordingConfiguration.VideoCodec.h264
    var frameRate = 30
    var windowScale = 0.9
    var background = SavedBackground(BackgroundStyle.defaultGradient)
    private static let key = "recorderPreferences.v1"

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.key)
    }
}

struct RecordingProject: Codable, Identifiable {
    var version = 1
    var id = UUID()
    var title: String
    var created = Date()
    var duration = 0.0
    var state = "recording"
    var failure: String?
    var screenFile = "screen.mov"
    var cameraFile: String?
    var microphoneFile: String?
    var systemAudioFile: String?
    var webcam: WebcamConfiguration
    var microphoneVolume: Float
    var background: SavedBackground
    var windowScale: Double
    var width: Int
    var height: Int
    var frameRate: Int
    var codec: RecordingConfiguration.VideoCodec
    var cursor: [CursorSample] = []
    var activity: [ActivitySample] = []
    var transcript: [TranscriptChunk] = []
    var edits = EditPlan()
    var folder: URL = URL(fileURLWithPath: "/")

    enum CodingKeys: String, CodingKey {
        case version, id, title, created, duration, state, failure, screenFile, cameraFile, microphoneFile,
             systemAudioFile, webcam, microphoneVolume, background, windowScale, width, height, frameRate,
             codec, cursor, activity, transcript, edits
    }

    func mediaURL(_ file: String) throws -> URL {
        guard !file.isEmpty, file == (file as NSString).lastPathComponent, file != ".", file != ".." else {
            throw EditingError.media("Invalid media path in the recording project.")
        }
        return folder.appendingPathComponent(file)
    }
    func save() throws {
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent("project.json"), options: .atomic)
    }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EasyDemo/Recordings", isDirectory: true)
    }
    static func load(folder: URL) throws -> Self {
        var value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: folder.appendingPathComponent("project.json")))
        guard value.version == 1 else { throw EditingError.media("This project was created by a newer version of EasyDemo.") }
        value.folder = folder
        _ = try value.mediaURL(value.screenFile)
        return value
    }
    static func library(root: URL = Self.root) throws -> [Self] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .compactMap { try? load(folder: $0) }.sorted { $0.created > $1.created }
    }
}
