///
//  AppSections.swift
//  SimpleWallpaper
//

//
//  AppSections.swift
//  SimpleWallpaper
//

import SwiftUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

struct TopNavigationBarView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Binding var isDarkMode: Bool
    @State private var showClearCacheAlert = false
    var body: some View { HStack { HStack(spacing: 8) { Image(systemName: "camera.aperture").font(.system(size: 22)); Text("胖楼壁纸").font(.system(size: 18, weight: .bold)) }.padding(.horizontal, 16).padding(.vertical, 8).background(capsuleBgColor).clipShape(Capsule()).foregroundColor(.primary); Spacer(); HStack(spacing: 4) { NavPillButtonView(title: AppTab.pc.rawValue, icon: "desktopcomputer", isSelected: viewModel.currentTab == .pc) { viewModel.currentTab = .pc }; NavPillButtonView(title: AppTab.downloaded.rawValue, icon: "square.and.arrow.down", isSelected: viewModel.currentTab == .downloaded) { viewModel.currentTab = .downloaded }; NavPillButtonView(title: AppTab.slideshow.rawValue, icon: "photo.on.rectangle.angled", isSelected: viewModel.currentTab == .slideshow) { viewModel.currentTab = .slideshow }; NavPillButtonView(title: AppTab.collection.rawValue, icon: "rectangle.stack", isSelected: viewModel.currentTab == .collection) { viewModel.currentTab = .collection }; NavPillButtonView(title: AppTab.upload.rawValue, icon: "icloud.and.arrow.up", isSelected: viewModel.currentTab == .upload) { viewModel.currentTab = .upload } }.padding(4).background(capsuleBgColor).clipShape(Capsule()); Spacer(); HStack(spacing: 15) { CustomThemeToggleView(isDarkMode: $isDarkMode); Image(systemName: "bell").font(.system(size: 16)).foregroundColor(.primary); Button(action: { viewModel.randomWallpaper() }) { Image(systemName: "shuffle").font(.system(size: 16)).foregroundColor(.primary).frame(width: 24, height: 24) }.buttonStyle(.plain).help("随机换一张壁纸"); Menu { Button(action: { viewModel.showAbout = true }) { Text("关于胖楼壁纸"); Image(systemName: "info.circle") }; Toggle("开机自动启动", isOn: Binding(get: { viewModel.isAutoStartEnabled }, set: { viewModel.toggleAutoStart(enable: $0) })); Button(action: { viewModel.importLocalWallpaper() }) { Text("导入本地壁纸"); Image(systemName: "folder.badge.plus") }; Divider(); Button(role: .destructive, action: { showClearCacheAlert = true }) { Text("清除全部缓存 (\(viewModel.cacheSizeString))"); Image(systemName: "trash") } } label: { Image(systemName: "gearshape.fill").font(.system(size: 16)).foregroundColor(.primary).frame(width: 24, height: 24) }.menuStyle(.borderlessButton).alert("确定要清除缓存吗？", isPresented: $showClearCacheAlert) { Button("取消", role: .cancel) { }; Button("确认清除", role: .destructive) { viewModel.clearCache() } } message: { Text("这将释放 \(viewModel.cacheSizeString) 磁盘空间。正在使用的壁纸和您的轮播列表不会被删除。") }; UserAccountButtonView(viewModel: viewModel) } } }
}

// MARK: - 登录按钮（导航栏右侧）

struct UserAccountButtonView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        if viewModel.isLoggedIn {
            Button(action: { viewModel.showUserSpace = true }) {
                let url = viewModel.currentProfile?.avatarURL ?? ""
                if !url.isEmpty, let imageURL = URL(string: url) {
                    AsyncImage(url: imageURL) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 22)).foregroundColor(.brandPurple)
                        }
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22)).foregroundColor(.brandPurple)
                }
            }.buttonStyle(.plain).help("用户空间")
        } else {
            Button(action: { viewModel.showLoginSheet = true }) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 28, height: 28)
            }.buttonStyle(.plain).help("登录 / 注册")
        }
    }
}

// MARK: - 上传 tab 未登录提示

struct LoginRequiredView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.circle")
                .font(.system(size: 60))
                .foregroundColor(.primary.opacity(0.2))
            Text("上传功能需要登录")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary.opacity(0.6))
            Text("登录后即可上传壁纸，合集也会自动云端同步")
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.4))
            Button(action: { viewModel.showLoginSheet = true }) {
                Text("立即登录 / 注册")
                    .fontWeight(.bold).foregroundColor(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Color.brandPurple).clipShape(Capsule())
            }.buttonStyle(.plain)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Upload Section

struct UploadManagerView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    private let uploadCategories = ["魅力", "自制", "安逸", "科幻", "动漫", "自然", "游戏"]
    private let uploadResolutions = ["1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K"]
    private let uploadColors = ["偏蓝", "偏绿", "偏红", "灰/白", "紫/粉", "暗色", "偏黄", "其他颜色"]

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶部工具栏 ──────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                if !viewModel.pendingUploads.isEmpty {
                    HStack(spacing: 7) {
                        Text("\(viewModel.pendingUploads.count)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.brandPurple.opacity(0.85))
                            .clipShape(Capsule())
                        Text("个文件待上传")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if viewModel.isUploading {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            Text("上传中…").font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        Button(action: { viewModel.cancelAllUploads() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill").font(.system(size: 10))
                                Text("停止")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.red.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(action: { viewModel.selectFilesForUpload() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                Text("添加文件")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary.opacity(0.75))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
                        }.buttonStyle(.plain)

                        if !viewModel.pendingUploads.isEmpty {
                            Button(action: { viewModel.clearPendingUploads() }) {
                                Text("清空")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)

                            Button(action: { viewModel.executeUpload() }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold))
                                    Text("全部上传 (\(viewModel.pendingUploads.count))")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(LinearGradient.brand)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: Color.brandPurple.opacity(0.35), radius: 5, y: 2)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 4).padding(.bottom, 16)

            if viewModel.pendingUploads.isEmpty {
                UploadDropZoneView { viewModel.selectFilesForUpload() }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($viewModel.pendingUploads) { $item in
                            UploadCardView(
                                item: $item,
                                progress: viewModel.uploadProgress[item.id],
                                categories: uploadCategories,
                                resolutions: uploadResolutions,
                                colors: uploadColors,
                                onDelete: { viewModel.removePendingUpload(id: item.id) }
                            )
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Upload Drop Zone (空状态)

struct UploadDropZoneView: View {
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(isHovered
                              ? Color.brandPurple.opacity(0.12)
                              : Color.primary.opacity(0.05))
                        .frame(width: 88, height: 88)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 30, weight: .thin))
                        .foregroundStyle(
                            isHovered
                                ? AnyShapeStyle(LinearGradient.brand)
                                : AnyShapeStyle(Color.secondary.opacity(0.4))
                        )
                }

                VStack(spacing: 7) {
                    Text("点击选择文件")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isHovered ? .primary.opacity(0.75) : .primary.opacity(0.4))
                    Text("支持图片与视频壁纸")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.4))
                }

                HStack(spacing: 7) {
                    ForEach(["JPG", "PNG", "MP4", "MOV"], id: \.self) { fmt in
                        Text(fmt)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.45))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isHovered
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.brandPurple.opacity(0.45), Color.brandPink.opacity(0.3)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.primary.opacity(0.1)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [9, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Upload Card (Linear-style 卡片)

struct UploadCardView: View {
    @Binding var item: PendingUploadItem
    let progress: Double?
    let categories: [String]
    let resolutions: [String]
    let colors: [String]
    let onDelete: () -> Void
    @State private var isHovered = false

    private var isVideo: Bool {
        ["mp4", "mov"].contains(item.url.pathExtension.lowercased())
    }
    private var isUploading: Bool { (progress ?? 0) > 0 && (progress ?? 0) < 1 }
    private var isDone: Bool { (progress ?? 0) >= 0.99 }

    var body: some View {
        HStack(spacing: 14) {
            // ── 缩略图 ──────────────────────────────────
            ZStack(alignment: .bottomLeading) {
                UploadThumbnailView(url: item.url)
                    .frame(width: 136, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill").font(.system(size: 7, weight: .bold))
                        Text("视频").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
                }

                if isUploading, let p = progress {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.42))
                        .frame(width: 136, height: 86)
                    UploadCircleProgress(progress: p)
                        .frame(width: 34, height: 34)
                        .frame(width: 136, height: 86)
                }
                if isDone {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.28))
                        .frame(width: 136, height: 86)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green.opacity(0.9))
                        .frame(width: 136, height: 86)
                }
            }

            // ── 右侧元数据 ───────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                // 行1：文件名 + 状态 badge + 删除按钮
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                        .lineLimit(1)
                    Spacer()
                    if isDone {
                        uploadStatusBadge("完成", icon: "checkmark", color: .green)
                    } else if isUploading {
                        uploadStatusBadge("上传中", icon: "arrow.up", color: .brandPurple)
                    }
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(isHovered ? 0.55 : 0.25))
                            .frame(width: 20, height: 20)
                            .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                            .clipShape(Circle())
                    }.buttonStyle(.plain)
                }

                // 行2：三列字段（标题 | 描述 | 标签）
                HStack(spacing: 0) {
                    uploadFieldColumn(label: "标题", placeholder: "留空则使用文件名", text: $item.title)
                    uploadFieldDivider()
                    uploadFieldColumn(label: "描述", placeholder: "霓虹灯光、雨后街道…", text: $item.wallpaperDescription)
                    uploadFieldDivider()
                    uploadFieldColumn(label: "标签", placeholder: "动漫, 夜晚, 城市", text: $item.tags)
                }
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(Color.primary.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))

                // 行3：分类选择器 + 进度
                HStack(spacing: 6) {
                    UploadPickerMenu(label: item.category.isEmpty ? "分类" : item.category,
                                     options: categories, selection: $item.category)
                    UploadPickerMenu(label: item.resolution.isEmpty ? "分辨率" : item.resolution,
                                     options: resolutions, selection: $item.resolution)
                    UploadPickerMenu(label: item.color.isEmpty ? "色系" : item.color,
                                     options: colors, selection: $item.color)
                    Spacer()
                    if let p = progress, !isDone {
                        HStack(spacing: 5) {
                            ProgressView(value: p)
                                .tint(.brandPurple)
                                .controlSize(.small)
                                .frame(width: 80)
                            Text("\(Int(p * 100))%")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundColor(.brandPurple)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isHovered ? Color.primary.opacity(0.13) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private func uploadStatusBadge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func uploadFieldColumn(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
                .kerning(0.3)
            TextField(placeholder, text: text)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func uploadFieldDivider() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 30)
            .padding(.horizontal, 10)
    }
}

// MARK: - Compact Picker Menu

struct UploadPickerMenu: View {
    let label: String
    let options: [String]
    @Binding var selection: String
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button("未选择") { selection = "" }
            Divider()
            ForEach(options, id: \.self) { opt in
                Button(opt) { selection = opt }
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: selection.isEmpty ? .regular : .semibold))
                .foregroundColor(selection.isEmpty ? .secondary : .primary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selection.isEmpty
                              ? Color.primary.opacity(isHovered ? 0.08 : 0.05)
                              : Color.brandPurple.opacity(isHovered ? 0.2 : 0.12))
                )
        }
        .menuStyle(.borderlessButton)
        
        .fixedSize()
        .onHover { isHovered = $0 }
    }
}

// MARK: - Upload Thumbnail

struct UploadThumbnailView: View {
    let url: URL
    @State private var thumbnail: NSImage?

    private var isVideoFile: Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        ZStack {
            Color.primary.opacity(0.07)
            if let img = thumbnail {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: isVideoFile ? "play.circle" : "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.secondary.opacity(0.35))
            }
        }
        .task {
            if isVideoFile {
                thumbnail = await Task.detached(priority: .utility) {
                    let asset = AVURLAsset(url: url)
                    let gen = AVAssetImageGenerator(asset: asset)
                    gen.appliesPreferredTrackTransform = true
                    gen.maximumSize = CGSize(width: 340, height: 220)
                    guard let (cg, _) = try? await gen.image(at: .zero) else { return nil }
                    return NSImage(cgImage: cg, size: .zero)
                }.value
            } else {
                thumbnail = await Task.detached(priority: .utility) {
                    NSImage(contentsOf: url)
                }.value
            }
        }
    }
}

// MARK: - Circular Progress

struct UploadCircleProgress: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(
                        colors: [Color.brandPurple, Color.brandPink, Color.brandPurple],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
        }
    }
}

// MARK: - 审核队列（开发者专用）

struct ReviewQueueView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 顶部操作栏
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("待审核壁纸")
                        .font(.displayTitle)
                    Text("审核通过后将显示在「电脑壁纸」界面")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { viewModel.fetchPendingReviews() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("刷新")
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.07))
                    .cornerRadius(9)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 18)

            if viewModel.isLoadingReview {
                Spacer()
                ProgressView("加载审核队列…").foregroundColor(.secondary)
                Spacer()
            } else if viewModel.pendingReviewItems.isEmpty {
                VStack(spacing: 18) {
                    Spacer()
                    ZStack {
                        Circle().fill(Color.green.opacity(0.1)).frame(width: 110, height: 110)
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 42, weight: .thin))
                            .foregroundColor(.green.opacity(0.7))
                    }
                    VStack(spacing: 8) {
                        Text("暂无待审核内容")
                            .font(.sectionTitle)
                            .foregroundColor(.primary.opacity(0.7))
                        Text("所有用户上传的壁纸均已处理完毕")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(viewModel.pendingReviewItems) { item in
                            ReviewItemRowView(item: item, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { viewModel.fetchPendingReviews() }
    }
}

struct ReviewItemRowView: View {
    let item: WallpaperItem
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var showRejectInput = false
    @State private var rejectReason = ""
    @State private var isHovered = false
    @State private var isApproveHovered = false
    @State private var isRejectHovered = false

    private func formattedDate(_ ts: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                // 缩略图
                AsyncThumbnailView(item: item)
                    .frame(width: 120, height: 75)
                    .cornerRadius(10)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                // 信息区
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        if item.isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.brandPurple)
                        }
                    }
                    HStack(spacing: 10) {
                        if !item.category.isEmpty {
                            Label(item.category, systemImage: "tag")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        if !item.resolution.isEmpty {
                            Label(item.resolution, systemImage: "tv")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Text(String(item.uploadedBy?.prefix(8) ?? "匿名") + "…")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Text("·").foregroundColor(.secondary.opacity(0.4))
                        Text(formattedDate(item.uploadedAt))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 8) {
                    // 拒绝
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showRejectInput.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: showRejectInput ? "xmark" : "hand.raised")
                                .font(.system(size: 11, weight: .semibold))
                            Text(showRejectInput ? "取消" : "拒绝")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(showRejectInput ? .secondary : .red.opacity(isRejectHovered ? 1.0 : 0.85))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            showRejectInput
                                ? Color.primary.opacity(0.06)
                                : Color.red.opacity(isRejectHovered ? 0.14 : 0.08)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    showRejectInput
                                        ? Color.primary.opacity(0.1)
                                        : Color.red.opacity(isRejectHovered ? 0.4 : 0.2),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isRejectHovered = $0 }
                    .animation(.easeInOut(duration: 0.12), value: isRejectHovered)

                    // 通过
                    Button(action: { viewModel.approveWallpaper(item: item) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("通过")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            isApproveHovered
                                ? Color(hex: "#3d8f38")
                                : Color(hex: "#449B3E")
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(
                            color: Color(hex: "#449B3E").opacity(isApproveHovered ? 0.5 : 0.25),
                            radius: isApproveHovered ? 8 : 4,
                            y: isApproveHovered ? 4 : 2
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isApproveHovered = $0 }
                    .animation(.easeInOut(duration: 0.12), value: isApproveHovered)
                }
            }
            .padding(14)

            // 拒绝原因输入
            if showRejectInput {
                HStack(spacing: 10) {
                    TextField("填写拒绝原因（可留空）", text: $rejectReason)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                        .onSubmit { submitReject() }

                    Button(action: submitReject) {
                        Text("确认拒绝")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(isHovered ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func submitReject() {
        viewModel.rejectWallpaper(item: item, reason: rejectReason)
        showRejectInput = false
        rejectReason = ""
    }
}

// MARK: - 普通用户上传记录

struct UserUploadsView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("我的上传记录")
                        .font(.displayTitle)
                    Text("共 \(viewModel.userUploads.count) 个，审核通过后将显示在电脑壁纸界面")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    guard let uid = viewModel.currentUser?.id else { return }
                    viewModel.isLoadingUserUploads = true
                    Task {
                        if let items = try? await MeilisearchService.shared.getUserUploads(userId: uid) {
                            await MainActor.run {
                                viewModel.userUploads = items.sorted { $0.uploadedAt > $1.uploadedAt }
                                viewModel.isLoadingUserUploads = false
                            }
                        } else {
                            await MainActor.run { viewModel.isLoadingUserUploads = false }
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                        Text("刷新").font(.system(size: 13))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.07)).cornerRadius(9)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 30).padding(.bottom, 18)

            if viewModel.isLoadingUserUploads {
                Spacer()
                ProgressView("加载中…").foregroundColor(.secondary)
                Spacer()
            } else if viewModel.userUploads.isEmpty {
                VStack(spacing: 18) {
                    Spacer()
                    ZStack {
                        Circle().fill(Color.brandPurple.opacity(0.08)).frame(width: 110, height: 110)
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 42, weight: .thin))
                            .foregroundColor(Color.brandPurple.opacity(0.7))
                    }
                    VStack(spacing: 8) {
                        Text("还没有上传记录").font(.sectionTitle).foregroundColor(.primary.opacity(0.7))
                        Text("切换到「待上传新壁纸」选择文件并上传").font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.userUploads) { item in
                            UserUploadRowView(item: item)
                        }
                    }
                    .padding(.horizontal, 30).padding(.bottom, 40)
                }
            }
        }
    }
}

struct UserUploadRowView: View {
    let item: WallpaperItem
    @State private var isHovered = false

    private var statusConfig: (icon: String, label: String, color: Color) {
        switch item.approvalStatus {
        case .pending, .none:
            return ("clock", "待审核", .orange)
        case .approved:
            return ("checkmark.circle.fill", "已通过", Color(hex: "#449B3E"))
        case .rejected:
            return ("xmark.circle.fill", "已拒绝", .red)
        }
    }

    private func formattedDate(_ ts: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 14) {
            // 缩略图
            ZStack(alignment: .bottomLeading) {
                AsyncThumbnailView(item: item)
                    .frame(width: 124, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if item.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill").font(.system(size: 7, weight: .bold))
                        Text("视频").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
                }
            }

            // 中部信息
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if !item.category.isEmpty {
                        metaTag(item.category)
                    }
                    if !item.resolution.isEmpty {
                        metaTag(item.resolution)
                    }
                    if !item.color.isEmpty {
                        metaTag(item.color)
                    }
                }

                Text(formattedDate(item.uploadedAt))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))

                // 拒绝原因
                if item.approvalStatus == .rejected,
                   let reason = item.rejectionReason, !reason.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.7))
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 审核状态 badge
            let cfg = statusConfig
            Label(cfg.label, systemImage: cfg.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(cfg.color)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(cfg.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(cfg.color.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isHovered ? Color.primary.opacity(0.13) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private func metaTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary.opacity(0.8))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

// 🌟🌟🌟 核心手术：无敌自适应切分布局引擎 🌟🌟🌟
struct WallpaperGridView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @AppStorage("isSidebarVisible") private var isSidebarVisible: Bool = true
    @Namespace private var uploadTabNamespace
    var emptyText: String {
        switch viewModel.currentTab {
        case .pc:
            return viewModel.searchText.isEmpty
                ? "未找到相关壁纸"
                : "未找到包含「\(viewModel.searchText)」的壁纸"
        case .downloaded:
            switch viewModel.downloadedSubTab {
            case .localImports: return "还没有本地导入的壁纸"
            case .workshop:     return "还没有 Workshop 下载的壁纸"
            case .local:        return "暂无下载缓存"
            }
        case .slideshow:  return "暂无轮播壁纸，请去已下载中点亮右上角星星添加"
        case .upload:         return viewModel.uploadMode == .manage ? "暂无壁纸" : ""
        case .collection:     return "该合集还没有壁纸，去其他标签页点击壁纸右下角书签按钮添加"
        case .steamWorkshop:  return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.currentTab == .steamWorkshop {
                SteamWorkshopView(viewModel: viewModel, isSidebarVisible: $isSidebarVisible)
            } else if viewModel.currentTab == .upload {
                // ── 胶囊 Tab 选择器（与已下载页风格统一）──
                HStack {
                    HStack(spacing: 2) {
                        uploadPillButton(.pending, label: "待上传新壁纸")
                        if viewModel.isDeveloper {
                            uploadPillButton(.review, label: "审核队列",
                                            badge: viewModel.pendingReviewItems.count)
                            uploadPillButton(.manage, label: "管理全部壁纸")
                        } else {
                            uploadPillButton(.manage, label: "我的上传记录")
                        }
                    }
                    .padding(3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    // Pill 高亮单独走 spring，与内容区动画解耦
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.uploadMode)
                    Spacer()
                }
                .padding(.horizontal, 30).padding(.bottom, 15)

                // ZStack 固定容器尺寸，避免两侧视图高度差导致布局在动画途中抖动。
                // .transition(.opacity) 让旧视图淡出、新视图淡入，消除瞬切顿挫感。
                ZStack(alignment: .topLeading) {
                    if !viewModel.isLoggedIn {
                        LoginRequiredView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    } else if viewModel.uploadMode == .pending {
                        UploadManagerView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    } else if viewModel.uploadMode == .review {
                        ReviewQueueView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    } else if viewModel.isDeveloper {
                        gridContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    } else {
                        UserUploadsView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: viewModel.uploadMode)
                .animation(.easeInOut(duration: 0.18), value: viewModel.isLoggedIn)
            } else if viewModel.currentTab == .collection {
                if viewModel.selectedCollectionId != nil {
                    // 合集详情：顶部返回按钮 + 壁纸网格
                    HStack {
                        Button(action: { viewModel.selectedCollectionId = nil }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("所有合集")
                            }.font(.system(size: 13, weight: .medium)).foregroundColor(.brandPurple)
                        }.buttonStyle(.plain)
                        Spacer()
                        if let collectionId = viewModel.selectedCollectionId,
                           let collection = viewModel.collections.first(where: { $0.id == collectionId }) {
                            Text(collection.name).font(.sectionTitle)
                            Text("(\(collection.wallpaperIds.count)张)").font(.system(size: 13)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }.padding(.horizontal, 30).padding(.bottom, 15)
                    gridContent
                } else {
                    CollectionsGridView(viewModel: viewModel)
                }
            } else {
                // 已下载 tab：有选中详情时整页替换为详情视图
                if viewModel.currentTab == .downloaded, let detailItem = viewModel.detailItem {
                    DownloadedDetailView(item: detailItem, viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                if viewModel.currentTab == .downloaded {
                    DownloadedHeaderView(viewModel: viewModel)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 16)
                }
                if viewModel.currentTab == .slideshow {
                    VStack(spacing: 10) {
                        HStack(spacing: 16) {
                            Toggle(isOn: $viewModel.isSlideshowEnabled) {
                                Text("自动轮播").font(.buttonLabel)
                            }.toggleStyle(.switch)

                            HStack(spacing: 6) {
                                Text("切换频率").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                                Picker("", selection: $viewModel.slideshowInterval) {
                                    Text("1 分钟").tag(60.0)
                                    Text("15 分钟").tag(900.0)
                                    Text("1 小时").tag(3600.0)
                                    Text("24 小时").tag(86400.0)
                                }.labelsHidden().frame(width: 100)
                            }

                            Toggle(isOn: $viewModel.isSlideshowRandom) {
                                Text("随机").font(.system(size: 13, weight: .medium))
                            }.toggleStyle(.switch)

                            if viewModel.isSlideshowEnabled && !viewModel.nextSlideshowCountdown.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(viewModel.nextSlideshowCountdown)
                                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(Capsule())
                            }

                            Spacer()

                            Button(action: {
                                viewModel.playlistIds.removeAll()
                                viewModel.statusMessage = "轮播列表已清空"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { viewModel.statusMessage = "" }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "trash")
                                    Text("清空列表 (\(viewModel.playlistIds.count)张)")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.red.opacity(0.08))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.playlistIds.isEmpty)
                        }

                        Divider().padding(.vertical, 2)

                        // ── 定时换壁纸 ──
                        HStack(spacing: 16) {
                            Toggle(isOn: $viewModel.isTimedPeriodEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("定时换壁纸").font(.sectionTitle)
                                    Text("按早晨/下午/夜晚自动切换，启用后自动轮播将停止")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                }
                            }.toggleStyle(.switch)
                            Spacer()
                        }
                        // 三个时段并排一行，高度与普通控件行相当
                        if viewModel.isTimedPeriodEnabled {
                            HStack(spacing: 10) {
                                ForEach(DayPeriod.allCases) { period in
                                    PeriodCompactCardView(period: period, viewModel: viewModel)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 30).padding(.bottom, 15)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.isTimedPeriodEnabled)
                }
                gridContent
                } // end else (no detailItem)
            }
        }
    }

    @ViewBuilder
    private func uploadPillButton(_ mode: UploadMode, label: String, badge: Int = 0) -> some View {
        let isActive = viewModel.uploadMode == mode
        Button(action: {
            viewModel.uploadMode = mode
        }) {
            ZStack(alignment: .topTrailing) {
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .primary.opacity(0.5))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background {
                        if isActive {
                            Capsule()
                                .fill(Color.brandPurple)
                                .matchedGeometryEffect(id: "uploadActivePill", in: uploadTabNamespace)
                        }
                    }
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // 彻底抛弃 LazyVGrid，使用绝对均匀的 HStack + VStack
    private var gridContent: some View {
        Group {
            // 首次加载：有请求进行中且结果为空时，展示骨架占位格代替空态
            if viewModel.currentTab == .pc && viewModel.isSearching && viewModel.searchResults.isEmpty {
                VStack(spacing: 15) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 15) {
                            ForEach(0..<4, id: \.self) { _ in
                                SkeletonCardView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
            } else if viewModel.displayWallpapers.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "tray").font(.system(size: 48)).foregroundColor(.primary.opacity(0.3))
                    Text(emptyText).font(.system(size: 16, weight: .medium)).foregroundColor(.primary.opacity(0.5))
                    if viewModel.currentTab == .pc && !viewModel.isSearching {
                        HStack(spacing: 10) {
                            if !viewModel.searchText.isEmpty {
                                Button(action: { viewModel.searchText = "" }) {
                                    Label("清除搜索", systemImage: "xmark.circle")
                                        .font(.system(size: 13, weight: .medium))
                                        .padding(.horizontal, 16).padding(.vertical, 7)
                                        .background(Color.primary.opacity(0.08)).clipShape(Capsule())
                                }.buttonStyle(.plain)
                            }
                            Button(action: { viewModel.performSearch() }) {
                                Label("重新加载", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(Color.primary.opacity(0.08)).clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    if viewModel.currentTab == .downloaded && viewModel.downloadedSubTab == .local {
                        Button(action: { viewModel.currentTab = .pc }) {
                            Label("去电脑壁纸下载", systemImage: "arrow.right.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18).padding(.vertical, 8)
                                .background(Color.brandPurple)
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 这个大框框会完美占据剩余的屏幕，死死限制住图片的最大膨胀体积
                VStack(spacing: 15) {
                    let items = viewModel.paginatedImages
                    // 强制划分 3 行
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 15) {
                            // 强制划分 4 列
                            ForEach(0..<4, id: \.self) { col in
                                let index = row * 4 + col
                                if index < items.count {
                                    WallpaperCardView(item: items[index], viewModel: viewModel)
                                        .id(items[index].id)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .clipped()
                                } else {
                                    // 不足 12 张图时，用透明块填满占位，保证网格阵型绝对不乱！
                                    // 用 Rectangle().opacity(0) 代替 Color.clear，避免 macOS 上 Color.clear 可能拦截点击事件的问题
                                    Rectangle()
                                        .opacity(0)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
            }
        }
    }
}

// MARK: - 已下载 Header

struct DownloadedHeaderView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Namespace private var tabNamespace

    private var subTabSize: String {
        switch viewModel.downloadedSubTab {
        case .local:        return viewModel.cloudCacheSizeString
        case .workshop:     return viewModel.workshopCacheSizeString
        case .localImports: return viewModel.localImportSizeString
        }
    }

    var body: some View {
        Group {
            if viewModel.isBatchSelectMode {
                batchHeader
            } else {
                normalHeader
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.isBatchSelectMode)
    }

    // MARK: Normal

    private var normalHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 第一行：大标题 + 数量徽章 + 批量按钮
            HStack(spacing: 10) {
                Text("已下载")
                    .font(.displayTitle)
                    .foregroundColor(.primary)

                let count = viewModel.displayWallpapers.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.brandPurple)
                        .clipShape(Capsule())
                }

                Spacer()

                if viewModel.downloadedSubTab == .local && !viewModel.displayWallpapers.isEmpty {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            viewModel.isBatchSelectMode = true
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle").font(.system(size: 12))
                            Text("批量选择").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.primary.opacity(0.65))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }

            // 第二行：胶囊 Tab + 缓存大小
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    pillButton(for: .local,        label: "云端下载")
                    pillButton(for: .workshop,     label: "Workshop")
                    pillButton(for: .localImports, label: "本地导入")
                }
                .padding(3)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())

                Spacer()

                if !subTabSize.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(subTabSize)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        // 与 batchHeader 高度对齐，避免切换时布局跳动
        .frame(minHeight: 70)
    }

    @ViewBuilder
    private func pillButton(for tab: DownloadedSubTab, label: String) -> some View {
        let isActive = viewModel.downloadedSubTab == tab
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.downloadedSubTab = tab
            }
        }) {
            Text(label)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .primary.opacity(0.5))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background {
                    if isActive {
                        Capsule()
                            .fill(Color.brandPurple)
                            .matchedGeometryEffect(id: "activePill", in: tabNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Batch mode

    private var batchHeader: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    viewModel.isBatchSelectMode = false
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    Text("退出").font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }.buttonStyle(.plain)

            Text(viewModel.batchSelectedIds.isEmpty ? "点击卡片选择" : "已选 \(viewModel.batchSelectedIds.count) 张")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: viewModel.batchSelectedIds.count)

            Spacer()

            Button(action: { viewModel.selectAllDownloaded() }) {
                Text("全选")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.brandPurple)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.brandPurple.opacity(0.1))
                    .clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        // 与 normalHeader 双行高度对齐，避免切换时布局跳动
        .frame(minHeight: 70)
    }
}

// MARK: - 批量操作底部栏

struct BatchActionBarView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        HStack(spacing: 14) {
            Text(viewModel.batchSelectedIds.isEmpty ? "未选中任何壁纸" : "已选 \(viewModel.batchSelectedIds.count) 张")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { viewModel.deleteBatchSelectedCache() }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("删除缓存")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(viewModel.batchSelectedIds.isEmpty ? Color.gray.opacity(0.4) : Color.red.opacity(0.85))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.batchSelectedIds.isEmpty)
        }
    }
}

// MARK: - 定时换壁纸：单行时间段设置

// MARK: - 定时换壁纸：紧凑横排卡片（3个时段并排一行）

struct PeriodCompactCardView: View {
    let period: DayPeriod
    @ObservedObject var viewModel: WallpaperViewModel

    private var assignedItem: WallpaperItem? {
        guard let id = viewModel.periodWallpaperIds[period.rawValue] else { return nil }
        return viewModel.allWallpapers.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: periodIcon)
                .font(.system(size: 13))
                .foregroundColor(periodColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(period.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                Text(assignedItem.map { $0.title.isEmpty ? "（无标题）" : $0.title } ?? "未指定")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { viewModel.periodPickerTargetPeriod = period }) {
                Text(assignedItem == nil ? "选择" : "更换")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.brandPurple)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.brandPurple.opacity(0.1))
                    .clipShape(Capsule())
            }.buttonStyle(.plain)

            if assignedItem != nil {
                Button(action: { viewModel.periodWallpaperIds.removeValue(forKey: period.rawValue) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.45))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .frame(maxWidth: .infinity)
    }

    private var periodIcon: String {
        switch period {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .night:     return "moon.stars.fill"
        }
    }

    private var periodColor: Color {
        switch period {
        case .morning:   return Color(hex: "#F59E0B")
        case .afternoon: return Color(hex: "#3B82F6")
        case .night:     return Color(hex: "#6366F1")
        }
    }
}

// MARK: - 定时换壁纸：竖排行（保留备用）

struct PeriodAssignmentRowView: View {
    let period: DayPeriod
    @ObservedObject var viewModel: WallpaperViewModel

    private var assignedItem: WallpaperItem? {
        guard let id = viewModel.periodWallpaperIds[period.rawValue] else { return nil }
        return viewModel.allWallpapers.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 时间段图标 + 名称
            HStack(spacing: 6) {
                Image(systemName: periodIcon)
                    .font(.system(size: 13))
                    .foregroundColor(periodColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(period.rawValue).font(.system(size: 13, weight: .semibold))
                    Text(period.timeRange).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            .frame(width: 100, alignment: .leading)

            // 已指定的壁纸缩略图
            if let item = assignedItem {
                AsyncThumbnailView(item: item)
                    .frame(width: 64, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(item.title.isEmpty ? "（无标题）" : item.title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 64, height: 40)
                    .overlay(Image(systemName: "photo").font(.system(size: 16)).foregroundColor(.secondary.opacity(0.4)))
                Text("未指定").font(.system(size: 12)).foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { viewModel.periodPickerTargetPeriod = period }) {
                Text(assignedItem == nil ? "选择壁纸" : "更换")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.brandPurple)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.brandPurple.opacity(0.1))
                    .clipShape(Capsule())
            }.buttonStyle(.plain)

            if assignedItem != nil {
                Button(action: { viewModel.periodWallpaperIds.removeValue(forKey: period.rawValue) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var periodIcon: String {
        switch period {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .night:     return "moon.stars.fill"
        }
    }

    private var periodColor: Color {
        switch period {
        case .morning:   return Color(hex: "#F59E0B")
        case .afternoon: return Color(hex: "#3B82F6")
        case .night:     return Color(hex: "#6366F1")
        }
    }
}

// MARK: - 定时换壁纸：选择壁纸 Sheet

struct PeriodWallpaperPickerView: View {
    let period: DayPeriod
    @ObservedObject var viewModel: WallpaperViewModel
    @Environment(\.dismiss) private var dismiss

    private var downloadedItems: [WallpaperItem] {
        viewModel.allWallpapers.filter {
            FileManager.default.fileExists(
                atPath: WallpaperCacheManager.shared.getLocalPath(for: $0.fullURL).path
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择壁纸 — \(period.rawValue)")
                        .font(.system(size: 16, weight: .bold))
                    Text(period.timeRange)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            if downloadedItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.4))
                    Text("还没有已下载的壁纸").font(.system(size: 14)).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180))], spacing: 10) {
                        ForEach(downloadedItems) { item in
                            Button(action: {
                                viewModel.setPeriodWallpaper(period: period, itemId: item.id)
                                dismiss()
                            }) {
                                ZStack(alignment: .bottomLeading) {
                                    AsyncThumbnailView(item: item)
                                        .aspectRatio(16/10, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    if viewModel.periodWallpaperIds[period.rawValue] == item.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .padding(5)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(viewModel.periodWallpaperIds[period.rawValue] == item.id
                                                ? Color.brandPurple : Color.clear, lineWidth: 2)
                                )
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - 骨架卡片（搜索加载中占位）

struct SkeletonCardView: View {
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(isAnimating ? 0.14 : 0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07), lineWidth: 1))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - 合集视图

struct CollectionsGridView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isCreating = false
    @State private var newName = ""

    private var totalWallpapers: Int {
        viewModel.collections.reduce(0) { $0 + $1.wallpaperIds.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("我的合集")
                        .font(.displayTitle)
                    if !viewModel.collections.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("\(viewModel.collections.count) 个合集")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("·").foregroundColor(.secondary.opacity(0.5))
                            Image(systemName: "photo.stack")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("共 \(totalWallpapers) 张壁纸")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                if isCreating {
                    HStack(spacing: 8) {
                        TextField("合集名称", text: $newName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.primary.opacity(0.07))
                            .cornerRadius(9)
                            .frame(width: 190)
                            .onSubmit { createIfValid() }
                        Button(action: createIfValid) {
                            Text("创建")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(newName.isEmpty ? Color.secondary.opacity(0.5) : Color.brandPurple)
                                .cornerRadius(9)
                        }.buttonStyle(.plain).disabled(newName.isEmpty)
                        Button(action: { isCreating = false; newName = "" }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color.primary.opacity(0.07))
                                .clipShape(Circle())
                        }.buttonStyle(.plain)
                    }
                } else {
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isCreating = true } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("新建合集")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Color.brandPurple)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: Color.brandPurple.opacity(0.35), radius: 10, y: 4)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 22)

            if viewModel.collections.isEmpty && !isCreating {
                // ── Empty State ──
                VStack(spacing: 22) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.brandPurple.opacity(0.09))
                            .frame(width: 130, height: 130)
                        Circle()
                            .fill(Color.brandPurple.opacity(0.05))
                            .frame(width: 100, height: 100)
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 46, weight: .thin))
                            .foregroundColor(Color.brandPurple.opacity(0.75))
                    }
                    VStack(spacing: 10) {
                        Text("还没有合集")
                            .font(.sectionTitle)
                            .foregroundColor(.primary.opacity(0.75))
                        Text("将喜欢的壁纸整理成合集，随时一键应用")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isCreating = true } }) {
                        HStack(spacing: 7) {
                            Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                            Text("创建第一个合集").font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 26).padding(.vertical, 12)
                        .background(Color.brandPurple)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: Color.brandPurple.opacity(0.4), radius: 12, y: 5)
                    }.buttonStyle(.plain)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 20
                    ) {
                        // 新建卡片（创建模式时显示在首位）
                        if isCreating {
                            CreateCollectionCardView(name: $newName, onCreate: createIfValid) {
                                isCreating = false; newName = ""
                            }
                            .aspectRatio(16/10, contentMode: .fit)
                        }
                        ForEach(viewModel.collections) { collection in
                            CollectionCardView(collection: collection, viewModel: viewModel)
                                .aspectRatio(16/10, contentMode: .fit)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func createIfValid() {
        guard !newName.isEmpty else { return }
        viewModel.createCollection(name: newName)
        newName = ""
        isCreating = false
    }
}

// MARK: - 新建合集卡片（内嵌输入）

struct CreateCollectionCardView: View {
    @Binding var name: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.brandPurple.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            Color.brandPurple.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                        )
                )
            VStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(Color.brandPurple.opacity(0.85))
                TextField("输入合集名称…", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(9)
                    .padding(.horizontal, 18)
                    .focused($focused)
                    .onSubmit { onCreate() }
                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(8)
                    }.buttonStyle(.plain)
                    Button(action: onCreate) {
                        Text("创建")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(name.isEmpty ? Color.secondary.opacity(0.35) : Color.brandPurple)
                            .cornerRadius(8)
                    }.buttonStyle(.plain).disabled(name.isEmpty)
                }
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - 合集卡片

struct CollectionCardView: View {
    let collection: WallpaperCollection
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    private var coverItems: [WallpaperItem] {
        var orderedIds: [String] = []
        if !collection.coverWallpaperId.isEmpty {
            orderedIds.append(collection.coverWallpaperId)
        }
        for id in collection.wallpaperIds {
            if !orderedIds.contains(id) { orderedIds.append(id) }
            if orderedIds.count >= 4 { break }
        }
        return orderedIds.compactMap { id in viewModel.allWallpapers.first { $0.id == id } }
    }

    private func formattedDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy.MM.dd"
        return fmt.string(from: date)
    }

    var body: some View {
        ZStack {
            // ── 封面拼贴 ──
            coverLayer

            // ── 底部渐变（仅在有封面图时显示，避免浅色模式下空合集出现黑色渐变块）──
            if !coverItems.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.45), location: 0.5),
                            .init(color: .black.opacity(0.85), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 110)
                }
            }

            // ── 底部信息 ──
            if !isRenaming {
                let hasCover = !coverItems.isEmpty
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collection.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(hasCover ? .white : .primary)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 10))
                                    .foregroundColor(hasCover ? .white.opacity(0.55) : .secondary)
                                Text("\(collection.wallpaperIds.count) 张")
                                    .font(.system(size: 11))
                                    .foregroundColor(hasCover ? .white.opacity(0.65) : .secondary)
                                if collection.createdAt > 0 {
                                    Text("·").foregroundColor(hasCover ? .white.opacity(0.3) : .secondary.opacity(0.5))
                                    Text(formattedDate(collection.createdAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(hasCover ? .white.opacity(0.45) : .secondary.opacity(0.7))
                                }
                            }
                        }
                        Spacer()
                        if collection.wallpaperIds.count > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(hasCover ? .white.opacity(0.7) : .secondary)
                                .padding(7)
                                .background(hasCover ? Color.white.opacity(0.15) : Color.primary.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }

            // ── Hover 遮罩 ──
            if isHovered && !isRenaming {
                Color.black.opacity(0.28)
                    .cornerRadius(16)

                // 进入按钮（居中）
                Button(action: { viewModel.selectedCollectionId = collection.id }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                        Text("进入合集")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 9).padding(.horizontal, 20)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                }.buttonStyle(.plain)

                // 操作按钮（左上：重命名 / 右上：删除）
                VStack {
                    HStack {
                        Button(action: {
                            renameText = collection.name
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                isRenaming = true
                            }
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        }.buttonStyle(.plain).padding(10)
                        Spacer()
                        Button(action: { viewModel.deleteCollection(id: collection.id) }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.red.opacity(0.85))
                                .clipShape(Circle())
                                .shadow(color: Color.red.opacity(0.4), radius: 6, y: 2)
                        }.buttonStyle(.plain).padding(10)
                    }
                    Spacer()
                }
            }

            // ── 重命名模式 ──
            if isRenaming {
                Color.black.opacity(0.55)
                    .cornerRadius(16)
                VStack(spacing: 14) {
                    Text("重命名合集")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    TextField("合集名称", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(9)
                        .padding(.horizontal, 20)
                        .focused($renameFocused)
                        .onSubmit { submitRename() }
                    HStack(spacing: 10) {
                        Button(action: { withAnimation { isRenaming = false } }) {
                            Text("取消")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.75))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }.buttonStyle(.plain)
                        Button(action: submitRename) {
                            Text("确认")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(renameText.isEmpty ? Color.gray.opacity(0.4) : Color.brandPurple)
                                .cornerRadius(8)
                        }.buttonStyle(.plain).disabled(renameText.isEmpty)
                    }
                }
                .onAppear { renameFocused = true }
            }
        }
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(isHovered ? 0.1 : 0.055), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(isHovered ? 0.28 : 0.1),
            radius: isHovered ? 18 : 6,
            y: isHovered ? 8 : 3
        )
        .scaleEffect(isHovered && !isRenaming ? 1.025 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isRenaming)
        .onHover { isHovered = $0 }
        .onTapGesture { if !isRenaming { viewModel.selectedCollectionId = collection.id } }
        
    }

    @ViewBuilder
    private var coverLayer: some View {
        let items = coverItems
        if items.isEmpty {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.brandPurple.opacity(0.07), Color.brandPink.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 34, weight: .thin))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.brandPurple.opacity(0.4), Color.brandPink.opacity(0.3)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                        Text("空合集")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.2))
                    }
                )
        } else if items.count == 1 {
            AsyncThumbnailView(item: items[0])
                .cornerRadius(16)
                .clipped()
        } else {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let hw = (w - 1) / 2
                let hh = (h - 1) / 2
                HStack(spacing: 1) {
                    VStack(spacing: 1) {
                        AsyncThumbnailView(item: items[0]).frame(width: hw, height: hh).clipped()
                        if items.count > 2 {
                            AsyncThumbnailView(item: items[2]).frame(width: hw, height: hh).clipped()
                        } else {
                            Color.primary.opacity(0.06).frame(width: hw, height: hh)
                        }
                    }
                    VStack(spacing: 1) {
                        AsyncThumbnailView(item: items[1]).frame(width: hw, height: hh).clipped()
                        if items.count > 3 {
                            AsyncThumbnailView(item: items[3]).frame(width: hw, height: hh).clipped()
                        } else {
                            Color.primary.opacity(0.06).frame(width: hw, height: hh)
                        }
                    }
                }
            }
            .cornerRadius(16)
            .clipped()
        }
    }

    private func submitRename() {
        guard !renameText.isEmpty else { return }
        viewModel.renameCollection(id: collection.id, newName: renameText)
        withAnimation { isRenaming = false }
    }
}

// MARK: - 本地导入壁纸网格

struct LocalImportsGridView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    var body: some View {
        if viewModel.localImports.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("还没有本地导入的壁纸")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                Text("点击右上角 ⚙️ → 导入本地壁纸")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280))], spacing: 16) {
                    ForEach(viewModel.localImports) { item in
                        WallpaperCardView(item: item, viewModel: viewModel)
                            .aspectRatio(16/10, contentMode: .fit)
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Sidebar Navigation

struct SidebarView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Binding var isDarkMode: Bool
    @Binding var showSettings: Bool
    @Binding var isSidebarVisible: Bool
    @AppStorage("isDarkMode") private var isDark: Bool = true

    private let navItems: [(AppTab, String)] = [
        (.pc,            "desktopcomputer"),
        (.downloaded,    "square.and.arrow.down"),
        (.slideshow,     "photo.on.rectangle.angled"),
        (.collection,    "rectangle.stack"),
        (.steamWorkshop, "gamecontroller.fill"),
        (.upload,        "icloud.and.arrow.up"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Logo ──
            HStack(spacing: 10) {
                ZStack {
                    LinearGradient.brand
                        .mask(
                            Image(systemName: "camera.aperture")
                                .font(.system(size: 20, weight: .semibold))
                        )
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text("胖楼壁纸")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    Text("壁纸管理器")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isSidebarVisible = false
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("隐藏侧边栏")
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 12).opacity(0.5)

            // ── Nav Items ──
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 壁纸 section
                    SidebarSectionLabel(title: "壁纸")
                    ForEach(navItems.prefix(3), id: \.0) { tab, icon in
                        SidebarNavItemView(
                            icon: icon,
                            title: tab.rawValue,
                            isSelected: viewModel.currentTab == tab && !showSettings
                        ) {
                            showSettings = false
                            viewModel.currentTab = tab
                        }
                    }

                    SidebarSectionLabel(title: "工具")
                    ForEach(navItems.dropFirst(3), id: \.0) { tab, icon in
                        SidebarNavItemView(
                            icon: icon,
                            title: tab.rawValue,
                            isSelected: viewModel.currentTab == tab && !showSettings
                        ) {
                            showSettings = false
                            viewModel.currentTab = tab
                        }
                    }

                    SidebarNavItemView(
                        icon: "gearshape.fill",
                        title: "设置",
                        isSelected: showSettings
                    ) {
                        showSettings = true
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }

            Divider().padding(.horizontal, 12).opacity(0.5)

            // ── Current Wallpaper Card ──
            SidebarCurrentWallpaperCard(viewModel: viewModel)

            // ── Quick Actions ──
            HStack(spacing: 8) {
                Button(action: { viewModel.randomWallpaper() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle").font(.system(size: 11))
                        Text("随机").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.brandPurple)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.brandPurple.opacity(0.1))
                    .cornerRadius(8)
                }.buttonStyle(.plain).help("随机换一张壁纸")

                Button(action: { viewModel.importLocalWallpaper() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 11))
                        Text("导入").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                }.buttonStyle(.plain).help("导入本地壁纸")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 12).opacity(0.5)

            // ── Bottom Controls ──
            VStack(spacing: 2) {
                // Theme toggle
                HStack(spacing: 10) {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text(isDarkMode ? "深色模式" : "浅色模式")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    CustomThemeToggleView(isDarkMode: $isDarkMode)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // User account
                SidebarUserRowView(viewModel: viewModel)
            }
            .padding(.bottom, 12)
        }
        .frame(width: 188)
        .background(isDark ? Color.sidebarDark : Color.sidebarLight)
    }
}

// MARK: - Current Wallpaper Card

struct SidebarCurrentWallpaperCard: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var videoThumbnail: NSImage? = nil
    @State private var webPreviewImage: NSImage? = nil
    @State private var lastLoadedPath: String = ""

    private var isVideoPath: Bool {
        let ext = (viewModel.currentWallpaperPath as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "webm"].contains(ext)
    }

    private var isWebPath: Bool {
        let ext = (viewModel.currentWallpaperPath as NSString).pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionLabel(title: "当前壁纸")

            HStack(spacing: 10) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))

                    if viewModel.currentWallpaperPath.isEmpty {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.35))
                    } else if isVideoPath {
                        if let thumb = videoThumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Image(systemName: "video.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(LinearGradient.brand)
                        }
                    } else if isWebPath {
                        if let thumb = webPreviewImage {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Image(systemName: "globe")
                                .font(.system(size: 14))
                                .foregroundStyle(LinearGradient.brand)
                        }
                    } else if let img = NSImage(contentsOfFile: viewModel.currentWallpaperPath) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.35))
                    }
                }
                .frame(width: 62, height: 40)
                .clipped()
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if viewModel.isSlideshowEnabled {
                            Circle().fill(Color.green).frame(width: 5, height: 5)
                            Text("轮播中")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.8))
                        } else {
                            Text(viewModel.currentWallpaperPath.isEmpty ? "未设置" : (isVideoPath ? "动态壁纸" : (isWebPath ? "网页壁纸" : "静态壁纸")))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.8))
                        }
                    }

                    if viewModel.isSlideshowEnabled && !viewModel.nextSlideshowCountdown.isEmpty {
                        Text(viewModel.nextSlideshowCountdown)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                            .lineLimit(1)
                    } else if !viewModel.currentWallpaperPath.isEmpty {
                        let displayName = viewModel.currentWallpaperTitle.isEmpty
                            ? (viewModel.currentWallpaperPath as NSString).lastPathComponent
                            : viewModel.currentWallpaperTitle
                        Text(displayName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("点击下方随机换一张")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.45))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .onChange(of: viewModel.currentWallpaperPath) { newPath in
            loadVideoThumbnailIfNeeded(path: newPath)
        }
        .onAppear {
            loadVideoThumbnailIfNeeded(path: viewModel.currentWallpaperPath)
        }
    }

    private func loadVideoThumbnailIfNeeded(path: String) {
        guard !path.isEmpty, path != lastLoadedPath else { return }
        lastLoadedPath = path
        let ext = (path as NSString).pathExtension.lowercased()

        if ext == "html" || ext == "htm" {
            videoThumbnail = nil
            let dir = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
            // 优先读 project.json 的 "preview" 字段（Workshop 壁纸常用 .gif 预览图）
            var previewURL: URL? = nil
            if let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["preview"] as? String, !name.isEmpty {
                let candidate = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    previewURL = candidate
                }
            }
            if previewURL == nil {
                let candidates = ["preview.jpg", "preview.jpeg", "preview.png",
                                  "preview.gif", "thumbnail.jpg", "thumbnail.png"]
                previewURL = candidates
                    .map { dir.appendingPathComponent($0) }
                    .first { FileManager.default.fileExists(atPath: $0.path) }
            }
            guard let finalURL = previewURL else { webPreviewImage = nil; return }
            Task.detached(priority: .userInitiated) {
                let img = WallpaperCacheManager.downsampledImage(at: finalURL, maxDimension: 160)
                await MainActor.run { self.webPreviewImage = img }
            }
            return
        }

        webPreviewImage = nil
        guard ["mp4", "mov", "m4v", "avi", "webm"].contains(ext) else {
            videoThumbnail = nil
            return
        }
        Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: path)

            // 先尝试 AVAssetImageGenerator 提取首帧（webm 等格式在 macOS 可能不支持）
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 124, height: 80)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter  = CMTime(seconds: 2, preferredTimescale: 600)
            for t in [CMTime(seconds: 1, preferredTimescale: 600), CMTime.zero] {
                if let cgImage = try? generator.copyCGImage(at: t, actualTime: nil) {
                    let nsImage = NSImage(cgImage: cgImage, size: .zero)
                    await MainActor.run { self.videoThumbnail = nsImage }
                    return
                }
            }

            // 帧提取失败 → fallback：在同目录寻找预览图（workshop 壁纸常带 preview.jpg）
            let dir = url.deletingLastPathComponent()
            var previewURL: URL?
            if let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["preview"] as? String, !name.isEmpty {
                let candidate = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) { previewURL = candidate }
            }
            if previewURL == nil {
                let fallbacks = ["preview.jpg", "preview.jpeg", "preview.png",
                                 "thumbnail.jpg", "thumbnail.png", "preview.gif"]
                previewURL = fallbacks.map { dir.appendingPathComponent($0) }
                    .first { FileManager.default.fileExists(atPath: $0.path) }
            }
            if let previewURL, let img = WallpaperCacheManager.downsampledImage(at: previewURL, maxDimension: 160) {
                await MainActor.run { self.videoThumbnail = img }
            }
        }
    }
}

struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.5))
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

struct SidebarNavItemView: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var bounceScale: CGFloat = 1.0
    @State private var iconRotation: Double = 0

    var body: some View {
        Button(action: {
            triggerIconAnimation()
            action()
        }) {
            HStack(spacing: 0) {
                // Leading accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? LinearGradient.brand : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: 18)
                    .padding(.leading, 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

                HStack(spacing: 9) {
                    Group {
                        if isSelected {
                            ZStack {
                                LinearGradient.brand
                                    .mask(Image(systemName: icon).font(.system(size: 13, weight: .medium)))
                            }
                            .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isHovered ? .primary : .primary.opacity(0.55))
                                .frame(width: 16)
                        }
                    }
                    .scaleEffect(bounceScale)
                    .rotationEffect(.degrees(iconRotation))

                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .brandPurple : (isHovered ? .primary : .primary.opacity(0.65)))
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.leading, 9)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            Color.brandPurple.opacity(0.1)
                        } else if isHovered {
                            Color.primary.opacity(0.05)
                        } else {
                            Color.clear
                        }
                    }
                )
                .cornerRadius(8)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private func triggerIconAnimation() {
        // 弹性缩放：快速弹起，再 spring 回落
        withAnimation(.spring(response: 0.16, dampingFraction: 0.38)) {
            bounceScale = 1.32
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                bounceScale = 1.0
            }
        }
        // 齿轮图标额外旋转 90°
        if icon == "gearshape.fill" {
            withAnimation(.easeInOut(duration: 0.38)) {
                iconRotation += 90
            }
        }
    }
}

struct SidebarUserRowView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if viewModel.isLoggedIn {
                viewModel.showUserSpace = true
            } else {
                viewModel.showLoginSheet = true
            }
        }) {
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    if viewModel.isLoggedIn {
                        let url = viewModel.currentProfile?.avatarURL ?? ""
                        if !url.isEmpty, let imageURL = URL(string: url) {
                            AsyncImage(url: imageURL) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())
                                } else {
                                    defaultAvatarIcon
                                }
                            }
                        } else {
                            defaultAvatarIcon
                        }
                    } else {
                        Circle()
                            .fill(Color.primary.opacity(0.07))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            )
                    }
                }

                // Text
                VStack(alignment: .leading, spacing: 1) {
                    if viewModel.isLoggedIn {
                        Text(viewModel.currentProfile?.username ?? "用户空间")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineLimit(1)
                        Text("查看个人空间")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                    } else {
                        Text("未登录")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("点击登录 / 注册")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help(viewModel.isLoggedIn ? "用户空间" : "登录 / 注册")
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var defaultAvatarIcon: some View {
        ZStack {
            Circle()
                .fill(LinearGradient.brand)
                .frame(width: 28, height: 28)
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Settings Page

struct SettingsView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Binding var isDarkMode: Bool
    @State private var showClearCacheAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                Text("设置")
                    .font(.displayTitle)
                    .padding(.bottom, 4)

                // ── 外观 ──
                SettingsSectionView(title: "外观") {
                    SettingsRowView(icon: isDarkMode ? "moon.fill" : "sun.max.fill", label: "深色模式") {
                        Toggle("", isOn: $isDarkMode)
                            .labelsHidden()
                            .toggleStyle(BrandSwitchStyle())
                    }
                }

                // ── 性能 ──
                SettingsSectionView(title: "性能") {
                    SettingsRowView(
                        icon: "leaf.fill",
                        label: "节能模式",
                        subLabel: "全屏游戏/应用时自动暂停动态壁纸渲染"
                    ) {
                        Toggle("", isOn: $viewModel.isEnergySavingEnabled)
                            .labelsHidden()
                            .toggleStyle(BrandSwitchStyle())
                    }
                }

                // ── 系统 ──
                SettingsSectionView(title: "系统") {
                    SettingsRowView(icon: "power", label: "开机自动启动") {
                        Toggle("", isOn: Binding(
                            get: { viewModel.isAutoStartEnabled },
                            set: { viewModel.toggleAutoStart(enable: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(BrandSwitchStyle())
                    }
                }

                // ── 文件管理 ──
                SettingsSectionView(title: "文件管理") {
                    SettingsRowView(icon: "folder.badge.plus", label: "导入本地壁纸") {
                        Button(action: { viewModel.importLocalWallpaper() }) {
                            Text("选择文件")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.brandPurple)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.brandPurple.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                    Divider().padding(.leading, 50)
                    SettingsRowView(icon: "folder", label: "缓存位置", subLabel: viewModel.cacheDirectoryPath) {
                        HStack(spacing: 8) {
                            Button(action: { viewModel.changeCacheDirectory() }) {
                                Text("更改")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.brandPurple)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.brandPurple.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                            if viewModel.cacheDirectoryPath != WallpaperCacheManager.defaultCacheDirectory.path {
                                Button(action: { viewModel.resetCacheDirectory() }) {
                                    Text("重置")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Divider().padding(.leading, 50)
                    SettingsRowView(icon: "internaldrive", label: "磁盘缓存") {
                        HStack(spacing: 10) {
                            Text(viewModel.cacheSizeString)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Button(action: { showClearCacheAlert = true }) {
                                Text("清除缓存")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                // ── 关于 ──
                SettingsSectionView(title: "关于") {
                    SettingsRowView(icon: "info.circle.fill", label: "关于胖楼壁纸") {
                        Button(action: { viewModel.showAbout = true }) {
                            Text("查看")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.brandPurple)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.brandPurple.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("确定要清除缓存吗？", isPresented: $showClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("确认清除", role: .destructive) { viewModel.clearCache() }
        } message: {
            Text("这将释放 \(viewModel.cacheSizeString) 磁盘空间。正在使用的壁纸和您的轮播列表不会被删除。")
        }
    }
}

struct SettingsSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
                .tracking(0.6)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        }
    }
}

struct SettingsRowView<Control: View>: View {
    let icon: String
    let label: String
    var subLabel: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.brandPurple)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                if let sub = subLabel {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, subLabel != nil ? 10 : 13)
    }
}

// MARK: - Search & Filter Bar (top of content area)

struct SearchFilterBarView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHotSelected = false
    @State private var isDragTargeted = false
    @FocusState private var isSearchFocused: Bool

    let types = ["全部", "静态壁纸", "动态壁纸"]
    let categories = ["全部", "魅力 | 迷人", "自制 | 艺术", "安逸 | 自由", "科幻 | 星云", "动漫 | 二次元", "自然 | 风景", "游戏 | 玩具"]
    let resolutions = ["全部", "1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K"]
    let colors: [(String, Color?)] = [
        ("全部", nil),
        ("偏蓝",   Color(hex: "#28A7D0")),
        ("偏绿",   Color(hex: "#449B3E")),
        ("偏红",   Color(hex: "#873229")),
        ("灰/白",  Color.gray.opacity(0.6)),
        ("紫/粉",  Color(hex: "#A030C8")),
        ("暗色",   Color(hex: "#333333")),
        ("偏黄",   Color(hex: "#C6AC2C")),
        ("其他颜色", nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Row 1: Search + optional shuffle ──
            // 整个搜索栏支持拖拽图片触发以图搜图
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            isSearchFocused
                                ? AnyShapeStyle(LinearGradient.brand)
                                : AnyShapeStyle(Color.secondary)
                        )
                        .animation(.easeInOut(duration: 0.15), value: isSearchFocused)
                    TextField("搜索标题、描述、标签…", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isSearchFocused)
                    if !viewModel.searchText.isEmpty {
                        Button(action: { viewModel.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSearchFocused
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.brandPurple.opacity(0.6), Color.brandPink.opacity(0.6)],
                                    startPoint: .leading, endPoint: .trailing
                                  ))
                                : AnyShapeStyle(Color.clear),
                            lineWidth: 1.5
                        )
                )
                .frame(maxWidth: 360)
                .animation(.easeInOut(duration: 0.15), value: isSearchFocused)

                Spacer()

                // PC tab only: shuffle + image search
                if viewModel.currentTab == .pc {
                    Button(action: { viewModel.randomWallpaper() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "shuffle").font(.system(size: 12, weight: .medium))
                            Text("随机").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(8)
                    }.buttonStyle(.plain)

                    Button(action: { pickImageForSearch() }) {
                        HStack(spacing: 5) {
                            Image(systemName: viewModel.imageSearchMode ? "sparkles" : "camera.viewfinder")
                                .font(.system(size: 12, weight: .medium))
                            Text("以图搜图").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(viewModel.imageSearchMode
                            ? AnyShapeStyle(LinearGradient.brand)
                            : AnyShapeStyle(Color.secondary))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.imageSearchMode
                            ? AnyShapeStyle(Color.brandPurple.opacity(0.1))
                            : AnyShapeStyle(Color.primary.opacity(0.06)))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    viewModel.imageSearchMode
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [Color.brandPurple.opacity(0.5), Color.brandPink.opacity(0.5)],
                                            startPoint: .leading, endPoint: .trailing
                                          ))
                                        : AnyShapeStyle(Color.clear),
                                    lineWidth: 1
                                )
                        )
                    }.buttonStyle(.plain)
                    .help("选择图片，搜索风格相似的壁纸（也可直接拖入图片）")
                }
            }

            // ── Row 2: Image search banner OR normal filter chips ──
            if viewModel.imageSearchMode {
                HStack(spacing: 12) {
                    // Query image preview
                    if let img = viewModel.imageSearchQueryImage {
                        Image(nsImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 52, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            Text("以图搜图")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        }
                        if viewModel.isImageSearching {
                            HStack(spacing: 5) {
                                ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
                                Text("正在分析图像特征…")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        } else {
                            HStack(spacing: 3) {
                                Text("找到")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                                Text("\(viewModel.imageSearchResults.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                Text("个相似壁纸")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button(action: { viewModel.clearImageSearch() }) {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 28, height: 28)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: Color.blue.opacity(0.11), location: 0),
                            .init(color: Color.purple.opacity(0.08), location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .cornerRadius(12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.25)], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1
                        )
                )
            } else {
            // ── Normal filter chips ──
            // 注意：不能用 ScrollView，否则其裁剪行为会把下拉菜单剪掉
            HStack(spacing: 8) {
                // Hot (PC only)
                if viewModel.currentTab == .pc {
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isHotSelected.toggle() } }) {
                        FilterTagView(title: "昨日热门", icon: "flame", isSelected: isHotSelected)
                    }.buttonStyle(.plain)
                }

                // Type
                Button(action: { withAnimation { viewModel.showTypeMenu.toggle(); closeOtherMenus(except: "Type") } }) {
                    FilterTagView(
                        title: viewModel.selectedType == "全部" ? "种类" : viewModel.selectedType,
                        icon: "square.grid.2x2",
                        isSelected: viewModel.showTypeMenu || viewModel.selectedType != "全部"
                    )
                }.buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if viewModel.showTypeMenu {
                        MenuPopoverView(options: types, selected: $viewModel.selectedType) { viewModel.showTypeMenu = false }
                            .offset(y: 36)
                            .zIndex(200)
                    }
                }

                // Category
                Button(action: { withAnimation { viewModel.showCategoryMenu.toggle(); closeOtherMenus(except: "Category") } }) {
                    let display = viewModel.selectedCategory == "全部"
                        ? "分类"
                        : (viewModel.selectedCategory.components(separatedBy: " | ").first ?? "分类")
                    FilterTagView(
                        title: display,
                        icon: "tag",
                        isSelected: viewModel.showCategoryMenu || viewModel.selectedCategory != "全部"
                    )
                }.buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if viewModel.showCategoryMenu {
                        MenuPopoverView(options: categories, selected: $viewModel.selectedCategory) { viewModel.showCategoryMenu = false }
                            .offset(y: 36)
                            .zIndex(200)
                    }
                }

                // Resolution
                Button(action: { withAnimation { viewModel.showResolutionMenu.toggle(); closeOtherMenus(except: "Resolution") } }) {
                    FilterTagView(
                        title: viewModel.selectedResolution == "全部" ? "分辨率" : viewModel.selectedResolution,
                        icon: "tv",
                        isSelected: viewModel.showResolutionMenu || viewModel.selectedResolution != "全部"
                    )
                }.buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if viewModel.showResolutionMenu {
                        ResolutionPopoverView(viewModel: viewModel, options: resolutions)
                            .offset(y: 36)
                            .zIndex(200)
                    }
                }

                // Color
                Button(action: { withAnimation { viewModel.showColorMenu.toggle(); closeOtherMenus(except: "Color") } }) {
                    FilterTagView(
                        title: viewModel.selectedColor == "全部" ? "色系" : viewModel.selectedColor,
                        icon: "paintpalette",
                        isSelected: viewModel.showColorMenu || viewModel.selectedColor != "全部"
                    )
                }.buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if viewModel.showColorMenu {
                        ColorPopoverView(options: colors, selected: $viewModel.selectedColor) { viewModel.showColorMenu = false }
                            .offset(y: 36)
                            .zIndex(200)
                    }
                }

                Spacer()
            }
            } // end else (normal filter chips)
        }
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isDragTargeted) { providers in
            guard viewModel.currentTab == .pc else { return false }
            handleImageDrop(providers: providers)
            return true
        }
        .overlay(
            Group {
                if isDragTargeted && viewModel.currentTab == .pc {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.09), Color.purple.opacity(0.09)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    LinearGradient(colors: [.blue.opacity(0.65), .purple.opacity(0.65)], startPoint: .leading, endPoint: .trailing),
                                    style: StrokeStyle(lineWidth: 2, dash: [6, 3])
                                )
                        )
                        .overlay(
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.blue.opacity(0.18), .purple.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "camera.viewfinder")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("松开以图搜图")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                    Text("支持 JPG · PNG · GIF · HEIC · MP4")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        )
                }
            }
        )
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        .onChange(of: viewModel.currentTab) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                viewModel.closeAllFilterMenus()
            }
        }
    }

    private func handleImageDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        // 优先尝试文件 URL（支持各类图片和视频）
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let urlString = String(data: data, encoding: .utf8)?
                          .trimmingCharacters(in: .whitespacesAndNewlines),
                      let url = URL(string: urlString) else { return }
                DispatchQueue.main.async { viewModel.searchByImage(url: url) }
            }
            return
        }

        // 回退：直接拖入图片数据（如从浏览器拖拽）
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            try? data.write(to: tmp)
            DispatchQueue.main.async { viewModel.searchByImage(url: tmp) }
        }
    }

    private func pickImageForSearch() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .bmp, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择一张图片，搜索风格相似的壁纸"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.searchByImage(url: url)
        }
    }

    private func closeOtherMenus(except name: String) {
        if name != "Type"       { viewModel.showTypeMenu = false }
        if name != "Category"   { viewModel.showCategoryMenu = false }
        if name != "Resolution" { viewModel.showResolutionMenu = false }
        if name != "Color"      { viewModel.showColorMenu = false }
    }
}

// MARK: - Pagination Bar (bottom of content area)

struct PaginationBarView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var jumpPageText = ""
    @State private var prevHovered = false
    @State private var nextHovered = false

    private var cur: Int { viewModel.currentPage }
    private var total: Int { viewModel.totalPages }

    // 计算要显示的页码列表，格式：[1, nil(…), 4, 5, 6, nil(…), 20]
    private var pageSlots: [Int?] {
        guard total > 1 else { return total == 1 ? [1] : [] }
        if total <= 7 { return (1...total).map { Optional($0) } }
        var slots: [Int?] = []
        // Clamp so the window stays valid at both ends and always shows ≥3 consecutive pages
        let left  = max(2, min(cur, total - 3))
        let right = min(total - 1, max(cur + 2, 3))
        slots.append(1)
        if left > 2  { slots.append(nil) }
        for p in left...right { slots.append(p) }
        if right < total - 1 { slots.append(nil) }
        slots.append(total)
        return slots
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧页码文字
            if total > 1 {
                Text("第 \(cur + 1) / \(total) 页")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.primary.opacity(0.3))
                    .padding(.trailing, 16)
            }

            // Prev
            Button(action: { withAnimation { viewModel.currentPage -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(cur == 0 ? .primary.opacity(0.2)
                                     : (prevHovered ? Color(hex: "#A855F7") : .primary.opacity(0.7)))
                    .frame(width: 28, height: 28)
                    .background(prevHovered && cur > 0
                                ? Color(hex: "#7C6BF5").opacity(0.1) : Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(cur == 0)
            .onHover { prevHovered = $0 }
            .animation(.easeInOut(duration: 0.12), value: prevHovered)

            // Page numbers
            HStack(spacing: 6) {
                ForEach(Array(pageSlots.enumerated()), id: \.offset) { _, slot in
                    if let p = slot {
                        PageNumberCircleView(number: p, isCurrent: cur == p - 1) {
                            withAnimation { viewModel.currentPage = p - 1 }
                        }
                    } else {
                        Text("…")
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.3))
                            .frame(width: 20)
                    }
                }
            }
            .padding(.horizontal, 8)

            // Next
            Button(action: { withAnimation { viewModel.currentPage += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(cur >= total - 1 ? .primary.opacity(0.2)
                                     : (nextHovered ? Color(hex: "#A855F7") : .primary.opacity(0.7)))
                    .frame(width: 28, height: 28)
                    .background(nextHovered && cur < total - 1
                                ? Color(hex: "#7C6BF5").opacity(0.1) : Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(cur >= total - 1)
            .onHover { nextHovered = $0 }
            .animation(.easeInOut(duration: 0.12), value: nextHovered)

            // Jump to page
            if total > 7 {
                HStack(spacing: 6) {
                    Text("跳转")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.3))
                    TextField("", text: $jumpPageText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .frame(width: 34, height: 26)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        .onSubmit {
                            if let page = Int(jumpPageText), page >= 1, page <= total {
                                withAnimation { viewModel.currentPage = page - 1 }
                                jumpPageText = ""
                            }
                        }
                    Button(action: {
                        if let page = Int(jumpPageText), page >= 1, page <= total {
                            withAnimation { viewModel.currentPage = page - 1 }
                            jumpPageText = ""
                        }
                    }) {
                        Text("Go")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#7C6BF5"))
                    }.buttonStyle(.plain)
                }
                .padding(.leading, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}


struct HoverableMenuRow: View { let option: String; @Binding var selected: String; let action: () -> Void; @State private var isHovered = false; var body: some View { Button(action: action) { Text(option).font(.system(size: 14, weight: selected == option ? .bold : .medium)).foregroundColor(selected == option ? .white : (isHovered ? .white : .white.opacity(0.8))).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8).padding(.horizontal, 16).background(isHovered ? Color.white.opacity(0.15) : Color.clear).cornerRadius(6).contentShape(Rectangle()) }.buttonStyle(.plain).onHover { isHovered = $0 } } }
struct MenuPopoverView: View { let options: [String]; @Binding var selected: String; let closeAction: () -> Void; var body: some View { VStack(spacing: 4) { ForEach(options, id: \.self) { option in HoverableMenuRow(option: option, selected: $selected) { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = option; closeAction() } } } }.padding(.vertical, 12).padding(.horizontal, 12).fixedSize().background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).environment(\.colorScheme, .dark)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1)).shadow(color: Color.black.opacity(0.4), radius: 15, y: 5).transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)) } }
struct HoverableColorRow: View { let option: (String, Color?); @Binding var selected: String; let action: () -> Void; @State private var isHovered = false; var body: some View { Button(action: action) { HStack(spacing: 0) { Text(option.0).font(.system(size: 14, weight: selected == option.0 ? .bold : .medium)).foregroundColor(selected == option.0 ? .white : (isHovered ? .white : .white.opacity(0.8))); Spacer(); if let color = option.1 { Circle().fill(color).frame(width: 14, height: 14) } else if option.0 == "其他颜色" { Circle().fill(AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .red]), center: .center)).frame(width: 14, height: 14) } else { Spacer().frame(width: 14) } }.padding(.vertical, 8).padding(.horizontal, 12).background(isHovered ? Color.white.opacity(0.15) : Color.clear).cornerRadius(6).contentShape(Rectangle()) }.buttonStyle(.plain).onHover { isHovered = $0 } } }
struct ColorPopoverView: View { let options: [(String, Color?)]; @Binding var selected: String; let closeAction: () -> Void; var body: some View { let contentHeight = CGFloat(options.count) * 40.0 + 24.0; let finalHeight = min(contentHeight, 280.0); ScrollView(showsIndicators: false) { VStack(spacing: 4) { ForEach(options, id: \.0) { option in HoverableColorRow(option: option, selected: $selected) { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = option.0; closeAction() } } } }.padding(.vertical, 12).padding(.horizontal, 12) }.frame(width: 150, height: finalHeight).background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).environment(\.colorScheme, .dark)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1)).shadow(color: Color.black.opacity(0.3), radius: 15, y: 5).transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity)) } }

struct HoverableResolutionRow: View { let option: String; @Binding var selected: String; let action: () -> Void; @State private var isHovered = false; var body: some View { Button(action: action) { Text(option).font(.system(size: 14, weight: selected == option ? .bold : .medium)).foregroundColor(selected == option ? .white : (isHovered ? .white : .white.opacity(0.8))).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.horizontal, 12).background(isHovered ? Color.white.opacity(0.15) : Color.clear).cornerRadius(6).contentShape(Rectangle()) }.buttonStyle(.plain).onHover { isHovered = $0 } } }
struct ResolutionPopoverView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    let options: [String]

    private func applyCustomResolution() {
        let w = viewModel.customWidth.trimmingCharacters(in: .whitespaces)
        let h = viewModel.customHeight.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty || !h.isEmpty else { return }
        if !w.isEmpty && !h.isEmpty {
            viewModel.selectedResolution = "\(w)×\(h)"
        } else if !w.isEmpty {
            viewModel.selectedResolution = w
        } else {
            viewModel.selectedResolution = h
        }
        viewModel.showResolutionMenu = false
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    HoverableResolutionRow(option: option, selected: $viewModel.selectedResolution) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.selectedResolution = option
                            viewModel.showResolutionMenu = false
                        }
                    }
                }
            }.padding(.all, 12)
            Divider().background(Color.white.opacity(0.1))
            VStack(alignment: .leading, spacing: 12) {
                Text("自定义：").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                HStack(spacing: 10) {
                    CustomDashedTextField(placeholder: "例: 1920", text: $viewModel.customWidth)
                    Text("×").foregroundColor(.gray)
                    CustomDashedTextField(placeholder: "例: 1080", text: $viewModel.customHeight)
                }
                HStack {
                    Text("提示：可单项查询").font(.system(size: 10)).foregroundColor(.gray.opacity(0.8))
                    Spacer()
                    Button(action: applyCustomResolution) {
                        Text("确认").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.brandPurple.opacity(0.8)).cornerRadius(6)
                    }.buttonStyle(.plain)
                        .disabled(viewModel.customWidth.trimmingCharacters(in: .whitespaces).isEmpty &&
                                  viewModel.customHeight.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.padding(.all, 20)
        }
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.4), radius: 15, y: 5)
        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }
}
struct CustomDashedTextField: View { var placeholder: String; @Binding var text: String; var body: some View { TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(.white).multilineTextAlignment(.center).padding(.vertical, 6).padding(.horizontal, 10).background(Color.white.opacity(0.05)).cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))) } }
// ==========================================
// MARK: - Hex 颜色翻译扩展 (补充代码)
// ==========================================
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
}
