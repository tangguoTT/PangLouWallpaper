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

// 🌟 新增：上传大厅的两种模式
enum UploadMode: String {
    case pending = "待上传列表"
    case manage = "云端壁纸管理"
}

class WallpaperViewModel: ObservableObject {
    @Published var allWallpapers: [WallpaperItem] = []
    @Published var statusMessage: String = ""
    @Published var currentPage: Int = 0
    let itemsPerPage: Int = 12
    
    @Published var isAutoStartEnabled: Bool = false
    @Published var cacheSizeString: String = "0 MB"
    
    @Published var currentTab: AppTab = .pc { didSet { currentPage = 0 } }
    @Published var searchText: String = "" { didSet { currentPage = 0 } }
    @Published var previewItem: WallpaperItem? = nil
    @Published var currentWallpaperPath: String = ""

    // 🌟 新增：绑定当前的上传大厅模式
    @Published var uploadMode: UploadMode = .pending { didSet { currentPage = 0 } }
    
    @Published var showTypeMenu: Bool = false
    @Published var showCategoryMenu: Bool = false
    @Published var showResolutionMenu: Bool = false
    @Published var showColorMenu: Bool = false
    
    @Published var selectedType: String = "全部" { didSet { currentPage = 0 } }
    @Published var selectedCategory: String = "全部" { didSet { currentPage = 0 } }
    @Published var selectedResolution: String = "全部" { didSet { currentPage = 0 } }
    @Published var selectedColor: String = "全部" { didSet { currentPage = 0 } }
    
    @Published var customWidth: String = ""
    @Published var customHeight: String = ""
    
    @Published var isSlideshowEnabled: Bool = false { didSet { UserDefaults.standard.set(isSlideshowEnabled, forKey: "isSlideshowEnabled"); setupSlideshowTimer() } }
    @Published var slideshowInterval: Double = 3600 { didSet { UserDefaults.standard.set(slideshowInterval, forKey: "slideshowInterval"); setupSlideshowTimer() } }
    @Published var isSlideshowRandom: Bool = false { didSet { UserDefaults.standard.set(isSlideshowRandom, forKey: "isSlideshowRandom") } }
    @Published var nextSlideshowCountdown: String = ""
    @Published var playlistIds: [String] = [] { didSet { UserDefaults.standard.set(playlistIds, forKey: "playlistIds"); setupSlideshowTimer() } }
    @Published var favoriteIds: [String] = [] { didSet { UserDefaults.standard.set(favoriteIds, forKey: "favoriteIds") } }
    @Published var showOnlyFavorites: Bool = false { didSet { currentPage = 0 } }
    @Published var wallpaperFit: WallpaperFit = .fill { didSet { UserDefaults.standard.set(wallpaperFit.rawValue, forKey: "wallpaperFit") } }
    @Published var targetScreenName: String = "全部" { didSet { UserDefaults.standard.set(targetScreenName, forKey: "targetScreenName") } }
    @Published var showAbout: Bool = false

    var availableScreenNames: [String] { ["全部"] + NSScreen.screens.map { $0.localizedName } }
    
    @Published var pendingUploads: [PendingUploadItem] = []
    
    @Published var editingWallpaper: WallpaperItem? = nil
    @Published var editCategory: String = "全部"
    @Published var editResolution: String = "全部"
    @Published var editColor: String = "全部"
    
    @Published var downloadProgress: [String: Double] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    
    private var slideshowTimer: Timer?
    private var countdownTimer: Timer?
    private var nextSlideshowDate: Date = Date()
    private var currentSlideshowIndex = 0
    private var cancellables = Set<AnyCancellable>()
    let jsonConfigURL = URL(string: "https://wallpapers-pl.oss-cn-beijing.aliyuncs.com/wallpapers/wallpapers.json")!

    var displayWallpapers: [WallpaperItem] {
        var items = allWallpapers
        if currentTab == .downloaded { items = items.filter { FileManager.default.fileExists(atPath: WallpaperCacheManager.shared.getLocalPath(for: $0.fullURL).path) } }
        else if currentTab == .slideshow { items = items.filter { playlistIds.contains($0.id) && FileManager.default.fileExists(atPath: WallpaperCacheManager.shared.getLocalPath(for: $0.fullURL).path) } }
        
        if showOnlyFavorites { items = items.filter { favoriteIds.contains($0.id) } }
        if selectedType == "静态壁纸" { items = items.filter { !$0.isVideo } } else if selectedType == "动态壁纸" { items = items.filter { $0.isVideo } }
        if selectedCategory != "全部" { let keyword = selectedCategory.components(separatedBy: " | ").first ?? selectedCategory; items = items.filter { $0.title.contains(keyword) } }
        if selectedColor != "全部" { items = items.filter { $0.title.contains(selectedColor) } }
        if selectedResolution != "全部" { items = items.filter { $0.title.contains(selectedResolution) } }
        if !customWidth.isEmpty || !customHeight.isEmpty { items = items.filter { $0.title.contains(customWidth) || $0.title.contains(customHeight) } }
        if !searchText.isEmpty { items = items.filter { $0.title.localizedCaseInsensitiveContains(searchText) } }
        return items
    }

    var totalPages: Int { max(1, Int(ceil(Double(displayWallpapers.count) / Double(itemsPerPage)))) }
    var paginatedImages: [WallpaperItem] {
        let items = displayWallpapers; let startIndex = currentPage * itemsPerPage; let endIndex = min(startIndex + itemsPerPage, items.count)
        guard startIndex < endIndex else { return [] }
        return Array(items[startIndex..<endIndex])
    }

    init() {
        if #available(macOS 13.0, *) { self.isAutoStartEnabled = SMAppService.mainApp.status == .enabled }
        calculateCacheSize()
        self.isSlideshowEnabled = UserDefaults.standard.bool(forKey: "isSlideshowEnabled")
        let savedInterval = UserDefaults.standard.double(forKey: "slideshowInterval")
        self.slideshowInterval = savedInterval == 0 ? 3600 : savedInterval
        self.playlistIds = UserDefaults.standard.stringArray(forKey: "playlistIds") ?? []
        self.isSlideshowRandom = UserDefaults.standard.bool(forKey: "isSlideshowRandom")
        self.favoriteIds = UserDefaults.standard.stringArray(forKey: "favoriteIds") ?? []
        if let fitRaw = UserDefaults.standard.string(forKey: "wallpaperFit"), let fit = WallpaperFit(rawValue: fitRaw) { self.wallpaperFit = fit }
        self.targetScreenName = UserDefaults.standard.string(forKey: "targetScreenName") ?? "全部"
        setupSlideshowTimer()
        self.currentWallpaperPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        NotificationCenter.default.publisher(for: .randomWallpaperTrigger)
            .sink { [weak self] _ in self?.randomWallpaper() }
            .store(in: &cancellables)
    }

    func randomWallpaper() {
        let downloaded = allWallpapers.filter { FileManager.default.fileExists(atPath: WallpaperCacheManager.shared.getLocalPath(for: $0.fullURL).path) }
        let pool = downloaded.isEmpty ? allWallpapers : downloaded
        guard let item = pool.randomElement() else { statusMessage = "⚠️ 暂无可用壁纸"; return }
        setWallpaper(item: item)
    }

    func importLocalWallpaper() {
        let panel = NSOpenPanel()
        panel.title = "选择本地壁纸"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isVideo = ["mp4", "mov", "m4v", "avi"].contains(url.pathExtension.lowercased())
        if isVideo {
            DesktopVideoManager.shared.playVideoOnDesktop(url: url, screenName: targetScreenName)
            Task { await syncLockScreenWallpaper(for: url) }
        } else {
            applyStaticWallpaper(url: url)
        }
        UserDefaults.standard.set(url.path, forKey: "LastWallpaperPath")
        currentWallpaperPath = url.path
        statusMessage = "✅ 已应用本地壁纸"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage == "✅ 已应用本地壁纸" { self.statusMessage = "" } }
    }

    func fetchCloudData() { Task { do { let (data, _) = try await URLSession.shared.data(from: jsonConfigURL); let items = try JSONDecoder().decode([WallpaperItem].self, from: data); await MainActor.run { self.allWallpapers = items } } catch { await MainActor.run { self.statusMessage = "❌ 同步失败" } } } }

    func selectFilesForUpload() { let panel = NSOpenPanel(); panel.title = "选择要上传的壁纸或视频"; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.allowedContentTypes = [.image, .movie]; if panel.runModal() == .OK { let newItems = panel.urls.map { PendingUploadItem(url: $0) }; pendingUploads.append(contentsOf: newItems) } }
    func removePendingUpload(id: UUID) { pendingUploads.removeAll { $0.id == id } }
    func clearPendingUploads() { pendingUploads.removeAll() }
    
    func executeUpload() {
        guard !pendingUploads.isEmpty else { return }
        statusMessage = "🚀 开始处理 \(pendingUploads.count) 个文件..."
        Task {
            var newItems: [WallpaperItem] = []; var successCount = 0; var skipCount = 0; let itemsToUpload = pendingUploads
            for (index, pendingItem) in itemsToUpload.enumerated() {
                await MainActor.run { self.statusMessage = "正在上传第 \(index + 1)/\(itemsToUpload.count) 个..." }
                do {
                    let fileData = try Data(contentsOf: pendingItem.url)
                    let hashString = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
                    if self.allWallpapers.contains(where: { $0.id == hashString }) { skipCount += 1; await MainActor.run { self.removePendingUpload(id: pendingItem.id) }; continue }
                    
                    var tags = ""
                    if pendingItem.category != "全部" { tags += "[\(pendingItem.category.components(separatedBy: " | ").first ?? pendingItem.category)]" }
                    if pendingItem.resolution != "全部" { tags += "[\(pendingItem.resolution)]" }
                    if pendingItem.color != "全部" { tags += "[\(pendingItem.color)]" }
                    
                    let originalName = pendingItem.url.lastPathComponent
                    let customTitle = tags.isEmpty ? originalName : "\(tags) \(originalName)"
                    let newItem = try await OSSUploader.shared.uploadFile(fileURL: pendingItem.url, fileData: fileData, hashString: hashString, customTitle: customTitle)
                    newItems.append(newItem); successCount += 1
                    await MainActor.run { self.removePendingUpload(id: pendingItem.id) }
                } catch { print("❌ 上传失败: \(pendingItem.url.lastPathComponent), 错误: \(error)") }
            }
            if successCount > 0 {
                await MainActor.run { self.statusMessage = "正在更新云端数据库..." }
                do {
                    let updatedWallpapers = newItems + self.allWallpapers; try await OSSUploader.shared.uploadJSON(items: updatedWallpapers)
                    await MainActor.run { self.allWallpapers = updatedWallpapers; self.statusMessage = "✅ 成功上传 \(successCount) 个素材 (跳过重复 \(skipCount) 个)"; DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.statusMessage = "" } }
                } catch { await MainActor.run { self.statusMessage = "❌ 更新数据库失败" } }
            } else { await MainActor.run { self.statusMessage = skipCount > 0 ? "⚠️ \(skipCount) 个文件已存在，无需重复上传" : "❌ 没有文件被成功上传"; DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.statusMessage = "" } } }
        }
    }
    
    // 🌟 核心：属性编辑引擎
    func beginEdit(item: WallpaperItem) {
        self.editingWallpaper = item; self.editCategory = "全部"; self.editResolution = "全部"; self.editColor = "全部"
        let title = item.title
        let categoriesList = ["魅力 | 迷人", "自制 | 艺术", "安逸 | 自由", "科幻 | 星云", "动漫 | 二次元", "自然 | 风景", "游戏 | 玩具"]
        for cat in categoriesList { if title.contains("[\(cat.components(separatedBy: " | ").first ?? cat)]") { self.editCategory = cat; break } }
        let resList = ["1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K"]; for res in resList { if title.contains("[\(res)]") { self.editResolution = res; break } }
        let colorList = ["偏蓝", "偏绿", "偏红", "灰/白", "紫/粉", "暗色", "偏黄", "其他颜色"]; for c in colorList { if title.contains("[\(c)]") { self.editColor = c; break } }
    }
    
    func saveWallpaperEdit() {
        guard let item = editingWallpaper, let index = allWallpapers.firstIndex(where: { $0.id == item.id }) else { return }
        var baseName = item.title
        while baseName.hasPrefix("[") { if let closeIndex = baseName.firstIndex(of: "]") { let afterBracket = baseName.index(after: closeIndex); baseName = String(baseName[afterBracket...]).trimmingCharacters(in: .whitespaces) } else { break } }
        var tags = ""
        if editCategory != "全部" { tags += "[\(editCategory.components(separatedBy: " | ").first ?? editCategory)]" }
        if editResolution != "全部" { tags += "[\(editResolution)]" }
        if editColor != "全部" { tags += "[\(editColor)]" }
        let newTitle = tags.isEmpty ? baseName : "\(tags) \(baseName)"
        let updatedItem = WallpaperItem(id: item.id, title: newTitle, fullURL: item.fullURL, isVideo: item.isVideo)
        var newWallpapers = allWallpapers; newWallpapers[index] = updatedItem
        statusMessage = "正在同步修改到云端..."
        Task {
            do {
                try await OSSUploader.shared.uploadJSON(items: newWallpapers)
                await MainActor.run { self.allWallpapers = newWallpapers; self.editingWallpaper = nil; self.statusMessage = "✅ 属性修改成功！"; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage == "✅ 属性修改成功！" { self.statusMessage = "" } } }
            } catch { await MainActor.run { self.statusMessage = "❌ 修改失败，请检查网络" } }
        }
    }
    
    func cancelEdit() { self.editingWallpaper = nil }

    // 🌟 超级附赠：云端彻底删除功能（仅在管理模式下出现）
    func deleteFromCloud(item: WallpaperItem) {
        guard let index = allWallpapers.firstIndex(where: { $0.id == item.id }) else { return }
        var newWallpapers = allWallpapers; newWallpapers.remove(at: index)
        statusMessage = "正在从云端移除..."
        Task {
            do {
                try await OSSUploader.shared.uploadJSON(items: newWallpapers)
                await MainActor.run { self.allWallpapers = newWallpapers; self.statusMessage = "🗑️ 已从云端数据库彻底移除"; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage.contains("移除") { self.statusMessage = "" } } }
            } catch { await MainActor.run { self.statusMessage = "❌ 移除失败" } }
        }
    }

    func downloadWallpaper(item: WallpaperItem) { if downloadProgress[item.id] != nil { return }; DispatchQueue.main.async { self.downloadProgress[item.id] = 0.01 }; Task { do { let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL); if !FileManager.default.fileExists(atPath: localURL.path) { let tempURL = try await downloadWithProgress(url: item.fullURL, itemId: item.id, isSilent: false); try FileManager.default.moveItem(at: tempURL, to: localURL) }; await MainActor.run { self.downloadProgress.removeValue(forKey: item.id); self.calculateCacheSize(); self.objectWillChange.send() } } catch { if (error as? URLError)?.code != .cancelled { await MainActor.run { self.downloadProgress.removeValue(forKey: item.id); self.statusMessage = "❌ 下载失败" } } } } }

    func setWallpaper(item: WallpaperItem, isSilent: Bool = false) { if downloadProgress[item.id] != nil { return }; if !isSilent { DispatchQueue.main.async { self.downloadProgress[item.id] = 0.01 } }; Task { do { let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL); if !FileManager.default.fileExists(atPath: localURL.path) { let tempURL = try await downloadWithProgress(url: item.fullURL, itemId: item.id, isSilent: isSilent); try FileManager.default.moveItem(at: tempURL, to: localURL) }; await MainActor.run { self.downloadProgress.removeValue(forKey: item.id); if item.isVideo { DesktopVideoManager.shared.playVideoOnDesktop(url: localURL, screenName: self.targetScreenName) } else { DesktopVideoManager.shared.clearVideoWallpaper(); self.applyStaticWallpaper(url: localURL) }; UserDefaults.standard.set(localURL.path, forKey: "LastWallpaperPath"); self.currentWallpaperPath = localURL.path; self.calculateCacheSize(); self.objectWillChange.send(); if !isSilent { statusMessage = "🎉 设置完成"; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage == "🎉 设置完成" { self.statusMessage = "" } } } }; if item.isVideo { await syncLockScreenWallpaper(for: localURL) } } catch { if (error as? URLError)?.code != .cancelled { if !isSilent { await MainActor.run { self.downloadProgress.removeValue(forKey: item.id); self.statusMessage = "❌ 操作失败" } } } } } }
    
    func toggleInPlaylist(item: WallpaperItem) { if let index = playlistIds.firstIndex(of: item.id) { playlistIds.remove(at: index); statusMessage = "已移出轮播列表" } else { playlistIds.append(item.id); statusMessage = "🌟 已加入轮播" }; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.statusMessage.contains("轮播") { self.statusMessage = "" } } }
    func toggleFavorite(item: WallpaperItem) { if let index = favoriteIds.firstIndex(of: item.id) { favoriteIds.remove(at: index); statusMessage = "已取消收藏" } else { favoriteIds.append(item.id); statusMessage = "❤️ 已加入收藏" }; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.statusMessage.contains("收藏") { self.statusMessage = "" } } }

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
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateCountdown() }
        if let t = countdownTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func updateCountdown() {
        let remaining = max(0, nextSlideshowDate.timeIntervalSinceNow)
        let h = Int(remaining) / 3600; let m = (Int(remaining) % 3600) / 60; let s = Int(remaining) % 60
        nextSlideshowCountdown = h > 0 ? "下次切换 \(h)h \(String(format: "%02d", m))m" : "下次切换 \(m):\(String(format: "%02d", s))"
    }

    private func playNextWallpaper() {
        guard !playlistIds.isEmpty else { return }
        if isSlideshowRandom {
            let randomIndex = Int.random(in: 0..<playlistIds.count)
            currentSlideshowIndex = randomIndex
        } else {
            currentSlideshowIndex = (currentSlideshowIndex + 1) % playlistIds.count
        }
        if let item = allWallpapers.first(where: { $0.id == playlistIds[currentSlideshowIndex] }) { setWallpaper(item: item, isSilent: true) }
    }
    func deleteSingleCache(for item: WallpaperItem) { let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL); if localURL.path == (UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? "") { statusMessage = "⚠️ 正在使用的壁纸无法删除"; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage.contains("⚠️") { self.statusMessage = "" } }; return }; try? FileManager.default.removeItem(at: localURL); if let idx = playlistIds.firstIndex(of: item.id) { playlistIds.remove(at: idx) }; self.calculateCacheSize(); self.objectWillChange.send(); statusMessage = "🗑️ 已清除该壁纸缓存"; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.statusMessage.contains("🗑️") { self.statusMessage = "" } } }
    private func syncLockScreenWallpaper(for videoURL: URL) async { let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL)); generator.appliesPreferredTrackTransform = true; do { let (cgImage, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)); if let jpegData = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [:]) { let lockScreenURL = WallpaperCacheManager.shared.cacheDirectory.appendingPathComponent("lockscreen_sync.jpg"); try jpegData.write(to: lockScreenURL); await MainActor.run { self.applyStaticWallpaper(url: lockScreenURL) } } } catch { } }
    func restoreLastWallpaper() { guard let path = UserDefaults.standard.string(forKey: "LastWallpaperPath") else { return }; let url = URL(fileURLWithPath: path); if FileManager.default.fileExists(atPath: url.path) { if url.pathExtension.lowercased() == "mp4" { DesktopVideoManager.shared.playVideoOnDesktop(url: url); Task { await syncLockScreenWallpaper(for: url) } } } }
    func toggleAutoStart(enable: Bool) { if #available(macOS 13.0, *) { do { if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; self.isAutoStartEnabled = enable } catch { self.isAutoStartEnabled = !enable } } }
    func calculateCacheSize() { var totalSize: Int64 = 0; if let files = try? FileManager.default.contentsOfDirectory(at: WallpaperCacheManager.shared.cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) { for file in files { if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize { totalSize += Int64(size) } } }; DispatchQueue.main.async { self.cacheSizeString = String(format: "%.1f MB", Double(totalSize) / (1024 * 1024)) } }
    func clearCache() { let currentPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""; if let files = try? FileManager.default.contentsOfDirectory(at: WallpaperCacheManager.shared.cacheDirectory, includingPropertiesForKeys: nil) { for file in files { if file.path != currentPath && file.lastPathComponent != "lockscreen_sync.jpg" { try? FileManager.default.removeItem(at: file) } } }; playlistIds.removeAll(); calculateCacheSize(); self.objectWillChange.send(); statusMessage = "✅ 缓存清理完成"; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage == "✅ 缓存清理完成" { self.statusMessage = "" } } }
    private func downloadWithProgress(url: URL, itemId: String, isSilent: Bool = false) async throws -> URL { return try await withCheckedThrowingContinuation { continuation in let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in DispatchQueue.main.async { self.progressObservations.removeValue(forKey: itemId) }; if let error = error { continuation.resume(throwing: error); return }; guard let tempURL = tempURL else { continuation.resume(throwing: URLError(.badServerResponse)); return }; let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try? FileManager.default.moveItem(at: tempURL, to: destination); continuation.resume(returning: destination) }; if !isSilent { self.progressObservations[itemId] = task.progress.observe(\.fractionCompleted) { progress, _ in DispatchQueue.main.async { self.downloadProgress[itemId] = progress.fractionCompleted } } }; task.resume() } }
    private func applyStaticWallpaper(url: URL) {
        let options = wallpaperFit.desktopImageOptions
        let screens: [NSScreen]
        if targetScreenName == "全部" {
            screens = NSScreen.screens
        } else {
            let filtered = NSScreen.screens.filter { $0.localizedName == targetScreenName }
            screens = filtered.isEmpty ? NSScreen.screens : filtered
        }
        for screen in screens { try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options) }
    }
}

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
