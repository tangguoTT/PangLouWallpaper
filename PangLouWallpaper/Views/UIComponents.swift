//
//  UIComponents.swift
//  SimpleWallpaper
//

import SwiftUI
import AppKit
import AVKit

let capsuleBgColor = Color.primary.opacity(0.05)

struct HoverVideoPlayerView: NSViewRepresentable {
    let item: WallpaperItem

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill
        let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
        let playURL = FileManager.default.fileExists(atPath: localURL.path) ? localURL : item.fullURL
        let player = AVPlayer(url: playURL)
        player.isMuted = true
        player.actionAtItemEnd = .none
        playerView.player = player
        context.coordinator.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        if let obs = coordinator.loopObserver { NotificationCenter.default.removeObserver(obs) }
        nsView.player?.pause()
        nsView.player = nil
    }

    class Coordinator {
        var loopObserver: Any?
    }
}

struct AsyncThumbnailView: View {
    let item: WallpaperItem
    @State private var thumbnail: NSImage?
    
    var body: some View {
        // 🌟 核心修复 2：彻底删掉强硬的 .aspectRatio
        // 使用色块打底，图片通过 overlay 附着，溢出部分被直接 clipped() 切掉。绝对不撑大父级！
        Color.primary.opacity(0.05)
            .overlay(
                Group {
                    if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            )
            .clipped()
            .task(id: item.fullURL) {
                let thumbURL = item.fullURL.ossThumb(isVideo: item.isVideo)
                if let img = await WallpaperCacheManager.shared.fetchImage(for: thumbURL) { self.thumbnail = img }
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
        let path = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL).path
        return !viewModel.currentWallpaperPath.isEmpty && path == viewModel.currentWallpaperPath
    }

    var body: some View {
        ZStack {
            AsyncThumbnailView(item: item).cornerRadius(12).clipped()
            
            if viewModel.currentTab == .pc && isDownloaded && !isHovered { VStack { Spacer(); HStack { Spacer(); Image(systemName: "checkmark.icloud.fill").font(.system(size: 14)).foregroundColor(Color(hex: "#449B3E")).padding(6).background(.ultraThinMaterial).clipShape(Circle()).padding(8).shadow(color: .black.opacity(0.2), radius: 3) } } }
            if isCurrentWallpaper && !isHovered { VStack { HStack { Text("使用中").font(.system(size: 10, weight: .bold)).foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Color.accentColor).clipShape(Capsule()).padding(8); Spacer() }; Spacer() } }
            if isHovered && item.isVideo { HoverVideoPlayerView(item: item).cornerRadius(12).clipped().transition(.opacity) }
            if item.isVideo { VStack { HStack { Spacer(); Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundColor(.white.opacity(0.9)).padding(10).opacity(isHovered ? 0 : 1).animation(.easeInOut, value: isHovered) }; Spacer() } }
            
            let isDownloading = viewModel.downloadProgress[item.id] != nil
            
            if isHovered && !isDownloading {
                (colorScheme == .dark ? Color.black : Color.white).opacity(0.3).cornerRadius(12)
                    .onTapGesture(count: 2) {
                        if viewModel.currentTab == .upload && viewModel.uploadMode == .manage {
                            withAnimation { viewModel.beginEdit(item: item) }
                        } else if viewModel.currentTab == .pc {
                            viewModel.downloadWallpaper(item: item)
                        } else {
                            viewModel.setWallpaper(item: item)
                        }
                    }
                    .overlay(
                        ZStack {
                            if viewModel.currentTab == .upload && viewModel.uploadMode == .manage {
                                Button(action: { withAnimation { viewModel.beginEdit(item: item) } }) {
                                    HStack { Image(systemName: "pencil"); Text("修改属性") }
                                        .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                        .padding(.vertical, 8).padding(.horizontal, 20)
                                        .background(Color.blue.opacity(0.8)).clipShape(Capsule())
                                        .shadow(radius: 3)
                                }.buttonStyle(.plain)
                                VStack { Spacer(); HStack { Spacer(); Button(action: { viewModel.deleteFromCloud(item: item) }) { Image(systemName: "trash.fill").font(.system(size: 12)).foregroundColor(.white).padding(8).background(Color.red.opacity(0.8)).clipShape(Circle()).shadow(color: .black.opacity(0.3), radius: 3, y: 2) }.buttonStyle(.plain).padding(8) } }
                            } else {
                                Button(action: { if viewModel.currentTab == .pc { viewModel.downloadWallpaper(item: item) } else { viewModel.setWallpaper(item: item) } }) {
                                    let buttonText = viewModel.currentTab == .pc ? (item.isVideo ? "下载动态壁纸" : "下载壁纸") : (item.isVideo ? "设为动态壁纸" : "设为壁纸")
                                    Text(buttonText).font(.system(size: 13, weight: .bold)).foregroundColor(colorScheme == .dark ? .white : .black).padding(.vertical, 8).padding(.horizontal, 20).background(.ultraThinMaterial).clipShape(Capsule()).overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                                }.buttonStyle(.plain)

                                // 收藏按钮（右上角，所有 tab 通用）
                                VStack { HStack { Spacer(); Button(action: { viewModel.toggleFavorite(item: item) }) { Image(systemName: viewModel.favoriteIds.contains(item.id) ? "heart.fill" : "heart").font(.system(size: 13)).foregroundColor(viewModel.favoriteIds.contains(item.id) ? .pink : .white).padding(8).background(Color.black.opacity(0.5)).clipShape(Circle()) }.buttonStyle(.plain).padding(8) }; Spacer() }

                                if viewModel.currentTab != .pc {
                                    VStack { HStack { Button(action: { viewModel.toggleInPlaylist(item: item) }) { Image(systemName: viewModel.playlistIds.contains(item.id) ? "star.fill" : "star").font(.system(size: 13)).foregroundColor(viewModel.playlistIds.contains(item.id) ? .yellow : .white).padding(8).background(Color.black.opacity(0.5)).clipShape(Circle()) }.buttonStyle(.plain).padding(8); Spacer() }; Spacer() }
                                }
                                if viewModel.currentTab == .downloaded { VStack { Spacer(); HStack { Spacer(); Button(action: { viewModel.deleteSingleCache(for: item) }) { Image(systemName: "trash.fill").font(.system(size: 12)).foregroundColor(.white).padding(8).background(Color.red.opacity(0.8)).clipShape(Circle()).shadow(color: .black.opacity(0.3), radius: 3, y: 2) }.buttonStyle(.plain).padding(8) } } }
                            }
                        }
                    )
            }
            
            if let progress = viewModel.downloadProgress[item.id] {
                ZStack { Color.black.opacity(0.6).cornerRadius(12); Circle().stroke(Color.white.opacity(0.2), lineWidth: 4).frame(width: 44, height: 44); Circle().trim(from: 0, to: CGFloat(progress)).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 44, height: 44).rotationEffect(.degrees(-90)).animation(.linear(duration: 0.1), value: progress); Text("\(Int(progress * 100))%").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundColor(.white) }.transition(.opacity).zIndex(10)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isCurrentWallpaper ? Color.accentColor : Color.primary.opacity(0.05), lineWidth: isCurrentWallpaper ? 2 : 1)).shadow(color: Color.primary.opacity(isHovered ? 0.2 : 0.05), radius: isHovered ? 10 : 4, y: isHovered ? 5 : 2).scaleEffect(isHovered ? 1.02 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered).onHover { isHovered = $0 }
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = item } }
        .task(id: viewModel.cacheSizeString) { let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL); isDownloaded = FileManager.default.fileExists(atPath: localURL.path) }
    }
}

struct EditWallpaperPopupView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    let categories = ["全部", "魅力 | 迷人", "自制 | 艺术", "安逸 | 自由", "科幻 | 星云", "动漫 | 二次元", "自然 | 风景", "游戏 | 玩具"]; let resolutions = ["全部", "1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K"]; let colors = ["全部", "偏蓝", "偏绿", "偏红", "灰/白", "紫/粉", "暗色", "偏黄", "其他颜色"]
    
    var body: some View {
        VStack(spacing: 24) {
            Text("修改壁纸属性").font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
            VStack(spacing: 16) {
                HStack { Text("当前分类：").frame(width: 70, alignment: .trailing); Picker("", selection: $viewModel.editCategory) { ForEach(categories, id: \.self) { Text($0).tag($0) } }.frame(width: 160).labelsHidden() }
                HStack { Text("分辨率：").frame(width: 70, alignment: .trailing); Picker("", selection: $viewModel.editResolution) { ForEach(resolutions, id: \.self) { Text($0).tag($0) } }.frame(width: 160).labelsHidden() }
                HStack { Text("当前色系：").frame(width: 70, alignment: .trailing); Picker("", selection: $viewModel.editColor) { ForEach(colors, id: \.self) { Text($0).tag($0) } }.frame(width: 160).labelsHidden() }
            }.font(.system(size: 14))
            HStack(spacing: 20) {
                Button(action: { withAnimation { viewModel.cancelEdit() } }) { Text("取消").fontWeight(.medium).padding(.horizontal, 24).padding(.vertical, 8).background(Color.primary.opacity(0.1)).cornerRadius(8) }.buttonStyle(.plain)
                Button(action: { viewModel.saveWallpaperEdit() }) { Text("保存修改").fontWeight(.bold).padding(.horizontal, 24).padding(.vertical, 8).background(Color.accentColor).foregroundColor(.white).cornerRadius(8) }.buttonStyle(.plain)
            }
        }.padding(30).background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.2), radius: 20, y: 10))
    }
}

struct CustomThemeToggleView: View {
    @Binding var isDarkMode: Bool
    var body: some View { ZStack { Capsule().fill(isDarkMode ? Color(white: 0.25) : Color(white: 0.8)).frame(width: 54, height: 28).overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 1)); HStack { if isDarkMode { Spacer(minLength: 0) }; ZStack { Circle().fill(Color(white: 0.75)).shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1); if isDarkMode { ZStack { Circle().stroke(Color.black, lineWidth: 1.5).frame(width: 14, height: 14); Image(systemName: "moon.fill").resizable().scaledToFit().frame(width: 8, height: 8).foregroundColor(.black).offset(x: -0.5, y: -0.5) }.transition(.scale.combined(with: .opacity)) } else { ZStack { Group { Rectangle().fill(Color.black).frame(width: 16, height: 16); Rectangle().fill(Color.black).frame(width: 16, height: 16).rotationEffect(.degrees(45)) }; Group { Rectangle().fill(Color(red: 0.98, green: 0.86, blue: 0.45)).frame(width: 13, height: 13); Rectangle().fill(Color(red: 0.98, green: 0.86, blue: 0.45)).frame(width: 13, height: 13).rotationEffect(.degrees(45)) }; Circle().stroke(Color.black, lineWidth: 1).frame(width: 7, height: 7).background(Circle().fill(Color(red: 0.98, green: 0.86, blue: 0.45))) }.transition(.scale.combined(with: .opacity)) } }.frame(width: 24, height: 24).padding(2); if !isDarkMode { Spacer(minLength: 0) } } }.frame(width: 54, height: 28).onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isDarkMode.toggle() } } }
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
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
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

    var body: some View {
        VStack(spacing: 0) {
            // 预览图/视频区域
            ZStack {
                Color.black
                if item.isVideo {
                    HoverVideoPlayerView(item: item)
                } else {
                    AsyncThumbnailView(item: item)
                }

                // 下载进度遮罩
                if let progress = viewModel.downloadProgress[item.id] {
                    ZStack {
                        Color.black.opacity(0.6)
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().stroke(Color.white.opacity(0.2), lineWidth: 4).frame(width: 52, height: 52)
                                Circle().trim(from: 0, to: CGFloat(progress))
                                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 52, height: 52).rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.1), value: progress)
                            }
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundColor(.white)
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
                                .padding(8).background(Color.black.opacity(0.55)).clipShape(Circle())
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
                }

                HStack(spacing: 10) {
                    if viewModel.currentTab == .pc {
                        Button(action: {
                            viewModel.downloadWallpaper(item: item)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isDownloaded ? "checkmark.circle.fill" : "square.and.arrow.down")
                                Text(isDownloaded ? "已下载" : "下载壁纸")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDownloaded ? .secondary : .primary)
                            .padding(.vertical, 9).padding(.horizontal, 18)
                            .background(Color.primary.opacity(0.08)).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(isDownloaded || isDownloading)
                    }

                    Button(action: {
                        viewModel.setWallpaper(item: item)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: item.isVideo ? "play.circle.fill" : "photo.fill")
                            Text(item.isVideo ? "设为动态壁纸" : "设为壁纸")
                        }
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .padding(.vertical, 9).padding(.horizontal, 18)
                        .background(Color.accentColor).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(isDownloading)

                    if viewModel.currentTab != .pc {
                        Button(action: { viewModel.toggleInPlaylist(item: item) }) {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.playlistIds.contains(item.id) ? "star.fill" : "star")
                                Text(viewModel.playlistIds.contains(item.id) ? "已加轮播" : "加入轮播")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(viewModel.playlistIds.contains(item.id) ? Color(hex: "#C6AC2C") : .primary)
                            .padding(.vertical, 9).padding(.horizontal, 18)
                            .background(viewModel.playlistIds.contains(item.id) ? Color(hex: "#C6AC2C").opacity(0.15) : Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
        .frame(width: 560)
    }
}
