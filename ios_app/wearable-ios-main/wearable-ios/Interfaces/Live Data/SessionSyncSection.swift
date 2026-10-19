//
//  SessionSyncSection.swift
//  wearable-ios
//
//  Created by Jade Chng on 10/14/26.
//
import SwiftUI
import Combine
import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Manual, atomic sync of saved metadata and markers. Never reads data.csv.
@MainActor
final class SessionSyncManager: ObservableObject {
    static let shared = SessionSyncManager()
    @Published private(set) var pending: Set<String> = []
    @Published private(set) var messages: [String: String] = [:]

    func key(_ info: RecordingInfo) -> String { info.userID + "/" + info.id }

    func sync(_ selected: RecordingInfo) {
        let identity = key(selected)
        guard !pending.contains(identity) else { return }
        do {
            guard let uid = Auth.auth().currentUser?.uid, uid == selected.userID else {
                throw SyncError.message("Sign in with the account that saved this recording.")
            }
            guard let (info, folder) = try RecordingStore.shared.savedRecordings(userID: uid)
                .first(where: { $0.0.id == selected.id && $0.0.watchID == selected.watchID }),
                  info.disposition == "saved" else {
                throw SyncError.message("Save the recording before syncing it.")
            }
            let notes = try RecordingNotes.load(folder: folder, recordingID: info.id)
            try checkText(notes.sessionNote)
            let db = Firestore.firestore()
            let session = db.collection("users").document(uid).collection("sessions").document(info.id)
            let batch = db.batch()
            var eventCount = 0
            var totalTextBytes = notes.sessionNote.utf8.count
            let markerFile = folder.appendingPathComponent("markers.jsonl")
            if FileManager.default.fileExists(atPath: markerFile.path) {
                let size = try markerFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2_000_000 else {
                    throw SyncError.message("This recording has too many markers for the first sync version. Local files were kept.")
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let lines = try String(contentsOf: markerFile, encoding: .utf8).components(separatedBy: "\n")
                for (index, line) in lines.enumerated() {
                    if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    let marker = try decoder.decode(WatchMarker.self, from: Data(line.utf8))
                    let note = notes.eventNotes[String(index)] ?? ""
                    try checkText(note)
                    try checkText(marker.label)
                    try checkText(marker.timing)
                    eventCount += 1
                    totalTextBytes += note.utf8.count + marker.label.utf8.count + marker.timing.utf8.count
                    guard eventCount <= 400, totalTextBytes <= 1_000_000 else {
                        throw SyncError.message("This recording exceeds the first sync version's event or note limit. Nothing was uploaded.")
                    }
                    batch.setData([
                        "lineIndex": index,
                        "button": marker.button,
                        "label": marker.label,
                        "watchTimestampMS": Int64(marker.watchTimestampMS),
                        "receivedAt": Timestamp(date: marker.receivedAt),
                        "pressCount": Int(marker.pressCount),
                        "timing": marker.timing,
                        "note": note
                    ], forDocument: session.collection("events").document("line-\(index)"))
                }
            }
            for value in [info.name, info.participantCode, info.watchDisplayName, info.outcome] {
                try checkText(value)
            }
            var fields: [String: Any] = [
                "schemaVersion": 1,
                "recordingID": info.id,
                "userID": uid,
                "watchID": info.watchID,
                "watchName": info.watchDisplayName,
                "sessionName": info.name,
                "participantCode": info.participantCode,
                "startedAt": Timestamp(date: info.startedAt),
                "outcome": info.outcome,
                "framesWritten": info.framesWritten,
                "protocolSessionID": Int64(info.protocolSessionID),
                "sensorMask": Int(info.sensorMask),
                "configurationWord": Int64(info.configurationWord),
                "formatVersion": info.formatVersion,
                "sessionNote": notes.sessionNote,
                "eventCount": eventCount,
                "rawDataLocation": "local",
                "syncedAt": FieldValue.serverTimestamp()
            ]
            // Explicit nulls clear missing values on a subsequent sync.
            fields["endedAt"] = info.endedAt.map { Timestamp(date: $0) } as Any? ?? NSNull()
            fields["generated"] = info.generated.map { Int64($0) } as Any? ?? NSNull()
            fields["dropped"] = info.dropped.map { Int64($0) } as Any? ?? NSNull()
            fields["anomalies"] = info.anomalies as Any? ?? NSNull()
            // Merge preserves future processing results owned by the dashboard.
            batch.setData(fields, forDocument: session, merge: true)
            pending.insert(identity)
            messages[identity] = "Waiting for server confirmation…"
            // Completion runs only after server acknowledgement, not a local cache write.
            batch.commit { error in
                let result = error.map { "Sync failed: \($0.localizedDescription)" }
                    ?? "Session synced"
                Task { @MainActor in
                    self.pending.remove(identity)
                    self.messages[identity] = result
                }
            }
        } catch {
            messages[identity] = error.localizedDescription
        }
    }

    private func checkText(_ text: String) throws {
        guard text.utf8.count <= 20_000 else {
            throw SyncError.message("A note or text field exceeds 20 KB. Shorten it before syncing; your local files were kept.")
        }
    }

    private enum SyncError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }
}

struct SessionSyncSection: View {
    let info: RecordingInfo
    @ObservedObject private var sync = SessionSyncManager.shared

    var body: some View {
        Section("Firestore") {
            Button("Sync session") { sync.sync(info) }
                .disabled(sync.pending.contains(sync.key(info)))
            if sync.pending.contains(sync.key(info)) { ProgressView() }
            if let message = sync.messages[sync.key(info)] {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
