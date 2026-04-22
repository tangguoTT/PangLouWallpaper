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
    case review  = "审核队列"
    case manage  = "云端壁纸管理"
}

/// 递归统计目录占用字节数（目录不存在时返回 0）
private func directorySize(at url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return 0 }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
        if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
           vals.isRegularFile == true,
           let size = vals.fileSize {
            total += Int64(size)
        }
    }
    return total
}

class WallpaperViewModel: ObservableObject {

    // MARK: - 全量数据（用于已下载/轮播等本地标签页）
    @Published var allWallpapers: [WallpaperItem] = [] {
        didSet { refreshDownloadedIds() }
    }

    /// 已缓存到本地的壁纸 ID 集合（异步计算，避免每帧渲染时同步调 fileExists）
    @Published private(set) var downloadedWallpaperIds: Set<String> = []

    private func refreshDownloadedIds() {
        let items = allWallpapers
        let cacheManager = WallpaperCacheManager.shared
        Task.detached(priority: .utility) { [weak self] in
            let ids = Set(items.compactMap { item -> String? in
                let path = cacheManager.getLocalPath(for: item.fullURL).path
                return FileManager.default.fileExists(atPath: path) ? item.id : nil
            })
            await MainActor.run { self?.downloadedWallpaperIds = ids }
        }
    }

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
    @Published var isEnergySavingEnabled: Bool = UserDefaults.standard.bool(forKey: "energySavingEnabled") {
        didSet { DesktopVideoManager.shared.isEnergySavingEnabled = isEnergySavingEnabled }
    }
    @Published var videoVolume: Float = UserDefaults.standard.float(forKey: "videoVolume") {
        didSet { DesktopVideoManager.shared.videoVolume = videoVolume }
    }
    @Published var cacheSizeString: String = "0 MB"
    @Published var cloudCacheSizeString: String = "计算中…"
    @Published var workshopCacheSizeString: String = "计算中…"
    @Published var localImportSizeString: String = "计算中…"
    @Published var cacheVersion: Int = 0
    @Published var cacheDirectoryPath: String = WallpaperCacheManager.shared.cacheDirectory.path

    // MARK: - 以图搜图
    @Published var imageSearchMode: Bool = false
    @Published var imageSearchQueryImage: NSImage? = nil
    @Published var isImageSearching: Bool = false
    @Published var imageSearchResults: [WallpaperItem] = []

    @Published var currentTab: AppTab = .pc {
        didSet {
            currentPage = 0
            selectedCollectionId = nil
            if isBatchSelectMode { isBatchSelectMode = false }
            if imageSearchMode { clearImageSearch() }
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
        didSet {
            UserDefaults.standard.set(isSlideshowEnabled, forKey: "isSlideshowEnabled")
            // 定时换壁纸和轮播互斥：开启轮播时自动关闭定时
            if isSlideshowEnabled && isTimedPeriodEnabled {
                isTimedPeriodEnabled = false
            }
            setupSlideshowTimer()
        }
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
    @Published var pendingReviewItems: [WallpaperItem] = []
    @Published var isLoadingReview: Bool = false

    // MARK: - 已下载 tab 子分类
    @Published var downloadedSubTab: DownloadedSubTab = .local {
        didSet {
            currentPage = 0
            if isBatchSelectMode { isBatchSelectMode = false }
        }
    }

    // MARK: - 批量操作
    @Published var isBatchSelectMode: Bool = false {
        didSet { if !isBatchSelectMode { batchSelectedIds.removeAll() } }
    }
    @Published var batchSelectedIds: Set<String> = []

    // MARK: - 定时换壁纸
    @Published var isTimedPeriodEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isTimedPeriodEnabled, forKey: "isTimedPeriodEnabled")
            // 定时换壁纸和轮播互斥：开启定时时自动关闭轮播
            if isTimedPeriodEnabled && isSlideshowEnabled {
                isSlideshowEnabled = false
            }
            setupPeriodTimer()
        }
    }
    @Published var periodWallpaperIds: [String: String] = [:] {
        didSet { savePeriodAssignments() }
    }
    @Published var periodPickerTargetPeriod: DayPeriod? = nil
    private var periodTimer: Timer?
    private var lastAppliedPeriod: DayPeriod? = nil

    var availableScreenNames: [String] { ["全部"] + NSScreen.screens.map { $0.localizedName } }

    @Published var pendingUploads: [PendingUploadItem] = []
    @Published var uploadProgress: [UUID: Double] = [:]
    @Published var isUploading: Bool = false
    private var uploadTask: Task<Void, Never>?

    // MARK: - 删除确认
    @Published var deleteConfirmItem: WallpaperItem? = nil

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
    private var activeTasks: [String: URLSessionDownloadTask] = [:]

    private var slideshowTimer: Timer?
    private var countdownTimer: Timer?
    private var nextSlideshowDate: Date = Date()
    private var currentSlideshowIndex = 0
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    // MARK: - 显示数据

    var displayWallpapers: [WallpaperItem] {
        if imageSearchMode { return imageSearchResults }
        switch currentTab {
        case .pc:
            return searchResults

        case .downloaded:
            switch downloadedSubTab {
            case .localImports:
                let ids = workshopImportIds
                return localImports.filter { !ids.contains($0.id) }
            case .workshop:
                let ids = workshopImportIds
                return localImports.filter { ids.contains($0.id) }
            case .local:
                let base = allWallpapers.filter { downloadedWallpaperIds.contains($0.id) }
                return applyLocalFilters(to: base)
            }

        case .slideshow:
            let base = allWallpapers.filter {
                playlistIds.contains($0.id) && downloadedWallpaperIds.contains($0.id)
            }
            return applyLocalFilters(to: base)

        case .collection:
            guard let collectionId = selectedCollectionId,
                  let collection = collections.first(where: { $0.id == collectionId }) else { return [] }
            return applyLocalFilters(to: allWallpapers.filter { collection.wallpaperIds.contains($0.id) })

        case .upload:
            // 开发者看全部；普通用户的管理模式只看自己的上传
            return isDeveloper ? allWallpapers : userUploads

        case .steamWorkshop:
            return []  // Workshop 使用独立的 workshopItems，不走此路径
        }
    }

    /// 本地过滤：统一用于 downloaded / slideshow 标签页
    private func applyLocalFilters(to items: [WallpaperItem]) -> [WallpaperItem] {
        var result = items
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
        // 👇 新增这一行：全局强制关闭 macOS 的“退出时保留窗口”特性
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        if #available(macOS 13.0, *) { self.isAutoStartEnabled = SMAppService.mainApp.status == .enabled }
        calculateCacheSize()
        self.isSlideshowEnabled = UserDefaults.standard.bool(forKey: "isSlideshowEnabled")
        let savedInterval = UserDefaults.standard.double(forKey: "slideshowInterval")
        self.slideshowInterval = savedInterval == 0 ? 3600 : savedInterval
        self.playlistIds = UserDefaults.standard.stringArray(forKey: "playlistIds") ?? []
        self.isSlideshowRandom = UserDefaults.standard.bool(forKey: "isSlideshowRandom")
        if let fitRaw = UserDefaults.standard.string(forKey: "wallpaperFit"),
           let fit = WallpaperFit(rawValue: fitRaw) { self.wallpaperFit = fit }
        self.targetScreenName = UserDefaults.standard.string(forKey: "targetScreenName") ?? "全部"
        setupSlideshowTimer()
        self.currentWallpaperPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        loadCollections()
        loadLocalImports()
        autoConfigureIndexIfNeeded()

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

        loadPeriodAssignments()
        setupPeriodTimer()
    }

    // MARK: - Meilisearch 搜索

    func performSearch() {
        searchTask?.cancel()
        searchTask = Task {
            await MainActor.run { isSearching = true }

            var baseFilters: [String] = []
            if selectedType == "静态壁纸"      { baseFilters.append("isVideo = false") }
            else if selectedType == "动态壁纸"  { baseFilters.append("isVideo = true") }
            if selectedCategory != "全部" {
                let cat = selectedCategory.components(separatedBy: " | ").first ?? selectedCategory
                baseFilters.append("category = \"\(cat)\"")
            }
            if selectedResolution != "全部" {
                baseFilters.append("resolution = \"\(selectedResolution)\"")
            }
            if selectedColor != "全部" {
                baseFilters.append("color = \"\(selectedColor)\"")
            }

            // 优先使用 NOT EXISTS（Meilisearch v1.2+）；失败时 fallback 到不带审核过滤，Swift 端再过滤
            let filtersWithNotExists = baseFilters + ["(approval_status = \"approved\" OR approval_status NOT EXISTS)"]
            let filtersWithoutApproval = baseFilters  // fallback：取回全部，Swift 端过滤

            do {
                let response = try await MeilisearchService.shared.search(
                    query: searchText,
                    filters: filtersWithNotExists,
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
                if Task.isCancelled { return }
                // NOT EXISTS 不可用（旧版 Meilisearch）→ 不带审核过滤重试，结果在 Swift 端过滤
                do {
                    let response = try await MeilisearchService.shared.search(
                        query: searchText,
                        filters: filtersWithoutApproval,
                        page: currentPage,
                        hitsPerPage: itemsPerPage
                    )
                    if !Task.isCancelled {
                        await MainActor.run {
                            searchResults = response.hits.filter { $0.isPubliclyVisible }
                            totalSearchPages = response.totalPages
                            isSearching = false
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        let msg = (error as? URLError)?.localizedDescription ?? error.localizedDescription
                        await MainActor.run {
                            isSearching = false
                            statusMessage = "❌ 加载失败：\(msg)"
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if self.statusMessage.hasPrefix("❌ 加载失败") { self.statusMessage = "" }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 云端数据加载

    func fetchCloudData() {
        Task {
            do {
                let items = try await MeilisearchService.shared.getAllDocuments()
                await MainActor.run { self.allWallpapers = items }
            } catch {
                let msg = (error as? URLError)?.localizedDescription ?? error.localizedDescription
                await MainActor.run { self.statusMessage = "❌ 同步失败：\(msg)" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if self.statusMessage.hasPrefix("❌ 同步失败") { self.statusMessage = "" }
                }
            }
        }
        performSearch()
    }

    /// 启动时检查：若 Meilisearch host 变更或从未配置过，则自动初始化索引设置
    private func autoConfigureIndexIfNeeded() {
        let currentHost = MeilisearchService.shared.currentHost
        let key = "meilisearchConfiguredHost"
        guard UserDefaults.standard.string(forKey: key) != currentHost else { return }
        Task {
            do {
                try await MeilisearchService.shared.configureIndex()
                UserDefaults.standard.set(currentHost, forKey: key)
            } catch {
                print("[Meilisearch] 自动索引配置失败：\(error.localizedDescription)")
            }
        }
    }

    /// 手动触发 Meilisearch 索引配置（仅需运行一次，供开发者调用）
    func reconfigureIndex() {
        Task {
            do {
                try await MeilisearchService.shared.configureIndex()
                await MainActor.run { self.statusMessage = "✅ 索引配置已更新" }
            } catch {
                await MainActor.run { self.statusMessage = "❌ 索引配置失败：\(error.localizedDescription)" }
            }
        }
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
        // 使用已缓存的 downloadedWallpaperIds，避免在主线程同步调用 fileExists
        let pool = downloadedWallpaperIds.isEmpty
            ? allWallpapers
            : allWallpapers.filter { downloadedWallpaperIds.contains($0.id) }
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
        calculateCacheSize()
        statusMessage = "✅ 已导入 \(added) 张壁纸，可在已下载壁纸-本地导入查看"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.statusMessage.hasPrefix("✅ 已导入") { self.statusMessage = "" }
        }
    }

    /// 将文件复制到 local_imports 目录并追加到 localImports 列表，返回是否新增
    /// 用于手动导入（文件选择器/拖拽）。对大文件会读入内存计算 SHA256，Workshop 文件请用 addWorkshopImport。
    @discardableResult
    private func addLocalImport(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        guard !localImports.contains(where: { $0.id == hash }) else { return false }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let isVideo = ["mp4", "mov", "m4v", "avi", "webm"].contains(ext.lowercased())
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

    @discardableResult
    private func addWorkshopImport(itemId: String, fileURL: URL) -> URL {
        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
        let isVideo = ["mp4", "mov", "m4v", "avi", "webm"].contains(ext.lowercased())
        let title = workshopItems.first(where: { $0.id == itemId })?.title ?? ""

        let destItemDir = WallpaperCacheManager.shared.workshopDirectory
            .appendingPathComponent(itemId)
        let destFileURL = destItemDir.appendingPathComponent(fileURL.lastPathComponent)

        let actualURL: URL
        if FileManager.default.fileExists(atPath: destFileURL.path) {
            // Already moved in a previous session
            actualURL = destFileURL
        } else {
            // Move the entire SteamCMD item directory so web wallpaper assets come along
            let srcItemDir = fileURL.deletingLastPathComponent()
            do {
                // Ensure parent exists but destItemDir itself must NOT exist for moveItem
                try FileManager.default.createDirectory(
                    at: destItemDir.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: srcItemDir, to: destItemDir)
                actualURL = destFileURL
            } catch {
                actualURL = fileURL   // fallback: keep original path
            }
        }

        // Only insert if not already tracked
        if !localImports.contains(where: { $0.id == itemId }) {
            let item = WallpaperItem(
                id: itemId,
                title: title,
                isVideo: isVideo,
                fullURL: actualURL,
                uploadedAt: Int(Date().timeIntervalSince1970)
            )
            localImports.insert(item, at: 0)
            var ids = workshopImportIds
            ids.insert(itemId)
            workshopImportIds = ids
            saveLocalImports()
        }
        return actualURL
    }

    func deleteLocalImport(_ item: WallpaperItem) {
        if workshopImportIds.contains(item.id) {
            // For workshop items: remove the entire app-managed directory (has all assets)
            let appItemDir = WallpaperCacheManager.shared.workshopDirectory
                .appendingPathComponent(item.id)
            try? FileManager.default.removeItem(at: appItemDir)
            // Also clean up the SteamCMD content dir in case the move failed and files are still there
            let steamDir = SteamWorkshopService.workshopItemDirectory(itemId: item.id)
            try? FileManager.default.removeItem(at: steamDir)
        } else if item.fullURL.isFileURL {
            try? FileManager.default.removeItem(at: item.fullURL)
        }
        localImports.removeAll { $0.id == item.id }
        var ids = workshopImportIds
        ids.remove(item.id)
        workshopImportIds = ids
        workshopDownloadStates.removeValue(forKey: item.id)
        saveLocalImports()
        calculateCacheSize()
    }

    private var localImportsDirectory: URL {
        let dir = WallpaperCacheManager.shared.cacheDirectory.appendingPathComponent("local_imports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Workshop 来源 ID 集合（持久化，用于与手动导入区分）

    private var workshopImportIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "workshopImportIds") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "workshopImportIds") }
    }

    func isWorkshopImport(_ item: WallpaperItem) -> Bool {
        workshopImportIds.contains(item.id)
    }

    private func loadLocalImports() {
        guard let data = UserDefaults.standard.data(forKey: "localImports"),
              let items = try? JSONDecoder().decode([WallpaperItem].self, from: data)
        else { return }
        var valid = items.filter { FileManager.default.fileExists(atPath: $0.fullURL.path) }

        // 迁移旧数据：若 workshopImportIds 为空，通过路径特征识别已有的 Workshop 条目
        if workshopImportIds.isEmpty {
            let detected = valid.filter { $0.fullURL.path.contains("steamapps/workshop") }
            if !detected.isEmpty {
                workshopImportIds = Set(detected.map { $0.id })
            }
        }

        // 迁移 Workshop 条目到统一 workshop/ 目录
        let workshopIds = workshopImportIds
        var needsSave = false
        for i in valid.indices {
            guard workshopIds.contains(valid[i].id) else { continue }
            let item = valid[i]
            let workshopItemDir = WallpaperCacheManager.shared.workshopDirectory
                .appendingPathComponent(item.id)
            // 已经在目标目录则跳过
            if item.fullURL.path.hasPrefix(workshopItemDir.path) { continue }
            try? FileManager.default.createDirectory(at: workshopItemDir, withIntermediateDirectories: true)
            let dest = workshopItemDir.appendingPathComponent(item.fullURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.moveItem(at: item.fullURL, to: dest)
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                valid[i].fullURL = dest
                needsSave = true
            }
        }

        localImports = valid
        if needsSave { saveLocalImports() }
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

    func cancelAllUploads() {
        uploadTask?.cancel()
        uploadTask = nil
        uploadProgress.removeAll()
        isUploading = false
        statusMessage = "⏹ 已停止上传"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.statusMessage.hasPrefix("⏹") { self.statusMessage = "" } }
    }

    func executeUpload() {
        guard !pendingUploads.isEmpty else { return }
        statusMessage = "🚀 开始处理 \(pendingUploads.count) 个文件..."
        isUploading = true
        uploadTask = Task {
            var newItems: [WallpaperItem] = []
            var successCount = 0
            var skipCount = 0
            // 遍历开始时的快照，但每项上传前检查是否已被用户从列表移除
            let itemsToUpload = pendingUploads

            for (index, pendingItem) in itemsToUpload.enumerated() {
                guard !Task.isCancelled else { break }
                // 用户已手动删除该项，直接跳过
                guard await MainActor.run(resultType: Bool.self, body: { self.pendingUploads.contains(where: { $0.id == pendingItem.id }) }) else { continue }
                await MainActor.run { self.statusMessage = "正在上传第 \(index + 1)/\(itemsToUpload.count) 个..." }
                do {
                    let fileData = try Data(contentsOf: pendingItem.url)
                    let hashString = SHA256.hash(data: fileData)
                        .compactMap { String(format: "%02x", $0) }.joined()

                    if await MainActor.run(resultType: Bool.self, body: { self.allWallpapers.contains(where: { $0.id == hashString }) }) {
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

                    // 开发者上传直接通过，普通用户需要审核
                    let uploadStatus: ApprovalStatus = self.isDeveloper ? .approved : .pending
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
                        uploadedBy: currentUser?.id,
                        approvalStatus: uploadStatus
                    )

                    await MainActor.run { self.uploadProgress[pendingItem.id] = 0 }
                    var uploaded = try await OSSUploader.shared.uploadFile(
                        fileURL: pendingItem.url,
                        fileData: fileData,
                        draft: draft,
                        onProgress: { p in
                            Task { @MainActor in self.uploadProgress[pendingItem.id] = p }
                        }
                    )
                    await MainActor.run { self.uploadProgress.removeValue(forKey: pendingItem.id) }

                    // 视频：截取首帧 + 生成轻量预览片段
                    if isVideo {
                        try? await OSSUploader.shared.uploadVideoThumbnail(
                            videoURL: pendingItem.url,
                            itemId: uploaded.id
                        )
                        if let previewURLStr = try? await OSSUploader.shared.uploadVideoPreview(
                            videoURL: pendingItem.url,
                            itemId: uploaded.id
                        ) {
                            uploaded.previewURL = URL(string: previewURLStr)
                        }
                    }

                    try await MeilisearchService.shared.addDocuments([uploaded])

                    // 后台存储图像特征向量，供以图搜图使用
                    let localURL = pendingItem.url
                    let uploadedId = uploaded.id
                    Task.detached(priority: .background) {
                        guard let vector = try? await ImageFeatureExtractor.extract(from: localURL) else { return }
                        let dim = vector.count
                        let savedDim = UserDefaults.standard.integer(forKey: "imageFeatureDimension")
                        if savedDim != dim {
                            try? await MeilisearchService.shared.configureVectorSearch(dimension: dim)
                            UserDefaults.standard.set(dim, forKey: "imageFeatureDimension")
                        }
                        try? await MeilisearchService.shared.updateDocumentVector(id: uploadedId, vector: vector)
                    }

                    newItems.append(uploaded)
                    successCount += 1
                    await MainActor.run {
                        // 每传完一张立即加入列表，管理界面实时可见
                        self.allWallpapers = [uploaded] + self.allWallpapers
                        if !self.isDeveloper { self.userUploads = [uploaded] + self.userUploads }
                        self.removePendingUpload(id: pendingItem.id)
                    }

                } catch {
                    await MainActor.run { self.uploadProgress.removeValue(forKey: pendingItem.id) }
                    print("❌ 上传失败: \(pendingItem.url.lastPathComponent), 错误: \(error)")
                }
            }

            await MainActor.run {
                self.isUploading = false
                self.uploadTask = nil
                if successCount > 0 {
                    // allWallpapers / userUploads 已在每张上传后实时更新，此处只更新状态
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
            previewURL: item.previewURL,
            uploadedAt: item.uploadedAt,
            uploadedBy: item.uploadedBy,
            approvalStatus: item.approvalStatus,
            rejectionReason: item.rejectionReason
        )

        var newWallpapers = allWallpapers
        newWallpapers[index] = updatedItem
        statusMessage = "正在同步修改..."

        Task {
            do {
                try await MeilisearchService.shared.updateDocuments([updatedItem])
                await MainActor.run {
                    self.allWallpapers = newWallpapers
                    // 同步更新 searchResults，避免「电脑壁纸」Tab 卡片显示旧元数据
                    if let srIdx = self.searchResults.firstIndex(where: { $0.id == updatedItem.id }) {
                        self.searchResults[srIdx] = updatedItem
                    }
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

    // MARK: - 审核

    func fetchPendingReviews() {
        guard isDeveloper else { return }
        isLoadingReview = true
        Task {
            do {
                let items = try await MeilisearchService.shared.getPendingWallpapers()
                await MainActor.run {
                    self.pendingReviewItems = items.sorted { $0.uploadedAt > $1.uploadedAt }
                    self.isLoadingReview = false
                }
            } catch {
                await MainActor.run { self.isLoadingReview = false }
            }
        }
    }

    func approveWallpaper(item: WallpaperItem) {
        Task {
            do {
                try await MeilisearchService.shared.updateApprovalStatus(id: item.id, status: .approved)
                await MainActor.run {
                    self.pendingReviewItems.removeAll { $0.id == item.id }
                    // 同步到 allWallpapers
                    if let index = self.allWallpapers.firstIndex(where: { $0.id == item.id }) {
                        var updated = item
                        updated.approvalStatus = .approved
                        self.allWallpapers[index] = updated
                    } else {
                        var updated = item
                        updated.approvalStatus = .approved
                        self.allWallpapers.insert(updated, at: 0)
                    }
                    self.statusMessage = "✅ 已通过「\(item.title)」"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if self.statusMessage.contains("已通过") { self.statusMessage = "" }
                    }
                }
            } catch {
                await MainActor.run { self.statusMessage = "❌ 操作失败，请检查网络" }
            }
        }
    }

    func rejectWallpaper(item: WallpaperItem, reason: String) {
        Task {
            do {
                try await MeilisearchService.shared.updateApprovalStatus(
                    id: item.id, status: .rejected,
                    rejectionReason: reason.isEmpty ? nil : reason
                )
                await MainActor.run {
                    self.pendingReviewItems.removeAll { $0.id == item.id }
                    self.statusMessage = "🚫 已拒绝「\(item.title)」"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if self.statusMessage.contains("已拒绝") { self.statusMessage = "" }
                    }
                }
            } catch {
                await MainActor.run { self.statusMessage = "❌ 操作失败，请检查网络" }
            }
        }
    }

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

    func renameCollection(id: String, newName: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = newName
        saveCollections()
        if isLoggedIn, let collection = collections.first(where: { $0.id == id }) {
            Task { try? await AuthService.shared.upsertCollection(collection) }
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
                    try? await OSSUploader.shared.deletePreview(itemId: item.id)
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
                    self.cacheVersion += 1
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
        Task {
            do {
                // 本地导入的壁纸直接使用文件路径，无需缓存
                let localURL: URL
                if item.fullURL.isFileURL && FileManager.default.fileExists(atPath: item.fullURL.path) {
                    localURL = item.fullURL
                } else {
                    let cachedURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
                    if !FileManager.default.fileExists(atPath: cachedURL.path) {
                        // 只有真正需要下载时才显示进度圆圈
                        if !isSilent { await MainActor.run { self.downloadProgress[item.id] = 0.01 } }
                        let tempURL = try await downloadWithProgress(url: item.fullURL, itemId: item.id, isSilent: isSilent)
                        try FileManager.default.moveItem(at: tempURL, to: cachedURL)
                    }
                    localURL = cachedURL
                }
                await MainActor.run {
                    self.downloadProgress.removeValue(forKey: item.id)
                    // 用户手动换壁纸时，停止自动轮播和定时换壁纸
                    if !isSilent {
                        if self.isSlideshowEnabled { self.isSlideshowEnabled = false }
                        if self.isTimedPeriodEnabled { self.isTimedPeriodEnabled = false }
                    }
                    let ext = localURL.pathExtension.lowercased()
                    if ext == "html" || ext == "htm" {
                        DesktopVideoManager.shared.clearVideoWallpaper()
                        DesktopWebManager.shared.showWebWallpaper(url: localURL, screenName: self.targetScreenName)
                    } else if item.isVideo {
                        DesktopWebManager.shared.clearWebWallpaper()
                        DesktopVideoManager.shared.playVideoOnDesktop(url: localURL, screenName: self.targetScreenName)
                    } else {
                        DesktopVideoManager.shared.clearVideoWallpaper()
                        DesktopWebManager.shared.clearWebWallpaper()
                        self.applyStaticWallpaper(url: localURL)
                        // macOS 14+ 桌面与锁屏同源，setDesktopImageURL 会自动同步锁屏，
                        // 无需再通过 killall WallpaperAgent 强制刷新（会导致桌面短暂蓝屏）
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
        // 同步删除视频预览缓存，避免孤儿文件导致 calculateCacheSize 数值偏大
        if item.isVideo {
            let remotePreview = item.previewURL ?? item.fullURL.ossPreview()
            let previewPath = WallpaperCacheManager.shared.getPreviewCachePath(for: remotePreview)
            try? FileManager.default.removeItem(at: previewPath)
        }
        if let idx = playlistIds.firstIndex(of: item.id) { playlistIds.remove(at: idx) }
        cacheVersion += 1
        calculateCacheSize()
        objectWillChange.send()
        statusMessage = "🗑️ 已清除该壁纸缓存"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.statusMessage.contains("🗑️") { self.statusMessage = "" }
        }
    }

    // MARK: - 批量操作

    func toggleBatchSelection(item: WallpaperItem) {
        if batchSelectedIds.contains(item.id) {
            batchSelectedIds.remove(item.id)
        } else {
            batchSelectedIds.insert(item.id)
        }
    }

    func selectAllDownloaded() {
        let currentPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        for item in displayWallpapers {
            let path = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL).path
            if path != currentPath { batchSelectedIds.insert(item.id) }
        }
    }

    func deleteBatchSelectedCache() {
        guard !batchSelectedIds.isEmpty else { return }
        let currentPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        var deleted = 0
        var skipped = 0
        let ids = batchSelectedIds
        for id in ids {
            guard let item = allWallpapers.first(where: { $0.id == id }) else { continue }
            let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
            if localURL.path == currentPath { skipped += 1; continue }
            try? FileManager.default.removeItem(at: localURL)
            if item.isVideo {
                let remotePreview = item.previewURL ?? item.fullURL.ossPreview()
                try? FileManager.default.removeItem(at: WallpaperCacheManager.shared.getPreviewCachePath(for: remotePreview))
            }
            if let idx = playlistIds.firstIndex(of: id) { playlistIds.remove(at: idx) }
            deleted += 1
        }
        isBatchSelectMode = false
        cacheVersion += 1
        calculateCacheSize()
        objectWillChange.send()
        if skipped > 0 {
            statusMessage = "🗑️ 已删除 \(deleted) 张，跳过 \(skipped) 张（正在使用中）"
        } else {
            statusMessage = "🗑️ 已删除 \(deleted) 张缓存"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.statusMessage.contains("🗑️") { self.statusMessage = "" }
        }
    }

    // MARK: - 定时换壁纸

    func loadPeriodAssignments() {
        isTimedPeriodEnabled = UserDefaults.standard.bool(forKey: "isTimedPeriodEnabled")
        if let data = UserDefaults.standard.data(forKey: "periodWallpaperIds"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            periodWallpaperIds = dict
        }
    }

    func savePeriodAssignments() {
        if let data = try? JSONEncoder().encode(periodWallpaperIds) {
            UserDefaults.standard.set(data, forKey: "periodWallpaperIds")
        }
    }

    func setPeriodWallpaper(period: DayPeriod, itemId: String) {
        periodWallpaperIds[period.rawValue] = itemId
    }

    func setupPeriodTimer() {
        periodTimer?.invalidate()
        periodTimer = nil
        guard isTimedPeriodEnabled else { return }
        // 每 60 秒检查一次是否需要切换
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndApplyPeriodWallpaper()
        }
        RunLoop.main.add(timer, forMode: .common)
        periodTimer = timer
        // 启动时立即检查一次
        checkAndApplyPeriodWallpaper()
    }

    func checkAndApplyPeriodWallpaper() {
        let current = DayPeriod.current()
        guard current != lastAppliedPeriod,
              let itemId = periodWallpaperIds[current.rawValue],
              let item = allWallpapers.first(where: { $0.id == itemId }) else { return }
        lastAppliedPeriod = current
        setWallpaper(item: item, isSilent: true)
    }

    func clearCache() {
        let currentPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        let cloudDir = WallpaperCacheManager.shared.cloudDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: cloudDir, includingPropertiesForKeys: nil) {
            for file in files {
                if file.path != currentPath {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        playlistIds.removeAll()
        cacheVersion += 1
        calculateCacheSize()
        objectWillChange.send()
        statusMessage = "✅ 缓存清理完成"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.statusMessage == "✅ 缓存清理完成" { self.statusMessage = "" }
        }
    }

    func changeCacheDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "新的壁纸缓存将保存到此文件夹，已有缓存不会自动移动。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? WallpaperCacheManager.shared.setCacheDirectory(url)
        cacheDirectoryPath = url.path
        cacheVersion += 1
        calculateCacheSize()
    }

    func resetCacheDirectory() {
        WallpaperCacheManager.shared.resetToDefaultCacheDirectory()
        cacheDirectoryPath = WallpaperCacheManager.shared.cacheDirectory.path
        cacheVersion += 1
        calculateCacheSize()
    }

    func calculateCacheSize() {
        let cloudDir      = WallpaperCacheManager.shared.cloudDirectory
        let workshopDir   = WallpaperCacheManager.shared.workshopDirectory
        let localImportsDir = WallpaperCacheManager.shared.cacheDirectory
            .appendingPathComponent("local_imports")

        Task.detached(priority: .background) { [weak self] in
            let cloud    = directorySize(at: cloudDir)
            let workshop = directorySize(at: workshopDir)
            let localImport = directorySize(at: localImportsDir)
            let total    = cloud + workshop + localImport

            func fmt(_ b: Int64) -> String { String(format: "%.1f MB", Double(b) / (1024 * 1024)) }
            await MainActor.run {
                self?.cloudCacheSizeString  = fmt(cloud)
                self?.workshopCacheSizeString = fmt(workshop)
                self?.localImportSizeString = fmt(localImport)
                self?.cacheSizeString       = fmt(total)
            }
        }
        refreshDownloadedIds()
    }

    // MARK: - 以图搜图

    func searchByImage(url: URL) {
        imageSearchQueryImage = NSImage(contentsOf: url)
        imageSearchResults = []
        isImageSearching = true
        imageSearchMode = true

        Task {
            do {
                let vector = try await ImageFeatureExtractor.extract(from: url)

                // 首次使用：向 Meilisearch 注册 userProvided 嵌入器
                let dim = vector.count
                let savedDim = UserDefaults.standard.integer(forKey: "imageFeatureDimension")
                if savedDim != dim {
                    try? await MeilisearchService.shared.configureVectorSearch(dimension: dim)
                    UserDefaults.standard.set(dim, forKey: "imageFeatureDimension")
                }

                let results = try await MeilisearchService.shared.vectorSearch(vector: vector, hitsPerPage: 24)
                await MainActor.run {
                    imageSearchResults = results
                    isImageSearching = false
                }
            } catch {
                await MainActor.run {
                    isImageSearching = false
                    imageSearchMode = false
                    statusMessage = "❌ 以图搜图失败，请检查网络连接"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.statusMessage.hasPrefix("❌") { self.statusMessage = "" }
                    }
                }
            }
        }
    }

    func clearImageSearch() {
        imageSearchMode = false
        imageSearchQueryImage = nil
        imageSearchResults = []
        isImageSearching = false
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
            let ext = url.pathExtension.lowercased()
            if ["mp4", "mov", "webm"].contains(ext) {
                DesktopVideoManager.shared.playVideoOnDesktop(url: url)
                Task { await syncLockScreenWallpaper(for: url) }
            } else if ext == "html" || ext == "htm" {
                DesktopWebManager.shared.showWebWallpaper(url: url)
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

    // MARK: - Steam Workshop

    @Published var workshopSelectedType: String = "全部" {
        didSet {
            workshopCurrentPage = 0
            workshopTotalResults = 0
            fetchWorkshopItems()
        }
    }

    /// 排序方式："1"=最新发布  "3"=热门趋势
    @Published var workshopSortType: String = "3" {
        didSet {
            workshopCurrentPage = 0
            workshopTotalResults = 0
            fetchWorkshopItems()
        }
    }

    @Published var workshopItems: [SteamWorkshopItem] = []
    @Published var isLoadingWorkshop: Bool = false
    @Published var workshopSearchText: String = ""
    @Published var workshopCurrentPage: Int = 0
    @Published var workshopHasNextPage: Bool = false
    @Published var workshopTotalResults: Int = 0
    @Published var workshopDownloadStates: [String: WorkshopDownloadState] = [:]
    @Published var workshopPreviewItem: SteamWorkshopItem? = nil
    @Published var workshopDownloadStartTime: [String: Date] = [:]
    /// SteamCMD-reported download progress per item (0–1). Absent when no progress output yet.
    @Published var workshopDownloadProgress: [String: Double] = [:]
    /// Total file size (bytes) reported by SteamCMD for each item.
    @Published var workshopTotalBytes: [String: Int64] = [:]
    let workshopItemsPerPage: Int = 12

    /// Tracks the active fetch so stale in-flight requests can be cancelled on page change.
    private var workshopFetchTask: Task<Void, Never>?
    /// Incremented on every new fetch. A task is only allowed to mutate state if its generation
    /// still matches, preventing a cancelled/stale task from corrupting the loading indicator or
    /// overwriting results with old data.
    private var workshopFetchGeneration = 0

    func fetchWorkshopItems() {
        workshopFetchTask?.cancel()
        workshopFetchGeneration += 1
        let gen         = workshopFetchGeneration
        let displayPage = workshopCurrentPage
        let query       = workshopSearchText
        let filterType  = workshopSelectedType  // "全部" | "Video" | "Scene" | "Web" | "Image"
        let sortType    = workshopSortType       // "0"=投票 | "1"=最新 | "3"=热门趋势

        workshopFetchTask = Task { @MainActor in
            isLoadingWorkshop = true
            defer {
                if gen == workshopFetchGeneration { isLoadingWorkshop = false }
            }
            do {
                // All types use page-based + server-side tag filtering (requiredtags via Worker).
                // This gives accurate results and total counts for all filter types.
                let tag: String? = filterType == "全部" ? nil : filterType
                let (items, more, _, pageTotal) = try await SteamWorkshopService.shared.fetchViaWorker(
                    query: query, page: displayPage + 1, filterTag: tag,
                    sortType: sortType, perPage: workshopItemsPerPage
                )
                guard gen == workshopFetchGeneration, !Task.isCancelled else { return }
                if pageTotal > 0 { workshopTotalResults = pageTotal }
                let enriched: [SteamWorkshopItem]
                if items.contains(where: { $0.fileSize == 0 }) {
                    enriched = await SteamWorkshopService.shared.fetchItemDetails(for: items)
                } else {
                    enriched = items
                }
                guard gen == workshopFetchGeneration, !Task.isCancelled else { return }
                // Client-side type filter: remove items whose tags don't match the selected type.
                // The server-side requiredtags filter is approximate; enriched tags are authoritative.
                let filtered: [SteamWorkshopItem]
                if filterType == "全部" {
                    filtered = enriched
                } else {
                    let ft = filterType.lowercased()
                    filtered = enriched.filter { $0.tags.map({ $0.lowercased() }).contains(ft) }
                }
                workshopItems = filtered
                workshopHasNextPage = more
            } catch {
                guard gen == workshopFetchGeneration, !Task.isCancelled else { return }
                statusMessage = "❌ Workshop 加载失败：\(error.localizedDescription)"
                let msgSnap = statusMessage
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    if self?.statusMessage == msgSnap { self?.statusMessage = "" }
                }
            }
        }
    }

    @Published var isInstallingWorkshopTool: Bool = false

    /// Sets the correct download state after a successful SteamCMD download.
    /// Distinguishes scene/web wallpapers (unsupported) from missing files.
    /// Sets the correct download state after a successful SteamCMD download.
    /// Distinguishes scene/web wallpapers (unsupported) from missing files.
    private func resolveWorkshopDownloadResult(itemId: String) {
        let dir = SteamWorkshopService.workshopItemDirectory(itemId: itemId)
        if let file = SteamWorkshopService.findWallpaperFile(in: dir) {
            // addWorkshopImport may move the entire directory; use the returned path
            let storedURL = addWorkshopImport(itemId: itemId, fileURL: file)
            workshopDownloadStates[itemId] = .done(storedURL)
            statusMessage = "✅ 下载完成，已自动加入本地壁纸"
        } else {
            let weType = SteamWorkshopService.detectWallpaperType(in: dir)
            if !weType.isSupported && weType != .unknown {
                let typeName = weType.rawValue
                workshopDownloadStates[itemId] = .failed("此壁纸为 \(typeName) 类型，需要 Wallpaper Engine 才能运行，macOS 不支持")
                statusMessage = "⚠️ \(typeName) 类型壁纸需要 Wallpaper Engine，macOS 无法直接使用"
            } else {
                workshopDownloadStates[itemId] = .failed("下载完成但找不到可用的壁纸文件")
                statusMessage = "⚠️ 下载完成但找不到壁纸文件"
            }
        }
    }

    /// Restores workshopDownloadStates for a card/overlay onAppear — checks localImports first
    /// (survives across sessions), then the app-managed workshop directory, then SteamCMD.
    func restoreWorkshopDownloadState(for item: SteamWorkshopItem) {
        guard workshopDownloadStates[item.id] == nil else { return }
        // 1. Already tracked in localImports (persisted to UserDefaults)
        if let existing = localImports.first(where: { $0.id == item.id }),
           FileManager.default.fileExists(atPath: existing.fullURL.path) {
            workshopDownloadStates[item.id] = .done(existing.fullURL)
            return
        }
        // 2. App-managed workshop directory (entire item dir moved here after download)
        let appDir = WallpaperCacheManager.shared.workshopDirectory.appendingPathComponent(item.id)
        if let file = SteamWorkshopService.findWallpaperFile(in: appDir) {
            workshopDownloadStates[item.id] = .done(file)
            return
        }
        // 3. SteamCMD directory (freshly downloaded, not yet imported)
        let steamDir = SteamWorkshopService.workshopItemDirectory(itemId: item.id)
        if let file = SteamWorkshopService.findWallpaperFile(in: steamDir) {
            workshopDownloadStates[item.id] = .done(file)
        }
    }

    /// Per-item download tasks, keyed by item ID. Stored so downloads can be cancelled mid-flight.
    private var workshopActiveTasks: [String: Task<Void, Never>] = [:]

    /// Cancels an active Workshop download and resets its state.
    func cancelWorkshopDownload(itemId: String) {
        workshopActiveTasks[itemId]?.cancel()
        workshopActiveTasks.removeValue(forKey: itemId)
        workshopDownloadStates[itemId] = nil
        workshopDownloadProgress.removeValue(forKey: itemId)
        workshopDownloadStartTime.removeValue(forKey: itemId)
        if statusMessage.contains("下载") { statusMessage = "" }
    }

    /// Downloads a Workshop item using SteamCMD (anonymous login). Installs SteamCMD automatically if missing.
    func downloadWorkshopItemViaSteamCMD(item: SteamWorkshopItem) {
        if case .downloading = workshopDownloadStates[item.id] { return }

        let task = Task { @MainActor in
            workshopDownloadStates[item.id] = .downloading

            var cmdPath = SteamWorkshopService.findSteamCMD()
            if cmdPath == nil {
                isInstallingWorkshopTool = true
                statusMessage = "正在安装 SteamCMD…"
                do {
                    try await SteamWorkshopService.installSteamCMD()
                    cmdPath = SteamWorkshopService.appSteamCMDPath.path
                } catch {
                    workshopDownloadStates[item.id] = .failed("SteamCMD 安装失败")
                    statusMessage = "❌ SteamCMD 安装失败：\(error.localizedDescription)"
                    isInstallingWorkshopTool = false
                    return
                }
                isInstallingWorkshopTool = false
            }

            guard let path = cmdPath else {
                workshopDownloadStates[item.id] = .failed("找不到 SteamCMD")
                return
            }

            statusMessage = "正在下载 Workshop 文件，请稍候…"
            workshopDownloadStartTime[item.id] = Date()
            workshopDownloadProgress.removeValue(forKey: item.id)
            workshopTotalBytes.removeValue(forKey: item.id)
            let itemId = item.id
            let success = await SteamWorkshopService.downloadWithSteamCMD(
                steamcmdPath: path, itemId: itemId,
                progressHandler: { [weak self] pct in
                    self?.workshopDownloadProgress[itemId] = pct
                },
                totalBytesHandler: { [weak self] total in
                    self?.workshopTotalBytes[itemId] = total
                }
            )
            workshopDownloadProgress.removeValue(forKey: item.id)
            workshopTotalBytes.removeValue(forKey: item.id)
            workshopDownloadStartTime.removeValue(forKey: item.id)
            workshopActiveTasks.removeValue(forKey: item.id)

            guard !Task.isCancelled else { return }   // cancelled by user — state already reset by cancelWorkshopDownload
            if success {
                resolveWorkshopDownloadResult(itemId: item.id)
            } else {
                workshopDownloadStates[item.id] = .failed("下载失败，请尝试在 Steam 中订阅")
                statusMessage = "❌ 下载失败，匿名下载仅支持免费订阅的壁纸"
            }
            let msgSnapshot = self.statusMessage
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                if self?.statusMessage == msgSnapshot { self?.statusMessage = "" }
            }
        }
        workshopActiveTasks[item.id] = task
    }

    // MARK: - Steam Credential Login Download

    /// State for the credential-login download sheet in the UI
    @Published var workshopLoginItem: SteamWorkshopItem? = nil      // which item triggered the sheet
    @Published var workshopLoginNeedsGuard: Bool = false             // waiting for guard code
    @Published var workshopLoginNeedsTwoFactor: Bool = false         // waiting for mobile auth code
    @Published var workshopLoginInProgress: Bool = false
    /// Temporarily holds password across sheet dismiss/re-open for Steam Guard flow
    var workshopLoginSavedPassword: String = ""

    /// Downloads a Workshop item using real Steam credentials via SteamCMD.
    func downloadWorkshopItemWithCredentials(
        item: SteamWorkshopItem,
        username: String,
        password: String,
        guardCode: String? = nil
    ) {
        let task = Task { @MainActor in
            workshopLoginInProgress = true
            workshopLoginNeedsGuard = false
            workshopLoginNeedsTwoFactor = false
            // Save credentials so the re-opened guard-code sheet can reuse them
            if !password.isEmpty { workshopLoginSavedPassword = password }

            // Prepare SteamCMD (install if missing) while login sheet is still visible
            var cmdPath = SteamWorkshopService.findSteamCMD()
            if cmdPath == nil {
                isInstallingWorkshopTool = true
                statusMessage = "正在安装 SteamCMD…"
                do {
                    try await SteamWorkshopService.installSteamCMD()
                    cmdPath = SteamWorkshopService.appSteamCMDPath.path
                } catch {
                    statusMessage = "❌ SteamCMD 安装失败"
                    workshopLoginInProgress = false
                    isInstallingWorkshopTool = false
                    return
                }
                isInstallingWorkshopTool = false
            }

            guard let path = cmdPath else {
                statusMessage = "❌ 找不到 SteamCMD"
                workshopLoginInProgress = false
                return
            }

            // Close login sheet and show download progress in preview overlay
            workshopLoginItem = nil
            workshopLoginInProgress = false
            workshopDownloadStates[item.id] = .downloading
            workshopDownloadStartTime[item.id] = Date()

            workshopDownloadProgress.removeValue(forKey: item.id)
            workshopTotalBytes.removeValue(forKey: item.id)
            let itemId = item.id
            let result = await SteamWorkshopService.downloadWithCredentials(
                steamcmdPath: path,
                username: username,
                password: password,
                guardCode: guardCode,
                itemId: item.id,
                progressHandler: { [weak self] pct in
                    self?.workshopDownloadProgress[itemId] = pct
                },
                totalBytesHandler: { [weak self] total in
                    self?.workshopTotalBytes[itemId] = total
                },
                mobileConfirmHandler: { [weak self] in
                    self?.statusMessage = "📱 请打开手机 Steam App，点击确认登录请求…"
                    let snap = "📱 请打开手机 Steam App，点击确认登录请求…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                        if self?.statusMessage == snap { self?.statusMessage = "" }
                    }
                }
            )

            workshopDownloadStartTime.removeValue(forKey: item.id)
            workshopDownloadProgress.removeValue(forKey: item.id)
            workshopTotalBytes.removeValue(forKey: item.id)
            workshopActiveTasks.removeValue(forKey: item.id)

            guard !Task.isCancelled else { return }

            switch result {
            case .success:
                workshopLoginSavedPassword = ""
                resolveWorkshopDownloadResult(itemId: item.id)
            case .needsSteamGuard:
                workshopDownloadStates[item.id] = nil
                workshopLoginNeedsGuard = true
                workshopLoginItem = item
                // 如果 guardCode 非空说明是验证码填错了，给用户提示
                if let code = guardCode, !code.isEmpty {
                    statusMessage = "❌ Steam Guard 验证码错误，请重新输入"
                } else {
                    statusMessage = "📧 Steam 已向邮箱发送验证码，请查收后输入"
                }
            case .needsTwoFactor:
                workshopDownloadStates[item.id] = nil
                workshopLoginNeedsTwoFactor = true
                workshopLoginItem = item
                if let code = guardCode, !code.isEmpty {
                    statusMessage = "❌ 令牌验证码错误，请重新输入"
                } else {
                    statusMessage = "📱 请打开 Steam 手机令牌，查看验证码后输入"
                }
            case .invalidCredentials:
                workshopLoginSavedPassword = ""
                workshopDownloadStates[item.id] = .failed("账号或密码错误")
                workshopLoginItem = item
                statusMessage = "❌ Steam 账号或密码错误，请重新输入"
            case .failed(let msg):
                workshopLoginSavedPassword = ""
                let brief = String(msg.suffix(200))
                workshopDownloadStates[item.id] = .failed("下载失败")
                statusMessage = "❌ 下载失败"
                print("[SteamCMD output] \(brief)")
            }

            let credMsgSnapshot = self.statusMessage
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if self?.statusMessage == credMsgSnapshot { self?.statusMessage = "" }
            }
        }
        workshopActiveTasks[item.id] = task
    }

    /// Opens the Steam Workshop page so the user can subscribe.
    /// Steam will download the item automatically; call checkWorkshopItemDownloaded() afterwards.
    func openWorkshopItemInSteam(_ item: SteamWorkshopItem) {
        let steamURL = URL(string: "steam://url/CommunityFilePage/\(item.id)")!
        let webURL   = URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(item.id)")!
        if NSWorkspace.shared.open(steamURL) { return }
        NSWorkspace.shared.open(webURL)
    }


    /// Checks whether a Workshop item has already been downloaded by Steam and updates state.
    func checkWorkshopItemDownloaded(_ item: SteamWorkshopItem) {
        let dir = SteamWorkshopService.workshopItemDirectory(itemId: item.id)
        if FileManager.default.fileExists(atPath: dir.path) {
            resolveWorkshopDownloadResult(itemId: item.id)
        } else {
            workshopDownloadStates[item.id] = nil
            statusMessage = "未找到本地文件，请先在 Steam 中订阅此壁纸"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.statusMessage.contains("订阅") { self.statusMessage = "" }
            }
        }
    }

    /// 设为壁纸（Workshop 下载后的"设为壁纸"按钮调用此方法）。
    /// 优先在已导入的本地壁纸中查找，找到直接设为壁纸；否则先导入再设置。
    func importWorkshopFile(url: URL, setImmediately: Bool) {
        // Workshop 下载时已由 addWorkshopImport 自动导入，直接查找已有条目
        if let existing = localImports.first(where: { $0.fullURL == url }) {
            if setImmediately { setWallpaper(item: existing) }
            return
        }
        // 手动场景（如从外部文件导入）：读取文件计算 hash 并复制
        let added = addLocalImport(from: url)
        if setImmediately, let item = localImports.first(where: { $0.fullURL.lastPathComponent == url.lastPathComponent }) {
            setWallpaper(item: item)
        } else if added {
            currentTab = .downloaded
            downloadedSubTab = .localImports
            statusMessage = "✅ 已导入到本地壁纸"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.statusMessage.hasPrefix("✅") { self.statusMessage = "" }
            }
        }
    }

    private func syncLockScreenWallpaper(for videoURL: URL) async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // 增大容差，避免因帧边界导致提取失败
        generator.requestedTimeToleranceBefore = CMTime(seconds: 3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 3, preferredTimescale: 600)

        // 依次尝试多个时间点，任意一个成功即可
        let candidates: [CMTime] = [
            CMTime(seconds: 1, preferredTimescale: 600),
            CMTime(seconds: 0, preferredTimescale: 600),
            CMTime(value: 1, timescale: 1)
        ]
        var cgImage: CGImage?
        for t in candidates {
            if let (img, _) = try? await generator.image(at: t) {
                cgImage = img; break
            }
        }
        guard let cgImage else { return }

        guard let jpegData = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [:]) else { return }
        let lockScreenURL = WallpaperCacheManager.shared.cloudDirectory
            .appendingPathComponent("lockscreen_sync.jpg")
        guard (try? jpegData.write(to: lockScreenURL)) != nil else { return }

        await MainActor.run {
            self.applyStaticWallpaper(url: lockScreenURL)
        }
    }

    private func downloadWithProgress(url: URL, itemId: String, isSilent: Bool = false) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
                DispatchQueue.main.async {
                    self.progressObservations.removeValue(forKey: itemId)
                    self.activeTasks.removeValue(forKey: itemId)
                }
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
            self.activeTasks[itemId] = task
            task.resume()
        }
    }

    func cancelDownload(itemId: String) {
        activeTasks[itemId]?.cancel()
        activeTasks.removeValue(forKey: itemId)
        progressObservations.removeValue(forKey: itemId)
        DispatchQueue.main.async { self.downloadProgress.removeValue(forKey: itemId) }
    }

    private func applyStaticWallpaper(url: URL) {
        let screens: [NSScreen]
        if targetScreenName == "全部" {
            screens = NSScreen.screens
        } else {
            let filtered = NSScreen.screens.filter { $0.localizedName == targetScreenName }
            screens = filtered.isEmpty ? NSScreen.screens : filtered
        }
        for screen in screens {
            if wallpaperFit == .fill, let filledURL = cropImageToFill(url: url, for: screen) {
                // 预裁剪到屏幕精确尺寸，绕过 macOS 新版本对 allowClipping 选项的兼容性问题
                let exactOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
                    .imageScaling: NSNumber(value: NSImageScaling.scaleNone.rawValue),
                    .allowClipping: NSNumber(value: false)
                ]
                try? NSWorkspace.shared.setDesktopImageURL(filledURL, for: screen, options: exactOptions)
            } else {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: wallpaperFit.desktopImageOptions)
            }
        }
    }

    /// 将图片裁剪并缩放以填满指定屏幕（crop-to-fill），返回临时文件 URL
    private func cropImageToFill(url: URL, for screen: NSScreen) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let scale = screen.backingScaleFactor
        let targetW = Int(screen.frame.width * scale)
        let targetH = Int(screen.frame.height * scale)
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard targetW > 0, targetH > 0, srcW > 0, srcH > 0 else { return nil }

        // 取较大缩放比使图片能覆盖整个屏幕，多余部分居中裁剪
        let fillScale = max(Double(targetW) / Double(srcW), Double(targetH) / Double(srcH))
        let scaledW = Int((Double(srcW) * fillScale).rounded())
        let scaledH = Int((Double(srcH) * fillScale).rounded())
        let cropX = (scaledW - targetW) / 2
        let cropY = (scaledH - targetH) / 2

        guard let ctx = CGContext(
            data: nil, width: targetW, height: targetH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = CGInterpolationQuality.high
        ctx.draw(cgImage, in: CGRect(x: -cropX, y: -cropY, width: scaledW, height: scaledH))
        guard let result = ctx.makeImage() else { return nil }

        // 每次用新文件名，避免 macOS 因 URL 相同而跳过壁纸更新
        // 同时清理上一次生成的同名旧文件
        let prefix = "wallpaper_fill_\(screen.localizedName.hashValue)_"
        let cacheDir = WallpaperCacheManager.shared.cacheDirectory
        if let old = try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path)
            .filter({ $0.hasPrefix(prefix) }) {
            old.forEach { try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent($0)) }
        }
        let tempURL = cacheDir.appendingPathComponent("\(prefix)\(Int(Date().timeIntervalSince1970)).jpg")
        guard let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, result, [kCGImageDestinationLossyCompressionQuality: NSNumber(value: 0.93)] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? tempURL : nil
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
        // 必须用 NSNumber 显式包装，Swift Bool/UInt 直接放入 Any 字典时不能被 ObjC API 正确识别
        switch self {
        case .fill:    return [.imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue), .allowClipping: NSNumber(value: true)]
        case .fit:     return [.imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue), .allowClipping: NSNumber(value: false)]
        case .stretch: return [.imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue),      .allowClipping: NSNumber(value: true)]
        case .center:  return [.imageScaling: NSNumber(value: NSImageScaling.scaleNone.rawValue),                   .allowClipping: NSNumber(value: false)]
        }
    }
}

extension Notification.Name {
    static let randomWallpaperTrigger = Notification.Name("com.panglou.wallpaper.random")
}
