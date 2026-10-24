//
//  FileHandleTest.swift
//  wearable-ios
//
//  Created by Luke Redmore on 10/10/24.
//

import SwiftUI

/// Test view to append directly to file without opening it. Currently unused
struct FileHandleTest: View {
    let fileManager = FileManager.default
    let deviceId: String
    private let uid = UserDefaults.standard.string(forKey: "auth-uid")!
    let pub: NotificationCenter.Publisher
    
    init(deviceId: String, text: String = "") {
        self.deviceId = deviceId
        self.pub = NotificationCenter.default.publisher(
            for: Notification.Name("Unsused")
        )
        self._text = State(initialValue: text)
    }
    
    @State private var text = ""
    
    var body: some View {
        VStack {
            Text(text)
                .onReceive(pub) { notification in
                    guard let (timestamp, sample) = notification.asSample() else { return }
                    text = sample.csvString
                    
                    let fileURL = URL.documentsDirectory
                        .appendingPathComponent("deviceData")
                        .appendingPathComponent(uid)
                        .appendingPathComponent(deviceId)
                        .appendingPathComponent("full.csv")
                    
                    // Convert the text to Data
                    if let data = "\n\(timestamp),\(sample.csvString)".data(using: .utf8) {
                        // Check if the file exists
                        if fileManager.fileExists(atPath: fileURL.path) {
                            // Append to the existing file
                            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                                fileHandle.seekToEndOfFile()
                                fileHandle.write(data)
                                fileHandle.closeFile()
                            } else {
                                print("Unable to open file for writing.")
                            }
                            
                            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                               let fileSize = attributes[FileAttributeKey.size] as? Int64 {
                                print("File now has a file size of \(fileSize)")
                            }
                        } else {
                            // Create the file if it doesn't exist
                            do {
                                let headers = "isodate,\(SampleData.CSV_COLUMN_ORDER.joined(separator: ","))\n" + sample.csvString
                                try headers.data(using: .utf8)?.write(to: fileURL)
                            } catch {
                                print("Failed to write to file: \(error)")
                            }
                        }
                    }
                }
        }
    }
}
