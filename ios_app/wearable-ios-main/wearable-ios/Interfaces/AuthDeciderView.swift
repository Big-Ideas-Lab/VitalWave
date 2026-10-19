import SwiftUI

// Kept for older source files that still refer to this request type.
struct GetSignInTokenRequest: Codable { var token: String }

struct AuthDeciderView: View {
    @StateObject private var authModel = AuthViewModel()

    var body: some View {
        Group {
            switch authModel.authenticationState {
            case .authenticating:
                ProgressView("Loading…")
            case .unauthenticated:
                AccountEntryView()
            case .authenticated:
                if authModel.needsProfile {
                    CompleteProfileView()
                } else {
                    MainTabView(initialTab: authModel.initialTab)
                }
            }
        }
        .environmentObject(authModel)
        .onAppear { authModel.listenToAuthState() }
    }
}

private struct AccountEntryView: View {
    @EnvironmentObject private var model: AuthViewModel
    private var creating: Bool { model.flow == .signup }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("VitalWave").font(.largeTitle.bold())
                    if creating {
                        Text("Create your account, then connect your watch.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section(creating ? "Create account" : "Sign in") {
                    if creating {
                        TextField("Name", text: $model.displayName)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                    }
                    TextField("Email", text: $model.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $model.password)
                        .textContentType(creating ? .newPassword : .password)
                }
                if !model.errorMessage.isEmpty {
                    Section { Text(model.errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task {
                            if creating { await model.createAccount() }
                            else { _ = await model.signInWithEmailPassword() }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isBusy { ProgressView() }
                            Text(creating ? "Create Account" : "Sign In")
                            Spacer()
                        }
                    }
                    .disabled(!model.isValid || model.isBusy)
                }
                Section {
                    Button(creating ? "Already have an account? Sign in" : "Create an account") {
                        model.flow = creating ? .login : .signup
                        model.password = ""
                        model.errorMessage = ""
                    }
                }
            }
            .disabled(model.isBusy)
            .navigationTitle(creating ? "Create Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CompleteProfileView: View {
    @EnvironmentObject private var model: AuthViewModel
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("What should we call you?").font(.title2.bold())
                    Text("Add your name to finish your profile.")
                        .foregroundStyle(.secondary)
                    TextField("Name", text: $model.displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                }
                if !model.errorMessage.isEmpty {
                    Section { Text(model.errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await model.completeProfile() }
                    } label: {
                        HStack {
                            if model.isBusy { ProgressView() }
                            Text("Save and connect watch")
                        }
                    }
                    .disabled(model.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Sign Out", role: .destructive) { model.signOut() }
                }
            }
            .disabled(model.isBusy)
            .navigationTitle("Your profile")
        }
    }
}
