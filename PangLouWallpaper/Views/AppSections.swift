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
    var body: some View { HStack { HStack(spacing: 8) { Image(systemName: "camera.aperture").font(.system(size: 22)); Text("胖楼壁纸").font(.system(size: 18, weight: .bold)) }.padding(.horizontal, 16).padding(.vertical, 8).background(capsuleBgColor).clipShape(Capsule()).foregroundColor(.primary); Spacer(); HStack(spacing: 4) { NavPillButtonView(title: AppTab.pc.rawValue, icon: "desktopcomputer", isSelected: viewModel.currentTab == .pc) { viewModel.currentTab = .pc }; NavPillButtonView(title: AppTab.downloaded.rawValue, icon: "square.and.arrow.down", isSelected: viewModel.currentTab == .downloaded) { viewModel.currentTab = .downloaded }; NavPillButtonView(title: AppTab.slideshow.rawValue, icon: "photo.on.rectangle.angled", isSelected: viewModel.currentTab == .slideshow) { viewModel.currentTab = .slideshow }; NavPillButtonView(title: AppTab.collection.rawValue, icon: "rectangle.stack", isSelected: viewModel.currentTab == .collection) { viewModel.currentTab = .collection }; NavPillButtonView(title: AppTab.upload.rawValue, icon: "icloud.and.arrow.up", isSelected: viewModel.currentTab == .upload) { viewModel.currentTab = .upload } }.padding(4).background(capsuleBgColor).clipShape(Capsule()); Spacer(); HStack(spacing: 15) { CustomThemeToggleView(isDarkMode: $isDarkMode); Image(systemName: "bell").font(.system(size: 16)).foregroundColor(.primary); Button(action: { viewModel.randomWallpaper() }) { Image(systemName: "shuffle").font(.system(size: 16)).foregroundColor(.primary).frame(width: 24, height: 24) }.buttonStyle(.plain).help("随机换一张壁纸"); Menu { Button(action: { viewModel.showAbout = true }) { Text("关于胖楼壁纸"); Image(systemName: "info.circle") }; Divider(); Menu("壁纸适配：\(viewModel.wallpaperFit.rawValue)") { ForEach(WallpaperFit.allCases, id: \.self) { fit in Button(action: { viewModel.wallpaperFit = fit }) { if viewModel.wallpaperFit == fit { Label(fit.rawValue, systemImage: "checkmark") } else { Text(fit.rawValue) } } } }; Menu("显示器：\(viewModel.targetScreenName)") { ForEach(viewModel.availableScreenNames, id: \.self) { name in Button(action: { viewModel.targetScreenName = name }) { if viewModel.targetScreenName == name { Label(name, systemImage: "checkmark") } else { Text(name) } } } }; Toggle("开机自动启动", isOn: Binding(get: { viewModel.isAutoStartEnabled }, set: { viewModel.toggleAutoStart(enable: $0) })); Button(action: { viewModel.importLocalWallpaper() }) { Text("导入本地壁纸"); Image(systemName: "folder.badge.plus") }; Divider(); Button(role: .destructive, action: { showClearCacheAlert = true }) { Text("清除全部缓存 (\(viewModel.cacheSizeString))"); Image(systemName: "trash") } } label: { Image(systemName: "gearshape.fill").font(.system(size: 16)).foregroundColor(.primary).frame(width: 24, height: 24) }.menuStyle(.borderlessButton).alert("确定要清除缓存吗？", isPresented: $showClearCacheAlert) { Button("取消", role: .cancel) { }; Button("确认清除", role: .destructive) { viewModel.clearCache() } } message: { Text("这将释放 \(viewModel.cacheSizeString) 磁盘空间。正在使用的壁纸和您的轮播列表不会被删除。") }; UserAccountButtonView(viewModel: viewModel) } } }
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
                                .font(.system(size: 22)).foregroundColor(.accentColor)
                        }
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22)).foregroundColor(.accentColor)
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
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary.opacity(0.6))
            Text("登录后即可上传壁纸，合集也会自动云端同步")
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.4))
            Button(action: { viewModel.showLoginSheet = true }) {
                Text("立即登录 / 注册")
                    .fontWeight(.bold).foregroundColor(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Color.accentColor).clipShape(Capsule())
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
            // ── 顶部工具栏 ────────────────────────────────
            HStack(spacing: 10) {
                Button(action: { viewModel.selectFilesForUpload() }) {
                    Label("添加文件", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)

                if !viewModel.pendingUploads.isEmpty {
                    Text("\(viewModel.pendingUploads.count) 个文件")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if viewModel.isUploading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("上传中…").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Button(action: { viewModel.cancelAllUploads() }) {
                        Label("停止", systemImage: "stop.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.red.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                } else if !viewModel.pendingUploads.isEmpty {
                    Button(action: { viewModel.clearPendingUploads() }) {
                        Text("清空")
                            .font(.system(size: 12))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                    Button(action: { viewModel.executeUpload() }) {
                        Label("上传全部 (\(viewModel.pendingUploads.count))", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color(hex: "#449B3E"))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            Divider()

            if viewModel.pendingUploads.isEmpty {
                // ── 空状态 ───────────────────────────────────
                Button(action: { viewModel.selectFilesForUpload() }) {
                    VStack(spacing: 14) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 42, weight: .thin))
                            .foregroundColor(.secondary.opacity(0.45))
                        VStack(spacing: 5) {
                            Text("点击选择文件")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.45))
                            Text("支持 JPG、PNG、MP4、MOV 格式")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 4]))
                            .foregroundColor(.secondary.opacity(0.22))
                    )
                    .padding(28)
                }
                .buttonStyle(.plain)
            } else {
                // ── 列表 ─────────────────────────────────────
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($viewModel.pendingUploads) { $item in
                            UploadRowView(
                                item: $item,
                                progress: viewModel.uploadProgress[item.id],
                                categories: uploadCategories,
                                resolutions: uploadResolutions,
                                colors: uploadColors,
                                onDelete: { viewModel.removePendingUpload(id: item.id) }
                            )
                            Divider().padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Upload Row (列表行)

struct UploadRowView: View {
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

    var body: some View {
        HStack(spacing: 14) {
            // 缩略图
            ZStack(alignment: .bottomLeading) {
                UploadThumbnailView(url: item.url)
                    .frame(width: 112, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(5)
                }
            }

            // 文本信息区
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("标题（留空用文件名）", text: $item.title)
                        .font(.system(size: 13, weight: .medium))
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 200)

                    Text(item.url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    TextField("描述（霓虹灯光、雨后街道…）", text: $item.wallpaperDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 220)

                    TextField("标签（动漫, 夜晚, 城市）", text: $item.tags)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 200)
                }

                if let p = progress {
                    HStack(spacing: 6) {
                        ProgressView(value: p)
                            .tint(.accentColor)
                            .controlSize(.small)
                            .frame(maxWidth: 160)
                        Text("\(Int(p * 100))%")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Spacer()

            // 内联选择器
            HStack(spacing: 8) {
                UploadPickerMenu(label: item.category.isEmpty ? "分类" : item.category,
                                 options: categories, selection: $item.category)
                UploadPickerMenu(label: item.resolution.isEmpty ? "分辨率" : item.resolution,
                                 options: resolutions, selection: $item.resolution)
                UploadPickerMenu(label: item.color.isEmpty ? "色系" : item.color,
                                 options: colors, selection: $item.color)
            }

            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(isHovered ? .red : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
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
                              : Color.accentColor.opacity(isHovered ? 0.2 : 0.12))
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
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
                        .font(.system(size: 18, weight: .bold))
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
                            .font(.system(size: 18, weight: .bold))
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
                                .foregroundColor(.accentColor)
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
                HStack(spacing: 10) {
                    // 拒绝
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showRejectInput.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: showRejectInput ? "xmark" : "hand.raised")
                                .font(.system(size: 12, weight: .semibold))
                            Text(showRejectInput ? "取消" : "拒绝")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(showRejectInput ? Color.secondary.opacity(0.6) : Color.red.opacity(0.8))
                        .cornerRadius(9)
                    }.buttonStyle(.plain)

                    // 通过
                    Button(action: { viewModel.approveWallpaper(item: item) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("通过")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color(hex: "#449B3E"))
                        .cornerRadius(9)
                        .shadow(color: Color(hex: "#449B3E").opacity(0.35), radius: 6, y: 3)
                    }.buttonStyle(.plain)
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(8)
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
                        .font(.system(size: 18, weight: .bold))
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
                        Circle().fill(Color.accentColor.opacity(0.08)).frame(width: 110, height: 110)
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 42, weight: .thin))
                            .foregroundColor(Color.accentColor.opacity(0.7))
                    }
                    VStack(spacing: 8) {
                        Text("还没有上传记录").font(.system(size: 18, weight: .bold)).foregroundColor(.primary.opacity(0.7))
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
            AsyncThumbnailView(item: item)
                .frame(width: 110, height: 68)
                .cornerRadius(9).clipped()
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if item.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 12)).foregroundColor(.accentColor)
                    }
                }
                HStack(spacing: 8) {
                    if !item.category.isEmpty {
                        Text(item.category)
                            .font(.system(size: 11))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07)).cornerRadius(4)
                    }
                    if !item.resolution.isEmpty {
                        Text(item.resolution)
                            .font(.system(size: 11))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07)).cornerRadius(4)
                    }
                }
                Text(formattedDate(item.uploadedAt))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            Spacer()

            // 审核状态徽标
            VStack(alignment: .trailing, spacing: 6) {
                let cfg = statusConfig
                HStack(spacing: 5) {
                    Image(systemName: cfg.icon)
                        .font(.system(size: 13))
                    Text(cfg.label)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(cfg.color)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(cfg.color.opacity(0.12))
                .cornerRadius(20)

                // 拒绝原因
                if item.approvalStatus == .rejected, let reason = item.rejectionReason, !reason.isEmpty {
                    Text("原因：\(reason)")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.75))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .frame(maxWidth: 200, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(isHovered ? 0.07 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// 🌟🌟🌟 核心手术：无敌自适应切分布局引擎 🌟🌟🌟
struct WallpaperGridView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @AppStorage("isSidebarVisible") private var isSidebarVisible: Bool = true
    var emptyText: String {
        switch viewModel.currentTab {
        case .pc:         return "未找到相关壁纸"
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
                // ── Segment 选择器 ──
                HStack {
                    if viewModel.isDeveloper {
                        // 开发者：待上传 / 审核队列 / 管理全部
                        Picker("", selection: $viewModel.uploadMode) {
                            Text("待上传新壁纸").tag(UploadMode.pending)
                            HStack {
                                Text("审核队列")
                                if !viewModel.pendingReviewItems.isEmpty {
                                    Text("(\(viewModel.pendingReviewItems.count))")
                                        .foregroundColor(.orange)
                                }
                            }.tag(UploadMode.review)
                            Text("管理全部壁纸").tag(UploadMode.manage)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 480)
                    } else {
                        // 普通用户：待上传 / 我的上传记录
                        Picker("", selection: $viewModel.uploadMode) {
                            Text("待上传新壁纸").tag(UploadMode.pending)
                            Text("我的上传记录").tag(UploadMode.manage)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                    }
                    Spacer()
                }
                .padding(.horizontal, 30).padding(.bottom, 15)

                if !viewModel.isLoggedIn {
                    LoginRequiredView(viewModel: viewModel)
                } else if viewModel.uploadMode == .pending {
                    UploadManagerView(viewModel: viewModel)
                } else if viewModel.uploadMode == .review {
                    ReviewQueueView(viewModel: viewModel)
                } else if viewModel.isDeveloper {
                    gridContent
                } else {
                    UserUploadsView(viewModel: viewModel)
                }
            } else if viewModel.currentTab == .collection {
                if viewModel.selectedCollectionId != nil {
                    // 合集详情：顶部返回按钮 + 壁纸网格
                    HStack {
                        Button(action: { viewModel.selectedCollectionId = nil }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("所有合集")
                            }.font(.system(size: 13, weight: .medium)).foregroundColor(.accentColor)
                        }.buttonStyle(.plain)
                        Spacer()
                        if let collectionId = viewModel.selectedCollectionId,
                           let collection = viewModel.collections.first(where: { $0.id == collectionId }) {
                            Text(collection.name).font(.system(size: 15, weight: .bold))
                            Text("(\(collection.wallpaperIds.count)张)").font(.system(size: 13)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }.padding(.horizontal, 30).padding(.bottom, 15)
                    gridContent
                } else {
                    CollectionsGridView(viewModel: viewModel)
                }
            } else {
                if viewModel.currentTab == .downloaded {
                    VStack(spacing: 10) {
                        HStack {
                            Picker("", selection: $viewModel.downloadedSubTab) {
                                Text("云端下载").tag(DownloadedSubTab.local)
                                Text("Workshop").tag(DownloadedSubTab.workshop)
                                Text("本地导入").tag(DownloadedSubTab.localImports)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 320)
                            // 当前子标签缓存大小
                            let subTabSize: String = {
                                switch viewModel.downloadedSubTab {
                                case .local:        return viewModel.cloudCacheSizeString
                                case .workshop:     return viewModel.workshopCacheSizeString
                                case .localImports: return viewModel.localImportSizeString
                                }
                            }()
                            Text(subTabSize)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            // 批量选择按钮（仅"云端下载"子标签可用）
                            if viewModel.downloadedSubTab == .local && !viewModel.displayWallpapers.isEmpty {
                                if viewModel.isBatchSelectMode {
                                    Button(action: { viewModel.selectAllDownloaded() }) {
                                        Text("全选")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.accentColor)
                                            .padding(.horizontal, 14).padding(.vertical, 6)
                                            .background(Color.accentColor.opacity(0.1))
                                            .clipShape(Capsule())
                                    }.buttonStyle(.plain)
                                }
                                Button(action: { viewModel.isBatchSelectMode.toggle() }) {
                                    Text(viewModel.isBatchSelectMode ? "退出选择" : "批量选择")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(viewModel.isBatchSelectMode ? .secondary : .primary)
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 15)
                }
                if viewModel.currentTab == .slideshow {
                    VStack(spacing: 10) {
                        HStack(spacing: 20) { Toggle(isOn: $viewModel.isSlideshowEnabled) { Text("启用自动轮播").font(.system(size: 14, weight: .bold)) }.toggleStyle(.switch); HStack(spacing: 8) { Text("切换频率:").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary); Picker("", selection: $viewModel.slideshowInterval) { Text("1 分钟").tag(60.0); Text("15 分钟").tag(900.0); Text("1 小时").tag(3600.0); Text("24 小时").tag(86400.0) }.labelsHidden().frame(width: 100) }; Toggle(isOn: $viewModel.isSlideshowRandom) { Text("随机播放").font(.system(size: 13, weight: .medium)) }.toggleStyle(.switch); Spacer()
                            if viewModel.isSlideshowEnabled && !viewModel.playlistIds.isEmpty {
                                Button(action: { viewModel.triggerNextSlideshow() }) { HStack(spacing: 4) { Image(systemName: "forward.fill"); Text("立即切换") }.font(.system(size: 13, weight: .medium)).foregroundColor(.accentColor).padding(.horizontal, 12).padding(.vertical, 6).background(Color.accentColor.opacity(0.1)).clipShape(Capsule()) }.buttonStyle(.plain)
                            }
                            Button(action: { viewModel.playlistIds.removeAll(); viewModel.statusMessage = "轮播列表已清空"; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { viewModel.statusMessage = "" } }) { HStack { Image(systemName: "trash"); Text("清空列表 (\(viewModel.playlistIds.count)张)") }.font(.system(size: 13, weight: .medium)).foregroundColor(.red).padding(.horizontal, 12).padding(.vertical, 6).background(Color.red.opacity(0.1)).clipShape(Capsule()) }.buttonStyle(.plain) }
                        if viewModel.isSlideshowEnabled && !viewModel.nextSlideshowCountdown.isEmpty { HStack { Image(systemName: "timer").font(.system(size: 12)).foregroundColor(.secondary); Text(viewModel.nextSlideshowCountdown).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundColor(.secondary); Spacer() } }

                        Divider().padding(.vertical, 4)

                        // ── 定时换壁纸 ──
                        HStack(spacing: 16) {
                            Toggle(isOn: $viewModel.isTimedPeriodEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("定时换壁纸").font(.system(size: 14, weight: .bold))
                                    Text("按早晨/下午/夜晚自动切换，与轮播互不影响")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                }
                            }.toggleStyle(.switch)
                            Spacer()
                        }
                        if viewModel.isTimedPeriodEnabled {
                            ForEach(DayPeriod.allCases) { period in
                                PeriodAssignmentRowView(period: period, viewModel: viewModel)
                            }
                        }
                    }.padding(.horizontal, 30).padding(.bottom, 15)
                }
                gridContent
            }
        }
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
                        Button(action: { viewModel.performSearch() }) {
                            Label("重新加载", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(Color.primary.opacity(0.08)).clipShape(Capsule())
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
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1))
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
                                                ? Color.accentColor : Color.clear, lineWidth: 2)
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
            .fill(Color.primary.opacity(isAnimating ? 0.09 : 0.04))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.05), lineWidth: 1))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
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
                        .font(.system(size: 22, weight: .bold))
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
                                .background(newName.isEmpty ? Color.secondary.opacity(0.5) : Color.accentColor)
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
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
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
                            .fill(Color.accentColor.opacity(0.09))
                            .frame(width: 130, height: 130)
                        Circle()
                            .fill(Color.accentColor.opacity(0.05))
                            .frame(width: 100, height: 100)
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 46, weight: .thin))
                            .foregroundColor(Color.accentColor.opacity(0.75))
                    }
                    VStack(spacing: 10) {
                        Text("还没有合集")
                            .font(.system(size: 20, weight: .bold))
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
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 12, y: 5)
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
                .fill(Color.accentColor.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            Color.accentColor.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                        )
                )
            VStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(Color.accentColor.opacity(0.85))
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
                            .background(name.isEmpty ? Color.secondary.opacity(0.35) : Color.accentColor)
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

            // ── 底部渐变 ──
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

            // ── 底部信息 ──
            if !isRenaming {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collection.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.55))
                                Text("\(collection.wallpaperIds.count) 张")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.65))
                                if collection.createdAt > 0 {
                                    Text("·").foregroundColor(.white.opacity(0.3))
                                    Text(formattedDate(collection.createdAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.45))
                                }
                            }
                        }
                        Spacer()
                        // 壁纸数量徽标
                        if collection.wallpaperIds.count > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(7)
                                .background(Color.white.opacity(0.15))
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
                                .background(renameText.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
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
                        colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 34, weight: .thin))
                            .foregroundColor(.primary.opacity(0.25))
                        Text("空合集")
                            .font(.system(size: 11))
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
                Image(systemName: "camera.aperture")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("胖楼壁纸")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isSidebarVisible = false
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("隐藏侧边栏")
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)

            Divider().padding(.horizontal, 14).opacity(0.6)

            // ── Nav Items ──
            VStack(spacing: 2) {
                ForEach(navItems, id: \.0) { tab, icon in
                    SidebarNavItemView(
                        icon: icon,
                        title: tab.rawValue,
                        isSelected: viewModel.currentTab == tab && !showSettings
                    ) {
                        showSettings = false
                        viewModel.currentTab = tab
                    }
                }

                // 设置（紧接上传壁纸下方）
                SidebarNavItemView(
                    icon: "gearshape.fill",
                    title: "设置",
                    isSelected: showSettings
                ) {
                    showSettings = true
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            Spacer()

            Divider().padding(.horizontal, 14).opacity(0.6).padding(.bottom, 8)

            // ── Bottom Controls ──
            VStack(spacing: 0) {
                // Theme toggle
                HStack(spacing: 10) {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 18)
                    Text(isDarkMode ? "深色" : "浅色")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    CustomThemeToggleView(isDarkMode: $isDarkMode)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)

                // User account
                SidebarUserRowView(viewModel: viewModel)
            }
            .padding(.bottom, 14)
        }
        .frame(width: 188)
        .background(Color.primary.opacity(0.025))
    }
}

struct SidebarNavItemView: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundColor(
                isSelected ? .accentColor : (isHovered ? .primary : .primary.opacity(0.6))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Group {
                    if isSelected {
                        Color.accentColor.opacity(0.13)
                    } else if isHovered {
                        Color.primary.opacity(0.06)
                    } else {
                        Color.clear
                    }
                }
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
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
                if viewModel.isLoggedIn {
                    let url = viewModel.currentProfile?.avatarURL ?? ""
                    if !url.isEmpty, let imageURL = URL(string: url) {
                        AsyncImage(url: imageURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                                    .frame(width: 22, height: 22)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                    }
                    Text(viewModel.currentProfile?.username ?? "用户空间")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary.opacity(0.75))
                        .lineLimit(1)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 22)
                    Text("登录 / 注册")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .help(viewModel.isLoggedIn ? "用户空间" : "登录 / 注册")
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
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
                    .font(.system(size: 22, weight: .bold))
                    .padding(.bottom, 4)

                // ── 壁纸 ──
                SettingsSectionView(title: "壁纸") {
                    SettingsRowView(icon: "aspectratio.fill", label: "适配方式") {
                        Picker("", selection: $viewModel.wallpaperFit) {
                            ForEach(WallpaperFit.allCases, id: \.self) { fit in
                                Text(fit.rawValue).tag(fit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    Divider().padding(.leading, 50)
                    SettingsRowView(icon: "display", label: "目标显示器") {
                        Picker("", selection: $viewModel.targetScreenName) {
                            ForEach(viewModel.availableScreenNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    Divider().padding(.leading, 50)
                    SettingsRowView(
                        icon: viewModel.videoVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: "壁纸音量",
                        subLabel: viewModel.videoVolume == 0 ? "静音" : "\(Int(viewModel.videoVolume * 100))%"
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Slider(value: $viewModel.videoVolume, in: 0...1, step: 0.05)
                                .frame(width: 160)
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // ── 外观 ──
                SettingsSectionView(title: "外观") {
                    SettingsRowView(icon: isDarkMode ? "moon.fill" : "sun.max.fill", label: "深色模式") {
                        Toggle("", isOn: $isDarkMode)
                            .labelsHidden()
                            .toggleStyle(.switch)
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
                            .toggleStyle(.switch)
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
                        .toggleStyle(.switch)
                    }
                }

                // ── 文件管理 ──
                SettingsSectionView(title: "文件管理") {
                    SettingsRowView(icon: "folder.badge.plus", label: "导入本地壁纸") {
                        Button(action: { viewModel.importLocalWallpaper() }) {
                            Text("选择文件")
                                .font(.system(size: 13))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(7)
                        }.buttonStyle(.plain)
                    }
                    Divider().padding(.leading, 50)
                    SettingsRowView(icon: "folder", label: "缓存位置", subLabel: viewModel.cacheDirectoryPath) {
                        HStack(spacing: 8) {
                            Button(action: { viewModel.changeCacheDirectory() }) {
                                Text("更改")
                                    .font(.system(size: 13))
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(7)
                            }.buttonStyle(.plain)
                            if viewModel.cacheDirectoryPath != WallpaperCacheManager.defaultCacheDirectory.path {
                                Button(action: { viewModel.resetCacheDirectory() }) {
                                    Text("重置")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(7)
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
                                    .font(.system(size: 13))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.08))
                                    .cornerRadius(7)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                // ── 关于 ──
                SettingsSectionView(title: "关于") {
                    SettingsRowView(icon: "info.circle.fill", label: "关于胖楼壁纸") {
                        Button(action: { viewModel.showAbout = true }) {
                            Text("查看")
                                .font(.system(size: 13))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(7)
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
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
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
                .foregroundColor(.accentColor)
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
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    TextField("搜索标题、描述、标签…", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !viewModel.searchText.isEmpty {
                        Button(action: { viewModel.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(8)
                .frame(maxWidth: 300)

                Spacer()

                // PC tab only: shuffle + image search
                if viewModel.currentTab == .pc {
                    Button(action: { viewModel.randomWallpaper() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "shuffle").font(.system(size: 12))
                            Text("随机").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(7)
                    }.buttonStyle(.plain)

                    Button(action: { pickImageForSearch() }) {
                        HStack(spacing: 5) {
                            Image(systemName: viewModel.imageSearchMode ? "sparkles" : "camera.viewfinder")
                                .font(.system(size: 12, weight: .medium))
                            Text("以图搜图").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(viewModel.imageSearchMode
                            ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.secondary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(viewModel.imageSearchMode
                            ? AnyShapeStyle(LinearGradient(colors: [Color.blue.opacity(0.14), Color.purple.opacity(0.14)], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.primary.opacity(0.06)))
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(
                                    viewModel.imageSearchMode
                                        ? AnyShapeStyle(LinearGradient(colors: [.blue.opacity(0.55), .purple.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
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

    var body: some View {
        HStack(spacing: 12) {
            // Previous
            Button(action: { viewModel.currentPage -= 1 }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(viewModel.currentPage == 0 ? .primary.opacity(0.25) : .primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPage == 0)

            // Page numbers
            HStack(spacing: 6) {
                ForEach(0..<min(viewModel.totalPages, 3), id: \.self) { index in
                    PageNumberCircleView(number: index + 1, isCurrent: viewModel.currentPage == index) {
                        viewModel.currentPage = index
                    }
                }
                if viewModel.totalPages > 3 {
                    Text("…")
                        .foregroundColor(.primary.opacity(0.35))
                        .font(.system(size: 13))
                    PageNumberCircleView(
                        number: viewModel.totalPages,
                        isCurrent: viewModel.currentPage == viewModel.totalPages - 1
                    ) {
                        viewModel.currentPage = viewModel.totalPages - 1
                    }
                }
            }

            // Next
            Button(action: { viewModel.currentPage += 1 }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(viewModel.currentPage >= viewModel.totalPages - 1 ? .primary.opacity(0.25) : .primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPage >= viewModel.totalPages - 1)

            // Jump to page
            if viewModel.totalPages > 5 {
                HStack(spacing: 6) {
                    Text("跳转")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("", text: $jumpPageText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .frame(width: 34, height: 26)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    Button(action: {
                        if let page = Int(jumpPageText), page >= 1, page <= viewModel.totalPages {
                            withAnimation { viewModel.currentPage = page - 1 }
                            jumpPageText = ""
                        }
                    }) {
                        Text("Go")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accentColor)
                    }.buttonStyle(.plain)
                }
            }
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
                            .background(Color.accentColor.opacity(0.8)).cornerRadius(6)
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
