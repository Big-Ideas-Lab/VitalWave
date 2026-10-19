//
//  ContentView.swift
//  wearable-ios
//
//  Created by Luke Redmore on 9/18/23.
//  Updated by Jade Chng 10/06/2026
//

import SwiftUI
import UIKit

/// Participant welcome page. The BLE model remains owned by MainTabView.
struct HomeView: View {
    @Binding var selectedTab: String
    @EnvironmentObject private var authModel: AuthViewModel
    @EnvironmentObject private var bleModel: BLEModel

    private var greeting: String {
        let name = authModel.user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Welcome!" : "Welcome, \(name)!"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        if let logo = UIImage(named: "BigIdeasLabLogo") {
                            Image(uiImage: logo)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 200, maxHeight: 80)
                                .accessibilityLabel("Big Ideas Lab")
                        } else {
                            Text("BIG IDEAS LAB")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(greeting)
                            .font(.largeTitle.bold())
                    }
                    .padding(.vertical, 12)
                }
                Section("Your watch") {
                    HomeWatchList(manager: bleModel.pairedPeripheralManager)
                }
                Section("How to use") {
                    Button { selectedTab = "Devices" } label: {
                        HStack {
                            Label("Connect your watch in Devices.", systemImage: "applewatch")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { selectedTab = "Live" } label: {
                        HStack {
                            Label("Start or stop streaming in Live.", systemImage: "waveform.path")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { selectedTab = "Self-Report" } label: {
                        HStack {
                            Label("Review events and add notes.", systemImage: "square.and.pencil")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct HomeWatchList: View {
    @ObservedObject var manager: PairedPeripheralManager
    @EnvironmentObject private var bleModel: BLEModel

    var body: some View {
        if manager.peripherals.isEmpty {
            Text("No watch added yet. Open Devices to add your watch.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(manager.peripherals, id: \.id) { device in
                HomeWatchCard(device: device,
                    connected: bleModel.connectedPeripherals.contains {
                        $0.identifier.uuidString == device.id
                    }, session: bleModel.v0Sessions[device.id])
            }
        }
    }
}

private struct HomeWatchCard: View {
    @ObservedObject var device: PairedPeripheral
    let connected: Bool
    let session: V0Session?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(device.name, systemImage: "applewatch")
                .font(.headline)
            LabeledContent("Connection", value: connected ? "Connected" : "Disconnected")
            if connected, let session {
                HomeSessionStatus(session: session)
            } else {
                LabeledContent("Recording", value: "Unknown")
                LabeledContent("Charger", value: "Unknown")
            }
        }
        .padding(.vertical, 8)
    }
}

private struct HomeSessionStatus: View {
    @ObservedObject var session: V0Session

    var body: some View {
        LabeledContent("Recording", value: session.watchStateLabel)
        LabeledContent {
            Text(session.chargerLabel)
        } label: {
            Label("Charger", systemImage: "bolt.fill")
        }
        Text("Charger enabled does not indicate battery level or confirm active charging.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
 
