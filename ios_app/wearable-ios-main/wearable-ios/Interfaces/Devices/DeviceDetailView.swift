//
//  DeviceDetailView.swift
//  wearable-ios
//
//  Created by Luke Redmore on 11/20/23.
//  Updated by Jade Chng 10/06/26
//

import SwiftUI


/** This view will show the details and settings for any paired peripheral. For now, it only shows a NavigationLink to browse all data collected by the device */
struct DeviceDetailView: View {
    @Binding var deviceDetails: PairedPeripheral
    @EnvironmentObject var authModel: AuthViewModel
    
    
    var body: some View {
        List{
            if let uid = authModel.user?.uid {
                WatchButtonConfiguration(
                    userID: uid,
                    watchID: deviceDetails.id
                )
            }
            Section {
                NavigationLink {
                    TextFieldForm(
                        text: deviceDetails.name,
                        title: "Device Nickname",
                        helperText: "Please enter a nickname to be used to identify this device throughout the app.",
                        onSubmit: { deviceDetails.name = $0 }
                    )
                } label: {
                    HStack {
                        Text("Nickname")
                        Spacer()
                        Text(deviceDetails.name).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("ID")
                    Spacer()
                    Text(deviceDetails.id).foregroundStyle(.secondary)
                }
            }
            Section {
                NavigationLink("Data Collected") {
                    if let uid = authModel.user?.uid {
                        DeviceDataBrowser(uid: uid, deviceId: deviceDetails.id)
                    }
                }
            }
            Section {
                Toggle("Firebase Storage", isOn: $deviceDetails.saveToCloud)
                Toggle("Local Disk", isOn: $deviceDetails.saveToDisk)
            } header: {
                Text("Save Data To:")
            }
            Section {
                            HStack {
                                
                                Text(verbatim: "Size: \(deviceDetails.counter / 1_000_000) MB")
                                Spacer()
                                Button("Increment") {
                                    
                                    $deviceDetails.counter.wrappedValue += 10000000 // Increment the counter
                                }
                                .buttonStyle(.bordered)
                            }
                        } header: {
                            Text("Max File Size")
                        }
            
        }
        
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(deviceDetails.name)
    }
}

//#Preview {
//    DeviceDetailView(deviceDetails: .constant(PairedPeripheral(id: "C469026-0B57-27B9-153F-473A48299CAA", name: "Feather Sense", saveToCloud: true, saveToDisk: true))).environmentObject(AuthViewModel())
//}
