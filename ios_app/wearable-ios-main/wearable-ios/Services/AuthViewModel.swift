//
//  AuthViewModel.swift
//  wearable-ios
//  Created by Carola Maglione on 10/9/23.
//  Updated by Jade Chng 10/6/2023


import SwiftUI
@preconcurrency import FirebaseAuth

enum AuthenticationState { case unauthenticated, authenticating, authenticated }
enum AuthenticationFlow { case login, signup }

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = "" // Compatibility with older views.
    @Published var displayName = ""
    @Published var flow: AuthenticationFlow = .login
    @Published var authenticationState: AuthenticationState = .authenticating
    @Published var user: User?
    @Published var errorMessage = ""
    @Published var isBusy = false
    @Published var needsProfile = false
    @Published var initialTab = "Home"
    private var listener: AuthStateDidChangeListenerHandle?

    var isValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        (flow == .login || !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func listenToAuthState() {
        guard listener == nil else { return }
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isBusy else { return }
                self.synchronize()
            }
        }
    }

    private func synchronize() {
        let current = Auth.auth().currentUser
        user = current
        if let current {
            UserDefaults.standard.set(current.uid, forKey: "auth-uid")
            let name = current.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            needsProfile = name.isEmpty
            if !name.isEmpty { displayName = name }
            authenticationState = .authenticated
        } else {
            UserDefaults.standard.removeObject(forKey: "auth-uid")
            needsProfile = false
            authenticationState = .unauthenticated
        }
    }

    func signInWithEmailPassword() async -> Bool {
        guard !isBusy, isValid else { return false }
        isBusy = true
        errorMessage = ""
        defer { password = ""; isBusy = false; synchronize() }
        do {
            _ = try await Auth.auth().signIn(
                withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            initialTab = "Home"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createAccount() async {
        guard !isBusy, isValid else { return }
        isBusy = true
        errorMessage = ""
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { password = ""; isBusy = false; synchronize() }
        do {
            let result = try await Auth.auth().createUser(
                withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            initialTab = "Devices"
            // Account creation signs in immediately. Hold the UI until the name is saved.
            do {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try await change.commitChanges()
            } catch {
                // The account exists: offer profile retry, not another account creation.
                errorMessage = "Your account was created, but your name could not be saved. Please try saving it again. \(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeProfile() async {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !name.isEmpty, let current = Auth.auth().currentUser else { return }
        isBusy = true
        errorMessage = ""
        defer { isBusy = false; synchronize() }
        do {
            let change = current.createProfileChangeRequest()
            change.displayName = name
            try await change.commitChanges()
            initialTab = "Devices"
        } catch { errorMessage = error.localizedDescription }
    }

    func signInWithToken(token: String) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = ""
        defer { isBusy = false; synchronize() }
        do { _ = try await Auth.auth().signIn(withCustomToken: token) }
        catch { errorMessage = error.localizedDescription }
    }

    func signOut() {
        guard !isBusy else { return }
        do {
            try Auth.auth().signOut()
            for key in ["auth-uid", "pairedPeripherals", "paired-peripherals", "cookies"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            email = ""; password = ""; confirmPassword = ""; displayName = ""
            errorMessage = ""; flow = .login; initialTab = "Home"
            synchronize()
        } catch { errorMessage = error.localizedDescription }
    }
}
