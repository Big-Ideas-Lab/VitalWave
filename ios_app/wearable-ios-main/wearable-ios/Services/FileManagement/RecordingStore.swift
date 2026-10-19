//
//  RecordingStore.swift
//  wearable-ios
//
//  Created by Jade Chng on 10/9/26.
//
import Foundation
import Combine

struct RecordingInfo: Codable, Identifiable {
    let id: String
    let userID: String
    let watchID: String
    let watchName: String? // Optional so previously saved recordings still decode.
    let name: String
    let participantCode: String
    let protocolSessionID: UInt32
    let startedAt: Date
    var endedAt: Date?
    var disposition: String // pending, interrupted, stopped, saved
    var outcome: String
    var framesWritten: Int
    var generated: UInt32?
    var dropped: UInt32?
    var anomalies: Int?
    let sensorMask: UInt8
    let configurationWord: UInt32
    let formatVersion: Int

    var watchDisplayName: String {
        let value = watchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Watch" : value
    }

    var exportBaseName: String {
        func safe(_ value: String) -> String {
            let pieces = value.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_" )).inverted)
                .filter { !$0.isEmpty }
            let result = String(pieces.joined(separator: "-").prefix(60))
            return result.isEmpty ? "Recording" : result
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HHmmss'Z'"
        var parts = [safe(watchDisplayName), safe(name)]
        let participant = participantCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !participant.isEmpty { parts.append(safe(participant)) }
        parts.append(formatter.string(from: startedAt))
        return parts.joined(separator: "_")
    }
}

/// Owns temporary files independently of the Bluetooth connection or visible page.
/// All calls are serialized on the main actor. Each BLE batch is appended once;
/// recordings are never accumulated in RAM.
@MainActor
final class RecordingStore: ObservableObject {
    static let shared = RecordingStore()
    @Published private(set) var pending: [RecordingInfo] = []
    @Published private(set) var errorMessage: String?
    private let fm = FileManager.default
    private let stagingRoot: URL
    private let savedRoot: URL
    private var open: [String: OpenRecording] = [:]

    private struct OpenRecording {
        var info: RecordingInfo
        let directory: URL
        let handle: FileHandle
    }

    // Injectable roots also allow testing without touching real recordings.
    init(stagingRoot: URL? = nil, savedRoot: URL? = nil) {
        self.stagingRoot = stagingRoot ?? URL.applicationSupportDirectory.appendingPathComponent("PendingRecordings", isDirectory: true)
        self.savedRoot = savedRoot ?? URL.documentsDirectory.appendingPathComponent("recordings", isDirectory: true)
        do { try recover() }
        catch { errorMessage = "Could not check unfinished recordings: \(error.localizedDescription)" }
    }

    private func component(_ value: String) throws -> String {
        guard !value.isEmpty, value != ".", value != "..",
              !value.contains("/"), !value.contains("\\") else {
            throw StoreError.invalidIdentity
        }
        return value
    }

    private func directory(root: URL, info: RecordingInfo) throws -> URL {
        try root.appendingPathComponent(component(info.userID), isDirectory: true)
            .appendingPathComponent(component(info.watchID), isDirectory: true)
            .appendingPathComponent(component(info.id), isDirectory: true)
    }

    private func writeMetadata(_ info: RecordingInfo, at directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(info).write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private func readMetadata(at directory: URL) throws -> RecordingInfo {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingInfo.self,
            from: Data(contentsOf: directory.appendingPathComponent("metadata.json")))
    }

    func begin(userID: String, watchID: String, watchName: String? = nil, name: String, participantCode: String,
               protocolSessionID: UInt32, sensorMask: UInt8, configurationWord: UInt32) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.missingName }
        let info = RecordingInfo(id: UUID().uuidString, userID: userID, watchID: watchID,
            watchName: watchName?.trimmingCharacters(in: .whitespacesAndNewlines),
            name: trimmed, participantCode: participantCode.trimmingCharacters(in: .whitespacesAndNewlines),
            protocolSessionID: protocolSessionID, startedAt: Date(), endedAt: nil,
            disposition: "pending", outcome: "Recording was interrupted before a confirmed stop.",
            framesWritten: 0, generated: nil, dropped: nil, anomalies: nil,
            sensorMask: sensorMask, configurationWord: configurationWord, formatVersion: 1)
        let dir = try directory(root: stagingRoot, info: info)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try writeMetadata(info, at: dir)
            let header = "received_at_unix_s,protocol_version,type,protocol_session_id,sequence,watch_timestamp_ms,x_raw,y_raw,z_raw,validity,ppg_raw\n"
            let file = dir.appendingPathComponent("data.csv")
            try Data(header.utf8).write(to: file, options: .atomic)
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            open[info.id] = OpenRecording(info: info, directory: dir, handle: handle)
            return info.id
        } catch {
            // No recording has started, so only this newly-created empty draft is removed.
            try? fm.removeItem(at: dir)
            throw error
        }
    }

    func append(_ data: Data, to id: String) throws {
        guard var recording = open[id] else { throw StoreError.notOpen }
        let b = Array(data)
        guard !b.isEmpty, b.count % 20 == 0 else { throw StoreError.badPacket }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
        let arrival = Date().timeIntervalSince1970
        var rows = ""
        var count = 0
        for i in stride(from: 0, to: b.count, by: 20) {
            guard b[i] == 3, u32(i + 2) == recording.info.protocolSessionID else { continue }
            let type = b[i + 1]
            let x = Int16(bitPattern: u16(i + 12))
            let y = Int16(bitPattern: u16(i + 14))
            let z = Int16(bitPattern: u16(i + 16))
            let ppg = (4...7).contains(type) && u16(i + 14) <= 7 && u16(i + 16) == 0
                ? String(u32(i + 12)) : ""
            let fields = [String(arrival), "3", String(type), String(u32(i + 2)),
                String(u16(i + 6)), String(u32(i + 8)), String(x), String(y), String(z),
                String(u16(i + 18)), ppg]
            rows += fields.joined(separator: ",") + "\n"
            count += 1
        }
        // Preserve frames even if they are invalid, duplicated or out of order.
        // The validity and sequence columns let researchers inspect those problems.
        try recording.handle.write(contentsOf: Data(rows.utf8))
        recording.info.framesWritten += count
        open[id] = recording
    }

    func appendMarker(_ marker: WatchMarker, to id: String) throws {
        guard let recording = open[id] else { throw StoreError.notOpen }
        let file = recording.directory.appendingPathComponent("markers.jsonl")
        if !fm.fileExists(atPath: file.path) { try Data().write(to: file, options: .atomic) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(marker)
        line.append(10)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    func finish(_ id: String, outcome: String, generated: UInt32? = nil,
                dropped: UInt32? = nil, anomalies: Int? = nil) {
        guard var recording = open.removeValue(forKey: id) else { return }
        recording.info.endedAt = Date()
        recording.info.disposition = "stopped"
        recording.info.outcome = outcome
        recording.info.generated = generated
        recording.info.dropped = dropped
        recording.info.anomalies = anomalies
        do { try recording.handle.synchronize() }
        catch { recording.info.outcome += " File flush failed: \(error.localizedDescription)" }
        do { try recording.handle.close() }
        catch { recording.info.outcome += " File close failed: \(error.localizedDescription)" }
        do { try writeMetadata(recording.info, at: recording.directory) }
        catch { errorMessage = "The draft was retained, but its details could not be updated: \(error.localizedDescription)" }
        pending.append(recording.info)
    }

    func hasPending(userID: String, watchID: String) -> Bool {
        pending.contains { $0.userID == userID && $0.watchID == watchID }
    }

    func save(_ info: RecordingInfo, userID: String) throws -> URL {
        guard info.userID == userID, pending.contains(where: { $0.id == info.id }) else { throw StoreError.wrongOwner }
        let source = try directory(root: stagingRoot, info: info)
        let destination = try directory(root: savedRoot, info: info)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var saved = info
        saved.disposition = "saved"
        try writeMetadata(saved, at: source)
        // Move instead of copying or overwriting. On failure the draft stays available.
        try fm.moveItem(at: source, to: destination)
        pending.removeAll { $0.id == info.id }
        return destination
    }

    func discard(_ info: RecordingInfo, userID: String) throws {
        guard info.userID == userID, pending.contains(where: { $0.id == info.id }) else { throw StoreError.wrongOwner }
        try fm.removeItem(at: directory(root: stagingRoot, info: info))
        pending.removeAll { $0.id == info.id }
    }

    func savedRecordings(userID: String) throws -> [(RecordingInfo, URL)] {
        let root = savedRoot.appendingPathComponent(try component(userID), isDirectory: true)
        return try manifests(under: root).compactMap { dir in
            let info = try readMetadata(at: dir)
            guard info.userID == userID else { return nil }
            return (info, dir)
        }.sorted { $0.0.startedAt > $1.0.startedAt }
    }

    private func manifests(under root: URL) throws -> [URL] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        var result: [URL] = []
        // The folder hierarchy is fixed: user/watch/recording, or watch/recording.
        var traversalError: Error?
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
            errorHandler: { _, error in traversalError = error; return false }) else { return [] }
        for case let file as URL in iterator where file.lastPathComponent == "metadata.json" {
            result.append(file.deletingLastPathComponent())
        }
        if let traversalError { throw traversalError }
        return result
    }

    private func recover() throws {
        for dir in try manifests(under: stagingRoot) {
            do {
                var info = try readMetadata(at: dir)
                if info.disposition == "pending" {
                    info.disposition = "interrupted"
                    info.outcome = "Recovered after the app closed. Recording may be incomplete; stop time is unknown."
                    // Count complete rows without loading a whole recording into RAM.
                    let handle = try FileHandle(forReadingFrom: dir.appendingPathComponent("data.csv"))
                    defer { try? handle.close() }
                    var lines = 0
                    while let data = try handle.read(upToCount: 65536), !data.isEmpty {
                        lines += data.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
                    }
                    info.framesWritten = max(0, lines - 1)
                    try writeMetadata(info, at: dir)
                }
                pending.append(info)
            } catch {
                errorMessage = "An unfinished recording could not be read. Its files were kept: \(error.localizedDescription)"
            }
        }
        pending.sort { $0.startedAt < $1.startedAt }
    }

    enum StoreError: LocalizedError {
        case invalidIdentity, missingName, notOpen, badPacket, wrongOwner
        var errorDescription: String? {
            switch self {
            case .invalidIdentity: return "A valid signed-in user and watch are required."
            case .missingName: return "Enter a session name first."
            case .notOpen: return "The temporary recording is not open."
            case .badPacket: return "Unexpected sample packet size."
            case .wrongOwner: return "This recording is not available to the signed-in account."
            }
        }
    }
}

/// Temporary export copies are separate from permanent recordings.
enum RecordingExportFile {
    static func prepare(info: RecordingInfo, folder: URL, metadata: Bool) throws -> URL {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("RecordingExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent(metadata ? "metadata.json" : "data.csv")
        let destination = directory.appendingPathComponent(info.exportBaseName + (metadata ? "_metadata.json" : ".csv"))
        do { try fm.copyItem(at: source, to: destination) }
        catch { try? fm.removeItem(at: directory); throw error }
        return destination
    }
}
