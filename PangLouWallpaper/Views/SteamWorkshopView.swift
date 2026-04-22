//
//  SteamWorkshopView.swift
//  SimpleWallpaper
//

import SwiftUI
import Security

// MARK: - Main View

struct SteamWorkshopView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Binding var isSidebarVisible: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    WorkshopSearchBar(viewModel: viewModel, isSidebarVisible: $isSidebarVisible)
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                        .padding(.bottom, 12)
                    Divider().opacity(0.5)
                }
                .background(.bar)

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
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.workshopPreviewItem = nil
                        }
                    }
                    .zIndex(10)

                if let item = viewModel.workshopPreviewItem {
                    WorkshopPreviewOverlay(item: item, viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(11)
                }
            }

            // Steam login sheet
            if viewModel.workshopLoginItem != nil {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture {
                        if !viewModel.workshopLoginInProgress {
                            viewModel.workshopLoginItem = nil
                        }
                    }
                    .zIndex(20)

                if let item = viewModel.workshopLoginItem {
                    SteamLoginSheet(item: item, viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(21)
                }
            }
        }
    }
}

// MARK: - Search & Filter Bar (全新现代化的头部与筛选)

struct WorkshopSearchBar: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Binding var isSidebarVisible: Bool
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    let filters = [
        ("全部", "全部类型"),
        ("Video", "视频壁纸"),
        ("Scene", "场景壁纸"),
        ("Web", "网页壁纸"),
        ("Image", "静态图片")
    ]

    private let sortOptions: [(String, String, String)] = [
        ("3", "热门趋势", "flame"),
        ("1", "最新发布", "clock"),
    ]

    private var currentSortLabel: String {
        sortOptions.first { $0.0 == viewModel.workshopSortType }?.1 ?? "投票数排名"
    }

    private var isNewestSort: Bool { viewModel.workshopSortType == "1" }

    var body: some View {
        VStack(spacing: 16) {
            // 搜索框层
            HStack(spacing: 12) {
                // Sidebar expand button (shown inline when sidebar is hidden)
                if !isSidebarVisible {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            isSidebarVisible = true
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary.opacity(0.6))
                            .frame(width: 30, height: 30)
                            .background(Color.primary.opacity(0.07))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("显示侧边栏")
                    .transition(.opacity)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(isNewestSort ? .secondary.opacity(0.5) : .secondary)
                        .font(.system(size: 14))
                    if isNewestSort {
                        Text("最新发布模式不支持关键词搜索")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("搜索 Wallpaper Engine 创意工坊…", text: $viewModel.workshopSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .onSubmit {
                                viewModel.workshopCurrentPage = 0
                                viewModel.workshopTotalResults = 0
                                viewModel.fetchWorkshopItems()
                            }
                        if !viewModel.workshopSearchText.isEmpty {
                            Button(action: {
                                viewModel.workshopSearchText = ""
                                viewModel.workshopCurrentPage = 0
                                viewModel.workshopTotalResults = 0
                                viewModel.fetchWorkshopItems()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 13))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                .cornerRadius(12)

                // 排序下拉菜单
                Menu {
                    ForEach(sortOptions, id: \.0) { value, label, icon in
                        Button(action: {
                            if value == "1" && !viewModel.workshopSearchText.isEmpty {
                                viewModel.workshopSearchText = ""
                            }
                            viewModel.workshopSortType = value
                        }) {
                            Label(label, systemImage: icon)
                            if viewModel.workshopSortType == value {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                        Text(currentSortLabel)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.primary.opacity(0.7))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .cornerRadius(10)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

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
        let items = viewModel.workshopItems
        VStack(spacing: 15) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 15) {
                    ForEach(0..<4, id: \.self) { col in
                        let index = row * 4 + col
                        if index < items.count {
                            WorkshopItemCard(item: items[index], viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
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

    private var isDownloading: Bool {
        if case .downloading = downloadState { return true }
        return false
    }

    var body: some View {
        ZStack {
            // 实心黑底：消除圆角区域直角渲染痕迹
            Color.black
            // 背景图片
            WorkshopCachedImage(url: item.previewURL)

            // 毛玻璃底部信息栏（标题 + 文件大小/类型 + 下载进度条）
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    // 标题行
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    // 文件信息行（类型 + 大小）
                    HStack(spacing: 8) {
                        let wt = item.weType
                        Label(wt.displayName, systemImage: wt.systemImage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        if item.fileSize > 0 {
                            let mb = Double(item.fileSize) / (1024.0 * 1024.0)
                            Text(mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 3)
                    .padding(.bottom, 8)
                }
                .background(.ultraThinMaterial)
            }

            // 类型标签（右上角，始终显示）
            VStack {
                HStack {
                    Spacer()
                    if item.weType != .unknown || !item.tags.isEmpty {
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
                }
                Spacer()
            }

            // 下载中居中覆盖层（常驻，不需要 hover）
            if isDownloading && !isHovered {
                Color.black.opacity(0.5)
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("下载中")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            // Hover overlay
            if isHovered {
                Color.black.opacity(0.3)
                downloadButton
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 16)
                .shadow(color: Color.primary.opacity(isHovered ? 0.15 : 0.1), radius: isHovered ? 24 : 12, y: isHovered ? 12 : 6)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.workshopPreviewItem = item
            }
        }
        .onAppear {
            viewModel.restoreWorkshopDownloadState(for: item)
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
            WorkshopCardDownloadView(item: item, viewModel: viewModel)

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
    @State private var jumpText = ""

    private var cur: Int { viewModel.workshopCurrentPage }
    private var isFiltered: Bool { viewModel.workshopSelectedType != "全部" }
    private var totalPages: Int {
        guard viewModel.workshopTotalResults > 0 else { return 0 }
        return max(1, Int(ceil(Double(viewModel.workshopTotalResults) / Double(viewModel.workshopItemsPerPage))))
    }

    private func go(_ page: Int) {
        viewModel.workshopCurrentPage = page
        viewModel.fetchWorkshopItems()
    }

    var body: some View {
        HStack(spacing: 12) {
            // Previous
            Button(action: { go(cur - 1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(cur == 0 ? .primary.opacity(0.25) : .primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(cur == 0)

            // Page number circles
            HStack(spacing: 6) {
                if cur > 1 {
                    WorkshopPageCircle(number: 1, isCurrent: false) { go(0) }
                }
                if cur > 2 {
                    Text("…").foregroundColor(.primary.opacity(0.35)).font(.system(size: 13))
                }
                if cur > 0 {
                    WorkshopPageCircle(number: cur, isCurrent: false) { go(cur - 1) }
                }
                WorkshopPageCircle(number: cur + 1, isCurrent: true) { }
                if totalPages > 0, cur + 2 <= totalPages - 1 {
                    Text("…").foregroundColor(.primary.opacity(0.35)).font(.system(size: 13))
                    WorkshopPageCircle(number: totalPages, isCurrent: false) { go(totalPages - 1) }
                } else if totalPages > 0, cur + 2 == totalPages {
                    WorkshopPageCircle(number: totalPages, isCurrent: false) { go(totalPages - 1) }
                }
            }

            // Next
            Button(action: { go(cur + 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(viewModel.workshopHasNextPage ? .primary : .primary.opacity(0.25))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.workshopHasNextPage)

            if totalPages > 5 {
                HStack(spacing: 6) {
                    Text("跳转")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("", text: $jumpText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .frame(width: 34, height: 26)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        .onSubmit {
                            if let p = Int(jumpText), p >= 1, p <= totalPages { go(p - 1); jumpText = "" }
                        }
                    Button(action: {
                        if let p = Int(jumpText), p >= 1, p <= totalPages { go(p - 1); jumpText = "" }
                    }) {
                        Text("Go").font(.system(size: 12, weight: .bold)).foregroundColor(.accentColor)
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// 自适应宽度的页码按钮：小数字用圆形，大数字（≥100）用胶囊避免溢出
private struct WorkshopPageCircle: View {
    let number: Int
    let isCurrent: Bool
    let action: () -> Void

    private var fg: Color { isCurrent ? Color.accentColor : Color.primary.opacity(0.7) }
    private var bg: Color { isCurrent ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05) }

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 12, weight: isCurrent ? .bold : .medium))
                .foregroundColor(fg)
                .padding(.horizontal, number >= 100 ? 8 : 0)
                .frame(width: number >= 100 ? nil : 28, height: 28)
                .background(bg)
                .clipShape(number >= 100 ? AnyShape(Capsule()) : AnyShape(Circle()))
        }.buttonStyle(.plain)
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
        item.previewURL
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
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .onAppear {
            viewModel.restoreWorkshopDownloadState(for: item)
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
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
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
    @State private var image: NSImage?
    @State private var failed = false
    @State private var retryCount = 0

    init(url: URL?) {
        self.url = url
        if let url, let cached = SteamWorkshopService.imageMemCache.object(forKey: url.absoluteString as NSString) {
            _image = State(initialValue: cached)
        } else {
            _image = State(initialValue: nil)
        }
    }

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

// MARK: - Card Downloading View (hover 状态下载中)

struct WorkshopCardDownloadView: View {
    let item: SteamWorkshopItem
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var elapsed: Int = 0
    @State private var timer: Timer? = nil

    private var elapsedText: String {
        elapsed < 60 ? "\(elapsed)秒" : "\(elapsed / 60)分\(elapsed % 60)秒"
    }

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)
            Text("下载中")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            if elapsed > 0 {
                Text("已用时 \(elapsedText)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        if let start = viewModel.workshopDownloadStartTime[item.id] {
            elapsed = Int(Date().timeIntervalSince(start))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let start = viewModel.workshopDownloadStartTime[item.id] {
                elapsed = Int(Date().timeIntervalSince(start))
            } else {
                elapsed += 1
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}

// MARK: - Download Progress View (解决看不见进度的终极方案)

struct WorkshopDownloadProgressView: View {
    let item: SteamWorkshopItem
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var elapsed: Int = 0
    @State private var timer: Timer? = nil

    private var elapsedText: String {
        if elapsed < 60 { return "\(elapsed) 秒" }
        return "\(elapsed / 60) 分 \(elapsed % 60) 秒"
    }

    private func formattedBytes(_ b: Int) -> String {
        if b < 1024 * 1024 { return String(format: "%.0f KB", Double(b) / 1024) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(b) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(b) / (1024 * 1024 * 1024))
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.primary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("正在下载")
                        .font(.system(size: 13, weight: .medium))
                    if elapsed > 0 {
                        Text("· 已用时 \(elapsedText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                if item.fileSize > 0 {
                    Text("文件大小 \(formattedBytes(item.fileSize))，下载完成后自动导入")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("下载完成后自动导入")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let start = viewModel.workshopDownloadStartTime[item.id] {
                elapsed = Int(Date().timeIntervalSince(start))
            } else {
                elapsed += 1
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
