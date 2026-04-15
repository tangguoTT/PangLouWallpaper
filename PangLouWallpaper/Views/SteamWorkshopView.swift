//
//  SteamWorkshopView.swift
//  SimpleWallpaper
//

import SwiftUI
import Security

// MARK: - Main View

struct SteamWorkshopView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                WorkshopSearchBar(viewModel: viewModel)
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                if viewModel.isLoadingWorkshop {
                    Spacer()
                    ProgressView("正在加载 Steam Workshop…")
                        .foregroundColor(.secondary)
                    Spacer()
                } else if viewModel.workshopItems.isEmpty {
                    WorkshopEmptyView(viewModel: viewModel)
                } else {
                    WorkshopGridView(viewModel: viewModel)
                }

                WorkshopPaginationBar(viewModel: viewModel)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if viewModel.workshopItems.isEmpty {
                    viewModel.fetchWorkshopItems()
                }
            }
            .disabled(viewModel.workshopPreviewItem != nil)

            // Preview overlay
            if viewModel.workshopPreviewItem != nil {
                Color.black.opacity(0.6).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.workshopPreviewItem = nil
                        }
                    }
                    .zIndex(10)

                if let item = viewModel.workshopPreviewItem {
                    WorkshopPreviewOverlay(item: item, viewModel: viewModel)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(11)
                }
            }

            // Steam login sheet
            if viewModel.workshopLoginItem != nil {
                Color.black.opacity(0.6).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture {
                        if !viewModel.workshopLoginInProgress {
                            viewModel.workshopLoginItem = nil
                        }
                    }
                    .zIndex(20)

                if let item = viewModel.workshopLoginItem {
                    SteamLoginSheet(item: item, viewModel: viewModel)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(21)
                }
            }
        }
    }
}

// MARK: - Search Bar

struct WorkshopSearchBar: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                TextField("搜索 Wallpaper Engine Workshop…", text: $viewModel.workshopSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        viewModel.workshopCurrentPage = 0
                        viewModel.fetchWorkshopItems()
                    }
                if !viewModel.workshopSearchText.isEmpty {
                    Button(action: {
                        viewModel.workshopSearchText = ""
                        viewModel.workshopCurrentPage = 0
                        viewModel.fetchWorkshopItems()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
            .cornerRadius(10)

            Button(action: {
                viewModel.workshopCurrentPage = 0
                viewModel.fetchWorkshopItems()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
                    .cornerRadius(8)
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - Empty View

struct WorkshopEmptyView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary.opacity(0.4))
            Text("没有找到相关壁纸")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Button("刷新") { viewModel.fetchWorkshopItems() }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid (3 rows × 4 cols, fills available space — mirrors the PC wallpaper grid)

struct WorkshopGridView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        VStack(spacing: 15) {
            let items = viewModel.workshopItems
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 15) {
                    ForEach(0..<4, id: \.self) { col in
                        let index = row * 4 + col
                        if index < items.count {
                            WorkshopItemCard(item: items[index], viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Item Card

struct WorkshopItemCard: View {
    let item: SteamWorkshopItem
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHovered = false

    private var downloadState: WorkshopDownloadState? {
        viewModel.workshopDownloadStates[item.id]
    }

    var body: some View {
        ZStack {
            // Background image — fills the whole cell (Color-based layout, never grows from pixel dims)
            WorkshopCachedImage(url: item.previewURL)

            // Bottom gradient + title (always visible)
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 56)
                .overlay(alignment: .bottomLeading) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 7)
                }
            }

            // Type badge (top-right) — shown when tags are loaded
            if item.weType != .unknown || !item.tags.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        let wt = item.weType
                        Label(wt.displayName, systemImage: wt.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(wt.needsWE ? Color.orange.opacity(0.85) : Color.black.opacity(0.6))
                            .cornerRadius(6)
                            .padding(8)
                    }
                    Spacer()
                }
            }

            // Hover overlay
            if isHovered {
                Color.black.opacity(0.45)
                downloadButton
            }
        }
        .cornerRadius(12)
        .clipped()
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.workshopPreviewItem = item
            }
        }
        .onAppear {
            let dir = SteamWorkshopService.workshopItemDirectory(itemId: item.id)
            if let file = SteamWorkshopService.findWallpaperFile(in: dir) {
                viewModel.workshopDownloadStates[item.id] = .done(file)
            }
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch downloadState {
        case .done(let url):
            Button(action: { viewModel.importWorkshopFile(url: url, setImmediately: true) }) {
                Label("设为壁纸", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(20)
            }.buttonStyle(.plain)

        case .downloading:
            VStack(spacing: 6) {
                if let pct = viewModel.workshopDownloadProgress[item.id], pct > 0 {
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    ProgressView(value: pct)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 90)
                } else {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8).tint(.white)
                }
                Text("下载中…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }

        case .failed:
            VStack(spacing: 8) {
                Button(action: { viewModel.downloadWorkshopItemViaSteamCMD(item: item) }) {
                    Label("重试下载", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.orange)
                        .cornerRadius(20)
                }.buttonStyle(.plain)

                Button(action: { viewModel.openWorkshopItemInSteam(item) }) {
                    Text("在 Steam 中订阅")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }.buttonStyle(.plain)
            }

        case nil:
            Button(action: { viewModel.downloadWorkshopItemViaSteamCMD(item: item) }) {
                Label("下载壁纸", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(20)
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - Pagination

struct WorkshopPaginationBar: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        HStack {
            Button(action: {
                guard viewModel.workshopCurrentPage > 0 else { return }
                viewModel.workshopCurrentPage -= 1
                viewModel.fetchWorkshopItems()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(viewModel.workshopCurrentPage > 0 ? .primary : .primary.opacity(0.25))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.07))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.workshopCurrentPage == 0)

            Spacer()

            Text("第 \(viewModel.workshopCurrentPage + 1) 页")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                guard viewModel.workshopHasNextPage else { return }
                viewModel.workshopCurrentPage += 1
                viewModel.fetchWorkshopItems()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(viewModel.workshopHasNextPage ? .primary : .primary.opacity(0.25))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.07))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.workshopHasNextPage)
        }
    }
}

// MARK: - Preview Overlay

struct WorkshopPreviewOverlay: View {
    let item: SteamWorkshopItem
    @ObservedObject var viewModel: WallpaperViewModel
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    private var downloadState: WorkshopDownloadState? {
        viewModel.workshopDownloadStates[item.id]
    }

    private var largePreviewURL: URL? {
        item.previewURL?.steamPreview(width: 1280, height: 720)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    // Type + file size badges
                    HStack(spacing: 8) {
                        let wt = item.weType
                        if wt != .unknown || !item.tags.isEmpty {
                            Label(wt.displayName, systemImage: wt.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(wt.needsWE ? .orange : .white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(wt.needsWE ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.8))
                                .cornerRadius(6)
                        }
                        if wt.needsWE {
                            Text("需要 Wallpaper Engine")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(6)
                        } else if wt != .unknown {
                            Text("macOS 可用")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(6)
                        }
                        if item.fileSize > 0 {
                            Text(formatWorkshopFileSize(item.fileSize))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(6)
                        }
                    }
                    if !item.tags.isEmpty {
                        Text(item.tags.prefix(4).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.workshopPreviewItem = nil
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            // Preview image
            if let url = largePreviewURL {
                WorkshopCachedImage(url: url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)
                    .clipped()
            } else {
                previewPlaceholder
                    .frame(height: 380)
            }

            // Action buttons
            HStack(spacing: 16) {
                actionButtons
                Spacer()
                // Open in Steam link
                Button(action: { viewModel.openWorkshopItemInSteam(item) }) {
                    Label("在 Steam 中查看", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 680)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isDarkMode ? Color(red: 0.12, green: 0.13, blue: 0.16) : Color.white)
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
        )
        .onAppear {
            // Auto-detect local file on open
            let dir = SteamWorkshopService.workshopItemDirectory(itemId: item.id)
            if let file = SteamWorkshopService.findWallpaperFile(in: dir),
               viewModel.workshopDownloadStates[item.id] == nil {
                viewModel.workshopDownloadStates[item.id] = .done(file)
            }
        }
    }

    // Human-readable title for the failed state
    private func failedTitle(reason: String) -> String {
        if reason.contains("scene") || reason.contains("web") || reason.contains("preset") {
            return "此壁纸类型需要 Wallpaper Engine，macOS 不支持"
        }
        if reason.contains("匿名") || reason.isEmpty || reason.contains("SteamCMD 未返回") {
            return "下载失败，请尝试用 Steam 账号下载"
        }
        return "下载失败"
    }

    private func isUnexpectedFailure(reason: String) -> Bool {
        let known = ["scene", "web", "preset", "匿名", "SteamCMD 未返回", "下载完成但"]
        return !known.contains(where: { reason.contains($0) }) && !reason.isEmpty
    }

    private var previewPlaceholder: some View {
        ZStack {
            Color.primary.opacity(0.06)
            Image(systemName: "photo")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary.opacity(0.3))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch downloadState {
        case .done(let url):
            Button(action: {
                viewModel.importWorkshopFile(url: url, setImmediately: true)
                withAnimation { viewModel.workshopPreviewItem = nil }
            }) {
                Label("设为壁纸", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(22)
            }.buttonStyle(.plain)

        case .downloading:
            WorkshopDownloadProgressView(itemId: item.id, viewModel: viewModel)

        case .failed(let reason):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 12))
                    Text(failedTitle(reason: reason))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                }
                // Show SteamCMD raw output only for unexpected errors (helps diagnose)
                if isUnexpectedFailure(reason: reason) {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button(action: { viewModel.downloadWorkshopItemViaSteamCMD(item: item) }) {
                        Label("重试免费下载", systemImage: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.primary.opacity(0.1))
                            .cornerRadius(20)
                    }.buttonStyle(.plain)

                    Button(action: {
                        viewModel.workshopLoginItem = item
                        viewModel.workshopLoginNeedsGuard = false
                        viewModel.workshopLoginNeedsTwoFactor = false
                    }) {
                        Label("Steam 账号下载", systemImage: "person.fill.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(red: 0.10, green: 0.48, blue: 0.90))
                            .cornerRadius(20)
                    }.buttonStyle(.plain)
                }
            }

        case nil:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button(action: { viewModel.downloadWorkshopItemViaSteamCMD(item: item) }) {
                        Label("免费下载", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Color.accentColor)
                            .cornerRadius(22)
                    }.buttonStyle(.plain)

                    Button(action: {
                        viewModel.workshopLoginItem = item
                        viewModel.workshopLoginNeedsGuard = false
                        viewModel.workshopLoginNeedsTwoFactor = false
                    }) {
                        Label("Steam 账号下载", systemImage: "person.fill.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color(red: 0.10, green: 0.48, blue: 0.90))
                            .cornerRadius(22)
                    }.buttonStyle(.plain)
                }
                Text("免费下载：无需登录   Steam 账号：需购买 Wallpaper Engine，支持付费壁纸")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private func formatWorkshopFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1   { return String(format: "%.1f GB", gb) }
        if mb >= 1   { return String(format: "%.0f MB", mb) }
        if kb >= 1   { return String(format: "%.0f KB", kb) }
        return "\(bytes) B"
    }
}

// MARK: - Steam Login Sheet

struct SteamLoginSheet: View {
    let item: SteamWorkshopItem
    @ObservedObject var viewModel: WallpaperViewModel
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var guardCode: String = ""

    private var needsGuard: Bool { viewModel.workshopLoginNeedsGuard || viewModel.workshopLoginNeedsTwoFactor }
    private var guardLabel: String { viewModel.workshopLoginNeedsTwoFactor ? "手机令牌验证码" : "Steam Guard 邮箱验证码" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.fill.badge.plus")
                    .foregroundColor(Color(red: 0.10, green: 0.48, blue: 0.90))
                    .font(.system(size: 18))
                Text("Steam 账号下载")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                if !viewModel.workshopLoginInProgress {
                    Button(action: {
                        viewModel.workshopLoginItem = nil
                        viewModel.workshopLoginSavedPassword = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 4)

            Text("壁纸：\(item.title)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            Divider().padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 14) {
                if !needsGuard {
                    // Credentials input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Steam 用户名").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        TextField("用户名", text: $username)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.primary.opacity(0.07))
                            .cornerRadius(8)
                            .autocorrectionDisabled()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("密码").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        SecureField("密码", text: $password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.primary.opacity(0.07))
                            .cornerRadius(8)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("密码仅用于本次 SteamCMD 调用，不会被存储")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Steam Guard code input
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope.badge.shield.half.filled")
                                .foregroundColor(.orange)
                            Text("需要 \(guardLabel)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        Text(viewModel.workshopLoginNeedsTwoFactor
                             ? "请打开 Steam 手机 App，查看令牌验证码"
                             : "Steam 已向你的邮箱发送了验证码，请查收")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        TextField(guardLabel, text: $guardCode)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .medium))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Color.primary.opacity(0.07))
                            .cornerRadius(8)
                            .autocorrectionDisabled()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().padding(.horizontal, 16)

            // Action buttons
            HStack(spacing: 12) {
                if viewModel.workshopLoginInProgress {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                    Text("正在处理…").font(.system(size: 13)).foregroundColor(.secondary)
                } else if needsGuard {
                    Button(action: {
                        viewModel.downloadWorkshopItemWithCredentials(
                            item: item,
                            username: username,
                            password: password,
                            guardCode: guardCode.isEmpty ? nil : guardCode
                        )
                    }) {
                        Text("提交验证码")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color(red: 0.10, green: 0.48, blue: 0.90))
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .disabled(guardCode.isEmpty)

                    Button(action: {
                        viewModel.workshopLoginNeedsGuard = false
                        viewModel.workshopLoginNeedsTwoFactor = false
                        guardCode = ""
                    }) {
                        Text("重新输入密码")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                } else {
                    Button(action: {
                        viewModel.downloadWorkshopItemWithCredentials(
                            item: item,
                            username: username,
                            password: password
                        )
                    }) {
                        Label("登录并下载", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color(red: 0.10, green: 0.48, blue: 0.90))
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .disabled(username.isEmpty || password.isEmpty)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isDarkMode ? Color(red: 0.12, green: 0.13, blue: 0.16) : Color.white)
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
        )
        .onAppear {
            // Pre-fill saved credentials (username persisted to UserDefaults; password held in ViewModel for Guard flow)
            username = UserDefaults.standard.string(forKey: "steamUsername") ?? ""
            if password.isEmpty { password = viewModel.workshopLoginSavedPassword }
        }
        .onChange(of: viewModel.workshopLoginItem) { newItem in
            if newItem == nil { guardCode = "" }
        }
        .onChange(of: username) { newValue in
            UserDefaults.standard.set(newValue, forKey: "steamUsername")
        }
    }
}

// MARK: - Cached Thumbnail Image
// Uses Color as the layout base (fills parent without being influenced by image pixel size),
// with the image in an overlay — the same pattern as AsyncThumbnailView in the PC grid.
// Tap the failed state to retry loading.

struct WorkshopCachedImage: View {
    let url: URL?
    @State private var image: NSImage? = nil
    @State private var failed = false
    @State private var retryCount = 0

    var body: some View {
        // Color fills whatever space the parent offers — it never grows due to image dimensions.
        Color.primary.opacity(0.06)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 20, weight: .thin))
                        .foregroundColor(.secondary.opacity(0.4))
                } else {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.55)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if failed { retryCount += 1 } }
            // task re-runs when URL changes (view reused for a different item on page change)
            // or when retryCount changes (manual retry tap). Always call load() — it resets state.
            .task(id: "\(url?.absoluteString ?? "")|\(retryCount)") {
                await load()
            }
    }

    private func load() async {
        // Reset stale state so the new URL's image is shown, not a previous page's leftover.
        image = nil
        failed = false
        guard let url else { failed = true; return }
        let key = url.absoluteString as NSString
        // 1. Memory cache hit (instant, no flicker for already-seen thumbnails)
        if let cached = SteamWorkshopService.imageMemCache.object(forKey: key) {
            image = cached; return
        }
        // 2. URLCache / network — retry once on failure
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        for attempt in 0..<2 {
            do {
                let (data, response) = try await SteamWorkshopService.thumbnailSession.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    if attempt == 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
                    continue
                }
                guard let img = NSImage(data: data) else {
                    if attempt == 0 { try? await Task.sleep(nanoseconds: 800_000_000); continue }
                    failed = true; return
                }
                SteamWorkshopService.imageMemCache.setObject(img, forKey: key)
                image = img
                return
            } catch {
                if attempt == 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
            }
        }
        failed = true
    }
}

// MARK: - Download Progress View (shown in preview overlay while SteamCMD runs)

struct WorkshopDownloadProgressView: View {
    let itemId: String
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var elapsed: Int = 0
    @State private var downloadedBytes: Int64 = 0
    @State private var timer: Timer? = nil

    private var progress: Double? {
        guard let p = viewModel.workshopDownloadProgress[itemId], p > 0 else { return nil }
        return p
    }

    private var totalBytes: Int64? { viewModel.workshopTotalBytes[itemId] }

    private var elapsedText: String {
        if elapsed < 60 { return "\(elapsed) 秒" }
        return "\(elapsed / 60) 分 \(elapsed % 60) 秒"
    }

    private var tipText: String {
        switch elapsed {
        case 0..<12:   return "正在连接 Steam 服务器…"
        case 12..<35:  return "正在登录并准备下载…"
        case 35..<90:  return "正在从 Steam CDN 下载…"
        case 90..<180: return "大文件下载需要几分钟，请勿关闭应用"
        default:       return "仍在下载中，请勿关闭应用"
        }
    }

    private func formattedBytes(_ b: Int64) -> String {
        if b < 1024 * 1024 { return String(format: "%.0f KB", Double(b) / 1024) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(b) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(b) / (1024 * 1024 * 1024))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pct = progress {
                // 确定进度 — SteamCMD 报告了百分比
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("正在下载")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    ProgressView(value: pct)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(width: 240)
                    HStack {
                        // 优先显示 "已下载 / 总大小"，无总大小时只显示已下载
                        if downloadedBytes > 0 {
                            if let total = totalBytes, total > downloadedBytes {
                                Text("\(formattedBytes(downloadedBytes)) / \(formattedBytes(total))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("已下载 \(formattedBytes(downloadedBytes))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else if let total = totalBytes {
                            Text("共 \(formattedBytes(total))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("已用时 \(elapsedText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // 不确定进度 — 等待 SteamCMD 开始报告
                HStack(spacing: 10) {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.85)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tipText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        HStack(spacing: 10) {
                            if downloadedBytes > 0 {
                                if let total = totalBytes, total > downloadedBytes {
                                    Text("\(formattedBytes(downloadedBytes)) / \(formattedBytes(total))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                } else {
                                    Text("已下载 \(formattedBytes(downloadedBytes))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                }
                            } else if let total = totalBytes {
                                Text("共 \(formattedBytes(total))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Text("已用时 \(elapsedText)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        if let start = viewModel.workshopDownloadStartTime[itemId] {
            elapsed = Int(Date().timeIntervalSince(start))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let start = viewModel.workshopDownloadStartTime[itemId] {
                elapsed = Int(Date().timeIntervalSince(start))
            } else {
                elapsed += 1
            }
            // Poll filesystem for bytes written so far (works even without SteamCMD progress output)
            let bytes = SteamWorkshopService.totalDownloadedBytes(itemId: itemId)
            if bytes > downloadedBytes { downloadedBytes = bytes }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
