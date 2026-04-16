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

// MARK: - Search & Filter Bar (全新现代化的头部与筛选)

struct WorkshopSearchBar: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    
    let filters = [
        ("全部", "全部类型"),
        ("Video", "视频壁纸"),
        ("Scene", "场景壁纸"),
        ("Web", "网页壁纸"),
        ("Image", "静态图片")
    ]

    var body: some View {
        VStack(spacing: 16) {
            // 搜索框层
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    TextField("搜索 Wallpaper Engine 创意工坊…", text: $viewModel.workshopSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit {
                            viewModel.workshopCurrentPage = 0
                            viewModel.workshopSteamCursor = 0
                            viewModel.workshopDisplayPageSteamStart = [:]
                            viewModel.fetchWorkshopItems()
                        }
                    if !viewModel.workshopSearchText.isEmpty {
                        Button(action: {
                            viewModel.workshopSearchText = ""
                            viewModel.workshopCurrentPage = 0
                            viewModel.workshopSteamCursor = 0
                            viewModel.workshopDisplayPageSteamStart = [:]
                            viewModel.fetchWorkshopItems()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                .cornerRadius(12)

                Button(action: {
                    viewModel.workshopCurrentPage = 0
                    viewModel.fetchWorkshopItems()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .cornerRadius(10)
                }.buttonStyle(.plain)
            }
            
            // 筛选器层
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filters, id: \.0) { tag, name in
                            Button(action: {
                                viewModel.workshopSelectedType = tag
                            }) {
                                Text(name)
                                    .font(.system(size: 13, weight: viewModel.workshopSelectedType == tag ? .bold : .medium))
                                    .foregroundColor(viewModel.workshopSelectedType == tag ? .white : .primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(viewModel.workshopSelectedType == tag ? Color.accentColor : Color.primary.opacity(0.06))
                                    .clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
            }
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

// MARK: - Item Card (全新现代化毛玻璃卡片)

struct WorkshopItemCard: View {
    let item: SteamWorkshopItem
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHovered = false

    private var downloadState: WorkshopDownloadState? {
        viewModel.workshopDownloadStates[item.id]
    }

    var body: some View {
        ZStack {
            // 背景图片
            WorkshopCachedImage(url: item.previewURL)

            // 现代化毛玻璃底部
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }

            // Type badge (top-right)
            if item.weType != .unknown || !item.tags.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        let wt = item.weType
                        Label(wt.displayName, systemImage: wt.systemImage)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(wt.needsWE ? Color.orange.opacity(0.9) : Color.accentColor.opacity(0.9))
                            .clipShape(Capsule())
                            .padding(8)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
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
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
            WorkshopCardDownloadView(itemId: item.id, viewModel: viewModel)

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
            // ⚠️ 这里更新了传参：传入整个 item 以支持体积读取
            WorkshopDownloadProgressView(item: item, viewModel: viewModel)

        case .failed(let reason):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 12))
                    Text(failedTitle(reason: reason))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                }
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

// MARK: - Cached Thumbnail Image (防止卡片图片热区溢出的全新组件)

struct WorkshopCachedImage: View {
    let url: URL?
    @State private var image: NSImage? = nil
    @State private var failed = false
    @State private var retryCount = 0

    var body: some View {
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
            .contentShape(Rectangle()) // ⬅️ 防止溢出遮挡导致死区的关键代码
            .onTapGesture { if failed { retryCount += 1 } }
            .task(id: "\(url?.absoluteString ?? "")|\(retryCount)") {
                await load()
            }
    }

    private func load() async {
        image = nil
        failed = false
        guard let url else { failed = true; return }
        let key = url.absoluteString as NSString
        if let cached = SteamWorkshopService.imageMemCache.object(forKey: key) {
            image = cached; return
        }
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
                // cost = 解码后的像素字节数，让 totalCostLimit 生效
                let cost = Int(img.size.width * img.size.height) * 4
                SteamWorkshopService.imageMemCache.setObject(img, forKey: key, cost: cost)
                image = img
                return
            } catch {
                if attempt == 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
            }
        }
        failed = true
    }
}

// MARK: - Card Downloading View (磁盘字节实时进度，用于卡片 hover 状态)

struct WorkshopCardDownloadView: View {
    let itemId: String
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var diskBytes: Int64 = 0

    var body: some View {
        VStack(spacing: 6) {
            if let pct = viewModel.workshopDownloadProgress[itemId], pct > 0 {
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                ProgressView(value: pct)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 90)
            } else if diskBytes > 0 {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 90)
                Text(formattedBytes(diskBytes))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(.white)
            }
            Text("下载中…")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
        .task {
            while !Task.isCancelled {
                let bytes = SteamWorkshopService.totalDownloadedBytes(itemId: itemId)
                if bytes > diskBytes { await MainActor.run { diskBytes = bytes } }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func formattedBytes(_ b: Int64) -> String {
        let mb = Double(b) / (1024 * 1024)
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(b) / 1024)
    }
}

// MARK: - Download Progress View (解决看不见进度的终极方案)

struct WorkshopDownloadProgressView: View {
    let item: SteamWorkshopItem
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var elapsed: Int = 0
    @State private var downloadedBytes: Int64 = 0
    @State private var timer: Timer? = nil

    private var totalBytes: Int64 {
        // 1. SteamCMD 实时上报的精确大小
        if let t = viewModel.workshopTotalBytes[item.id], t > 0 { return t }
        // 2. workshopItems 中的最新 fileSize（fetchItemDetails 异步回填，item 是值类型副本可能已过期）
        let liveSize = viewModel.workshopItems.first(where: { $0.id == item.id })?.fileSize ?? 0
        if liveSize > 0 { return Int64(liveSize) }
        // 3. 降级：使用 item 自带的 fileSize（可能为 0）
        return Int64(item.fileSize)
    }

    private var calculatedProgress: Double? {
        // 1. 如果 SteamCMD 有正常打印进度，直接用
        if let p = viewModel.workshopDownloadProgress[item.id], p > 0 { return p }
        // 2. 核心后备方案：通过硬盘文件大小 / API告诉的总大小 自己算进度！
        let total = totalBytes
        if total > 0 && downloadedBytes > 0 {
            return min(1.0, Double(downloadedBytes) / Double(total))
        }
        return nil
    }

    private var elapsedText: String {
        if elapsed < 60 { return "\(elapsed) 秒" }
        return "\(elapsed / 60) 分 \(elapsed % 60) 秒"
    }

    private func formattedBytes(_ b: Int64) -> String {
        if b < 1024 * 1024 { return String(format: "%.0f KB", Double(b) / 1024) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(b) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(b) / (1024 * 1024 * 1024))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pct = calculatedProgress {
                // 完美显示进度条
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
                        if totalBytes > 0 {
                            Text("\(formattedBytes(downloadedBytes)) / \(formattedBytes(totalBytes))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("已下载 \(formattedBytes(downloadedBytes))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("已用时 \(elapsedText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            } else if downloadedBytes > 0 {
                // 已有磁盘写入但不知道总大小时，显示不定式进度条 + 已下载量
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("正在下载")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("已用时 \(elapsedText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(width: 240)
                    Text("已下载 \(formattedBytes(downloadedBytes))（总大小未知）")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                // 下载刚刚开始，尚无任何磁盘写入
                HStack(spacing: 10) {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.85)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("正在建立 Steam 链接…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("已用时 \(elapsedText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        if let start = viewModel.workshopDownloadStartTime[item.id] {
            elapsed = Int(Date().timeIntervalSince(start))
        }
        // 每 0.5 秒查一次本地临时文件夹写入了多少
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if let start = viewModel.workshopDownloadStartTime[item.id] {
                elapsed = Int(Date().timeIntervalSince(start))
            } else {
                elapsed += 1
            }
            let bytes = SteamWorkshopService.totalDownloadedBytes(itemId: item.id)
            if bytes > downloadedBytes { downloadedBytes = bytes }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
