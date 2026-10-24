//
//  LiveDataGraph.swift
//  wearable-ios
//
//  Created by Luke Redmore on 3/23/24.
//  Updated by Jade Chng on 10/06/2026
//

import SwiftUI
import Charts

extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/** Display live data from a single parameter in a graph format*/
struct LiveDataGraph<T: WearableDataType>: View {
    @EnvironmentObject private var bleModel: BLEModel
    @State private var allData: [(timestamp: Date, data: T)] = []
    @State private var mostRecentTimestamp = Date.distantPast
    @State private var didGoBackInTime = false
    @AppStorage("debug-mode") public var debugMode : Bool = false

    let dataLabel: String
    let id: String
    let path: KeyPath<SampleData, T?>
    let dateFormatter: ISO8601DateFormatter
    
    init(id: String, dataLabel: String, path: KeyPath<SampleData, T?>) {
        self.dataLabel = dataLabel
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = id
        self.path = path
    }
    
    var sampleRate: Double {
        guard allData.count > 1,
              let first = allData.first?.timestamp,
              let last = allData.last?.timestamp else { return 0.0 }
        let delta = first.distance(to: last)
        return delta > 0 ? Double(allData.count - 1) / delta : 0
    }
    
    var body: some View {
        VStack {
            Text("Sample Rate: \(sampleRate) Hz")
            if debugMode {
                HStack {
                    Text("Data received in order:")
                    if didGoBackInTime {
                        Color.red.frame(width: 10, height: 10)
                    } else {
                        Color.green.frame(width: 10, height: 10)
                    }
                }
            }
            Chart {
                ForEach(allData, id: \.timestamp) { item in
                    LineMark(
                        x: .value("Date", item.timestamp),
                        y: .value("Value", item.data)
                    )
                }
            }
                .chartYScale(domain: .automatic(includesZero: false))
        }
        .onReceive(bleModel.samplePublisher) { (deviceId, timestamp, sample) in
            guard id == deviceId, let parsed = sample[keyPath: path] else { return }
            didGoBackInTime = timestamp < mostRecentTimestamp
            mostRecentTimestamp = timestamp
            allData.append((timestamp: timestamp, data: parsed))
            // Bound display memory while streaming continues.
            let cutoff = timestamp.addingTimeInterval(-30)
            allData.removeAll { $0.timestamp < cutoff }
            if allData.count > 6000 { allData.removeFirst(allData.count - 6000) }
        }
        .onDisappear {
            allData = []
        }
        .navigationTitle(dataLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    allData = []
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
    }
}
