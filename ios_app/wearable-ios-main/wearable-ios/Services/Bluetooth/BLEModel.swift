//
//  BLEModel.swift
//  wearable-ios
//
//  Created by Luke Redmore on 11/15/23.
//  Updated by Jade Chng on 10/6/226
//

import SwiftUI
import CoreBluetooth
@preconcurrency import AsyncBluetooth
import Combine
import os

/** This class is the top level entry point for all BLE actions. It uses the `AsyncBluetooth` SDK, which is just a wrapper around the `CoreBluetooth` methods allowing async/await code instead of delegate callbacks */
@MainActor class BLEModel: NSObject, ObservableObject {
    
    
    /** The BLE Central Manager responsible for orchestrating BLE connections*/
    private let central = CentralManager(dispatchQueue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "wearable-ios-ble-background"])
    
    /** No use other than holding the pointer to cancel the central.eventPublisher subscriptions in `init` */
    internal var cancellables = Set<AnyCancellable>()
    @Published var v0Sessions: [String: V0Session] = [:]
    
    /** Stateful value holding the status of the BLE antenna. Could be useful for displaying messages like "Your bluetooth is off!" */
    @Published private(set) var bleState: CBManagerState = .unknown
    
    /** Stateful array of all peripheral objects currently connected to the phone */
    @Published var connectedPeripherals: [Peripheral] = []
    
    /** Stateful array of all peripheral objects that were restored in willRestoreState */
    @Published var restoredPeripherals: [Peripheral] = []
    
    /** Stateful array (also mapped to local storage of all) `PairedPeripheral`s remembered by the phone. A `PairedPeripheral` is just the string values of the name and id of a peripheral so that we can recognize it later */
    @Published var pairedPeripheralManager = PairedPeripheralManager()
    
    /** Whether or not iOS is scanning for new BLE devices */
    @Published private(set) var isScanning = false
    
    /** Error message found when scanning, if present */
    @Published private(set) var scanningError: String? = nil
    
    /** Stateful array of all peripheral objects in the advertising state */
    @Published private(set) var advertisingPeripherals: [Peripheral]? = nil
    
    var samplePublisher = PassthroughSubject<(String, Date, SampleData), Never>()
    
    /** Stateful computed array of all peripheral objects in the advertising state that are also not paired (i.e. new devices) */
    var unknownPeripherals: [Peripheral]? {
        advertisingPeripherals?.filter { advPerif in
            !pairedPeripheralManager.peripherals.contains { $0.id == advPerif.identifier.uuidString }
        }
    }
    
    /** All `init` does is setup the event listeners for dis/connection of a peripheral and BLE state updated */
    override init() {
        super.init()
        // TODO: Fix bug where it think bluetooth is off
        central.eventPublisher
            .sink {
                switch $0 {
                case .didConnectPeripheral(let peripheral):
                    DispatchQueue.main.async {
                        print("Connected to \(peripheral.identifier)")
                        self.connectedPeripherals.append(peripheral)
                        NotificationModel.shared.cancelNotifications()
                        
                    }
                    self.onPeripheralConnect(peripheral)
                case .didDisconnectPeripheral(let peripheral, let isReconnecting, let error):
                    DispatchQueue.main.async {
                        print("Discconnected from \(peripheral.identifier)")
                        NotificationModel.shared.createNotification()
                        if let error = error { print("Error disconnecting peripheral", error) }
                        self.connectedPeripherals = self.connectedPeripherals.filter { $0.identifier != peripheral.identifier }
                    }
                case .didUpdateState(let state):
                    DispatchQueue.main.async {
                        self.bleState = state
                        switch state {
                        case .poweredOn:
                            print("BLE powered on")
                            if (self.restoredPeripherals.count > 0) {
                                print("Found restored peripherals, connecting to them")
                                self.reconnectToRestoredPeripherals()
                            } else {
                                print("No restored peripherals, looking for advertising paired ones")
                                self.connectToPairedPeripherals()
                            }
                        case .resetting:
                            print("BLE resetting, don't do anything here")
                        default:
                            print("Bluetooth unavailable with state:", state)
                            self.connectedPeripherals = []
                            self.advertisingPeripherals = []
                        }
                    }
                case .willRestoreState(let state):
                    print("Calling Restore state")
                    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ble-background")
                    logger.info("Restoring state")
                    self.bleState = self.central.bluetoothState
                    guard let peripherals = state[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
                        logger.error("Could not cast to array of peripherals in background!")
                        return
                    }
                    print("we found \(peripherals.count) peripherals:")
                    self.restoredPeripherals = peripherals.compactMap { peri in
                        switch peri.state {
                        case .connected: print("Peri \(peri.identifier) is connected")
                        case .connecting: print("Peri \(peri.identifier) is connected")
                        case .disconnected: print("Peri \(peri.identifier) is disconnected")
                        case .disconnecting: print("Peri \(peri.identifier) is disconnecting")
                        @unknown default:
                            print("Unknonw state!")
                        }
                        if (peri.state == .connected) {
                            return Peripheral(peri)
                        }
                            return nil
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /** Wrapper method to `central.connect`  to connect to a peripheral with the required options*/
    private func connectPeripheral(_ peripheral: Peripheral) async throws {
        try await central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true,
        ])
    }
    
}

// This extension adds pairing + forgetting capabilities as well as the ability to connect to them
extension BLEModel {
    
    /** Pairs with an unknown peripheral by connecting to it first. If the connection succeeds, add the name and id of peripheral to the pairedPeripherals array */
    func pair(newPeripheral peripheral: Peripheral) async throws {
        try await connectPeripheral(peripheral)
        
        let peripheralToAdd = PairedPeripheral(id: peripheral.identifier.uuidString, name: peripheral.name ?? "Unknown Device", saveToCloud: false, saveToDisk: true, counter: 1000000)
        if !pairedPeripheralManager.peripherals.map({ $0.id }).contains(peripheral.identifier.uuidString) {
            pairedPeripheralManager.peripherals.append(peripheralToAdd)
        }
    }
    
    /** Disconnect from a peripheral and remove it from pairedPeripherals*/
    func forget(pairedPeripheral peripheral: PairedPeripheral) async {
        // Before forgetting, disconnect from it first
        if let connectedPeripheral = connectedPeripherals.first(where: { $0.identifier.uuidString == peripheral.id }) {
            try? await central.cancelPeripheralConnection(connectedPeripheral)
        }
        
        pairedPeripheralManager.peripherals = pairedPeripheralManager.peripherals.filter { $0.id != peripheral.id }
    }
    
    /** Scan for 1 second to find all advertising devices. If any of those devices are paired + not already connected, connect to them */
    func connectToPairedPeripherals() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.stopScan()
        }
        startScan { peripheral in
            // Ignore if not paired
            guard self.pairedPeripheralManager.peripherals.contains(where: {$0.id == peripheral.identifier.uuidString}) else {
                print("Peripheral \(peripheral.identifier.uuidString) is not paired!")
                return
            }
            
            // Ignore if already connected
            guard !self.connectedPeripherals.contains(where: {$0.identifier == peripheral.identifier}) else {
                print("Peripheral \(peripheral.identifier.uuidString) is already connected!")
                return
            }
            
            // Otherwise, connect to it
            Task {
                do {
                    try await self.connectPeripheral(peripheral)
                } catch {
                    print("Failed to connect to peripheral \(peripheral.identifier.uuidString)")
                }
            }
            
        }
    }
    
    func reconnectToRestoredPeripherals() {
        self.restoredPeripherals.forEach(self.onPeripheralConnect)
        self.connectedPeripherals = restoredPeripherals
        self.restoredPeripherals = []
    }
    
}


// This extension adds functions to start/end the scanning for advertising peripherals
extension BLEModel {
    
    /** Tells iOS to start scanning for new BLE devices and populating them inside `advertisingPeripherals`. This array will keep updating in real time until `stopScan()` is called */
    func startScan(onDiscoverPeripheral: ((_ : Peripheral) -> Void)? = nil) {
        self.scanningError = nil
        self.advertisingPeripherals?.removeAll()
        self.isScanning = true
        
        Task {
            do {
                try await self.central.waitUntilReady()
                
                let scanDataStream = try await self.central.scanForPeripherals(withServices: [CBUUIDs.BLEService_UUID])
                // The below for loop will run FOREVER until stopScan is called
                for await scanData in scanDataStream {
                    // The below print statements show any additional data included in the advertising packet. Once method of finding truly
                    // unique IDs would be to pass it as a custom service UUID, since this is not obfuscated per iOS device
                    print("[ADV DATA] For \(scanData.peripheral.identifier.uuidString)")
                    print("[ADV DATA] Service: \(scanData.peripheral.discoveredServices)")
                    for (scanDataKey, scanDataVal) in scanData.advertisementData {
                        print("[ADV DATA]\t\(scanDataKey): \(scanDataVal)")
                    }
                    let identifier = scanData.peripheral.identifier
                    var existingPeripherals = self.advertisingPeripherals ?? []
                    guard !existingPeripherals.contains(where: { $0.identifier == identifier }) else { continue }

                    DispatchQueue.main.async {
                        existingPeripherals.append(scanData.peripheral)
                        onDiscoverPeripheral?(scanData.peripheral)
                        self.advertisingPeripherals = existingPeripherals
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.scanningError = error.localizedDescription
                    self.isScanning = false
                }
            }
        }
    }
    
    /** Stop scanning for new BLE devices (connected devices are not affected) */
    func stopScan() {
        Task {
            if self.central.isScanning {
                await self.central.stopScan()
            }
            
            DispatchQueue.main.async {
                self.isScanning = false
            }
        }
    }
}
