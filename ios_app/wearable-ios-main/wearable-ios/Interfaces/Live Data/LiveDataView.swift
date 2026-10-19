//
//  LiveDataView.swift
//  wearable-ios
//
//  Created by Luke Redmore on 12/6/23.
//  Updated by Jade Chng on 10/08/2026
//

import SwiftUI

/** This view displays live data from each device*/
struct LiveDataView: View {
    @EnvironmentObject private var bleModel: BLEModel
    
    var body: some View {
        NavigationStack{
            List {
                if bleModel.connectedPeripherals.isEmpty {
                    Text("Connect to a device to view realtime data here")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bleModel.pairedPeripheralManager.peripherals, id:\.id) { periph in
                        if (bleModel.connectedPeripherals.contains(where: { $0.identifier.uuidString == periph.id })) {
                            if let session = bleModel.v0Sessions[periph.id] {
                                V0RecordingSection(session: session)
                            }
                            LiveDataViewSingle(peripheral: periph)
                        }
                    }
                }
                Section {
                    NavigationLink("Saved recordings") { LocalRecordingsView() }
                }
            }.navigationTitle("Live Data")
        }
    }
}

#Preview {
    LiveDataView()
}
