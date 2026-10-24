//
//  LiveDataViewSingle.swift
//  wearable-ios
//
//  Created by Luke Redmore on 3/23/24.
//  Updated by Jade Chng on 10/06/2026
//

import SwiftUI

/** All live data being received from a single device */
struct LiveDataViewSingle: View {
    @EnvironmentObject var bleModel: BLEModel
    let peripheral: PairedPeripheral
    
    @ViewBuilder
    private func LiveDataRow<T: WearableDataType>(label: String, numDecimals decimals: Int, for path: KeyPath<SampleData, T?>) -> some View {
        NavigationLink {
            LiveDataGraph(id: peripheral.id, dataLabel: label, path: path)
        } label: {
            LiveDataRowLabel(peripheral.id, label: label, numDecimals: decimals, path: path)
        }
    }
        
    var body: some View {
        Section {
            NavigationLink {
                HeartRateView(viewModel: HeartRateViewModel(id: peripheral.id, samplePublisher: bleModel.samplePublisher.eraseToAnyPublisher()))
            } label : {
                Text("Heart Rate")
            }
            LiveDataRow(label: "PPG_R", numDecimals: 1, for: \.ppg_r)
            LiveDataRow(label: "PPG_G", numDecimals: 1, for: \.ppg_g)
            LiveDataRow(label: "PPG_B", numDecimals: 1, for: \.ppg_b)
            LiveDataRow(label: "PPG_IR", numDecimals: 1, for: \.ppg_ir)
            LiveDataRow(label: "ACC_X", numDecimals: 6, for: \.acc_x)
            LiveDataRow(label: "ACC_Y", numDecimals: 6, for: \.acc_y)
            LiveDataRow(label: "ACC_Z", numDecimals: 6, for: \.acc_z)
            LiveDataRow(label: "GYRO_X", numDecimals: 6, for: \.gyro_x)
            LiveDataRow(label: "GYRO_Y", numDecimals: 6, for: \.gyro_y)
            LiveDataRow(label: "GYRO_Z", numDecimals: 6, for: \.gyro_z)
            LiveDataRow(label: "MAG_X", numDecimals: 1, for: \.mag_x)
            LiveDataRow(label: "MAG_Y", numDecimals: 1, for: \.mag_y)
            LiveDataRow(label: "MAG_Z", numDecimals: 1, for: \.mag_z)
            LiveDataRow(label: "AIR_TEMP", numDecimals: 2, for: \.air_temp)
            LiveDataRow(label: "HUMID", numDecimals: 2, for: \.humid)
        } header: {
            Text("Metrics")
        }
    }
}
