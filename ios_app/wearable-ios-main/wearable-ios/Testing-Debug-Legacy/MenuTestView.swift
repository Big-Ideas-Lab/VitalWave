//
//  ContentView.swift
//  wearable-ios
//
//  Created by Aseda Asomani on 10/3/23.
//

import Foundation
import SwiftUI
import os

struct MenuTestView: View {
    @State static var data: String = ""
    @State var username: String = "" //will store username input
    @State var password: String = "" //will store password input
    var body: some View {
        
        NavigationView {
            VStack{
                Menu {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Help!!!", systemImage: "questionmark.app.fill")
                    }
                    NavigationLink {
                        SelfReportView()
                    } label: {
                        Label("Self-Report", systemImage: "exclamationmark.bubble.fill")
                    }
                    NavigationLink {
                        DevicesView()
                    } label: {
                        Label("Devices", systemImage: "applewatch")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    NavigationLink {
                        MainTabView()
                    } label: {
                        Label("Home", systemImage: "gearshape.fill")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Color(red: 0/255, green: 0/255, blue: 128/255))
                }
                .frame(alignment: .leading)
            }
        }
        .navigationTitle("iOS Wearable Device")
//        .toolbar{
//            ToolbarItem (placement: .topBarTrailing) {
//                Menu {
//                        NavigationLink("Home", destination: Text("HomeView"))
//                        Button("Help") {
//                            selectedView = "help"
//                        }
//                        Button("Self-Report") {
//                            selectedView = "selfReport"
//                        }
//                        Button("Devices") {
//                            selectedView = "devices"
//                        }
//                        Button("Settings") {
//                            selectedView = "settings"
//                        }
//                        Button("Home") {
//                            selectedView = "home"
//                        }
//
//                } label: {
//                    Image(systemName: "line.3.horizontal")
//                        .font(.system(size: 30, weight: .semibold))
//                        .foregroundColor(Color(red: 0/255, green: 0/255, blue: 128/255))
//                }
//            }
//        }
        
       
    }
}

#Preview {
    MenuTestView()
}

//if selectedView == "help" {
//    NavigationStack{
//        HelpView()
//    }
//} else if selectedView == "selfReport" {
//    NavigationStack{
//        SelfReportView()
//    }
//} else if selectedView == "devices" {
//    NavigationStack{
//        DevicesView()
//    }
//} else if selectedView == "settings" {
//    NavigationStack{
//        SettingsView()
//    }
//}
