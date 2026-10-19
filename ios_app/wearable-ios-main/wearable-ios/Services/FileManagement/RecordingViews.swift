//
//  RecordingViews.swift
//  wearable-ios
//
//  Created by Jade Chng on 10/9/26.
//
import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers

/// Attach this to the whole tab interface so Stop/disconnect can present the
/// decision even if the user has navigated away from Live.
struct RecordingDecisionModifier: ViewModifier {
    @EnvironmentObject private var authModel: AuthViewModel
    @ObservedObject private var store = RecordingStore.shared

    private var pending: RecordingInfo? {
        guard let uid = authModel.user?.uid else { return nil }
        return store.pending.first { $0.userID == uid }
    }

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { pending }, set: { _ in })) { info in
            RecordingDecisionView(info: info, userID: info.userID)
                .id(info.id)
                .interactiveDismissDisabled()
        }
    }
}

private struct RecordingDecisionView: View {
    let info: RecordingInfo
    let userID: String
    @ObservedObject private var store = RecordingStore.shared
    @State private var error: String?
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(info.name).font(.title2.bold())
                    LabeledContent("Watch", value: info.watchDisplayName)
                    if !info.participantCode.isEmpty {
                        LabeledContent("Participant", value: info.participantCode)
                    }
                    Text(info.startedAt, style: .date)
                    Text(info.startedAt, style: .time)
                    LabeledContent("Frames written", value: String(info.framesWritten))
                    Text(info.outcome).foregroundStyle(.secondary)
                    Text("This recording has not been saved to your recordings library or uploaded.")
                        .font(.caption)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("Save Recording") {
                        do { _ = try store.save(info, userID: userID) }
                        catch { self.error = "Save failed. Your draft is still available. \(error.localizedDescription)" }
                    }
                }
                Section {
                    Button("Discard Recording", role: .destructive) {
                        confirmingDiscard = true
                    }
                }
            }
            .navigationTitle("Keep this recording?")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Permanently discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard Recording", role: .destructive) {
                    do { try store.discard(info, userID: userID) }
                    catch { self.error = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}

/// Small local library for verifying a save and exporting the two recording files.
struct LocalRecordingsView: View {
    @EnvironmentObject private var authModel: AuthViewModel
    @ObservedObject private var store = RecordingStore.shared
    @State private var records: [(RecordingInfo, URL)] = []
    @State private var error: String?

    private func reload() {
        guard let uid = authModel.user?.uid else { records = []; return }
        do { records = try store.savedRecordings(userID: uid); error = nil }
        catch { self.error = error.localizedDescription }
    }

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let recoveryError = store.errorMessage {
                Text(recoveryError).foregroundStyle(.red)
            }
            if records.isEmpty && error == nil {
                Text("No saved recordings yet. After Stop, choose Save Recording.")
                    .foregroundStyle(.secondary)
            }
            ForEach(records, id: \.0.id) { record in
                let info = record.0
                let folder = record.1
                NavigationLink {
                    List {
                        Section("Session") {
                            Text(info.name).font(.headline)
                            LabeledContent("Watch", value: info.watchDisplayName)
                            if !info.participantCode.isEmpty {
                                LabeledContent("Participant", value: info.participantCode)
                            }
                            Text(info.startedAt, style: .date)
                            Text(info.startedAt, style: .time)
                            LabeledContent("Frames", value: String(info.framesWritten))
                            Text(info.outcome)
                        }
                        Section("Export") {
                            RecordingCSVExportButton(info: info, folder: folder)
                            ShareLink("Export session details (JSON)", item: RecordingMetadataExport(info: info, folder: folder), preview: SharePreview(info.name))
                            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("markers.jsonl").path) {
                                ShareLink("Export button markers", item: RecordingMarkerExport(info: info, folder: folder), preview: SharePreview(info.name))
                            }
                        }
                        Section("Saved on this iPhone") {
                            Text("\(info.watchDisplayName) → \(info.name)")
                            DisclosureGroup("Storage details") {
                                Text("Documents/recordings/\(info.userID)/\(info.watchID)/\(info.id)/")
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .navigationTitle("Recording")
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.name)
                        Text(info.watchDisplayName).font(.subheadline).foregroundStyle(.secondary)
                        Text(info.startedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        if !info.participantCode.isEmpty {
                            Text(info.participantCode).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved recordings")
        .onAppear { reload() }
        .refreshable { reload() }
    }
}

// Prepare temporary export copies on demand; never rename originals.
private struct RecordingCSVExportButton: View {
    let info: RecordingInfo
    let folder: URL
    @State private var export: CSVExportItem?
    @State private var exportError: String?

    var body: some View {
        Button {
            do {
                let file = try RecordingExportFile.prepare(info: info, folder: folder, metadata: false)
                export = CSVExportItem(file: file)
            } catch {
                exportError = error.localizedDescription
            }
        } label: {
            Label("Export raw data (CSV)", systemImage: "square.and.arrow.up")
        }
        .sheet(item: $export) { item in
            RecordingCSVShareSheet(file: item.file)
        }
        .alert("Could not export CSV", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Please try again.")
        }
    }
}

private struct CSVExportItem: Identifiable {
    let id = UUID()
    let file: URL
}

/// Share the actual .csv file URL so the receiving app gets its filename
/// and file contents directly, bypassing the Transferable sharing path.
private struct RecordingCSVShareSheet: UIViewControllerRepresentable {
    let file: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private struct RecordingMetadataExport: Transferable {
    let info: RecordingInfo
    let folder: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            let file = try RecordingExportFile.prepare(info: item.info, folder: item.folder, metadata: true)
            return SentTransferredFile(file)
        }
    }
}

private struct RecordingMarkerExport: Transferable {
    let info: RecordingInfo
    let folder: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("RecordingExports")
                .appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(item.info.exportBaseName + "_markers.jsonl")
            do { try fm.copyItem(at: item.folder.appendingPathComponent("markers.jsonl"), to: file) }
            catch { try? fm.removeItem(at: dir); throw error }
            return SentTransferredFile(file)
        }
    }
}
