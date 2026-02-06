import SwiftUI

// MARK: - Auth View

struct AuthView: View {
    @ObservedObject var firebase = FirebaseManager.shared

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo

                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.purple)

                    Text("Daisy")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)

                    Text("Command Center")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                // Form

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button {
                        authenticate()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else {
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(email.isEmpty || password.isEmpty || isLoading)

                    Button(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up") {
                        isSignUp.toggle()
                        error = nil
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                }
                .frame(width: 300)

                Spacer()
            }
        }
    }

    private func authenticate() {
        isLoading = true
        error = nil

        Task {
            do {
                if isSignUp {
                    try await firebase.signUp(email: email, password: password)
                } else {
                    try await firebase.signIn(email: email, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
