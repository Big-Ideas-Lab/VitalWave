import SwiftUI

struct V0RecordingSection: View {
    @ObservedObject var session: V0Session

    private var hasRecordingName: Bool {
        !session.recordingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section {
            TextField("Session name", text: $session.recordingName)
                .textInputAutocapitalization(.sentences)
                .disabled(session.active || session.busy)
            TextField("Participant name/number (optional)", text: $session.participantCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(session.active || session.busy)
            HStack {
                Button("Start") { session.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasRecordingName || !session.settings.valid || !session.ready || session.busy || session.active)
                Spacer()
                Button("Stop", role: .destructive) { session.stop() }
                    .buttonStyle(.bordered)
                    .disabled(!session.active || session.busy)
            }
            Text(session.message).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Recording session")
        }
        Section("Sensors") {
            DisclosureGroup("PPG colours") {
                Toggle("Infrared", isOn: $session.settings.infrared)
                Toggle("Red", isOn: $session.settings.red)
                Toggle("Green", isOn: $session.settings.green)
                Toggle("Blue", isOn: $session.settings.blue)
                if session.settings.colourCount > 0 {
                    Picker("PPG sample rate", selection: $session.settings.ppgHz) {
                        Text("50 Hz").tag(50)
                        if session.settings.colourCount == 1 {
                            Text("100 Hz").tag(100)
                        }
                    }
                    if session.settings.colourCount > 1 {
                        Text("Multiple colours use 50 Hz.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Toggle("IMU (acceleration + gyroscope)", isOn: $session.settings.imu)
            if session.settings.imu {
                Picker("IMU sample rate", selection: $session.settings.imuHz) {
                    Text("10 Hz").tag(10)
                    Text("25 Hz").tag(25)
                    Text("50 Hz").tag(50)
                }
            }
            Toggle("Temperature + humidity", isOn: $session.settings.temperatureHumidity)
            if session.settings.temperatureHumidity {
                Picker("Temperature + humidity rate", selection: $session.settings.temperaturePeriod) {
                    Text("Every 2 seconds").tag(20)
                    Text("Every second").tag(10)
                    Text("Twice per second").tag(5)
                }
            }
        }
        .disabled(session.active || session.busy)
        .onChange(of: session.settings.colourCount) { count in
            if count != 1 { session.settings.ppgHz = 50 }
        }
    }
}
