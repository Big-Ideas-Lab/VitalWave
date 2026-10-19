//
//  WatchMarkers.swift
//  wearable-ios
//
//  Created by Jade Chng on 10/12/26.
//

import Foundation
import SwiftUI

struct WatchMarker: Codable {
    let button: Int
    let label: String
    let watchTimestampMS: UInt32
    let receivedAt: Date
    let pressCount: UInt16
    let timing: String
}

/// Counters are cumulative. Baseline prevents replay of presses from before recording.
struct WatchButtonTracker {
    private var counters: (UInt16, UInt16)?
    private var lastTime: UInt32?

    mutating func receive(_ data: Data) -> [(button: Int, count: UInt16, time: UInt32)] {
        let b = Array(data)
        guard b.count == 20, b[0] == 3 else { return [] }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        let time = UInt32(u16(8)) | UInt32(u16(10)) << 16
        if let lastTime, Int32(bitPattern: time &- lastTime) < 0 { return [] }
        let current = (u16(4), u16(6))
        defer { counters = current; lastTime = time }
        guard let old = counters else { return [] }
        let deltas = [current.0 &- old.0, current.1 &- old.1]
        // Large backwards jumps mean reset/discontinuity, not thousands of presses.
        return deltas.enumerated().compactMap { index, count in
            guard count > 0, count < 32768 else { return nil }
            return (index + 1, count, time)
        }
    }
}

enum WatchButtonLabels {
    static func key(userID: String, watchID: String, button: Int) -> String {
        "watch-button.\(userID).\(watchID).\(button)"
    }
    static func value(userID: String, watchID: String, button: Int) -> String {
        let text = UserDefaults.standard.string(forKey: key(userID: userID, watchID: watchID, button: button))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? (button == 1 ? "Event" : "Issue") : text
    }
}

struct WatchButtonConfiguration: View {
    @AppStorage private var firstLabel: String
    @AppStorage private var secondLabel: String

    init(userID: String, watchID: String) {
        _firstLabel = AppStorage(wrappedValue: "Event", WatchButtonLabels.key(userID: userID, watchID: watchID, button: 1))
        _secondLabel = AppStorage(wrappedValue: "Issue", WatchButtonLabels.key(userID: userID, watchID: watchID, button: 2))
    }

    var body: some View {
        Section {
            LabeledContent("Button 1") {
                TextField("Event", text: $firstLabel).multilineTextAlignment(.trailing)
            }
            LabeledContent("Button 2") {
                TextField("Issue", text: $secondLabel).multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Button markers")
        } footer: {
            Text("Each press marks the recording. Labels apply when the next recording starts.")
        }
    }
}
