//
//  WallpaperCacheManager.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/21.
//

// 负责所有的硬盘读写、哈希加密防重复。

import AppKit
import CryptoKit
import ImageIO

class WallpaperCacheManager {
    static let shared = WallpaperCacheManager()
    let fileManager = FileManager.default

    /// 专用 Session：禁用内存响应缓存（文件已由我们自己写磁盘，避免双重占用内存）
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    // MARK: - 内存缩略图缓存
    // NSCache 在系统内存压力下自动驱逐条目，不需要手动管理。
    // cost = 解码像素字节数（width × height × 4），上限约 150 MB。
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 80
        c.totalCostLimit = 150_000_000
        return c
    }()

    /// 从本地文件加载缩略图，最长边缩放到 maxDimension 像素。
    /// 使用 CGImageSource thumbnail API，全分辨率图像**不会**被解码进内存。
    static func downsampledImage(at url: URL, maxDimension: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }

    private static let customCacheDirKey = "CustomCacheDirectory"

    static var defaultCacheDirectory: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("PangLouWallpaperCache")
    }

    private(set) var cacheDirectory: URL

    /// 云端下载文件存放目录
    var cloudDirectory: URL {
        let url = cacheDirectory.appendingPathComponent("cloud")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Workshop 下载文件存放目录（每个 item 一个子目录）
    var workshopDirectory: URL {
        let url = cacheDirectory.appendingPathComponent("workshop")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() {
        if let savedPath = UserDefaults.standard.string(forKey: WallpaperCacheManager.customCacheDirKey) {
            let url = URL(fileURLWithPath: savedPath)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            cacheDirectory = url
        } else {
            let url = WallpaperCacheManager.defaultCacheDirectory
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            cacheDirectory = url
        }
        migrateRootFilesToCloud()
    }

    /// 首次升级迁移：把旧版本平铺在根目录的云端缓存文件移入 cloud/ 子目录
    private func migrateRootFilesToCloud() {
        let cloud = cacheDirectory.appendingPathComponent("cloud")
        try? FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        let skipNames: Set<String> = ["cloud", "workshop", "local_imports", "steamcmd"]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for entry in entries {
            if skipNames.contains(entry.lastPathComponent) { continue }
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDir else { continue }
            let dest = cloud.appendingPathComponent(entry.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.moveItem(at: entry, to: dest)
            }
        }
    }

    func setCacheDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        // 预先建好三个子目录
        try fileManager.createDirectory(at: url.appendingPathComponent("cloud"),    withIntermediateDirectories: true)
        try fileManager.createDirectory(at: url.appendingPathComponent("workshop"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: url.appendingPathComponent("local_imports"), withIntermediateDirectories: true)
        UserDefaults.standard.set(url.path, forKey: WallpaperCacheManager.customCacheDirKey)
        cacheDirectory = url
    }

    func resetToDefaultCacheDirectory() {
        UserDefaults.standard.removeObject(forKey: WallpaperCacheManager.customCacheDirKey)
        let url = WallpaperCacheManager.defaultCacheDirectory
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        cacheDirectory = url
    }

    private func stableHash(for string: String) -> String {
        let data = Data(string.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 已下载壁纸的完整缓存路径（存于 cloud/ 子目录）
    func getLocalPath(for url: URL) -> URL {
        let key = stableHash(for: url.absoluteString)
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return cloudDirectory.appendingPathComponent("\(key).\(ext)")
    }

    /// 缩略图专用缓存路径（thumb_ 前缀，cloud/ 子目录）
    private func getThumbnailPath(for url: URL) -> URL {
        let key = stableHash(for: url.absoluteString)
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return cloudDirectory.appendingPathComponent("thumb_\(key).\(ext)")
    }

    /// 预览视频专用缓存路径（preview_ 前缀，cloud/ 子目录）
    func getPreviewCachePath(for url: URL) -> URL {
        let key = stableHash(for: url.absoluteString)
        return cloudDirectory.appendingPathComponent("preview_\(key).mp4")
    }

    /// 下载并缓存预览视频，返回本地路径；已缓存则直接返回
    func fetchAndCachePreview(for url: URL) async -> URL? {
        let localPath = getPreviewCachePath(for: url)
        if fileManager.fileExists(atPath: localPath.path) {
            // 有效 MP4 至少几十 KB；404 HTML 响应通常 < 2 KB，直接删除重下
            let size = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int) ?? 0
            if size > 4096 { return localPath }
            try? fileManager.removeItem(at: localPath)
        }
        do {
            let (data, response) = try await WallpaperCacheManager.session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            try data.write(to: localPath)
            return localPath
        } catch {
            return nil
        }
    }

    // MARK: - 磁盘缓存清理

    /// cloud/ 目录当前占用字节数
    func cloudCacheSize() -> Int64 {
        let dir = cloudDirectory
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    /// 当 cloud/ 缓存超过 limitBytes 时，按最久未访问顺序删除旧文件，直到降至 limitBytes 以下。
    /// 默认上限 3 GB。
    func cleanupCloudCacheIfNeeded(limitBytes: Int64 = 3 * 1024 * 1024 * 1024) {
        let dir = cloudDirectory
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }

        var files: [(url: URL, size: Int64, accessed: Date)] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentAccessDateKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            let accessed = values?.contentAccessDate ?? .distantPast
            files.append((fileURL, size, accessed))
        }

        let total = files.reduce(0) { $0 + $1.size }
        guard total > limitBytes else { return }

        // 按最久未访问排序，优先删除
        files.sort { $0.accessed < $1.accessed }
        var running = total
        for file in files {
            guard running > limitBytes else { break }
            if (try? fileManager.removeItem(at: file.url)) != nil {
                running -= file.size
            }
        }
    }

    /// 加载完整壁纸图片（用于已下载缓存，写入 getLocalPath 路径）
    func fetchImage(for url: URL) async -> NSImage? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        }
        let localPath = getLocalPath(for: url)
        let diskImg = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let data = try? Data(contentsOf: localPath) else { return nil }
            return NSImage(data: data)
        }.value
        if let image = diskImg { return image }
        do {
            let (data, _) = try await WallpaperCacheManager.session.data(from: url)
            return await Task.detached(priority: .utility) { () -> NSImage? in
                try? data.write(to: localPath)
                return NSImage(data: data)
            }.value
        } catch { return nil }
    }

    /// 加载缩略图（写入 thumb_ 前缀路径，绝不影响 isDownloaded 判断）。
    /// 本地文件使用 CGImageSource 降采样，远端图片命中磁盘缓存后同样降采样。
    /// 解码结果写入内存 NSCache（自动在系统内存压力下驱逐）。
    func fetchThumbnail(for url: URL) async -> NSImage? {
        let cacheKey = url.absoluteString as NSString
        if let hit = WallpaperCacheManager.thumbnailCache.object(forKey: cacheKey) { return hit }

        func store(_ img: NSImage) -> NSImage {
            let cost = Int(img.size.width * img.size.height) * 4
            WallpaperCacheManager.thumbnailCache.setObject(img, forKey: cacheKey, cost: cost)
            return img
        }

        if url.isFileURL {
            return await Task.detached(priority: .utility) {
                guard let img = WallpaperCacheManager.downsampledImage(at: url, maxDimension: 400) else { return nil }
                return store(img)
            }.value
        }

        let localPath = getThumbnailPath(for: url)
        let diskImg = await Task.detached(priority: .utility) { () -> NSImage? in
            guard FileManager.default.fileExists(atPath: localPath.path) else { return nil }
            return WallpaperCacheManager.downsampledImage(at: localPath, maxDimension: 400)
        }.value
        if let img = diskImg { return store(img) }

        do {
            let (data, _) = try await WallpaperCacheManager.session.data(from: url)
            return await Task.detached(priority: .utility) { () -> NSImage? in
                try? data.write(to: localPath)
                guard let img = WallpaperCacheManager.downsampledImage(at: localPath, maxDimension: 400) else { return nil }
                return store(img)
            }.value
        } catch { return nil }
    }
}
