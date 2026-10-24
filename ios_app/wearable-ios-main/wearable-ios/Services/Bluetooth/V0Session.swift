import Foundation
import Combine
@preconcurrency import CoreBluetooth
@preconcurrency import FirebaseAuth
@preconcurrency import AsyncBluetooth

/// Device-owned streaming session. Navigation does not stop acquisition.
@MainActor
final class V0Session: ObservableObject {
    @Published var settings = V0SensorSettings()
    @Published var recordingName = ""
    @Published var participantCode = ""

    @Published private(set) var chargerLabel = "Unknown"
    @Published private(set) var watchStateLabel = "Unknown"
    @Published private(set) var message = "Connecting…"
    @Published private(set) var ready = false
    @Published private(set) var active = false
    @Published private(set) var busy = false
    @Published private(set) var received = 0
    @Published private(set) var anomalies = 0

    var onSample: ((Date, SampleData) -> Void)?

    private var buttonTracker = WatchButtonTracker()
    private var markerLabels = ["Event", "Issue"]

    private let telemetryUUID = CBUUID(
        string: "7bfa0005-6e4d-4b9d-923b-5d234081a100"
    )

    private var localRecordingID: String?
    private let recordings = RecordingStore.shared

    private var firstWatchMS: UInt32?
    private var firstReceiptDate: Date?
    private var lastTimeByType: [UInt8: Date] = [:]

    private let peripheral: Peripheral
    private var subscription: AnyCancellable?
    private var setupTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?

    private var connected = true
    private var latest: V0Status?
    private var pending: UInt16?
    private var acknowledgement: V0Status?
    private var requestID: UInt16 = 0
    private var sessionID: UInt32 = 0
    private var expectedSequence: UInt16 = 0
    private var accepting = false
    private var stopRequested = false
    private var mask: UInt8 = 13
    private var recordingConfiguration = V0Command.liveConfiguration

    enum Failure: LocalizedError {
        case timeout
        case disconnected
        case rejected(UInt8)
        case mismatch
        case noStatus

        var errorDescription: String? {
            switch self {
            case .timeout:
                return "Watch response timed out."
            case .disconnected:
                return "Watch disconnected."
            case .rejected(let reason):
                return "Watch rejected command; reason \(reason)."
            case .mismatch:
                return "Watch acknowledgement did not match the session."
            case .noStatus:
                return "No valid status from the watch."
            }
        }
    }

    init(peripheral: Peripheral) {
        self.peripheral = peripheral
    }

    private func finishDraft(
        _ outcome: String,
        status: V0Status? = nil
    ) {
        guard let id = localRecordingID else { return }
        localRecordingID = nil

        recordings.finish(
            id,
            outcome: outcome,
            generated: status?.framesGenerated,
            dropped: status?.framesDropped,
            anomalies: anomalies
        )
    }

    func connect() {
        guard setupTask == nil else { return }

        subscription = peripheral.characteristicValueUpdatedPublisher
            .compactMap { characteristic -> (String, Data)? in
                guard let value = characteristic.value else { return nil }

                // Copy the bytes before switching queues.
                return (
                    characteristic.uuid.uuidString,
                    Data(Array(value))
                )
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] update in
                    guard let self, self.connected else { return }

                    do {
                        let (uuid, data) = update

                        if uuid == CBUUIDs.statusUUID.uuidString {
                            let status = try V0Status(data: data)
                            self.updateHomeStatus(data)
                            self.receiveStatus(status)
                        } else if uuid == self.telemetryUUID.uuidString {
                            self.receiveButtons(data)
                        } else if uuid ==
                                    CBUUIDs.BLE_Characteristic_uuid_Rx.uuidString {
                            self.receiveSamples(data)
                        }
                    } catch {
                        if self.accepting {
                            self.anomalies += 1
                        }

                        self.message =
                            "Invalid watch data: \(error.localizedDescription)"
                    }
                }
            )

        setupTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.bounded(seconds: 5) {
                    try await self.peripheral.setNotifyValue(
                        true,
                        forCharacteristicWithCBUUID: CBUUIDs.statusUUID,
                        ofServiceWithCBUUID: CBUUIDs.BLEService_UUID
                    )

                    try await self.peripheral.setNotifyValue(
                        true,
                        forCharacteristicWithCBUUID:
                            CBUUIDs.BLE_Characteristic_uuid_Rx,
                        ofServiceWithCBUUID: CBUUIDs.BLEService_UUID
                    )
                }

                try await self.bounded(seconds: 3) {
                    try await self.peripheral.setNotifyValue(
                        true,
                        forCharacteristicWithCBUUID: self.telemetryUUID,
                        ofServiceWithCBUUID: CBUUIDs.BLEService_UUID
                    )
                }

                try await self.readButtons()
                let status = try await self.readStatus()

                try Task.checkCancellation()
                guard self.connected else { return }

                self.ready = status.state == .idle

                self.message = self.ready
                    ? "Ready"
                    : "Watch is not idle. State: \(status.state), reason: \(status.reason)"
            } catch {
                if self.connected {
                    self.message =
                        "Setup failed: \(error.localizedDescription). Reconnect to retry."
                }
            }
        }
    }

    private func receiveButtons(_ data: Data) {
        let changes = buttonTracker.receive(data)

        guard active,
              !stopRequested,
              let id = localRecordingID else {
            return
        }

        for change in changes {
            let marker = WatchMarker(
                button: change.button,
                label: markerLabels[change.button - 1],
                watchTimestampMS: change.time,
                receivedAt: Date(),
                pressCount: change.count,
                timing: change.count == 1
                    ? "telemetry_snapshot"
                    : "multiple_presses_exact_times_unknown"
            )

            do {
                try recordings.appendMarker(marker, to: id)
            } catch {
                fail(error)
                return
            }
        }
    }

    private func readButtons() async throws {
        let data: Data? = try await bounded(seconds: 1) {
            try await self.peripheral.readValue(
                forCharacteristicWithCBUUID: self.telemetryUUID,
                ofServiceWithCBUUID: CBUUIDs.BLEService_UUID
            )
        }

        guard let data,
              data.count == 20,
              data.first == 3 else {
            throw Failure.noStatus
        }

        receiveButtons(data)
    }

    private func updateHomeStatus(_ data: Data) {
        let bytes = Array(data)

        guard bytes.count == 20, bytes[0] == 3 else { return }

        switch bytes[1] {
        case 0:
            watchStateLabel = "Not recording"
        case 1:
            watchStateLabel = "Recording"
        case 2:
            watchStateLabel = "Watch fault"
        default:
            watchStateLabel = "Unknown"
        }

        switch Self.u16(bytes, 10) {
        case 0:
            chargerLabel = "Off"
        case 1:
            chargerLabel = "Enabled"
        case 2:
            chargerLabel = "Fault"
        default:
            chargerLabel = "Unknown"
        }
    }

    private func receiveStatus(_ status: V0Status) {
        latest = status

        if status.lastRequestID == pending {
            acknowledgement = status
        }

        if active && !busy &&
            (
                status.sessionID != sessionID ||
                status.state != .recording ||
                status.reason != 0
            ) {
            heartbeat?.cancel()
            active = false
            ready = false
            accepting = false

            finishDraft(
                "Watch interrupted the stream; reason \(status.reason).",
                status: status.sessionID == sessionID ? status : nil
            )

            message =
                "Stream interrupted; reason \(status.reason). Reconnect before starting again."
        }
    }

    private func receiveSamples(_ data: Data) {
        guard accepting else { return }

        let b = Array(data)

        guard !b.isEmpty, b.count % 20 == 0 else {
            anomalies += 1
            return
        }

        if let id = localRecordingID {
            do {
                try recordings.append(data, to: id)
            } catch {
                fail(error)
                return
            }
        }

        for offset in stride(from: 0, to: b.count, by: 20) {
            let id = Self.u32(b, offset + 2)

            guard b[offset] == 3, id == sessionID else {
                anomalies += 1
                continue
            }

            let type = b[offset + 1]

            guard (1...7).contains(type) else {
                anomalies += 1
                continue
            }

            let requiredMask: UInt8 =
                type == 1 ? 1 :
                (type == 2 ? 8 :
                (type == 3 ? 2 : 4))

            if mask & requiredMask == 0 {
                anomalies += 1
            }

            let sequence = Self.u16(b, offset + 6)

            if sequence != expectedSequence {
                anomalies += 1
            }

            expectedSequence = sequence &+ 1

            if Self.u16(b, offset + 18) != 1 {
                anomalies += 1
            }

            received += 1

            if mask & requiredMask != 0 {
                let frame = Array(b[offset..<(offset + 20)])

                if let sample = SampleData.fromV0Frame(frame) {
                    let watchMS = Self.u32(frame, 8)

                    if firstWatchMS == nil {
                        firstWatchMS = watchMS
                        firstReceiptDate = Date()
                    }

                    // Sample spacing uses watch time, not BLE arrival time.
                    let elapsed = Double(
                        Int32(bitPattern: watchMS &- firstWatchMS!)
                    ) / 1000

                    let timestamp =
                        firstReceiptDate!.addingTimeInterval(elapsed)

                    if lastTimeByType[type].map({ timestamp > $0 }) ?? true {
                        if lastTimeByType[type] == nil {
                            let names = [
                                1: "ACC",
                                2: "GYRO",
                                3: "TEMP",
                                4: "PPG_IR",
                                5: "PPG_R",
                                6: "PPG_G",
                                7: "PPG_B"
                            ]

                            print(
                                "[VitalWave] Receiving \(names[Int(type)] ?? "unknown") samples"
                            )
                        }

                        lastTimeByType[type] = timestamp
                        onSample?(timestamp, sample)
                    }
                }
            }
        }
    }

    func start() {
        guard connected,
              ready,
              !busy,
              !active,
              latest?.state == .idle else {
            return
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            message = "Sign in before recording."
            return
        }

        guard !recordings.hasPending(
            userID: uid,
            watchID: peripheral.identifier.uuidString
        ) else {
            message = "Save or discard the previous recording first."
            return
        }

        guard !recordingName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            message = "Enter a session name first."
            return
        }

        guard settings.valid else {
            message = "Select at least one sensor and a supported sample rate."
            return
        }

        markerLabels = (1...2).map {
            WatchButtonLabels.value(
                userID: uid,
                watchID: peripheral.identifier.uuidString,
                button: $0
            )
        }

        // Freeze the selected settings for this recording.
        mask = settings.sensorMask
        recordingConfiguration = settings.configurationWord

        busy = true
        ready = false
        stopRequested = false
        received = 0
        firstWatchMS = nil
        firstReceiptDate = nil
        lastTimeByType.removeAll()
        anomalies = 0
        expectedSequence = 0

        repeat {
            sessionID = UInt32.random(in: 1...UInt32.max)
        } while sessionID == latest?.sessionID

        accepting = false

        do {
            localRecordingID = try recordings.begin(
                userID: uid,
                watchID: peripheral.identifier.uuidString,
                watchName: PairedPeripheralManager.pairedPeripheralWithId(
                    deviceId: peripheral.identifier.uuidString
                )?.name,
                name: recordingName,
                participantCode: participantCode,
                protocolSessionID: sessionID,
                sensorMask: mask,
                configurationWord: recordingConfiguration
            )
        } catch {
            busy = false
            ready = true
            message =
                "Could not create a temporary recording: \(error.localizedDescription)"
            return
        }

        message = "Preparing sensors…"

        commandTask = Task { [weak self] in
            guard let self else { return }

            do {
                // CONFIGURE retains the watch's previous session ID.
                _ = try await self.send(.configure, expected: .idle)

                try Task.checkCancellation()

                guard !self.stopRequested else {
                    self.busy = false
                    self.ready = true
                    self.finishDraft("Start cancelled before streaming began.")
                    self.message = "Start cancelled — review recording."
                    return
                }

                // Establish the button baseline before recording starts.
                try await self.readButtons()

                self.accepting = true
                self.message = "Starting…"

                let status = try await self.send(
                    .start,
                    expected: .recording
                )

                guard status.sensorMask == self.mask else {
                    throw Failure.mismatch
                }

                try Task.checkCancellation()

                self.active = true
                self.busy = false
                self.message = "Streaming"

                if self.stopRequested {
                    self.stop()
                } else {
                    self.startHeartbeat()
                }
            } catch {
                self.fail(error)
            }
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()

        heartbeat = Task { [weak self] in
            guard let self else { return }

            do {
                while self.connected && self.active {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    try Task.checkCancellation()

                    _ = try await self.send(
                        .keepalive,
                        expected: .recording
                    )
                }
            } catch {
                if !Task.isCancelled {
                    self.fail(error)
                }
            }
        }
    }

    func stop() {
        stopRequested = true

        guard connected, active, !busy else { return }

        busy = true
        message = "Waiting for STOP acknowledgement…"

        let oldHeartbeat = heartbeat
        oldHeartbeat?.cancel()
        heartbeat = nil

        commandTask = Task { [weak self] in
            guard let self else { return }

            // Wait for heartbeat cancellation before sending STOP.
            await oldHeartbeat?.value

            do {
                let status = try await self.send(.stop, expected: .idle)
                self.active = false

                guard status.framesDropped <= status.framesGenerated else {
                    throw Failure.mismatch
                }

                let expected = Int(
                    status.framesGenerated - status.framesDropped
                )

                self.message = "Watch stopped; receiving remaining samples…"

                let deadline = Date().addingTimeInterval(3)

                while self.received < expected && Date() < deadline {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }

                try Task.checkCancellation()

                self.accepting = false
                self.busy = false
                self.ready = true

                let clean =
                    self.received == Int(status.framesGenerated) &&
                    status.framesDropped == 0 &&
                    self.anomalies == 0

                self.finishDraft(
                    clean
                        ? "Complete: frame counts match; no detected gaps."
                        : "Incomplete: data gaps or anomalies detected.",
                    status: status
                )

                self.message = "Stopped"

                print(
                    "[VitalWave] Received \(self.received), generated \(status.framesGenerated), dropped \(status.framesDropped), anomalies \(self.anomalies). Awaiting Save or Discard."
                )
            } catch {
                self.fail(error)
            }
        }
    }

    // Navigation views must not call this when switching pages.
    func pause() {
        stop()
    }

    func disconnect() {
        connected = false
        chargerLabel = "Unknown"
        watchStateLabel = "Unknown"

        setupTask?.cancel()
        commandTask?.cancel()
        heartbeat?.cancel()
        subscription?.cancel()
        subscription = nil

        let interrupted = active || busy || accepting

        active = false
        busy = false
        ready = false
        accepting = false

        finishDraft("Bluetooth disconnected; recording may be incomplete.")

        message = interrupted
            ? "Disconnected — review the unfinished recording."
            : "Disconnected"
    }

    private func fail(_ error: Error) {
        guard connected else { return }

        heartbeat?.cancel()
        active = false
        busy = false
        ready = false
        accepting = false

        finishDraft(
            "Recording interrupted: \(error.localizedDescription)"
        )

        message =
            "\(error.localizedDescription) Stream interrupted. Keepalives stopped; watch timeout is 5 seconds. Reconnect before retrying."
    }

    private func send(
        _ operation: V0Command.Operation,
        expected: V0Status.RecordingState
    ) async throws -> V0Status {
        guard connected else {
            throw Failure.disconnected
        }

        requestID = requestID == UInt16.max ? 1 : requestID + 1

        let request = requestID
        pending = request
        acknowledgement = nil

        defer {
            pending = nil
            acknowledgement = nil
        }

        let bytes = V0Command.encode(
            operation: operation,
            requestID: request,
            sessionID: sessionID,
            sensorMask: UInt32(mask),
            configuration: recordingConfiguration
        )

        try await bounded(seconds: 1.5) {
            try await self.peripheral.writeValue(
                bytes,
                forCharacteristicWithCBUUID:
                    CBUUIDs.BLE_Characteristic_uuid_Tx,
                ofServiceWithCBUUID: CBUUIDs.BLEService_UUID,
                type: .withResponse
            )
        }

        let deadline = Date().addingTimeInterval(1)

        while acknowledgement == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        if acknowledgement == nil {
            _ = try await readStatus()
        }

        try Task.checkCancellation()

        guard connected else {
            throw Failure.disconnected
        }

        guard let result = acknowledgement,
              result.lastRequestID == request else {
            throw Failure.timeout
        }

        guard result.reason == 0 else {
            throw Failure.rejected(result.reason)
        }

        guard result.state == expected else {
            throw Failure.mismatch
        }

        if operation != .configure && result.sessionID != sessionID {
            throw Failure.mismatch
        }

        return result
    }

    private func readStatus() async throws -> V0Status {
        let data: Data? = try await bounded(seconds: 1) {
            try await self.peripheral.readValue(
                forCharacteristicWithCBUUID: CBUUIDs.statusUUID,
                ofServiceWithCBUUID: CBUUIDs.BLEService_UUID
            )
        }

        guard let data else {
            throw Failure.noStatus
        }

        let status = try V0Status(data: data)
        updateHomeStatus(data)
        receiveStatus(status)

        return status
    }

    private func bounded<T: Sendable>(
        seconds: Double,
        operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(seconds * 1_000_000_000)
                )
                throw Failure.timeout
            }

            defer {
                group.cancelAll()
            }

            return try await group.next()!
        }
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) |
        UInt16(b[i + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) |
        UInt32(b[i + 1]) << 8 |
        UInt32(b[i + 2]) << 16 |
        UInt32(b[i + 3]) << 24
    }
}
