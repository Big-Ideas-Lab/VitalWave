import SwiftUI
import Charts


// The original LiveDataView and LiveDataGraph now display live samples.

///// Bounded display history only. This is not a recording buffer.
//@MainActor
//final class V0LiveBuffer {
//    struct Point: Identifiable {
//        let id: Int
//        let seconds: Double
//        let value: Double
//        let segment: Int
//    }
//
//    enum Channel: String, CaseIterable, Identifiable {
//        case infrared = "PPG Infrared", red = "PPG Red"
//        case green = "PPG Green", blue = "PPG Blue"
//        case ax = "Acceleration X", ay = "Acceleration Y", az = "Acceleration Z"
//        case gx = "Gyroscope X", gy = "Gyroscope Y", gz = "Gyroscope Z"
//        case temperature = "Temperature", humidity = "Humidity"
//        var id: String { rawValue }
//        var unit: String {
//            switch self {
//            case .infrared, .red, .green, .blue: return "Raw ADC counts"
//            case .ax, .ay, .az: return "g"
//            case .gx, .gy, .gz: return "degrees/second"
//            case .temperature: return "°C"
//            case .humidity: return "% RH"
//            }
//        }
//    }
//
//    private var history: [Channel: [Point]] = [:]
//    private var origin: UInt32?
//    private var expectedSequence: UInt16 = 0
//    private var segment = 0
//    private var nextID = 0
//    private(set) var latestSeconds: Double = 0
//
//    func reset() {
//        history.removeAll()
//        origin = nil
//        expectedSequence = 0
//        segment = 0
//        nextID = 0
//        latestSeconds = 0
//    }
//
//    func points(for channel: Channel) -> [Point] {
//        (history[channel] ?? []).filter { $0.seconds >= latestSeconds - 10 }
//    }
//
//    /// Called only for a frame belonging to the active session.
//    func append(_ b: [UInt8]) {
//        guard b.count == 20, b[0] == 3 else { segment += 1; return }
//        let sequence = Self.u16(b, 6)
//        if sequence != expectedSequence { segment += 1 }
//        expectedSequence = sequence &+ 1
//        guard Self.u16(b, 18) == 1 else { segment += 1; return }
//
//        let watchMS = Self.u32(b, 8)
//        if origin == nil { origin = watchMS }
//        // Signed modular difference tolerates the watch clock wrapping and
//        // slightly earlier reconstructed PPG timestamps. Intended for short tests.
//        let seconds = Double(Int32(bitPattern: watchMS &- origin!)) / 1000
//        latestSeconds = max(latestSeconds, seconds)
//        let x = Double(Int16(bitPattern: Self.u16(b, 12)))
//        let y = Double(Int16(bitPattern: Self.u16(b, 14)))
//        let z = Double(Int16(bitPattern: Self.u16(b, 16)))
//        switch b[1] {
//        case 1:
//            add(.ax, x * 0.000061, seconds)
//            add(.ay, y * 0.000061, seconds)
//            add(.az, z * 0.000061, seconds)
//        case 2:
//            add(.gx, x * 0.00875, seconds)
//            add(.gy, y * 0.00875, seconds)
//            add(.gz, z * 0.00875, seconds)
//        case 3:
//            add(.temperature, x / 100, seconds)
//            add(.humidity, y / 100, seconds)
//        case 4...7:
//            let high = Self.u16(b, 14)
//            guard high <= 7, Self.u16(b, 16) == 0 else { segment += 1; return }
//            let raw = UInt32(Self.u16(b, 12)) | UInt32(high) << 16
//            let channels: [Channel] = [.infrared, .red, .green, .blue]
//            add(channels[Int(b[1]) - 4], Double(raw), seconds)
//        default: segment += 1
//        }
//    }
//
//    private func add(_ channel: Channel, _ value: Double, _ seconds: Double) {
//        var points = history[channel] ?? []
//        if let last = points.last, seconds <= last.seconds {
//            segment += 1
//            return
//        }
//        nextID += 1
//        points.append(Point(id: nextID, seconds: seconds, value: value, segment: segment))
//        points.removeAll { $0.seconds < latestSeconds - 10 }
//        if points.count > 1200 { points.removeFirst(points.count - 1200) }
//        history[channel] = points
//    }
//
//    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
//        UInt16(b[i]) | UInt16(b[i + 1]) << 8
//    }
//    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
//        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
//    }
//}
//
//struct V0LivePlot: View {
//    @ObservedObject var session: V0Session
//    @State private var channel: V0LiveBuffer.Channel = .infrared
//
//    var body: some View {
//        Section {
//            Picker("Channel", selection: $channel) {
//                ForEach(V0LiveBuffer.Channel.allCases) { choice in
//                    Text(choice.rawValue).tag(choice)
//                }
//            }
//            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
//                let points = session.live.points(for: channel)
//                if points.isEmpty {
//                    Text("No samples for this channel in the current display window. Start a stream and choose an enabled channel.")
//                        .foregroundStyle(.secondary)
//                        .frame(height: 220)
//                } else {
//                    Chart(points) { point in
//                        LineMark(
//                            x: .value("Seconds", point.seconds),
//                            y: .value(channel.unit, point.value),
//                            series: .value("Segment", point.segment)
//                        )
//                        .interpolationMethod(.linear)
//                        .foregroundStyle(.blue)
//                    }
//                    .chartXAxisLabel("Seconds from first received sample")
//                    .chartYAxisLabel(channel.unit)
//                    .chartXScale(domain: (session.live.latestSeconds - 10)...max(0.001, session.live.latestSeconds))
//                    .frame(height: 240)
//                    if let latest = points.last {
//                        Text("Latest: \(latest.value.formatted(.number.precision(.fractionLength(0...4)))) \(channel.unit)")
//                            .font(.caption)
//                    }
//                }
//            }
//        } header: {
//            Text("Live signal — last 10 seconds")
//        } footer: {
//            Text("Display only; not saved. PPG is unfiltered raw intensity, not SpO₂. Channels not enabled by the firmware stay empty. Lines break at detected gaps or invalid samples.")
//        }
//    }
//}
