import Foundation
import UniformTypeIdentifiers
// CoreTransferable provides `Transferable`, `TransferRepresentation`,
// and `DataRepresentation` — the protocols that bridge our JSON
// export bundle into ShareLink. Without this import the compiler
// can't resolve those names even though Swift's symbol fuzzing
// hints suggest they should "just work."
import CoreTransferable
#if canImport(UIKit)
import UIKit
#endif

// JSON-export plumbing for race data. Wraps each `Race` row in a
// flat Codable struct that mirrors the persisted fields (sans the
// photo blob — base64-encoding hundreds of KB of binary into JSON
// would balloon the file size for marginal value; users who want
// photos already have them in iCloud Photos / their camera roll).
//
// Output is a single JSON document containing version metadata and
// the array of races, suitable for backup or import on a fresh
// install. Versioning the document means future schema additions
// can be migrated cleanly — readers branch on `formatVersion`.
//
// Wrapped as a `RaceExportFile: Transferable` so SwiftUI's
// ShareLink can hand the bytes to AirDrop / Files / iCloud Drive
// directly with a sensible suggested filename.
//
// Guarded `#if !os(watchOS) && canImport(UIKit)` because Race +
// the export plumbing are iOS-only.
#if !os(watchOS) && canImport(UIKit)

// Wire-format snapshot of a single race. One-way mapping — we
// never decode this back into a SwiftData @Model row in v1.
// Decode/import lands in the v1+ feature set when cloud sync ships.
struct ExportableRace: Codable, Sendable {
    let id: UUID
    let name: String
    let startedAt: Date
    let endedAt: Date?
    let createdAt: Date
    let splits: [Split]
    let sequenceRaw: [Int]
    let modeRawValue: String
    let notes: String
    let targetDuration: TimeInterval?
    let pausedAt: Date?

    init(_ race: Race) {
        self.id = race.id
        self.name = race.name
        self.startedAt = race.startedAt
        self.endedAt = race.endedAt
        self.createdAt = race.createdAt
        self.splits = race.splits
        self.sequenceRaw = race.sequenceRaw
        self.modeRawValue = race.modeRawValue
        self.notes = race.notes
        self.targetDuration = race.targetDuration
        self.pausedAt = race.pausedAt
    }
}

// Top-level export document — `formatVersion` lets future readers
// branch on schema (v1: this shape; v2 might add laps, photo
// references, etc.).
struct RaceExportDocument: Codable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String
    let races: [ExportableRace]

    static let currentFormatVersion = 1

    init(races: [Race]) {
        self.formatVersion = Self.currentFormatVersion
        self.exportedAt = Date()
        // Pull marketing version + build for traceability — useful
        // when someone reports an export-time bug ("which build
        // produced this file?").
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        self.appVersion = "\(marketing) (\(build))"
        self.races = races.map(ExportableRace.init)
    }

    // Encode self to pretty-printed JSON Data. Pretty-printed (vs.
    // minified) because exports are human-eyeballable artifacts —
    // someone might want to grep their own data.
    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// Transferable wrapper for ShareLink. Carries the encoded JSON
// bytes plus a date-stamped filename so exports land with
// descriptive names instead of "Export.json".
struct RaceExportFile: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { item in
            item.data
        }
        .suggestedFileName { item in item.filename }
    }

    static func makeFilename(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "HYROXAPP-races-\(f.string(from: date)).json"
    }
}

#endif
