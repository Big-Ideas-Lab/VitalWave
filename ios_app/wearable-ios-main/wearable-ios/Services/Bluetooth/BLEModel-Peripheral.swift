//
//  BLEModel-Peripheral.swift
//  wearable-ios
//
//  Created by Luke Redmore on 11/16/23.
//  Updated by Jade Chng on 10/06/26
//

//import Foundation
//import Combine
//@preconcurrency import AsyncBluetooth
//
//extension BLEModel {
//    internal func onPeripheralConnect(_ peripheral: Peripheral) {
//        Task {
//            do {
//                // Listen before enabling notifications.
//                peripheral.characteristicValueUpdatedPublisher
//                    .filter { $0.uuid == CBUUIDs.statusUUID }
//                    .receive(on: DispatchQueue.main)
//                    .sink(
//                        receiveCompletion: { completion in
//                            print("[VitalWave] Status stream: \(completion)")
//                        },
//                        receiveValue: { characteristic in
//                            do {
//                                guard let data =
//                                    try characteristic.parsedValue() as Data?
//                                else {
//                                    return
//                                }
//
//                                let bytes = Array(data)
//
//                                guard bytes.count == 20 else {
//                                    print(
//                                        "[VitalWave] Unexpected status length:",
//                                        bytes.count
//                                    )
//                                    return
//                                }
//
//                                guard bytes[0] == 3 else {
//                                    print(
//                                        "[VitalWave] Unsupported protocol:",
//                                        bytes[0]
//                                    )
//                                    return
//                                }
//
//                                let state: String
//                                switch bytes[1] {
//                                case 0:
//                                    state = "Idle"
//                                case 1:
//                                    state = "Recording"
//                                case 2:
//                                    state = "Fault"
//                                default:
//                                    state = "Unknown"
//                                }
//
//                                print(
//                                    "[VitalWave] Protocol 3 |",
//                                    "State:", state,
//                                    "| Reason:", bytes[2],
//                                    "| Sensor mask:", bytes[3]
//                                )
//                            } catch {
//                                print(
//                                    "[VitalWave] Could not read status:",
//                                    error
//                                )
//                            }
//                        }
//                    )
//                    .store(in: &cancellables)
//
//                try await peripheral.setNotifyValue(
//                    true,
//                    forCharacteristicWithCBUUID: CBUUIDs.statusUUID,
//                    ofServiceWithCBUUID: CBUUIDs.BLEService_UUID
//                )
//
//                print("[VitalWave] Connected; status notifications enabled.")
//                // Read the current status instead of waiting for a notification.
//                let initialData: Data? = try await peripheral.readValue(
//                    forCharacteristicWithCBUUID: CBUUIDs.statusUUID,
//                    ofServiceWithCBUUID: CBUUIDs.BLEService_UUID
//                )
//
//                if let data = initialData {
//                    let status = try V0Status(data: data)
//
//                    print("[VitalWave] Protocol 3 confirmed")
//                    print("[VitalWave] Watch state:", status.state)
//                    print("[VitalWave] Session ID:", status.sessionID)
//                    print("[VitalWave] Reason:", status.reason)
//                } else {
//                    print("[VitalWave] Watch returned no status data.")
//                }
//                print("[VitalWave] Recording has not been started.")
//            } catch {
//                print("[VitalWave] Connection setup failed:", error)
//            }
//        }
//    }
//}

import Foundation
@preconcurrency import AsyncBluetooth

extension BLEModel {
    internal func onPeripheralConnect(_ peripheral: Peripheral) {
        let id = peripheral.identifier.uuidString
        // Replacing a connection always cancels the previous listener and tasks.
        v0Sessions[id]?.disconnect()
        let session = V0Session(peripheral: peripheral)
        session.onSample = { [weak self] timestamp, sample in
            self?.samplePublisher.send((id, timestamp, sample))
        }
        v0Sessions[id] = session
        session.connect()
    }

    internal func onV0Disconnect(_ id: String) {
        v0Sessions[id]?.disconnect()
    }

    internal func disconnectAllV0Sessions() {
        for session in v0Sessions.values { session.disconnect() }
    }
}
