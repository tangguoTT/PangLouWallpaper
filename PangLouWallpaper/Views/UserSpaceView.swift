//
//  UserSpaceView.swift
//  PangLouWallpaper
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct UserSpaceView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 关闭按钮
            HStack {
                Spacer()
                Button(action: { viewModel.showUserSpace = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    profileSection
                    Divider()
                    uploadsSection
                    Divider()
                    collectionsSection
                    Divider()
                    dangerSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
        }
        // 注意：不在此处使用 .sheet()，弹窗统一由 ContentView 的 ZStack 层管理，
        // 避免 macOS 上 ZStack overlay 内嵌 .sheet() 导致 window 冻结的问题。
        .onAppear {
            Task {
                await viewModel.fetchUserProfile()
                await viewModel.fetchUserUploads()
            }
        }
    }

    // MARK: - Profile section

    private var profileSection: some View {
        VStack(spacing: 12) {
            // 头像
            avatarView
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))

            // 用户名 + 邮箱
            VStack(spacing: 4) {
                let name = viewModel.currentProfile?.username ?? ""
                Text(name.isEmpty ? "未设置用户名" : name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(name.isEmpty ? .secondary : .primary)
                Text(viewModel.currentUser?.email ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Button(action: { viewModel.showEditProfile = true }) {
                Text("编辑资料")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 20).padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var avatarView: some View {
        let url = viewModel.currentProfile?.avatarURL ?? ""
        if !url.isEmpty, let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: defaultAvatar
                }
            }
        } else {
            defaultAvatar
        }
    }

    private var defaultAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 60))
            .foregroundColor(.secondary)
    }

    // MARK: - My uploads section

    private var uploadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我上传的壁纸")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(viewModel.userUploads.count) 张")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            if viewModel.isLoadingUserUploads {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 20)
            } else if viewModel.userUploads.isEmpty {
                Text("还没有上传过壁纸")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(viewModel.userUploads.prefix(12)) { item in
                        AsyncThumbnailView(item: item)
                            .aspectRatio(16/10, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture { viewModel.previewItem = item }
                            
                    }
                }
                if viewModel.userUploads.count > 12 {
                    Button(action: {
                        viewModel.showUserSpace = false
                        viewModel.currentTab = .upload
                    }) {
                        Text("查看全部 \(viewModel.userUploads.count) 张")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Collections section

    private var collectionsSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("我的合集")
                    .font(.system(size: 15, weight: .bold))
                Text("\(viewModel.collections.count) 个合集")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                viewModel.showUserSpace = false
                viewModel.currentTab = .collection
            }) {
                HStack(spacing: 4) {
                    Text("查看")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.accentColor)
            }.buttonStyle(.plain)
        }
    }

    // MARK: - Danger section

    private var dangerSection: some View {
        VStack(spacing: 10) {
            Button(action: { viewModel.showChangePassword = true }) {
                HStack {
                    Image(systemName: "lock.rotation")
                    Text("修改密码")
                }
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)

            Button(action: {
                viewModel.showUserSpace = false
                viewModel.logout()
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("退出登录")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    @State private var username: String = ""
    @State private var pendingAvatarData: Data? = nil
    @State private var pendingAvatarImage: NSImage? = nil
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 24) {
            Text("编辑资料").font(.system(size: 18, weight: .bold))

            // 头像选择
            Button(action: pickAvatar) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let img = pendingAvatarImage {
                            Image(nsImage: img).resizable().scaledToFill()
                        } else {
                            let url = viewModel.currentProfile?.avatarURL ?? ""
                            if !url.isEmpty, let imageURL = URL(string: url) {
                                AsyncImage(url: imageURL) { phase in
                                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                                    else { avatarPlaceholder }
                                }
                            } else { avatarPlaceholder }
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .overlay(Image(systemName: "camera.fill").font(.system(size: 11)).foregroundColor(.white))
                }
            }.buttonStyle(.plain)

            // 用户名
            VStack(alignment: .leading, spacing: 6) {
                Text("用户名").font(.system(size: 13)).foregroundColor(.secondary)
                TextField("输入用户名", text: $username)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button(action: { viewModel.showEditProfile = false }) {
                    Text("取消")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)

                Button(action: save) {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().controlSize(.small).tint(.white) }
                        Text("保存").fontWeight(.bold).foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(isSaving)
            }
        }
        .padding(28)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        .onAppear { username = viewModel.currentProfile?.username ?? "" }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 60))
            .foregroundColor(.secondary)
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let nsImage = NSImage(contentsOf: url),
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return }
        pendingAvatarData = jpeg
        pendingAvatarImage = nsImage
    }

    private func save() {
        isSaving = true
        Task {
            await viewModel.saveProfile(username: username, avatarImageData: pendingAvatarData)
            await MainActor.run { isSaving = false; viewModel.showEditProfile = false }
        }
    }
}

// MARK: - Change Password Sheet

struct ChangePasswordView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var didSucceed = false

    var body: some View {
        VStack(spacing: 20) {
            Text("修改密码").font(.system(size: 18, weight: .bold))

            if didSucceed {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40)).foregroundColor(.green)
                    Text("密码已修改成功")
                        .font(.system(size: 15, weight: .medium))
                    Button("关闭") { viewModel.showChangePassword = false }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
            } else {
                VStack(spacing: 12) {
                    SecureField("新密码（至少 6 位）", text: $newPassword)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    SecureField("确认新密码", text: $confirmPassword)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 13)).foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: { viewModel.showChangePassword = false }) {
                        Text("取消")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)

                    Button(action: save) {
                        HStack(spacing: 6) {
                            if isSaving { ProgressView().controlSize(.small).tint(.white) }
                            Text("确认修改").fontWeight(.bold).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(isSaving || newPassword.isEmpty)
                }
            }
        }
        .padding(28)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
    }

    private func save() {
        guard newPassword == confirmPassword else {
            errorMessage = "两次密码不一致"; return
        }
        guard newPassword.count >= 6 else {
            errorMessage = "密码至少 6 位"; return
        }
        errorMessage = ""
        isSaving = true
        Task {
            do {
                try await viewModel.changePassword(newPassword: newPassword)
                await MainActor.run { didSucceed = true; isSaving = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isSaving = false }
            }
        }
    }
}
