//
//  WallpaperViewModel.swift
//  SimpleWallpaper
//

import SwiftUI
import AppKit
import AVKit
import Combine
import ServiceManagement
import CryptoKit

enum UploadMode: String {
    case pending = "待上传列表"
    case manage  = "云端壁纸管理"
}

class WallpaperViewModel: ObservableObject {

    // MARK: - 全量数据（用于已下载/轮播等本地标签页）
    @Published var allWallpapers: [WallpaperItem] = []

    // MARK: - 搜索结果（Meilisearch，用于「电脑壁纸」标签页）
    @Published var searchResults: [WallpaperItem] = []
    @Published var totalSearchPages: Int = 1
    @Published var isSearching: Bool = false

    @Published var statusMessage: String = ""
    @Published var currentPage: Int = 0 {
        didSet {
            if currentTab == .pc && oldValue != currentPage { performSearch() }
        }
    }
    let itemsPerPage: Int = 12

    @Published var isAutoStartEnabled: Bool = false
    @Published var cacheSizeString: String = "0 MB"

    @Published var currentTab: AppTab = .pc {
        didSet {
            currentPage = 0
            selectedCollectionId = nil
            if currentTab == .pc { performSearch() }
        }
    }
    @Published var searchText: String = ""
    @Published var previewItem: WallpaperItem? = nil
    @Published var currentWallpaperPath: String = ""
    @Published var uploadMode: UploadMode = .pending { didSet { currentPage = 0 } }

    @Published var showTypeMenu: Bool = false
    @Published var showCategoryMenu: Bool = false
    @Published var showResolutionMenu: Bool = false
    @Published var showColorMenu: Bool = false

    @Published var selectedType: String = "全部" {
        didSet { currentPage = 0; if currentTab == .pc { performSearch() } else { objectWillChange.send() } }
    }
    @Published var selectedCategory: String = "全部" {
        didSet { currentPage = 0; if currentTab == .pc { performSearch() } else { objectWillChange.send() } }
    }
    @Published var selectedResolution: String = "全部" {
        didSet { currentPage = 0; if currentTab == .pc { performSearch() } else { objectWillChange.send() } }
    }
    @Published var selectedColor: String = "全部" {
        didSet { currentPage = 0; if currentTab == .pc { performSearch() } else { objectWillChange.send() } }
    }
    @Published var customWidth: String = ""
    @Published var customHeight: String = ""

    @Published var isSlideshowEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isSlideshowEnabled, forKey: "isSlideshowEnabled"); setupSlideshowTimer() }
    }
    @Published var slideshowInterval: Double = 3600 {
        didSet { UserDefaults.standard.set(slideshowInterval, forKey: "slideshowInterval"); setupSlideshowTimer() }
    }
    @Published var isSlideshowRandom: Bool = false {
        didSet { UserDefaults.standard.set(isSlideshowRandom, forKey: "isSlideshowRandom") }
    }
    @Published var nextSlideshowCountdown: String = ""
    @Published var playlistIds: [String] = [] {
        didSet { UserDefaults.standard.set(playlistIds, forKey: "playlistIds"); setupSlideshowTimer() }
    }
    @Published var favoriteIds: [String] = [] {
        didSet { UserDefaults.standard.set(favoriteIds, forKey: "favoriteIds") }
    }
    @Published var showOnlyFavorites: Bool = false {
        didSet { currentPage = 0; if currentTab == .pc { performSearch() } }
    }
    @Published var wallpaperFit: WallpaperFit = .fill {
        didSet { UserDefaults.standard.set(wallpaperFit.rawValue, forKey: "wallpaperFit") }
    }
    @Published var targetScreenName: String = "全部" {
        didSet { UserDefaults.standard.set(targetScreenName, forKey: "targetScreenName") }
    }
    @Published var showAbout: Bool = false

    // MARK: - 登录状态
    @Published var currentUser: AuthUser? = nil
    @Published var showLoginSheet: Bool = false
    var isLoggedIn: Bool { currentUser != nil }

    // MARK: - 开发者标识（从 Secrets.plist 读取）
    let developerUserId: String = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String]
        else { return "" }
        return dict["DeveloperUserId"] ?? ""
    }()

    var isDeveloper: Bool {
        guard !developerUserId.isEmpty, let uid = currentUser?.id else { return false }
        return uid == developerUserId
    }

    // MARK: - 用户空间
    @Published var currentProfile: UserProfile? = nil {
        didSet { persistProfile() }
    }

    private func persistProfile() {
        if let profile = currentProfile, let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "cachedUserProfile")
        } else {
            UserDefaults.standard.removeObject(forKey: "cachedUserProfile")
        }
    }

    private func loadPersistedProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: "cachedUserProfile"),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else { return nil }
        return profile
    }
    @Published var showUserSpace: Bool = false {
        didSet { if !showUserSpace { showEditProfile = false; showChangePassword = false } }
    }
    @Published var showEditProfile: Bool = false
    @Published var showChangePassword: Bool = false
    @Published var localImports: [WallpaperItem] = []
    @Published var userUploads: [WallpaperItem] = []
    @Published var isLoadingUserUploads: Bool = false

    // MARK: - 已下载 tab 子分类
    @Published var downloadedSubTab: DownloadedSubTab = .local

    var availableScreenNames: [String] { ["全部"] + NSScreen.screens.map { $0.localizedName } }

    @Published var pendingUploads: [PendingUploadItem] = []
    @Published var uploadProgress: [UUID: Double] = [:]

    // MARK: - 合集
    @Published var collections: [WallpaperCollection] = []
    @Published var selectedCollectionId: String? = nil
    @Published var addToCollectionTargetItem: WallpaperItem? = nil

    // MARK: - 编辑状态
    @Published var editingWallpaper: WallpaperItem? = nil
    @Published var editTitle: String = ""
    @Published var editDescription: String = ""
    @Published var editTags: String = ""
    @Published var editCategory: String = ""
    @Published var editResolution: String = ""
    @Published var editColor: String = ""

    @Published var downloadProgress: [String: Double] = [:]
    @Published var failedDownloadIds: Set<String> = []
    private var progressObservations: [String: NSKeyValueObservation] = [:]

    private var slideshowTimer: Timer?
    private var countdownTimer: Timer?
    private var nextSlideshowDate: Date = Date()
    private var currentSlideshowIndex = 0
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    // MARK: - 显示数据

    var displayWallpapers: [WallpaperItem] {
        switch currentTab {
        case .pc:
            // 电脑壁纸标签：结果来自 Meilisearch，只需在本地处理收藏过滤
            if showOnlyFavorites {
                return searchResults.filter { favoriteIds.contains($0.id) }
            }
            return searchResults

        case .downloaded:
            if downloadedSubTab == .localImports { return localImports }
            let base = allWallpapers.filter {
                FileManager.default.fileExists(atPath: WallpaperCacheManager.shared.getLocalPath(for: $0.fullURL).path)
            }
            return applyLocalFilters(to: base)

        case .slideshow:
            let base = allWallpapers.filter {
                playlistIds.contains($0.id) &&
                FileManager.default.fileExists(atPath: WallpaperCacheManager.shared.getLocalPath(for: $0.fullURL).path)
            }
            return applyLocalFilters(to: base)

        case .collection:
            guard let collectionId = selectedCollectionId,
                  let collection = collections.first(where: { $0.id == collectionId }) else { return [] }
            return applyLocalFilters(to: allWallpapers.filter { collection.wallpaperIds.contains($0.id) })

        case .upload:
            // 开发者看全部；普通用户的管理模式只看自己的上传
            return isDeveloper ? allWallpapers : userUploads
        }
    }

    /// 本地过滤：统一用于 downloaded / slideshow 标签页
    private func applyLocalFilters(to items: [WallpaperItem]) -> [WallpaperItem] {
        var result = items
        if showOnlyFavorites { result = result.filter { favoriteIds.contains($0.id) } }
        if selectedType == "静态壁纸"     { result = result.filter { !$0.isVideo } }
        else if selectedType == "动态壁纸" { result = result.filter { $0.isVideo } }
        if selectedCategory != "全部" {
            let cat = selectedCategory.components(separatedBy: " | ").first ?? selectedCategory
            result = result.filter { $0.category == cat }
        }
        if selectedResolution != "全部" {
            result = result.filter { $0.resolution == selectedResolution }
        }
        if selectedColor != "全部" {
            result = result.filter { $0.color == selectedColor }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.wallpaperDescription.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }
        return result
    }

    var totalPages: Int {
        switch currentTab {
        case .pc:       return max(1, totalSearchPages)
        default:        return max(1, Int(ceil(Double(displayWallpapers.count) / Double(itemsPerPage))))
        }
    }

    var paginatedImages: [WallpaperItem] {
        switch currentTab {
        case .pc:
            return displayWallpapers   // Meilisearch 已分页，直接返回
        default:
            let items = displayWallpapers
            let start = currentPage * itemsPerPage
            let end = min(start + itemsPerPage, items.count)
            guard start < end else { return [] }
            return Array(items[start..<end])
        }
    }

    // MARK: - Init

    init() {
        if #available(macOS 13.0, *) { self.isAutoStartEnabled = SMAppService.mainApp.status == .enabled }
        calculateCacheSize()
        self.isSlideshowEnabled = UserDefaults.standard.bool(forKey: "isSlideshowEnabled")
        let savedInterval = UserDefaults.standard.double(forKey: "slideshowInterval")
        self.slideshowInterval = savedInterval == 0 ? 3600 : savedInterval
        self.playlistIds = UserDefaults.standard.stringArray(forKey: "playlistIds") ?? []
        self.isSlideshowRandom = UserDefaults.standard.bool(forKey: "isSlideshowRandom")
        self.favoriteIds = UserDefaults.standard.stringArray(forKey: "favoriteIds") ?? []
        if let fitRaw = UserDefaults.standard.string(forKey: "wallpaperFit"),
           let fit = WallpaperFit(rawValue: fitRaw) { self.wallpaperFit = fit }
        self.targetScreenName = UserDefaults.standard.string(forKey: "targetScreenName") ?? "全部"
        setupSlideshowTimer()
        self.currentWallpaperPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        loadCollections()
        loadLocalImports()

        // 恢复登录会话，若已登录则同步云端合集
        self.currentUser = AuthService.shared.currentUser
        if self.currentUser != nil {
            self.currentProfile = loadPersistedProfile()
        }
        if self.currentUser != nil {
            Task {
                await syncCollectionsFromCloud()
                await fetchUserProfile()
                await fetchUserUploads()
            }
        }

        // 搜索文本防抖 300ms
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.currentTab == .pc {
                    self.currentPage = 0
                    self.performSearch()
                } else {
                    self.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .randomWallpaperTrigger)
            .sink { [weak self] _ in self?.randomWallpaper() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .authCallbackCompleted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.currentUser = AuthService.shared.currentUser
                Task {
                    await self.syncCollectionsFromCloud()
                    await self.fetchUserProfile()
                    await self.fetchUserUploads()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Meilisearch 搜索

    func performSearch() {
        searchTask?.cancel()
        searchTask = Task {
            await MainActor.run { isSearching = true }
            do {
                var filters: [String] = []
                if selectedType == "静态壁纸"      { filters.append("isVideo = false") }
                else if selectedType == "动态壁纸"  { filters.append("isVideo = true") }

                if selectedCategory != "全部" {
                    let cat = selectedCategory.components(separatedBy: " | ").first ?? selectedCategory
                    filters.append("category = \"\(cat)\"")
                }
                if selectedResolution != "全部" {
                    filters.append("resolution = \"\(selectedResolution)\"")
                }
                if selectedColor != "全部" {
                    filters.append("color = \"\(selectedColor)\"")
                }

                // 电脑壁纸只展示开发者或无 uploadedBy 的公共壁纸
                if !developerUserId.isEmpty {
                    filters.append("(uploaded_by = \"\(developerUserId)\" OR uploaded_by NOT EXISTS)")
                }

                let response = try await MeilisearchService.shared.search(
                    query: searchText,
                    filters: filters,
                    page: currentPage,
                    hitsPerPage: itemsPerPage
                )

                if !Task.isCancelled {
                    await MainActor.run {
                        searchResults = response.hits
                        totalSearchPages = response.totalPages
                        isSearching = false
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { isSearching = false }
                }
            }
        }
    }

    // MARK: - 云端数据加载

    func fetchCloudData() {
        Task {
            // 确保 uploaded_by 已加入过滤字段（幂等）
            try? await MeilisearchService.shared.configureIndex()
            do {
                let items = try await MeilisearchService.shared.getAllDocuments()
                await MainActor.run { self.allWallpapers = items }
            } catch {
                await MainActor.run { self.statusMessage = "❌ 同步失败" }
            }
        }
        performSearch()
    }

    // MARK: - 随机换壁纸

    // MARK: - 预览弹窗导航

    /// 返回当前预览项在 paginatedImages 中的上一张和下一张
    func adjacentPreviewItems() -> (prev: WallpaperItem?, next: WallpaperItem?) {
        let items = paginatedImages
        guard let current = previewItem,
              let idx = items.firstIndex(where: { $0.id == current.id }) else { return (nil, nil) }
        return (idx > 0 ? items[idx - 1] : nil,
                idx < items.count - 1 ? items[idx + 1] : nil)
    }

    func randomWallpaper() {
        let downloaded = allWallpapers.filter {
            FileManager.default.fileExists(atPath: WallpaperCacheManager.shared.getLocalPath(for: $0.fullURL).path)
        }
        let pool = downloaded.isEmpty ? allWallpapers : downloaded
        guard let item = pool.randomElement() else { statusMessage = "⚠️ 暂无可用壁纸"; return }
        setWallpaper(item: item)
    }

    // MARK: - 本地导入

    func importLocalWallpaper() {
        let panel = NSOpenPanel()
        panel.title = "选择本地壁纸"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var added = 0
        for url in panel.urls {
            if addLocalImport(from: url) { added += 1 }
        }
        guard added > 0 else { return }
        statusMessage = "✅ 已导入 \(added) 张壁纸，可在个人中心查看"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.statusMessage.hasPrefix("✅ 已导入") { self.statusMessage = "" }
        }
    }

    /// 将文件复制到 local_imports 目录并追加到 localImports 列表，返回是否新增
    @discardableResult
    private func addLocalImport(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        guard !localImports.contains(where: { $0.id == hash }) else { return false }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let isVideo = ["mp4", "mov", "m4v", "avi"].contains(ext.lowercased())
        let destURL = localImportsDirectory.appendingPathComponent("\(hash).\(ext)")
        if !FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.copyItem(at: url, to: destURL)
        }
        let item = WallpaperItem(
            id: hash,
            title: url.deletingPathExtension().lastPathComponent,
            isVideo: isVideo,
            fullURL: destURL,
            uploadedAt: Int(Date().timeIntervalSince1970)
        )
        localImports.insert(item, at: 0)
        saveLocalImports()
        return true
    }

    func deleteLocalImport(_ item: WallpaperItem) {
        if item.fullURL.isFileURL {
            try? FileManager.default.removeItem(at: item.fullURL)
        }
        localImports.removeAll { $0.id == item.id }
        saveLocalImports()
    }

    private var localImportsDirectory: URL {
        let dir = WallpaperCacheManager.shared.cacheDirectory.appendingPathComponent("local_imports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadLocalImports() {
        guard let data = UserDefaults.standard.data(forKey: "localImports"),
              let items = try? JSONDecoder().decode([WallpaperItem].self, from: data)
        else { return }
        // 过滤掉文件已被删除的条目
        localImports = items.filter { FileManager.default.fileExists(atPath: $0.fullURL.path) }
    }

    private func saveLocalImports() {
        if let data = try? JSONEncoder().encode(localImports) {
            UserDefaults.standard.set(data, forKey: "localImports")
        }
    }

    // MARK: - 上传

    func selectFilesForUpload() {
        let panel = NSOpenPanel()
        panel.title = "选择要上传的壁纸或视频"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]
        if panel.runModal() == .OK {
            let newItems = panel.urls.map { PendingUploadItem(url: $0) }
            pendingUploads.append(contentsOf: newItems)
        }
    }

    func removePendingUpload(id: UUID) { pendingUploads.removeAll { $0.id == id } }
    func clearPendingUploads() { pendingUploads.removeAll() }

    func executeUpload() {
        guard !pendingUploads.isEmpty else { return }
        statusMessage = "🚀 开始处理 \(pendingUploads.count) 个文件..."
        Task {
            var newItems: [WallpaperItem] = []
            var successCount = 0
            var skipCount = 0
            let itemsToUpload = pendingUploads

            for (index, pendingItem) in itemsToUpload.enumerated() {
                await MainActor.run { self.statusMessage = "正在上传第 \(index + 1)/\(itemsToUpload.count) 个..." }
                do {
                    let fileData = try Data(contentsOf: pendingItem.url)
                    let hashString = SHA256.hash(data: fileData)
                        .compactMap { String(format: "%02x", $0) }.joined()

                    if self.allWallpapers.contains(where: { $0.id == hashString }) {
                        skipCount += 1
                        await MainActor.run { self.removePendingUpload(id: pendingItem.id) }
                        continue
                    }

                    let ext = pendingItem.url.pathExtension.lowercased()
                    let isVideo = ["mp4", "mov"].contains(ext)
                    let displayTitle = pendingItem.title.isEmpty
                        ? pendingItem.url.deletingPathExtension().lastPathComponent
                        : pendingItem.title
                    let tagsArray = pendingItem.tags
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let category = pendingItem.category.isEmpty ? ""
                        : (pendingItem.category.components(separatedBy: " | ").first ?? pendingItem.category)
                    let resolution = pendingItem.resolution
                    let color = pendingItem.color

                    let draft = WallpaperItem(
                        id: hashString,
                        title: displayTitle,
                        wallpaperDescription: pendingItem.wallpaperDescription,
                        tags: tagsArray,
                        category: category,
                        resolution: resolution,
                        color: color,
                        isVideo: isVideo,
                        fullURL: URL(string: "placeholder://")!,   // 上传后替换
                        uploadedAt: Int(Date().timeIntervalSince1970),
                        uploadedBy: currentUser?.id
                    )

                    await MainActor.run { self.uploadProgress[pendingItem.id] = 0 }
                    let uploaded = try await OSSUploader.shared.uploadFile(
                        fileURL: pendingItem.url,
                        fileData: fileData,
                        draft: draft,
                        onProgress: { p in
                            Task { @MainActor in self.uploadProgress[pendingItem.id] = p }
                        }
                    )
                    await MainActor.run { self.uploadProgress.removeValue(forKey: pendingItem.id) }

                    // 视频：截取首帧上传到 thumbnails/
                    if isVideo {
                        try? await OSSUploader.shared.uploadVideoThumbnail(
                            videoURL: pendingItem.url,
                            itemId: uploaded.id
                        )
                    }

                    try await MeilisearchService.shared.addDocuments([uploaded])
                    newItems.append(uploaded)
                    successCount += 1
                    await MainActor.run { self.removePendingUpload(id: pendingItem.id) }

                } catch {
                    await MainActor.run { self.uploadProgress.removeValue(forKey: pendingItem.id) }
                    print("❌ 上传失败: \(pendingItem.url.lastPathComponent), 错误: \(error)")
                }
            }

            await MainActor.run {
                if successCount > 0 {
                    self.allWallpapers = newItems + self.allWallpapers
                    // 普通用户上传后同步更新个人上传列表
                    if !self.isDeveloper {
                        self.userUploads = newItems + self.userUploads
                    }
                    self.statusMessage = "✅ 成功上传 \(successCount) 个素材（跳过重复 \(skipCount) 个）"
                } else {
                    self.statusMessage = skipCount > 0
                        ? "⚠️ \(skipCount) 个文件已存在，无需重复上传"
                        : "❌ 没有文件被成功上传"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.statusMessage = "" }
            }
        }
    }

    // MARK: - 编辑

    func beginEdit(item: WallpaperItem) {
        self.editingWallpaper = item
        self.editTitle = item.title
        self.editDescription = item.wallpaperDescription
        self.editTags = item.tags.joined(separator: ", ")
        self.editCategory = item.category.isEmpty ? "全部" : item.category
        self.editResolution = item.resolution.isEmpty ? "全部" : item.resolution
        self.editColor = item.color.isEmpty ? "全部" : item.color
    }

    func saveWallpaperEdit() {
        guard let item = editingWallpaper,
              let index = allWallpapers.firstIndex(where: { $0.id == item.id }) else { return }

        let tagsArray = editTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let updatedItem = WallpaperItem(
            id: item.id,
            title: editTitle.isEmpty ? item.title : editTitle,
            wallpaperDescription: editDescription,
            tags: tagsArray,
            category: editCategory == "全部" ? "" : (editCategory.components(separatedBy: " | ").first ?? editCategory),
            resolution: editResolution == "全部" ? "" : editResolution,
            color: editColor == "全部" ? "" : editColor,
            isVideo: item.isVideo,
            fullURL: item.fullURL,
            uploadedAt: item.uploadedAt
        )

        var newWallpapers = allWallpapers
        newWallpapers[index] = updatedItem
        statusMessage = "正在同步修改..."

        Task {
            do {
                try await MeilisearchService.shared.updateDocuments([updatedItem])
                await MainActor.run {
                    self.allWallpapers = newWallpapers
                    self.editingWallpaper = nil
                    self.statusMessage = "✅ 属性修改成功！"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.statusMessage == "✅ 属性修改成功！" { self.statusMessage = "" }
                    }
                }
            } catch {
                await MainActor.run { self.statusMessage = "❌ 修改失败，请检查网络" }
            }
        }
    }

    func cancelEdit() { self.editingWallpaper = nil }

    // MARK: - 合集

    private func loadCollections() {
        if let data = UserDefaults.standard.data(forKey: "wallpaperCollections"),
           let decoded = try? JSONDecoder().decode([WallpaperCollection].self, from: data) {
            self.collections = decoded
        }
    }

    private func saveCollections() {
        if let data = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(data, forKey: "wallpaperCollections")
        }
    }

    func createCollection(name: String) {
        let collection = WallpaperCollection(name: name)
        collections.append(collection)
        saveCollections()
        if isLoggedIn { Task { try? await AuthService.shared.upsertCollection(collection) } }
        statusMessage = "✅ 合集「\(name)」已创建"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.statusMessage.contains("合集") { self.statusMessage = "" }
        }
    }

    func deleteCollection(id: String) {
        collections.removeAll { $0.id == id }
        if selectedCollectionId == id { selectedCollectionId = nil }
        saveCollections()
        if isLoggedIn { Task { try? await AuthService.shared.deleteCloudCollection(id: id) } }
    }

    func toggleWallpaperInCollection(itemId: String, collectionId: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        if collections[index].wallpaperIds.contains(itemId) {
            collections[index].wallpaperIds.removeAll { $0 == itemId }
            collections[index].coverWallpaperId = collections[index].wallpaperIds.first ?? ""
        } else {
            collections[index].wallpaperIds.append(itemId)
            if collections[index].coverWallpaperId.isEmpty {
                collections[index].coverWallpaperId = itemId
            }
        }
        saveCollections()
        if isLoggedIn, let collection = collections.first(where: { $0.id == collectionId }) {
            Task { try? await AuthService.shared.upsertCollection(collection) }
        }
    }

    func isItemInAnyCollection(_ item: WallpaperItem) -> Bool {
        collections.contains { $0.wallpaperIds.contains(item.id) }
    }

    func setCoverWallpaper(for collectionId: String, wallpaperId: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        collections[index].coverWallpaperId = wallpaperId
        saveCollections()
        if isLoggedIn, let collection = collections.first(where: { $0.id == collectionId }) {
            Task { try? await AuthService.shared.upsertCollection(collection) }
        }
        statusMessage = "✅ 已设为合集封面"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.statusMessage.contains("封面") { self.statusMessage = "" }
        }
    }

    // MARK: - 登录 / 登出 / 云同步

    func logout() {
        Task {
            await AuthService.shared.signOut()
            await MainActor.run {
                self.currentUser = nil
                self.currentProfile = nil
            }
        }
    }

    func syncCollectionsFromCloud() async {
        guard let user = currentUser else { return }
        do {
            let cloudCollections = try await AuthService.shared.fetchCollections(userId: user.id)
            await MainActor.run {
                self.collections = cloudCollections
                self.saveCollections()
            }
        } catch { }
    }

    // MARK: - 用户空间

    func fetchUserProfile() async {
        guard let user = currentUser else { return }
        do {
            let profile = try await AuthService.shared.fetchProfile(userId: user.id)
            await MainActor.run {
                self.currentProfile = profile ?? UserProfile(id: user.id, username: "", avatarURL: "")
            }
        } catch { }
    }

    func saveProfile(username: String, avatarImageData: Data?) async {
        guard let user = currentUser else { return }
        do {
            var avatarURL = currentProfile?.avatarURL ?? ""
            if let data = avatarImageData {
                avatarURL = try await OSSUploader.shared.uploadAvatar(userId: user.id, imageData: data)
            }
            let profile = UserProfile(id: user.id, username: username, avatarURL: avatarURL)
            try await AuthService.shared.upsertProfile(profile)
            await MainActor.run {
                self.currentProfile = profile
                self.statusMessage = "✅ 资料已更新"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if self.statusMessage == "✅ 资料已更新" { self.statusMessage = "" }
            }
        } catch {
            await MainActor.run { self.statusMessage = "❌ 保存失败：\(error.localizedDescription)" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.statusMessage.hasPrefix("❌") { self.statusMessage = "" }
            }
        }
    }

    func fetchUserUploads() async {
        guard let user = currentUser else { return }
        await MainActor.run { isLoadingUserUploads = true }
        do {
            let uploads = try await MeilisearchService.shared.getUserUploads(userId: user.id)
            await MainActor.run {
                self.userUploads = uploads
                self.isLoadingUserUploads = false
            }
        } catch {
            await MainActor.run { isLoadingUserUploads = false }
        }
    }

    func changePassword(newPassword: String) async throws {
        try await AuthService.shared.changePassword(newPassword: newPassword)
    }

    // MARK: - 删除

    func deleteFromCloud(item: WallpaperItem) {
        guard let index = allWallpapers.firstIndex(where: { $0.id == item.id }) else { return }
        var newWallpapers = allWallpapers
        newWallpapers.remove(at: index)
        statusMessage = "正在从云端移除..."
        Task {
            do {
                try await MeilisearchService.shared.deleteDocument(id: item.id)
                try await OSSUploader.shared.deleteObject(for: item)
                if item.isVideo {
                    try? await OSSUploader.shared.deleteThumbnail(itemId: item.id)
                }
                await MainActor.run {
                    self.allWallpapers = newWallpapers
                    self.userUploads.removeAll { $0.id == item.id }
                    self.statusMessage = "🗑️ 已从云端彻底移除"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.statusMessage.contains("移除") { self.statusMessage = "" }
                    }
                }
            } catch {
                await MainActor.run { self.statusMessage = "❌ 移除失败: \(error.localizedDescription)" }
            }
        }
    }

    // MARK: - 下载 / 设置壁纸

    func downloadWallpaper(item: WallpaperItem) {
        if downloadProgress[item.id] != nil { return }
        failedDownloadIds.remove(item.id)
        DispatchQueue.main.async { self.downloadProgress[item.id] = 0.01 }
        Task {
            do {
                let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
                if !FileManager.default.fileExists(atPath: localURL.path) {
                    let tempURL = try await downloadWithProgress(url: item.fullURL, itemId: item.id, isSilent: false)
                    try FileManager.default.moveItem(at: tempURL, to: localURL)
                }
                await MainActor.run {
                    self.downloadProgress.removeValue(forKey: item.id)
                    self.calculateCacheSize()
                    self.objectWillChange.send()
                }
            } catch {
                if (error as? URLError)?.code != .cancelled {
                    await MainActor.run {
                        self.downloadProgress.removeValue(forKey: item.id)
                        self.failedDownloadIds.insert(item.id)
                    }
                }
            }
        }
    }

    func retryDownload(item: WallpaperItem) {
        failedDownloadIds.remove(item.id)
        downloadWallpaper(item: item)
    }

    func setWallpaper(item: WallpaperItem, isSilent: Bool = false) {
        if downloadProgress[item.id] != nil { return }
        if !isSilent { DispatchQueue.main.async { self.downloadProgress[item.id] = 0.01 } }
        Task {
            do {
                // 本地导入的壁纸直接使用文件路径，无需缓存
                let localURL: URL
                if item.fullURL.isFileURL && FileManager.default.fileExists(atPath: item.fullURL.path) {
                    localURL = item.fullURL
                } else {
                    let cachedURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
                    if !FileManager.default.fileExists(atPath: cachedURL.path) {
                        let tempURL = try await downloadWithProgress(url: item.fullURL, itemId: item.id, isSilent: isSilent)
                        try FileManager.default.moveItem(at: tempURL, to: cachedURL)
                    }
                    localURL = cachedURL
                }
                await MainActor.run {
                    self.downloadProgress.removeValue(forKey: item.id)
                    if item.isVideo {
                        DesktopVideoManager.shared.playVideoOnDesktop(url: localURL, screenName: self.targetScreenName)
                    } else {
                        DesktopVideoManager.shared.clearVideoWallpaper()
                        self.applyStaticWallpaper(url: localURL)
                        self.applyLockScreenWallpaper(url: localURL)
                    }
                    UserDefaults.standard.set(localURL.path, forKey: "LastWallpaperPath")
                    self.currentWallpaperPath = localURL.path
                    self.calculateCacheSize()
                    self.objectWillChange.send()
                    if !isSilent {
                        statusMessage = "🎉 设置完成"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            if self.statusMessage == "🎉 设置完成" { self.statusMessage = "" }
                        }
                    }
                }
                if item.isVideo { await syncLockScreenWallpaper(for: localURL) }
            } catch {
                if (error as? URLError)?.code != .cancelled, !isSilent {
                    await MainActor.run {
                        self.downloadProgress.removeValue(forKey: item.id)
                        self.statusMessage = "❌ 操作失败"
                    }
                }
            }
        }
    }

    // MARK: - 轮播 / 收藏

    func toggleInPlaylist(item: WallpaperItem) {
        if let index = playlistIds.firstIndex(of: item.id) {
            playlistIds.remove(at: index); statusMessage = "已移出轮播列表"
        } else {
            playlistIds.append(item.id); statusMessage = "🌟 已加入轮播"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.statusMessage.contains("轮播") { self.statusMessage = "" }
        }
    }

    func toggleFavorite(item: WallpaperItem) {
        if let index = favoriteIds.firstIndex(of: item.id) {
            favoriteIds.remove(at: index); statusMessage = "已取消收藏"
        } else {
            favoriteIds.append(item.id); statusMessage = "❤️ 已加入收藏"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.statusMessage.contains("收藏") { self.statusMessage = "" }
        }
    }

    // MARK: - 缓存

    func deleteSingleCache(for item: WallpaperItem) {
        let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
        if localURL.path == (UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? "") {
            statusMessage = "⚠️ 正在使用的壁纸无法删除"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.statusMessage.contains("⚠️") { self.statusMessage = "" }
            }
            return
        }
        try? FileManager.default.removeItem(at: localURL)
        if let idx = playlistIds.firstIndex(of: item.id) { playlistIds.remove(at: idx) }
        calculateCacheSize()
        objectWillChange.send()
        statusMessage = "🗑️ 已清除该壁纸缓存"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.statusMessage.contains("🗑️") { self.statusMessage = "" }
        }
    }

    func clearCache() {
        let currentPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        if let files = try? FileManager.default.contentsOfDirectory(
            at: WallpaperCacheManager.shared.cacheDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files {
                if file.path != currentPath && file.lastPathComponent != "lockscreen_sync.jpg" {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        playlistIds.removeAll()
        calculateCacheSize()
        objectWillChange.send()
        statusMessage = "✅ 缓存清理完成"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.statusMessage == "✅ 缓存清理完成" { self.statusMessage = "" }
        }
    }

    func calculateCacheSize() {
        var totalSize: Int64 = 0
        if let files = try? FileManager.default.contentsOfDirectory(
            at: WallpaperCacheManager.shared.cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for file in files {
                if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]),
                   let size = attrs.fileSize { totalSize += Int64(size) }
            }
        }
        DispatchQueue.main.async {
            self.cacheSizeString = String(format: "%.1f MB", Double(totalSize) / (1024 * 1024))
        }
    }

    // MARK: - 轮播计时器

    private func setupSlideshowTimer() {
        slideshowTimer?.invalidate()
        countdownTimer?.invalidate()
        nextSlideshowCountdown = ""
        guard isSlideshowEnabled && !playlistIds.isEmpty else { return }
        nextSlideshowDate = Date().addingTimeInterval(slideshowInterval)
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: slideshowInterval, repeats: true) { [weak self] _ in
            self?.playNextWallpaper()
            self?.nextSlideshowDate = Date().addingTimeInterval(self?.slideshowInterval ?? 3600)
        }
        if let t = slideshowTimer { RunLoop.main.add(t, forMode: .common) }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
        if let t = countdownTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func updateCountdown() {
        let remaining = max(0, nextSlideshowDate.timeIntervalSinceNow)
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        let s = Int(remaining) % 60
        nextSlideshowCountdown = h > 0
            ? "下次切换 \(h)h \(String(format: "%02d", m))m"
            : "下次切换 \(m):\(String(format: "%02d", s))"
    }

    func playNextWallpaper() {
        guard !playlistIds.isEmpty else { return }
        if isSlideshowRandom {
            currentSlideshowIndex = Int.random(in: 0..<playlistIds.count)
        } else {
            currentSlideshowIndex = (currentSlideshowIndex + 1) % playlistIds.count
        }
        if let item = allWallpapers.first(where: { $0.id == playlistIds[currentSlideshowIndex] }) {
            setWallpaper(item: item, isSilent: true)
        }
    }

    func triggerNextSlideshow() {
        playNextWallpaper()
        nextSlideshowDate = Date().addingTimeInterval(slideshowInterval)
    }

    // MARK: - 内部工具

    func restoreLastWallpaper() {
        guard let path = UserDefaults.standard.string(forKey: "LastWallpaperPath") else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            if url.pathExtension.lowercased() == "mp4" {
                DesktopVideoManager.shared.playVideoOnDesktop(url: url)
                Task { await syncLockScreenWallpaper(for: url) }
            }
        }
    }

    func toggleAutoStart(enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                self.isAutoStartEnabled = enable
            } catch {
                self.isAutoStartEnabled = !enable
            }
        }
    }

    private func syncLockScreenWallpaper(for videoURL: URL) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        do {
            let (cgImage, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            if let jpegData = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [:]) {
                let lockScreenURL = WallpaperCacheManager.shared.cacheDirectory
                    .appendingPathComponent("lockscreen_sync.jpg")
                try jpegData.write(to: lockScreenURL)
                await MainActor.run {
                    self.applyStaticWallpaper(url: lockScreenURL)
                    self.applyLockScreenWallpaper(url: lockScreenURL)
                }
            }
        } catch {}
    }

    private func downloadWithProgress(url: URL, itemId: String, isSilent: Bool = false) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
                DispatchQueue.main.async { self.progressObservations.removeValue(forKey: itemId) }
                if let error = error { continuation.resume(throwing: error); return }
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: URLError(.badServerResponse)); return
                }
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                try? FileManager.default.moveItem(at: tempURL, to: destination)
                continuation.resume(returning: destination)
            }
            if !isSilent {
                self.progressObservations[itemId] = task.progress.observe(\.fractionCompleted) { progress, _ in
                    DispatchQueue.main.async { self.downloadProgress[itemId] = progress.fractionCompleted }
                }
            }
            task.resume()
        }
    }

    private func applyStaticWallpaper(url: URL) {
        let options = wallpaperFit.desktopImageOptions
        let screens: [NSScreen]
        if targetScreenName == "全部" {
            screens = NSScreen.screens
        } else {
            let filtered = NSScreen.screens.filter { $0.localizedName == targetScreenName }
            screens = filtered.isEmpty ? NSScreen.screens : filtered
        }
        for screen in screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    /// 同步锁屏壁纸（macOS Ventura+ 锁屏与桌面分离，需单独设置）
    private func applyLockScreenWallpaper(url: URL) {
        guard let prefs = UserDefaults(suiteName: "com.apple.wallpaper") else { return }
        prefs.set(url.absoluteString, forKey: "SystemWallpaperURL")
        prefs.synchronize()
        // WallpaperAgent 只在启动时读取 SystemWallpaperURL，写入后需重启才生效
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.3) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            p.arguments = ["WallpaperAgent"]
            try? p.run()
        }
    }
}

// MARK: - Extensions

extension WallpaperFit {
    var desktopImageOptions: [NSWorkspace.DesktopImageOptionKey: Any] {
        switch self {
        case .fill:    return [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true]
        case .fit:     return [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: false]
        case .stretch: return [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,      .allowClipping: true]
        case .center:  return [.imageScaling: NSImageScaling.scaleNone.rawValue,                   .allowClipping: false]
        }
    }
}

extension Notification.Name {
    static let randomWallpaperTrigger = Notification.Name("com.panglou.wallpaper.random")
}
