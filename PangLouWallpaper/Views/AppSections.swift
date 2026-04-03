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

struct LocalFileThumbnailView: View {
    let url: URL; @State private var thumbnail: NSImage?; @State private var isLoading = true
    var body: some View { ZStack { if let img = thumbnail { Image(nsImage: img).resizable().scaledToFill() } else { Rectangle().fill(Color.gray.opacity(0.2)); if isLoading { ProgressView().controlSize(.small) } else { Image(systemName: "film").foregroundColor(.gray) } } }.frame(width: 80, height: 50).clipped().cornerRadius(8).task { thumbnail = await generateThumbnail(for: url); isLoading = false } }
    private func generateThumbnail(for url: URL) async -> NSImage? { let ext = url.pathExtension.lowercased(); if ext == "mp4" || ext == "mov" { let asset = AVURLAsset(url: url); let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 300, height: 300); do { let (cgImage, _) = try await generator.image(at: .zero); return NSImage(cgImage: cgImage, size: .zero) } catch { return nil } } else { return await Task.detached { return NSImage(contentsOf: url) }.value } }
}

struct UploadManagerView: View {
    @ObservedObject var viewModel: WallpaperViewModel

    private let uploadCategories = ["", "魅力", "自制", "安逸", "科幻", "动漫", "自然", "游戏"]
    private let uploadResolutions = ["", "1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K"]
    private let uploadColors = ["", "偏蓝", "偏绿", "偏红", "灰/白", "紫/粉", "暗色", "偏黄", "其他颜色"]

    var body: some View {
        VStack(spacing: 20) {
            // 顶部操作栏
            HStack {
                Button(action: { viewModel.selectFilesForUpload() }) {
                    HStack { Image(systemName: "plus.circle.fill"); Text("添加待传壁纸").fontWeight(.bold) }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.accentColor).foregroundColor(.white).clipShape(Capsule())
                }.buttonStyle(.plain)
                Spacer()
                if !viewModel.pendingUploads.isEmpty {
                    Button(action: { viewModel.clearPendingUploads() }) {
                        HStack { Image(systemName: "trash.fill"); Text("清空列表").fontWeight(.bold) }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.red.opacity(0.8)).foregroundColor(.white).clipShape(Capsule())
                    }.buttonStyle(.plain)
                    Button(action: { viewModel.executeUpload() }) {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up.fill")
                            Text("一键上传全部 (\(viewModel.pendingUploads.count))").fontWeight(.bold)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color(hex: "#449B3E")).foregroundColor(.white).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 30).padding(.bottom, 10)

            if viewModel.pendingUploads.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "folder.badge.plus").font(.system(size: 60)).foregroundColor(.primary.opacity(0.2))
                    Text("待上传列表为空").font(.system(size: 18, weight: .bold)).foregroundColor(.primary.opacity(0.6))
                    Text("点击左上角按钮选择本地文件，填写描述和标签后上传").font(.system(size: 14)).foregroundColor(.primary.opacity(0.4))
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($viewModel.pendingUploads) { $item in
                            PendingUploadRowView(
                                item: $item,
                                uploadProgress: viewModel.uploadProgress[item.id],
                                categories: uploadCategories,
                                resolutions: uploadResolutions,
                                colors: uploadColors,
                                onDelete: { viewModel.removePendingUpload(id: item.id) }
                            )
                        }
                    }.padding(.horizontal, 30).padding(.bottom, 40)
                }
            }
        }
    }
}

struct PendingUploadRowView: View {
    @Binding var item: PendingUploadItem
    let uploadProgress: Double?
    let categories: [String]
    let resolutions: [String]
    let colors: [String]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：缩略图 + 标题 + 分类/分辨率/色系 + 删除
            HStack(spacing: 12) {
                LocalFileThumbnailView(url: item.url)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.url.lastPathComponent)
                        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                    TextField("自定义标题（留空则用文件名）", text: $item.title)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05)).cornerRadius(6)
                }
                .frame(width: 200)

                Picker("", selection: $item.category) {
                    Text("—分类").tag("")
                    ForEach(categories.filter { !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
                }.frame(width: 90).labelsHidden()

                Picker("", selection: $item.resolution) {
                    Text("—分辨率").tag("")
                    ForEach(resolutions.filter { !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
                }.frame(width: 90).labelsHidden()

                Picker("", selection: $item.color) {
                    Text("—色系").tag("")
                    ForEach(colors.filter { !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
                }.frame(width: 90).labelsHidden()

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red.opacity(0.8)).padding(8)
                        .background(Color.red.opacity(0.1)).clipShape(Circle())
                }.buttonStyle(.plain)
            }

            // 第二行：描述 + 标签（缩进对齐）
            HStack(spacing: 8) {
                Color.clear.frame(width: 80)   // 对齐缩略图宽度

                TextField("描述（如：霓虹灯光、雨后街道）", text: $item.wallpaperDescription)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05)).cornerRadius(6)

                TextField("标签，逗号分隔（如：动漫, 夜晚, 城市）", text: $item.tags)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05)).cornerRadius(6)
            }

            // 上传进度条
            if let progress = uploadProgress {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.1)).frame(height: 6)
                            Capsule().fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                                .animation(.linear(duration: 0.1), value: progress)
                        }
                    }.frame(height: 6)
                    HStack {
                        Text("上传中…").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .padding(12).background(Color.primary.opacity(0.05)).cornerRadius(12)
    }
}

// 🌟🌟🌟 核心手术：无敌自适应切分布局引擎 🌟🌟🌟
struct WallpaperGridView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    var emptyText: String {
        switch viewModel.currentTab {
        case .pc:         return "未找到相关壁纸"
        case .downloaded:
            return viewModel.downloadedSubTab == .localImports ? "还没有本地导入的壁纸" : "暂无下载缓存"
        case .slideshow:  return "暂无轮播壁纸，请去已下载中点亮右上角星星添加"
        case .upload:     return viewModel.uploadMode == .manage ? "暂无壁纸" : ""  // local handled internally
        case .collection: return "该合集还没有壁纸，去其他标签页点击壁纸右下角书签按钮添加"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.currentTab == .upload {
                Picker("", selection: $viewModel.uploadMode) {
                    Text("待上传新壁纸").tag(UploadMode.pending)
                    Text(viewModel.isDeveloper ? "管理全部壁纸" : "我的上传记录").tag(UploadMode.manage)
                }
                .pickerStyle(.segmented).padding(.horizontal, 30).padding(.bottom, 15)

                if !viewModel.isLoggedIn {
                    LoginRequiredView(viewModel: viewModel)
                } else if viewModel.uploadMode == .pending {
                    UploadManagerView(viewModel: viewModel)
                } else {
                    gridContent
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
                    HStack {
                        Picker("", selection: $viewModel.downloadedSubTab) {
                            Text("已下载").tag(DownloadedSubTab.local)
                            Text("本地导入").tag(DownloadedSubTab.localImports)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        Spacer()
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
                    }.padding(.horizontal, 30).padding(.bottom, 15)
                }
                gridContent
            }
        }
    }
    
    // 彻底抛弃 LazyVGrid，使用绝对均匀的 HStack + VStack
    private var gridContent: some View {
        Group {
            if viewModel.displayWallpapers.isEmpty {
                VStack(spacing: 16) { Spacer(); Image(systemName: "tray").font(.system(size: 48)).foregroundColor(.primary.opacity(0.3)); Text(emptyText).font(.system(size: 16, weight: .medium)).foregroundColor(.primary.opacity(0.5)); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    // 不足 12 张图时，用透明块填满占位，保证网格阵型绝对不乱！
                                    Color.clear
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - 合集视图

struct CollectionsGridView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("我的合集").font(.system(size: 18, weight: .bold))
                Spacer()
                if isCreating {
                    HStack(spacing: 8) {
                        TextField("合集名称", text: $newName)
                            .textFieldStyle(.plain).font(.system(size: 13))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06)).cornerRadius(8)
                            .frame(width: 180)
                            .onSubmit { createIfValid() }
                        Button(action: createIfValid) {
                            Text("创建").fontWeight(.bold).foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(newName.isEmpty ? Color.secondary : Color.accentColor).cornerRadius(8)
                        }.buttonStyle(.plain).disabled(newName.isEmpty)
                        Button(action: { isCreating = false; newName = "" }) {
                            Text("取消").foregroundColor(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                } else {
                    Button(action: { isCreating = true }) {
                        HStack { Image(systemName: "plus.circle.fill"); Text("新建合集").fontWeight(.bold) }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.accentColor).foregroundColor(.white).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 30).padding(.bottom, 15)

            if viewModel.collections.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 60)).foregroundColor(.primary.opacity(0.2))
                    Text("还没有合集").font(.system(size: 18, weight: .bold)).foregroundColor(.primary.opacity(0.6))
                    Text("点击右上角「新建合集」，将喜欢的壁纸归类整理").font(.system(size: 14)).foregroundColor(.primary.opacity(0.4))
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                        ForEach(viewModel.collections) { collection in
                            CollectionCardView(collection: collection, viewModel: viewModel)
                                .aspectRatio(16/10, contentMode: .fit)
                        }
                    }.padding(.horizontal, 30).padding(.bottom, 40)
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

struct CollectionCardView: View {
    let collection: WallpaperCollection
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHovered = false

    private var coverItems: [WallpaperItem] {
        // coverWallpaperId 优先显示在左上角（第一格），其余按添加顺序填充
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

    var body: some View {
        ZStack {
            // 封面：多图拼贴
            let items = coverItems
            if items.isEmpty {
                RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08))
                    .overlay(Image(systemName: "rectangle.stack").font(.system(size: 36)).foregroundColor(.primary.opacity(0.3)))
            } else if items.count == 1 {
                AsyncThumbnailView(item: items[0]).cornerRadius(12).clipped()
            } else {
                GeometryReader { geo in
                    let w = geo.size.width; let h = geo.size.height
                    let hw = (w - 1) / 2; let hh = (h - 1) / 2
                    HStack(spacing: 1) {
                        VStack(spacing: 1) {
                            AsyncThumbnailView(item: items[0]).frame(width: hw, height: hh).clipped()
                            if items.count > 2 {
                                AsyncThumbnailView(item: items[2]).frame(width: hw, height: hh).clipped()
                            } else {
                                Color.primary.opacity(0.08).frame(width: hw, height: hh)
                            }
                        }
                        VStack(spacing: 1) {
                            AsyncThumbnailView(item: items[1]).frame(width: hw, height: hh).clipped()
                            if items.count > 3 {
                                AsyncThumbnailView(item: items[3]).frame(width: hw, height: hh).clipped()
                            } else {
                                Color.primary.opacity(0.08).frame(width: hw, height: hh)
                            }
                        }
                    }
                }.cornerRadius(12).clipped()
            }

            // 底部渐变信息栏
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80).cornerRadius(12)
            }
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collection.name).font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Text("\(collection.wallpaperIds.count) 张壁纸").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }.padding(12)
            }

            // hover 遮罩
            if isHovered {
                Color.black.opacity(0.25).cornerRadius(12)
                // 进入按钮（中央）
                Button(action: { viewModel.selectedCollectionId = collection.id }) {
                    Text("进入合集").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .padding(.vertical, 8).padding(.horizontal, 20)
                        .background(.ultraThinMaterial).clipShape(Capsule())
                }.buttonStyle(.plain)
                // 删除按钮（右上角）
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { viewModel.deleteCollection(id: collection.id) }) {
                            Image(systemName: "trash.fill").font(.system(size: 12)).foregroundColor(.white)
                                .padding(8).background(Color.red.opacity(0.8)).clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        }.buttonStyle(.plain).padding(8)
                    }
                    Spacer()
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .shadow(color: Color.primary.opacity(isHovered ? 0.2 : 0.05), radius: isHovered ? 10 : 4, y: isHovered ? 5 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { viewModel.selectedCollectionId = collection.id }
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
                        ZStack(alignment: .topTrailing) {
                            WallpaperCardView(item: item, viewModel: viewModel)
                                .aspectRatio(16/10, contentMode: .fit)
                            Button(action: { viewModel.deleteLocalImport(item) }) {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.red)
                                    .background(Circle().fill(Color.white).padding(2))
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

// ============== 底部栏代码保持不变 =================
struct BottomFloatingBarView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHotSelected = false; @State private var jumpPageText = ""
    let types = ["全部", "静态壁纸", "动态壁纸"]
    let categories = ["全部", "魅力 | 迷人", "自制 | 艺术", "安逸 | 自由", "科幻 | 星云", "动漫 | 二次元", "自然 | 风景", "游戏 | 玩具"]
    let resolutions = ["全部", "1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K"]
    let colors: [(String, Color?)] = [("全部", nil), ("偏蓝", Color(hex: "#28A7D0")), ("偏绿", Color(hex: "#449B3E")), ("偏红", Color(hex: "#873229")), ("灰/白", Color.gray.opacity(0.6)), ("紫/粉", Color(hex: "#A030C8")), ("暗色", Color(hex: "#333333")), ("偏黄", Color(hex: "#C6AC2C")), ("其他颜色", nil)]
    var body: some View { VStack(spacing: 16) { HStack(spacing: 12) { HStack { TextField("插画、简单、动漫...", text: $viewModel.searchText).textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.primary) }.padding(.horizontal, 16).padding(.vertical, 10).frame(width: 180).background(capsuleBgColor).clipShape(Capsule()); HStack(spacing: 6) { Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isHotSelected.toggle() } }) { FilterTagView(title: "昨日热门", isSelected: isHotSelected) }.buttonStyle(.plain); Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { viewModel.showTypeMenu.toggle(); if viewModel.showTypeMenu { closeOtherMenus(except: "Type") } } }) { FilterTagView(title: viewModel.selectedType == "全部" ? "种类" : viewModel.selectedType, icon: "square.grid.2x2", isSelected: viewModel.showTypeMenu || viewModel.selectedType != "全部") }.buttonStyle(.plain).overlay(alignment: .bottom) { if viewModel.showTypeMenu { MenuPopoverView(options: types, selected: $viewModel.selectedType) { viewModel.showTypeMenu = false }.offset(y: -46) } }; Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { viewModel.showCategoryMenu.toggle(); if viewModel.showCategoryMenu { closeOtherMenus(except: "Category") } } }) { let displayTitle = viewModel.selectedCategory == "全部" ? "分类" : (viewModel.selectedCategory.components(separatedBy: " | ").first ?? "分类"); FilterTagView(title: displayTitle, icon: "tag", isSelected: viewModel.showCategoryMenu || viewModel.selectedCategory != "全部") }.buttonStyle(.plain).overlay(alignment: .bottom) { if viewModel.showCategoryMenu { MenuPopoverView(options: categories, selected: $viewModel.selectedCategory) { viewModel.showCategoryMenu = false }.offset(y: -46) } }; Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { viewModel.showResolutionMenu.toggle(); if viewModel.showResolutionMenu { closeOtherMenus(except: "Resolution") } } }) { FilterTagView(title: viewModel.selectedResolution == "全部" ? "分辨率" : viewModel.selectedResolution, icon: "tv", isSelected: viewModel.showResolutionMenu || viewModel.selectedResolution != "全部") }.buttonStyle(.plain).overlay(alignment: .bottom) { if viewModel.showResolutionMenu { ResolutionPopoverView(viewModel: viewModel, options: resolutions).offset(y: -46) } }; Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { viewModel.showColorMenu.toggle(); if viewModel.showColorMenu { closeOtherMenus(except: "Color") } } }) { FilterTagView(title: viewModel.selectedColor == "全部" ? "色系" : viewModel.selectedColor, icon: "paintpalette", isSelected: viewModel.showColorMenu || viewModel.selectedColor != "全部") }.buttonStyle(.plain).overlay(alignment: .bottom) { if viewModel.showColorMenu { ColorPopoverView(options: colors, selected: $viewModel.selectedColor) { viewModel.showColorMenu = false }.offset(y: -46) } }; Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { viewModel.showOnlyFavorites.toggle() } }) { FilterTagView(title: "收藏", icon: viewModel.showOnlyFavorites ? "heart.fill" : "heart", isSelected: viewModel.showOnlyFavorites) }.buttonStyle(.plain) }; HStack(spacing: 8) { Button(action:{}) { Image(systemName: "viewfinder").font(.system(size: 14)).padding(10).background(capsuleBgColor).clipShape(Circle()) }.buttonStyle(.plain) } }.padding(.horizontal, 10).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)).shadow(color: Color.black.opacity(0.1), radius: 15, y: 8); HStack(spacing: 16) { Button(action: { viewModel.currentPage -= 1 }) { Image(systemName: "arrow.left").font(.system(size: 12, weight: .bold)) }.buttonStyle(.plain).disabled(viewModel.currentPage == 0).foregroundColor(viewModel.currentPage == 0 ? Color.primary.opacity(0.3) : Color.primary); HStack(spacing: 10) { ForEach(0..<min(viewModel.totalPages, 3), id: \.self) { index in PageNumberCircleView(number: index + 1, isCurrent: viewModel.currentPage == index) { viewModel.currentPage = index } }; if viewModel.totalPages > 3 { Text("...").foregroundColor(.primary.opacity(0.6)).font(.system(size: 12, weight: .bold)); PageNumberCircleView(number: viewModel.totalPages, isCurrent: viewModel.currentPage == viewModel.totalPages - 1) { viewModel.currentPage = viewModel.totalPages - 1 } } }; HStack(spacing: 8) { TextField("页码", text: $jumpPageText).textFieldStyle(.plain).font(.system(size: 12)).multilineTextAlignment(.center).frame(width: 36, height: 24).background(Color.primary.opacity(0.05)).cornerRadius(4).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.1), lineWidth: 1)); Button(action: { if let targetPage = Int(jumpPageText), targetPage >= 1, targetPage <= viewModel.totalPages { withAnimation { viewModel.currentPage = targetPage - 1 }; jumpPageText = "" } }) { Text("Go").font(.system(size: 13, weight: .bold)).foregroundColor(.accentColor) }.buttonStyle(.plain) }.padding(.leading, 10); Button(action: { viewModel.currentPage += 1 }) { Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)) }.buttonStyle(.plain).disabled(viewModel.currentPage >= viewModel.totalPages - 1).foregroundColor(viewModel.currentPage >= viewModel.totalPages - 1 ? Color.primary.opacity(0.3) : Color.primary) } } }
    private func closeOtherMenus(except name: String) { if name != "Type" { viewModel.showTypeMenu = false }; if name != "Category" { viewModel.showCategoryMenu = false }; if name != "Resolution" { viewModel.showResolutionMenu = false }; if name != "Color" { viewModel.showColorMenu = false } }
}

struct HoverableMenuRow: View { let option: String; @Binding var selected: String; let action: () -> Void; @State private var isHovered = false; var body: some View { Button(action: action) { Text(option).font(.system(size: 14, weight: selected == option ? .bold : .medium)).foregroundColor(selected == option ? .white : (isHovered ? .white : .white.opacity(0.8))).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8).padding(.horizontal, 16).background(isHovered ? Color.white.opacity(0.15) : Color.clear).cornerRadius(6).contentShape(Rectangle()) }.buttonStyle(.plain).onHover { isHovered = $0 } } }
struct MenuPopoverView: View { let options: [String]; @Binding var selected: String; let closeAction: () -> Void; var body: some View { VStack(spacing: 4) { ForEach(options, id: \.self) { option in HoverableMenuRow(option: option, selected: $selected) { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = option; closeAction() } } } }.padding(.vertical, 12).padding(.horizontal, 12).fixedSize().background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).environment(\.colorScheme, .dark)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1)).shadow(color: Color.black.opacity(0.4), radius: 15, y: 5).transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)) } }
struct HoverableColorRow: View { let option: (String, Color?); @Binding var selected: String; let action: () -> Void; @State private var isHovered = false; var body: some View { Button(action: action) { HStack(spacing: 0) { Text(option.0).font(.system(size: 14, weight: selected == option.0 ? .bold : .medium)).foregroundColor(selected == option.0 ? .white : (isHovered ? .white : .white.opacity(0.8))); Spacer(); if let color = option.1 { Circle().fill(color).frame(width: 14, height: 14) } else if option.0 == "其他颜色" { Circle().fill(AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .red]), center: .center)).frame(width: 14, height: 14) } else { Spacer().frame(width: 14) } }.padding(.vertical, 8).padding(.horizontal, 12).background(isHovered ? Color.white.opacity(0.15) : Color.clear).cornerRadius(6).contentShape(Rectangle()) }.buttonStyle(.plain).onHover { isHovered = $0 } } }
struct ColorPopoverView: View { let options: [(String, Color?)]; @Binding var selected: String; let closeAction: () -> Void; var body: some View { let contentHeight = CGFloat(options.count) * 40.0 + 24.0; let finalHeight = min(contentHeight, 280.0); ScrollView(showsIndicators: false) { VStack(spacing: 4) { ForEach(options, id: \.0) { option in HoverableColorRow(option: option, selected: $selected) { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = option.0; closeAction() } } } }.padding(.vertical, 12).padding(.horizontal, 12) }.frame(width: 150, height: finalHeight).background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).environment(\.colorScheme, .dark)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1)).shadow(color: Color.black.opacity(0.3), radius: 15, y: 5).transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity)) } }
struct HoverableResolutionRow: View { let option: String; @Binding var selected: String; let action: () -> Void; @State private var isHovered = false; var body: some View { Button(action: action) { Text(option).font(.system(size: 14, weight: selected == option ? .bold : .medium)).foregroundColor(selected == option ? .white : (isHovered ? .white : .white.opacity(0.8))).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.horizontal, 12).background(isHovered ? Color.white.opacity(0.15) : Color.clear).cornerRadius(6).contentShape(Rectangle()) }.buttonStyle(.plain).onHover { isHovered = $0 } } }
struct ResolutionPopoverView: View { @ObservedObject var viewModel: WallpaperViewModel; let options: [String]; var body: some View { VStack(spacing: 0) { VStack(spacing: 4) { ForEach(options, id: \.self) { option in HoverableResolutionRow(option: option, selected: $viewModel.selectedResolution) { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { viewModel.selectedResolution = option; viewModel.showResolutionMenu = false } } } }.padding(.all, 12); Divider().background(Color.white.opacity(0.1)); VStack(alignment: .leading, spacing: 12) { Text("自定义：").font(.system(size: 12)).foregroundColor(.white.opacity(0.8)); HStack(spacing: 10) { CustomDashedTextField(placeholder: "例: 1920", text: $viewModel.customWidth); Text("×").foregroundColor(.gray); CustomDashedTextField(placeholder: "例: 1080", text: $viewModel.customHeight) }; Text("提示：【可单项查询】 【点击空白处触发搜索】").font(.system(size: 10)).foregroundColor(.gray.opacity(0.8)) }.padding(.all, 20) }.fixedSize().background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).environment(\.colorScheme, .dark)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1)).shadow(color: Color.black.opacity(0.4), radius: 15, y: 5).transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)) } }
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
