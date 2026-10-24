//
//  EventsNotesView.swift
//  wearable-ios
//
//  Created by Jade Chng on 10/12/26.
//
import SwiftUI

struct EventsNotesView: View {
    @EnvironmentObject private var authModel: AuthViewModel
    @State private var recordings: [RecordingInfo] = []
    @State private var error: String?

    private func reload() {
        guard let uid = authModel.user?.uid else { recordings = []; return }
        do {
            recordings = try RecordingStore.shared.savedRecordings(userID: uid).map { $0.0 }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if recordings.isEmpty && error == nil {
                    Text("Save a recording to view its events and add notes.")
                        .foregroundStyle(.secondary)
                }
                ForEach(recordings) { info in
                    NavigationLink {
                        RecordingEventsDetail(info: info)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(info.name)
                            Text(info.watchDisplayName).font(.subheadline).foregroundStyle(.secondary)
                            Text(info.startedAt, style: .date).font(.caption)
                            if !info.participantCode.isEmpty {
                                Text(info.participantCode).font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Events & Notes")
            .onAppear { reload() }
            .refreshable { reload() }
        }
    }
}

private struct MarkerEntry: Identifiable {
    let id: String
    let marker: WatchMarker
}

private struct NoteSelection: Identifiable {
    let eventID: String?
    let title: String
    let text: String
    var id: String { eventID ?? "session" }
}

private struct RecordingEventsDetail: View {
    let info: RecordingInfo
    @EnvironmentObject private var authModel: AuthViewModel
    @State private var entries: [MarkerEntry] = []
    @State private var notes: RecordingNotes?
    @State private var error: String?
    @State private var markerWarning: String?
    @State private var selection: NoteSelection?
    @State private var folder: URL?
    @State private var hasNotesFile = false

    private func load() {
        guard let uid = authModel.user?.uid, uid == info.userID else { return }
        do {
            guard let found = try RecordingStore.shared.savedRecordings(userID: uid)
                .first(where: { $0.0.id == info.id }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            folder = found.1
            notes = try RecordingNotes.load(folder: found.1, recordingID: info.id)
            hasNotesFile = FileManager.default.fileExists(atPath: found.1.appendingPathComponent("notes.json").path)
            error = nil
            entries = []
            markerWarning = nil
            let markersURL = found.1.appendingPathComponent("markers.jsonl")
            if FileManager.default.fileExists(atPath: markersURL.path) {
                let lines = try String(contentsOf: markersURL, encoding: .utf8)
                    .components(separatedBy: "\n")
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                for (index, line) in lines.enumerated() where !line.isEmpty {
                    do {
                        let marker = try decoder.decode(WatchMarker.self, from: Data(line.utf8))
                        entries.append(MarkerEntry(id: String(index), marker: marker))
                    } catch {
                        markerWarning = "Some event entries could not be read. Original files have been kept."
                    }
                }
            }
        } catch {
            notes = nil
            self.error = error.localizedDescription
        }
    }

    private func save(_ text: String, eventID: String?) throws {
        guard authModel.user?.uid == info.userID, let folder, var updated = notes else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if let eventID {
            updated.eventNotes[eventID] = text.isEmpty ? nil : text
        } else {
            updated.sessionNote = text
        }
        updated.updatedAt = Date()
        try updated.save(folder: folder)
        notes = updated
        hasNotesFile = true
    }

    var body: some View {
        List {
            Section {
                Text(info.name).font(.headline)
                Text(info.watchDisplayName).foregroundStyle(.secondary)
                if !info.participantCode.isEmpty {
                    LabeledContent("Participant", value: info.participantCode)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let notes {
                Section("Session note") {
                    Button {
                        selection = NoteSelection(eventID: nil, title: "Session note", text: notes.sessionNote)
                    } label: {
                        Text(notes.sessionNote.isEmpty ? "Add a session note" : notes.sessionNote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Section {
                    if let markerWarning { Text(markerWarning).foregroundStyle(.orange) }
                    if entries.isEmpty {
                        Text("No button events in this recording.").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        Button {
                            selection = NoteSelection(eventID: entry.id, title: entry.marker.label,
                                text: notes.eventNotes[entry.id] ?? "")
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.marker.label).font(.headline)
                                Text("Button \(entry.marker.button)").font(.caption)
                                Text(entry.marker.receivedAt, style: .time).font(.subheadline)
                                if entry.marker.pressCount > 1 {
                                    Text("\(entry.marker.pressCount) presses reported together; individual times unavailable.")
                                        .font(.caption)
                                }
                                if let note = notes.eventNotes[entry.id], !note.isEmpty {
                                    Text(note).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Events")
                } footer: {
                    Text("Times shown are when the phone received the event. Watch timestamps remain in the exported markers.")
                }
                if hasNotesFile, let folder {
                    Section {
                        ShareLink("Export notes", item: folder.appendingPathComponent("notes.json"))
                    }
                }
            }
        }
        .navigationTitle("Events & Notes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .sheet(item: $selection) { selected in
            NoteEditor(title: selected.title, initialText: selected.text) { text in
                try save(text, eventID: selected.eventID)
            }
            .interactiveDismissDisabled()
        }
    }
}

private struct NoteEditor: View {
    let title: String
    let onSave: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: String?

    init(title: String, initialText: String, onSave: @escaping (String) throws -> Void) {
        self.title = title
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .accessibilityLabel("Note")
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try onSave(text); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}
