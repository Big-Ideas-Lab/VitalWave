//
//  MainTabView.swift
//  wearable-ios
//
//  Created by Carola Maglione on 10/9/23.
//  Updated by Jade Chng 10/06/2026.
//

import SwiftUI

/** The main TabView displayed in the application */
struct MainTabView: View {
    @State private var selectedTab: String

    init(initialTab: String = "Home") {
        _selectedTab = State(initialValue: initialTab)
    }
    @StateObject private var bleModel = BLEModel()
    
    @ViewBuilder
    func Tab(_ title: String, systemImage: String, view: () -> some View) -> some View {
        view()
            .tabItem { Label(title, systemImage: systemImage) }
            .tag(title)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house") { HomeView(selectedTab: $selectedTab) }
                Tab("Live", systemImage: "livephoto") { LiveDataView() }
                EventsNotesView()
                    .tabItem { Label("Events & Notes", systemImage: "square.and.pencil") }
                    .tag("Self-Report")
                Tab("Devices", systemImage: "applewatch") { DevicesView() }
                Tab("Settings", systemImage: "gearshape.fill") { SettingsView() }
            }
        }.environmentObject(bleModel)
            .modifier(RecordingDecisionModifier())
            // Only leaving the whole signed-in interface stops sessions; tab changes do not.
            .onDisappear { bleModel.disconnectAllV0Sessions() }
    }
}

#Preview {
    MainTabView().environmentObject(BLEModel())
    //MainTabView().environmentObject(NotificationModel())
   
}
