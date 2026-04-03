//
//  AuthView.swift
//  PangLouWallpaper
//

import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isLoginMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isLoginMode ? "登录账户" : "注册账户")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button(action: { viewModel.showLoginSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }.padding(.bottom, 24)

            // Login / Register toggle
            HStack(spacing: 0) {
                modeButton(title: "登录", selected: isLoginMode) {
                    isLoginMode = true; errorMessage = ""
                }
                modeButton(title: "注册", selected: !isLoginMode) {
                    isLoginMode = false; errorMessage = ""
                }
            }
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 20)

            // Fields
            VStack(spacing: 12) {
                AuthTextField(placeholder: "邮箱地址", text: $email, isSecure: false)
                AuthTextField(placeholder: "密码（至少 6 位）", text: $password, isSecure: true)
                if !isLoginMode {
                    AuthTextField(placeholder: "确认密码", text: $confirmPassword, isSecure: true)
                }
            }.padding(.bottom, 16)

            // Success / Error message
            if !successMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(successMessage).font(.system(size: 13)).foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            } else if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
            }

            // Submit
            Button(action: submit) {
                HStack(spacing: 8) {
                    if isLoading { ProgressView().controlSize(.small).tint(.white) }
                    Text(isLoginMode ? "登录" : "注册")
                        .fontWeight(.bold).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(canSubmit ? Color.accentColor : Color.accentColor.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isLoading)
        }
        .padding(28)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
    }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty
    }

    private func modeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(selected ? Color.accentColor : Color.clear)
                .foregroundColor(selected ? .white : .secondary)
        }.buttonStyle(.plain)
    }

    private func submit() {
        guard canSubmit else { return }
        if !isLoginMode && password != confirmPassword {
            errorMessage = "两次密码不一致"
            return
        }
        errorMessage = ""
        successMessage = ""
        isLoading = true
        Task {
            do {
                if isLoginMode {
                    try await AuthService.shared.signIn(email: email, password: password)
                } else {
                    try await AuthService.shared.signUp(email: email, password: password)
                }
                await MainActor.run {
                    viewModel.currentUser = AuthService.shared.currentUser
                    viewModel.showLoginSheet = false
                    isLoading = false
                }
                await viewModel.syncCollectionsFromCloud()
                await viewModel.fetchUserProfile()
                await viewModel.fetchUserUploads()
            } catch AuthError.confirmationRequired {
                await MainActor.run {
                    successMessage = "注册成功！请查收验证邮件，点击链接确认后再登录"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

private struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }
}
