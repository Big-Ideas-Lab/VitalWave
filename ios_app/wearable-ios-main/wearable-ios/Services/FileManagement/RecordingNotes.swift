//
//  RecordingNotes.swift
//  wearable-ios
//
//  Created by Jade Chng on 10/12/26.
//

import Foundation

struct RecordingNotes: Codable {
    let recordingID: String
    var sessionNote: String = ""
    // Keys are line indexes in the immutable markers.jsonl file.
    var eventNotes: [String: String] = [:]
    var updatedAt: Date = Date()
    var version: Int = 1

    static func load(folder: URL, recordingID: String) throws -> RecordingNotes {
        let url = folder.appendingPathComponent("notes.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RecordingNotes(recordingID: recordingID)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notes = try decoder.decode(RecordingNotes.self, from: Data(contentsOf: url))
        guard notes.recordingID == recordingID, notes.version == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return notes
    }

    func save(folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: folder.appendingPathComponent("notes.json"), options: .atomic)
    }
}
