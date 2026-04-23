//
//  UIComponents.swift
//  SimpleWallpaper
//

import SwiftUI
import AppKit
import AVKit

let capsuleBgColor = Color.primary.opacity(0.05)


/// 卡片动态预览
/// - 卡片出现：优先读本地缓存，命中立刻播
/// - 无缓存：延迟600ms（让缩略图先加载）后后台下载预览，完成后自动替换缩略图
struct HoverVideoPlayerView: View {
    let item: WallpaperItem
    @State private var localURL: URL?

    var body: some View {
        ZStack {
            if let url = localURL {
                VideoLayerView.Representable(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            // 先查本地缓存（零网络请求）
            if let cached = fromCacheOnly() {
                localURL = cached
                return
            }
            // 延迟让缩略图先加载，再后台下载预览
            try? await Task.sleep(nanoseconds: 600_000_000)
            let remotePreview = item.previewURL ?? item.fullURL.ossPreview()
            localURL = await WallpaperCacheManager.shared.fetchAndCachePreview(for: remotePreview)
        }
    }

    private func fromCacheOnly() -> URL? {
        // 优先使用轻量预览，避免用大体积全量视频渲染卡片，降低 GPU 压力
        let remotePreview = item.previewURL ?? item.fullURL.ossPreview()
        let cached = WallpaperCacheManager.shared.getPreviewCachePath(for: remotePreview)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        // 预览未缓存时才回退到全量视频（本地文件直接播）
        let full = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
        return FileManager.default.fileExists(atPath: full.path) ? full : nil
    }
}

/// AVPlayerLayer 作为 backing layer，AppKit 自动同步尺寸，背景透明，视频未渲染时缩略图透出
class VideoLayerView: NSView {
    private var player: AVPlayer?
    private var loopObserver: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer {
        let pl = AVPlayerLayer()
        pl.videoGravity = .resizeAspectFill
        pl.backgroundColor = .clear
        return pl
    }

    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    func setup(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 2  // 预览卡片只缓冲2秒，节省内存
        let p = AVPlayer(playerItem: playerItem)
        p.isMuted = true
        p.actionAtItemEnd = .none
        p.automaticallyWaitsToMinimizeStalling = false  // 有数据立刻播，不等缓冲
        playerLayer?.player = p
        player = p
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem, queue: .main
        ) { [weak p] _ in p?.seek(to: .zero); p?.play() }
        p.play()
    }

    func teardown() {
        if let obs = loopObserver { NotificationCenter.default.removeObserver(obs) }
        player?.pause()
        player = nil
        playerLayer?.player = nil
    }

    // 不拦截鼠标点击事件，让上层 SwiftUI 按钮（删除、设为壁纸等）正常响应
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // NSViewRepresentable 包装，供 SwiftUI 使用
    struct Representable: NSViewRepresentable {
        let url: URL
        func makeNSView(context: Context) -> VideoLayerView {
            let v = VideoLayerView()
            v.setup(url: url)
            return v
        }
        func updateNSView(_ nsView: VideoLayerView, context: Context) {}
        static func dismantleNSView(_ nsView: VideoLayerView, coordinator: Coordinator) { nsView.teardown() }
        func makeCoordinator() -> Coordinator { Coordinator() }
        class Coordinator {}
    }
}

struct AsyncThumbnailView: View {
    let item: WallpaperItem
    @State private var thumbnail: NSImage?
    @State private var isWebWallpaper = false   // HTML 文件且无预览图时置 true

    var body: some View {
        Color.primary.opacity(0.05)
            .overlay(
                Group {
                    if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    } else if isWebWallpaper {
                        // 网页壁纸无预览图时显示占位图标
                        VStack(spacing: 5) {
                            Image(systemName: "globe")
                                .font(.system(size: 22, weight: .thin))
                                .foregroundColor(.secondary.opacity(0.45))
                            Text("网页壁纸")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            )
            .clipped()
            .contentShape(Rectangle())
            .task(id: item.fullURL) {
                isWebWallpaper = false
                // 本地 HTML 壁纸：先找同目录 preview 图，否则显示占位图标
                let ext = item.fullURL.pathExtension.lowercased()
                if item.fullURL.isFileURL && (ext == "html" || ext == "htm") {
                    let dir = item.fullURL.deletingLastPathComponent()
                    let candidates = ["preview.jpg", "preview.jpeg", "preview.png",
                                      "thumbnail.jpg", "thumbnail.png"]
                    for name in candidates {
                        let previewURL = dir.appendingPathComponent(name)
                        if FileManager.default.fileExists(atPath: previewURL.path),
                           let img = NSImage(contentsOf: previewURL) {
                            thumbnail = img
                            return
                        }
                    }
                    isWebWallpaper = true   // 无预览图可用
                    return
                }

                if item.fullURL.isFileURL && item.isVideo {
                    thumbnail = await Task.detached(priority: .utility) {
                        let asset = AVAsset(url: item.fullURL)
                        let gen = AVAssetImageGenerator(asset: asset)
                        gen.appliesPreferredTrackTransform = true
                        gen.maximumSize = CGSize(width: 800, height: 500)
                        // 跳过第一秒，避免抓到视频开头的黑帧
                        let t1 = CMTime(seconds: 1, preferredTimescale: 600)
                        gen.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
                        gen.requestedTimeToleranceAfter  = CMTime(seconds: 2, preferredTimescale: 600)
                        if let cgImage = try? gen.copyCGImage(at: t1, actualTime: nil) {
                            return NSImage(cgImage: cgImage, size: .zero)
                        }
                        // 回退到第 0 帧
                        guard let cgImage = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
                        return NSImage(cgImage: cgImage, size: .zero)
                    }.value
                } else {
                    // 本地图片直接读取；远端图片走 Cloudflare，视频走 thumbnails/{id}.jpg
                    // 使用 fetchThumbnail（写入 thumb_ 前缀路径），避免污染 isDownloaded 判断
                    let thumbURL = item.fullURL.isFileURL
                        ? item.fullURL
                        : item.fullURL.ossThumb(isVideo: item.isVideo)
                    thumbnail = await WallpaperCacheManager.shared.fetchThumbnail(for: thumbURL)
                }
            }
            .onDisappear { thumbnail = nil; isWebWallpaper = false }
    }
}

// MARK: - 悬停操作按钮层
// 用独立 struct + .overlay(alignment:) 替代 VStack/HStack/Spacer 定位，
// 解决 `HStack { Spacer; Button }` 导致 trailing 按钮 hit-testing 区域不准确的问题。
private struct CardHoverOverlay: View {
    let item: WallpaperItem
    @ObservedObject var viewModel: WallpaperViewModel
    let isDownloaded: Bool
    let centerButtonText: String
    let isInAnyCollection: Bool
    let colorScheme: ColorScheme

    private var isLocalImport: Bool { viewModel.downloadedSubTab == .localImports || viewModel.downloadedSubTab == .workshop }
    private var isUploadManage: Bool { viewModel.currentTab == .upload && viewModel.uploadMode == .manage }
    private var isNormalMode: Bool { viewModel.currentTab != .slideshow && !isUploadManage }

    var body: some View {
        Color.black.opacity(0.28)
            .overlay(alignment: .center) { centerButtons }
            .overlay(alignment: .topLeading) { topLeadingButton }
            .overlay(alignment: .bottomLeading) { bottomLeadingButton }
            .overlay(alignment: .bottomTrailing) { bottomTrailingButton }
    }

    @ViewBuilder private var centerButtons: some View {
        if isUploadManage {
            Button(action: { withAnimation { viewModel.beginEdit(item: item) } }) {
                HStack { Image(systemName: "pencil"); Text("修改属性") }
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .padding(.vertical, 8).padding(.horizontal, 20)
                    .background(Color.blue.opacity(0.8)).clipShape(Capsule()).shadow(radius: 3)
            }.buttonStyle(.plain)
        } else if isNormalMode {
            Button(action: {
                if viewModel.currentTab == .pc {
                    guard viewModel.isLoggedIn else { viewModel.showLoginSheet = true; return }
                    if isDownloaded { viewModel.setWallpaper(item: item) } else { viewModel.downloadWallpaper(item: item) }
                } else { viewModel.setWallpaper(item: item) }
            }) {
                Text(centerButtonText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.vertical, 8).padding(.horizontal, 20)
                    .background(.ultraThinMaterial).clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var topLeadingButton: some View {
        if isNormalMode && !isLocalImport && viewModel.currentTab != .pc && viewModel.currentTab != .collection {
            Button(action: { viewModel.toggleInPlaylist(item: item) }) {
                Image(systemName: viewModel.playlistIds.contains(item.id) ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.playlistIds.contains(item.id) ? .yellow : .white)
                    .padding(8).background(Color.primary.opacity(0.08)).clipShape(Circle())
            }.buttonStyle(.plain).padding(8)
        }
    }

    @ViewBuilder private var bottomLeadingButton: some View {
        if isNormalMode && !isLocalImport {
            Button(action: {
                if viewModel.isLoggedIn { viewModel.addToCollectionTargetItem = item }
                else { viewModel.showLoginSheet = true }
            }) {
                Image(systemName: isInAnyCollection ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13))
                    .foregroundColor(isInAnyCollection ? Color(hex: "#C6AC2C") : .white)
                    .padding(8).background(Color.primary.opacity(0.08)).clipShape(Circle())
            }.buttonStyle(.plain).padding(8)
        }
    }

    @ViewBuilder private var bottomTrailingButton: some View {
        if isUploadManage {
            Button(action: { viewModel.deleteFromCloud(item: item) }) {
                Image(systemName: "trash.fill").font(.system(size: 12)).foregroundColor(.white)
                    .padding(8).background(Color.red.opacity(0.8)).clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            }.buttonStyle(.plain).padding(8)
        } else if viewModel.currentTab == .collection, let colId = viewModel.selectedCollectionId {
            Button(action: { viewModel.setCoverWallpaper(for: colId, wallpaperId: item.id) }) {
                Image(systemName: "photo.badge.checkmark").font(.system(size: 12)).foregroundColor(.white)
                    .padding(8).background(Color.accentColor.opacity(0.85)).clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            }.buttonStyle(.plain).help("设为合集封面").padding(8)
        } else if viewModel.currentTab == .downloaded {
            Button(action: { viewModel.deleteConfirmItem = item }) {
                Image(systemName: "trash.fill").font(.system(size: 12)).foregroundColor(.white)
                    .padding(8).background(Color.red.opacity(0.8)).clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            }.buttonStyle(.plain).padding(8)
        }
    }
}

struct WallpaperCardView: View {
    let item: WallpaperItem
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHovered = false
    @State private var isDownloaded = false
    @Environment(\.colorScheme) var colorScheme

    private var isCurrentWallpaper: Bool {
        let path = item.fullURL.isFileURL
            ? item.fullURL.path
            : WallpaperCacheManager.shared.getLocalPath(for: item.fullURL).path
        return !viewModel.currentWallpaperPath.isEmpty && path == viewModel.currentWallpaperPath
    }

    private var centerButtonText: String {
        if viewModel.currentTab == .pc {
            if !viewModel.isLoggedIn { return "登录后下载" }
            return isDownloaded
                ? (item.isVideo ? "设为动态壁纸" : "设为壁纸")
                : (item.isVideo ? "下载动态壁纸" : "下载壁纸")
        }
        return item.isVideo ? "设为动态壁纸" : "设为壁纸"
    }

    private var isInAnyCollection: Bool {
        viewModel.isItemInAnyCollection(item)
    }

    private var isBatchMode: Bool {
        viewModel.isBatchSelectMode
            && viewModel.currentTab == .downloaded
            && viewModel.downloadedSubTab == .local
    }

    private var isBatchSelected: Bool {
        viewModel.batchSelectedIds.contains(item.id)
    }

    var body: some View {
        ZStack {
            // 实心黑底：确保圆角区域四角不透明，消除矩形渲染痕迹
            Color.black

            // 预览点击区：悬停时从视图树彻底移除（不能只用 allowsHitTesting(false)，
            // 在 macOS 上含 contentShape(Rectangle()) 的 Button 即使禁用仍可能拦截点击）
            if !isHovered && !isBatchMode {
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = item } }) {
                    Color.clear.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }

            AsyncThumbnailView(item: item)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
                .contentShape(Rectangle())

            if item.isVideo {
                HoverVideoPlayerView(item: item)
                    .scaleEffect(isHovered ? 1.05 : 1.0)
                    .contentShape(Rectangle())
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
                    // NSViewRepresentable 在 SwiftUI 手势路由层面是不透明的，
                    // 即使底层 NSView.hitTest 返回 nil 也会拦截 SwiftUI 手势。
                    // 视频预览纯展示无需交互，禁用后点击事件正确传递给上层按钮。
                    .allowsHitTesting(false)
            }

            // 底部渐变信息栏（标题，置于视频层之上确保始终可见）
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.65), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 50)
                .overlay(alignment: .bottomLeading) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
            }
            .allowsHitTesting(false)

            if isCurrentWallpaper && !isHovered { VStack { HStack { Text("使用中").font(.system(size: 10, weight: .bold)).foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Color.accentColor).clipShape(Capsule()).padding(8); Spacer() }; Spacer() } }
            
            let isDownloading = viewModel.downloadProgress[item.id] != nil

            // 批量选择模式下不渲染悬停操作层：
            // 悬停层内的 Button(.plain) 会与外层批量 overlay 的 onTapGesture 竞争手势，
            // 导致两者都失效（类似 contentShape(Rectangle()) Button 在 macOS 上的已知问题）。
            if isHovered && !isDownloading && !isBatchMode {
                CardHoverOverlay(item: item, viewModel: viewModel,
                                 isDownloaded: isDownloaded,
                                 centerButtonText: centerButtonText,
                                 isInAnyCollection: isInAnyCollection,
                                 colorScheme: colorScheme)
            }
            
            if let progress = viewModel.downloadProgress[item.id] {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.2), lineWidth: 4).frame(width: 44, height: 44)
                            Circle().trim(from: 0, to: CGFloat(progress))
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 44, height: 44).rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.1), value: progress)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundColor(.white)
                        }
                        Button(action: { viewModel.cancelDownload(itemId: item.id) }) {
                            Text("取消")
                                .font(.system(size: 10, weight: .medium)).foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background(Color.white.opacity(0.2)).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }.transition(.opacity).zIndex(10)
            }

            if viewModel.failedDownloadIds.contains(item.id) {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.icloud.fill").font(.system(size: 22)).foregroundColor(.red)
                        Text("下载失败").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                        Button(action: { viewModel.retryDownload(item: item) }) {
                            Text("重试").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 5)
                                .background(Color.accentColor).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }.transition(.opacity).zIndex(11)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isCurrentWallpaper
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                          )),
                    lineWidth: isCurrentWallpaper ? 2 : 0.5
                )
        )
        // 批量选择覆盖层
        .overlay(
            Group {
                if isBatchMode {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isBatchSelected ? Color.accentColor : Color.white.opacity(0.3), lineWidth: isBatchSelected ? 2.5 : 1)
                        if isBatchSelected {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor.opacity(0.18))
                        }
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: isBatchSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(isBatchSelected ? .accentColor : .white.opacity(0.7))
                                    .shadow(color: .black.opacity(0.3), radius: 3)
                                    .padding(8)
                            }
                            Spacer()
                        }
                        // macOS 上 ZStack 透明区域的 onTapGesture 不可靠（右侧死区问题）。
                        // 与 preview button 保持一致：用 Button + Color.clear.contentShape 作为置顶透明热区，
                        // 确保整张卡片可点击。
                        Button(action: { viewModel.toggleBatchSelection(item: item) }) {
                            Color.clear.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isBatchSelected)
        .background(
            // SwiftUI 对 Shape.shadow() 会显式设置 CALayer.shadowPath = 圆角路径，
            // 避免 CA 用矩形 bounds 计算阴影导致浅色背景下出现"幽灵直角"。
            RoundedRectangle(cornerRadius: 16)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        )
        .onHover { isHovered = $0 }
        .task(id: "\(item.id)_\(viewModel.cacheVersion)") { let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL); isDownloaded = FileManager.default.fileExists(atPath: localURL.path) }
    }
}

// MARK: - 删除确认弹窗（走 ContentView ZStack overlay，与其他弹窗模式一致）
struct DeleteConfirmView: View {
    let item: WallpaperItem
    @ObservedObject var viewModel: WallpaperViewModel
    @Environment(\.colorScheme) var colorScheme

    private var isLocalImport: Bool { viewModel.downloadedSubTab == .localImports || viewModel.downloadedSubTab == .workshop }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.red)

            Text(isLocalImport ? "删除本地导入的壁纸" : "删除壁纸缓存")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.primary)

            Text(isLocalImport
                ? "「\(item.title.isEmpty ? "该壁纸" : item.title)」将从本地导入列表中移除，原始文件不受影响。"
                : "「\(item.title.isEmpty ? "该壁纸" : item.title)」的本地缓存将被删除，可重新下载。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            HStack(spacing: 12) {
                Button(action: { viewModel.deleteConfirmItem = nil }) {
                    Text("取消")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 100, height: 34)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)

                Button(action: {
                    if isLocalImport {
                        viewModel.deleteLocalImport(item)
                    } else {
                        viewModel.deleteSingleCache(for: item)
                    }
                    viewModel.deleteConfirmItem = nil
                }) {
                    Text("删除")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 100, height: 34)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
        .padding(28)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
    }
}

struct EditWallpaperPopupView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    private let categories  = ["全部", "魅力", "自制", "安逸", "科幻", "动漫", "自然", "游戏"]
    private let resolutions = ["全部", "1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K"]
    private let colors      = ["全部", "偏蓝", "偏绿", "偏红", "灰/白", "紫/粉", "暗色", "偏黄", "其他颜色"]

    var body: some View {
        VStack(spacing: 20) {
            Text("修改壁纸属性").font(.system(size: 18, weight: .bold)).foregroundColor(.primary)

            VStack(spacing: 12) {
                // 标题
                HStack {
                    Text("标题：").frame(width: 60, alignment: .trailing).font(.system(size: 14))
                    TextField("壁纸标题", text: $viewModel.editTitle)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06)).cornerRadius(6)
                        .frame(width: 280)
                }
                // 描述
                HStack {
                    Text("描述：").frame(width: 60, alignment: .trailing).font(.system(size: 14))
                    TextField("一句话描述（用于全文搜索）", text: $viewModel.editDescription)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06)).cornerRadius(6)
                        .frame(width: 280)
                }
                // 标签
                HStack {
                    Text("标签：").frame(width: 60, alignment: .trailing).font(.system(size: 14))
                    TextField("逗号分隔，如：动漫, 夜晚, 城市", text: $viewModel.editTags)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06)).cornerRadius(6)
                        .frame(width: 280)
                }
                Divider().padding(.vertical, 2)
                // 分类 / 分辨率 / 色系
                HStack {
                    Text("分类：").frame(width: 60, alignment: .trailing).font(.system(size: 14))
                    Picker("", selection: $viewModel.editCategory) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 120).labelsHidden()
                }
                HStack {
                    Text("分辨率：").frame(width: 60, alignment: .trailing).font(.system(size: 14))
                    Picker("", selection: $viewModel.editResolution) {
                        ForEach(resolutions, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 120).labelsHidden()
                }
                HStack {
                    Text("色系：").frame(width: 60, alignment: .trailing).font(.system(size: 14))
                    Picker("", selection: $viewModel.editColor) {
                        ForEach(colors, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 120).labelsHidden()
                }
            }

            HStack(spacing: 20) {
                Button(action: { withAnimation { viewModel.cancelEdit() } }) {
                    Text("取消").fontWeight(.medium)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.1)).cornerRadius(8)
                }.buttonStyle(.plain)
                Button(action: { viewModel.saveWallpaperEdit() }) {
                    Text("保存修改").fontWeight(.bold)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .background(Color.accentColor).foregroundColor(.white).cornerRadius(8)
                }.buttonStyle(.plain)
            }
        }
        .padding(30)
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.15), radius: 24, y: 10))
    }
}

struct CustomThemeToggleView: View {
    @Binding var isDarkMode: Bool
    var body: some View {
        ZStack {
            Capsule()
                .fill(isDarkMode ? Color(white: 0.2) : Color(red: 0.85, green: 0.92, blue: 1.0))
                .frame(width: 54, height: 28)
            HStack {
                if isDarkMode { Spacer(minLength: 0) }
                ZStack {
                    Circle()
                        .fill(isDarkMode ? Color(white: 0.18) : Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    if isDarkMode {
                        Image(systemName: "moon.fill")
                            .resizable().scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundColor(Color(red: 0.78, green: 0.85, blue: 1.0))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "sun.max.fill")
                            .resizable().scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.2))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 24, height: 24)
                .padding(2)
                if !isDarkMode { Spacer(minLength: 0) }
            }
        }
        .frame(width: 54, height: 28)
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isDarkMode.toggle() }
        }
    }
}
struct NavPillButtonView: View {
    let title: String; let icon: String; let isSelected: Bool; var showBadge: Bool = false; let action: () -> Void
    var bgColor: Color { isSelected ? Color.accentColor.opacity(0.15) : Color.clear }; var fgColor: Color { isSelected ? Color.accentColor : Color.primary.opacity(0.6) }
    var body: some View { Button(action: action) { HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 12)); Text(title).font(.system(size: 13, weight: isSelected ? .bold : .regular)) }.foregroundColor(fgColor).padding(.vertical, 8).padding(.horizontal, 16).background(bgColor).clipShape(Capsule()).overlay(ZStack { if showBadge { Text("N").font(.system(size: 8, weight: .bold)).foregroundColor(.white).padding(4).background(Color.red).clipShape(Circle()).offset(x: 10, y: -10) } }, alignment: .topTrailing) }.buttonStyle(.plain) }
}
struct FilterTagView: View {
    let title: String; var icon: String? = nil; let isSelected: Bool
    var fgColor: Color { isSelected ? Color.accentColor : Color.primary.opacity(0.7) }; var bgColor: Color { isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05) }
    var body: some View { HStack(spacing: 4) { if let icon = icon { Image(systemName: icon).font(.system(size: 11)) }; Text(title).font(.system(size: 13)) }.foregroundColor(fgColor).padding(.vertical, 8).padding(.horizontal, 16).background(bgColor).clipShape(Capsule()) }
}
struct PageNumberCircleView: View {
    let number: Int; let isCurrent: Bool; let action: () -> Void
    var fgColor: Color { isCurrent ? Color.accentColor : Color.primary.opacity(0.7) }; var bgColor: Color { isCurrent ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05) }
    var body: some View { Button(action: action) { Text("\(number)").font(.system(size: 13, weight: isCurrent ? .bold : .medium)).foregroundColor(fgColor).frame(width: 32, height: 32).background(bgColor).clipShape(Circle()) }.buttonStyle(.plain) }
}

// MARK: - 关于页面

struct AboutView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "版本 \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().frame(width: 80, height: 80).cornerRadius(18)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }

            VStack(spacing: 6) {
                Text("胖楼壁纸").font(.system(size: 22, weight: .bold))
                Text(versionString).font(.system(size: 13)).foregroundColor(.secondary)
            }

            Divider().padding(.horizontal, 20)

            VStack(spacing: 6) {
                Text("一款简洁优雅的 Mac 桌面壁纸软件")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                Text("支持静态壁纸与动态视频，云端同步，本地轮播")
                    .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.8))
            }

            Text("© 2026 唐潇. 保留所有权利.")
                .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.6))

            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.showAbout = false } }) {
                Text("好").fontWeight(.semibold)
                    .padding(.horizontal, 32).padding(.vertical, 8)
                    .background(Color.accentColor).foregroundColor(.white).cornerRadius(8)
            }.buttonStyle(.plain)
        }
        .padding(30)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
    }
}

// MARK: - 壁纸大图预览弹窗

struct WallpaperPreviewView: View {
    let item: WallpaperItem
    @ObservedObject var viewModel: WallpaperViewModel

    private var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: WallpaperCacheManager.shared.getLocalPath(for: item.fullURL).path)
    }
    private var isDownloading: Bool { viewModel.downloadProgress[item.id] != nil }

    private var cleanTitle: String {
        var t = item.title
        while t.hasPrefix("[") {
            guard let close = t.firstIndex(of: "]") else { break }
            t = String(t[t.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return t.isEmpty ? item.title : t
    }

    private var fileTypeText: String {
        let ext = item.fullURL.pathExtension.lowercased()
        return ext.isEmpty ? "未知格式" : ext.uppercased()
    }

    private var parsedTags: [String] {
        var tags: [String] = [item.isVideo ? "动态壁纸" : "静态壁纸"]
        var t = item.title
        while t.hasPrefix("[") {
            guard let open = t.firstIndex(of: "["), let close = t.firstIndex(of: "]") else { break }
            let tag = String(t[t.index(after: open)..<close])
            tags.append(tag.components(separatedBy: " | ").first ?? tag)
            t = String(t[t.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return tags
    }

    @State private var keyMonitor: Any?
    @State private var fileSizeText: String = ""

    private var prevItem: WallpaperItem? { viewModel.adjacentPreviewItems().prev }
    private var nextItem: WallpaperItem? { viewModel.adjacentPreviewItems().next }

    private func navigate(to target: WallpaperItem?) {
        guard let target else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = target }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 预览图/视频区域
            ZStack {
                Color.black
                if item.isVideo {
                    // 缩略图先铺底，视频渲染出帧后自然覆盖，避免黑屏闪烁
                    AsyncThumbnailView(item: item)
                    HoverVideoPlayerView(item: item).id(item.id)
                } else {
                    AsyncThumbnailView(item: item)
                }

                // 左右导航箭头
                HStack {
                    if let prev = prevItem {
                        Button(action: { navigate(to: prev) }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .clipShape(Circle())
                        }.buttonStyle(.plain)
                            .padding(.leading, 12)
                    } else {
                        Spacer().frame(width: 60)
                    }
                    Spacer()
                    if let next = nextItem {
                        Button(action: { navigate(to: next) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .clipShape(Circle())
                        }.buttonStyle(.plain)
                            .padding(.trailing, 12)
                    } else {
                        Spacer().frame(width: 60)
                    }
                }

                // 下载进度遮罩
                if let progress = viewModel.downloadProgress[item.id] {
                    ZStack {
                        Color.black.opacity(0.6)
                        VStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(Color.white.opacity(0.2), lineWidth: 4).frame(width: 52, height: 52)
                                Circle().trim(from: 0, to: CGFloat(progress))
                                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 52, height: 52).rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.1), value: progress)
                            }
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundColor(.white)
                            Button(action: { viewModel.cancelDownload(itemId: item.id) }) {
                                Text("取消")
                                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 5)
                                    .background(Color.white.opacity(0.2)).clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }

                // 关闭按钮
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil } }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .clipShape(Circle())
                        }.buttonStyle(.plain).padding(12)
                    }
                    Spacer()
                }
            }
            .frame(height: 360)
            .clipped()

            // 信息与操作区域
            VStack(alignment: .leading, spacing: 12) {
                Text(cleanTitle)
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.primary).lineLimit(2)

                HStack(spacing: 6) {
                    ForEach(parsedTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.07)).clipShape(Capsule())
                    }
                    Text(fileTypeText)
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.07)).clipShape(Capsule())
                    if !fileSizeText.isEmpty {
                        Text(fileSizeText)
                            .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundColor(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.07)).clipShape(Capsule())
                    }
                }

                VStack(spacing: 8) {
                    if viewModel.currentTab == .pc {
                        if !viewModel.isLoggedIn {
                            // 未登录：全宽登录入口
                            Button(action: {
                                viewModel.previewItem = nil
                                viewModel.showLoginSheet = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                    Text("登录后下载")
                                }
                                .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        } else {
                            // 主按钮：设为壁纸（全宽，强调色）
                            Button(action: {
                                viewModel.setWallpaper(item: item)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: item.isVideo ? "play.circle.fill" : "photo.fill")
                                    Text(item.isVideo ? "设为动态壁纸" : "设为壁纸")
                                }
                                .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(isDownloading)
                            // 次级按钮：下载壁纸（全宽，ghost）
                            Button(action: {
                                viewModel.downloadWallpaper(item: item)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: isDownloaded ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    Text(isDownloaded ? "已下载" : "下载壁纸")
                                }
                                .font(.system(size: 13))
                                .foregroundColor(isDownloaded ? .secondary : .primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(Color.primary.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).disabled(isDownloaded || isDownloading)
                        }
                    } else if viewModel.currentTab != .slideshow {
                        // 主按钮：设为壁纸（全宽，强调色）
                        Button(action: {
                            viewModel.setWallpaper(item: item)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: item.isVideo ? "play.circle.fill" : "photo.fill")
                                Text(item.isVideo ? "设为动态壁纸" : "设为壁纸")
                            }
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(isDownloading)
                        // 次级按钮：加入轮播（全宽，ghost）
                        Button(action: { viewModel.toggleInPlaylist(item: item) }) {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.playlistIds.contains(item.id) ? "star.fill" : "star")
                                Text(viewModel.playlistIds.contains(item.id) ? "已加轮播" : "加入轮播")
                            }
                            .font(.system(size: 13))
                            .foregroundColor(viewModel.playlistIds.contains(item.id) ? Color(hex: "#C6AC2C") : .primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(viewModel.playlistIds.contains(item.id) ? Color(hex: "#C6AC2C").opacity(0.12) : Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
        .frame(width: 560)
        .task(id: item.id) {
            await fetchFileSize()
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 123: // ← 左箭头
                    let prev = viewModel.adjacentPreviewItems().prev
                    if let prev {
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = prev }
                        }
                    }
                    return nil
                case 124: // → 右箭头
                    let next = viewModel.adjacentPreviewItems().next
                    if let next {
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = next }
                        }
                    }
                    return nil
                case 53: // Esc 关闭预览
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil }
                    }
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        }
    }

    private func fetchFileSize() async {
        let localPath = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
        if FileManager.default.fileExists(atPath: localPath.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: localPath.path),
           let size = attrs[.size] as? Int64 {
            fileSizeText = formatFileSize(size)
            return
        }
        guard !item.fullURL.isFileURL else { fileSizeText = ""; return }
        var request = URLRequest(url: item.fullURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse,
           let lenStr = http.allHeaderFields["Content-Length"] as? String,
           let size = Int64(lenStr) {
            fileSizeText = formatFileSize(size)
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}

// MARK: - 加入合集弹窗

struct AddToCollectionView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("加入合集").font(.system(size: 18, weight: .bold))
                Spacer()
                Button(action: { viewModel.addToCollectionTargetItem = nil }) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(.primary)
                        .padding(8).background(Color.primary.opacity(0.1)).clipShape(Circle())
                }.buttonStyle(.plain)
            }

            if viewModel.collections.isEmpty && !isCreating {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 36)).foregroundColor(.primary.opacity(0.3))
                    Text("还没有合集").font(.system(size: 14)).foregroundColor(.secondary)
                    Button(action: { isCreating = true }) {
                        HStack(spacing: 6) { Image(systemName: "plus.circle.fill"); Text("新建合集").fontWeight(.bold) }
                            .font(.system(size: 13)).foregroundColor(.white)
                            .padding(.vertical, 8).padding(.horizontal, 16)
                            .background(Color.accentColor).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }.padding(.vertical, 8)
            } else {
                // 合集列表
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(viewModel.collections) { collection in
                            let itemId = viewModel.addToCollectionTargetItem?.id ?? ""
                            let isIn = collection.wallpaperIds.contains(itemId)
                            Button(action: {
                                if !itemId.isEmpty {
                                    viewModel.toggleWallpaperInCollection(itemId: itemId, collectionId: collection.id)
                                }
                            }) {
                                HStack(spacing: 12) {
                                    if let coverItem = viewModel.allWallpapers.first(where: { collection.wallpaperIds.contains($0.id) }) {
                                        AsyncThumbnailView(item: coverItem).frame(width: 52, height: 32).cornerRadius(6).clipped()
                                    } else {
                                        RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)).frame(width: 52, height: 32)
                                            .overlay(Image(systemName: "rectangle.stack").font(.system(size: 12)).foregroundColor(.secondary))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(collection.name).font(.system(size: 14, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                                        Text("\(collection.wallpaperIds.count) 张").font(.system(size: 11)).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isIn ? .accentColor : Color.primary.opacity(0.3))
                                        .font(.system(size: 20))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.primary.opacity(0.05)).cornerRadius(10)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)

                if !isCreating {
                    Button(action: { isCreating = true }) {
                        HStack(spacing: 6) { Image(systemName: "plus.circle"); Text("新建合集") }
                            .font(.system(size: 13)).foregroundColor(.accentColor)
                    }.buttonStyle(.plain)
                }
            }

            if isCreating {
                HStack(spacing: 8) {
                    TextField("合集名称", text: $newName)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06)).cornerRadius(6)
                        .onSubmit { createAndAdd() }
                    Button(action: createAndAdd) {
                        Text("创建").fontWeight(.bold).foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(newName.isEmpty ? Color.secondary : Color.accentColor).cornerRadius(6)
                    }.buttonStyle(.plain).disabled(newName.isEmpty)
                    Button(action: { isCreating = false; newName = "" }) {
                        Text("取消").font(.system(size: 13)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }

            Button(action: { viewModel.addToCollectionTargetItem = nil }) {
                Text("完成").fontWeight(.semibold)
                    .padding(.horizontal, 32).padding(.vertical, 8)
                    .background(Color.accentColor).foregroundColor(.white).cornerRadius(8)
            }.buttonStyle(.plain)
        }
        .padding(24)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.15), radius: 24, y: 10))
    }

    private func createAndAdd() {
        guard !newName.isEmpty else { return }
        viewModel.createCollection(name: newName)
        if let item = viewModel.addToCollectionTargetItem,
           let newCollection = viewModel.collections.last {
            viewModel.toggleWallpaperInCollection(itemId: item.id, collectionId: newCollection.id)
        }
        newName = ""
        isCreating = false
    }
}
