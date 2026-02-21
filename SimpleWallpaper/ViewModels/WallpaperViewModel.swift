//
//  WallpaperManager.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/21.
//

// 负责网络请求、开机自启、页面路由控制等所有的业务逻辑。

import SwiftUI
import AppKit
import AVKit
import Combine
import ServiceManagement

class WallpaperViewModel: ObservableObject {
    @Published var allWallpapers: [WallpaperItem] = []
    @Published var statusMessage: String = ""
    @Published var currentPage: Int = 0
    let itemsPerPage: Int = 12
    
    @Published var isAutoStartEnabled: Bool = false
    @Published var cacheSizeString: String = "0 MB"
    
    @Published var currentTab: AppTab = .pc { didSet { currentPage = 0 } }
    
    // 💡 菜单的显示状态
    @Published var showTypeMenu: Bool = false
    @Published var showCategoryMenu: Bool = false
    @Published var showResolutionMenu: Bool = false
    @Published var showColorMenu: Bool = false
    
    // 💡 用户的选择状态
    @Published var selectedType: String = "全部" { didSet { currentPage = 0 } }
    @Published var selectedCategory: String = "全部" { didSet { currentPage = 0 } }
    @Published var selectedResolution: String = "全部" { didSet { currentPage = 0 } }
    @Published var selectedColor: String = "全部" { didSet { currentPage = 0 } }
    
    // 💡 分辨率自定义输入框
    @Published var customWidth: String = ""
    @Published var customHeight: String = ""
    
    private var currentDownloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    let jsonConfigURL = URL(string: "https://wallpapers-pl.oss-cn-beijing.aliyuncs.com/wallpapers/wallpapers.json")!

    var displayWallpapers: [WallpaperItem] {
        var items = allWallpapers
        
        if currentTab == .downloaded {
            items = items.filter { item in
                let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
                return FileManager.default.fileExists(atPath: localURL.path)
            }
        }
        
        if selectedType == "静态壁纸" {
            items = items.filter { !$0.isVideo }
        } else if selectedType == "动态壁纸" {
            items = items.filter { $0.isVideo }
        }
        
        if selectedCategory != "全部" {
            let keyword = selectedCategory.components(separatedBy: " | ").first ?? selectedCategory
            items = items.filter { $0.title.contains(keyword) }
        }
        
        // 💡 色系过滤（根据实际数据格式扩展，目前简单通过 title 匹配做 Demo）
        if selectedColor != "全部" {
            items = items.filter { $0.title.contains(selectedColor) }
        }
        
        // 💡 分辨率过滤（同样通过 title 匹配做 Demo，真实环境应比对图片 meta 数据）
        if selectedResolution != "全部" {
            items = items.filter { $0.title.contains(selectedResolution) }
        }
        if !customWidth.isEmpty || !customHeight.isEmpty {
            // 这里假装触发自定义搜索逻辑
            items = items.filter { $0.title.contains(customWidth) || $0.title.contains(customHeight) }
        }
        
        return items
    }

    var totalPages: Int { max(1, Int(ceil(Double(displayWallpapers.count) / Double(itemsPerPage)))) }
    
    var paginatedImages: [WallpaperItem] {
        let items = displayWallpapers
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, items.count)
        guard startIndex < endIndex else { return [] }
        return Array(items[startIndex..<endIndex])
    }

    init() {
        if #available(macOS 13.0, *) { self.isAutoStartEnabled = SMAppService.mainApp.status == .enabled }
        calculateCacheSize()
    }

    // ... (保持原有的 fetchCloudData, setWallpaper, clearCache 等底层方法完全不变) ...
    func fetchCloudData() {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: jsonConfigURL)
                let items = try JSONDecoder().decode([WallpaperItem].self, from: data)
                await MainActor.run { self.allWallpapers = items }
            } catch { await MainActor.run { self.statusMessage = "❌ 同步失败" } }
        }
    }

    func setWallpaper(item: WallpaperItem) {
        currentDownloadTask?.cancel()
        statusMessage = "正在准备素材..."
        Task {
            do {
                let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
                if !FileManager.default.fileExists(atPath: localURL.path) {
                    let tempURL = try await downloadWithProgress(url: item.fullURL)
                    try FileManager.default.moveItem(at: tempURL, to: localURL)
                }
                await MainActor.run {
                    if item.isVideo { DesktopVideoManager.shared.playVideoOnDesktop(url: localURL) }
                    else { DesktopVideoManager.shared.clearVideoWallpaper(); self.applyStaticWallpaper(url: localURL) }
                    UserDefaults.standard.set(localURL.path, forKey: "LastWallpaperPath")
                    self.calculateCacheSize()
                    self.objectWillChange.send()
                    statusMessage = "🎉 设置完成"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage == "🎉 设置完成" { self.statusMessage = "" } }
                }
                if item.isVideo { await syncLockScreenWallpaper(for: localURL) }
            } catch {
                if (error as? URLError)?.code != .cancelled { await MainActor.run { self.statusMessage = "❌ 操作失败" } }
            }
        }
    }
    
    func deleteSingleCache(for item: WallpaperItem) {
        let localURL = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
        let currentWallpaperPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        if localURL.path == currentWallpaperPath {
            statusMessage = "⚠️ 正在使用的壁纸无法删除"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage.contains("⚠️") { self.statusMessage = "" } }
            return
        }
        try? FileManager.default.removeItem(at: localURL)
        self.calculateCacheSize()
        self.objectWillChange.send()
        statusMessage = "🗑️ 已清除该壁纸缓存"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.statusMessage.contains("🗑️") { self.statusMessage = "" } }
    }
    
    private func syncLockScreenWallpaper(for videoURL: URL) async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        do {
            let time = CMTime(seconds: 1, preferredTimescale: 600)
            let (cgImage, _) = try await generator.image(at: time)
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            if let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                let lockScreenURL = WallpaperCacheManager.shared.cacheDirectory.appendingPathComponent("lockscreen_sync.jpg")
                try jpegData.write(to: lockScreenURL)
                await MainActor.run { self.applyStaticWallpaper(url: lockScreenURL) }
            }
        } catch { }
    }
    
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
            } catch { self.isAutoStartEnabled = !enable }
        }
    }
    
    func calculateCacheSize() {
        let cacheURL = WallpaperCacheManager.shared.cacheDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        var totalSize: Int64 = 0
        for file in files {
            if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize { totalSize += Int64(size) }
        }
        let sizeInMB = Double(totalSize) / (1024 * 1024)
        DispatchQueue.main.async { self.cacheSizeString = String(format: "%.1f MB", sizeInMB) }
    }
    
    func clearCache() {
        let cacheURL = WallpaperCacheManager.shared.cacheDirectory
        let currentWallpaperPath = UserDefaults.standard.string(forKey: "LastWallpaperPath") ?? ""
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil) else { return }
        for file in files {
            if file.path != currentWallpaperPath && file.lastPathComponent != "lockscreen_sync.jpg" { try? FileManager.default.removeItem(at: file) }
        }
        calculateCacheSize()
        self.objectWillChange.send()
        statusMessage = "✅ 缓存清理完成"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.statusMessage == "✅ 缓存清理完成" { self.statusMessage = "" } }
    }
    
    private func downloadWithProgress(url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let tempURL = tempURL else { continuation.resume(throwing: URLError(.badServerResponse)); return }
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? FileManager.default.moveItem(at: tempURL, to: destination)
                continuation.resume(returning: destination)
            }
            self.currentDownloadTask = task
            self.progressObservation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let percent = Int(progress.fractionCompleted * 100)
                DispatchQueue.main.async { self.statusMessage = "正在下载原件... \(percent)%" }
            }
            task.resume()
        }
    }
    
    private func applyStaticWallpaper(url: URL) {
        for screen in NSScreen.screens { try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
    }
}
