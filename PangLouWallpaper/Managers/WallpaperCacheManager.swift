//
//  WallpaperCacheManager.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/21.
//

// 负责所有的硬盘读写、哈希加密防重复。

import AppKit
import CryptoKit

class WallpaperCacheManager {
    static let shared = WallpaperCacheManager()
    let fileManager = FileManager.default

    /// 专用 Session：禁用内存响应缓存（文件已由我们自己写磁盘，避免双重占用内存）
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static let customCacheDirKey = "CustomCacheDirectory"

    static var defaultCacheDirectory: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("PangLouWallpaperCache")
    }

    private(set) var cacheDirectory: URL

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
    }

    func setCacheDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
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

    /// 已下载壁纸的完整缓存路径（不含 thumb_ 前缀）
    func getLocalPath(for url: URL) -> URL {
        let key = stableHash(for: url.absoluteString)
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return cacheDirectory.appendingPathComponent("\(key).\(ext)")
    }

    /// 缩略图专用缓存路径（thumb_ 前缀，与完整下载文件严格区分）
    private func getThumbnailPath(for url: URL) -> URL {
        let key = stableHash(for: url.absoluteString)
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return cacheDirectory.appendingPathComponent("thumb_\(key).\(ext)")
    }

    /// 预览视频专用缓存路径（preview_ 前缀）
    func getPreviewCachePath(for url: URL) -> URL {
        let key = stableHash(for: url.absoluteString)
        return cacheDirectory.appendingPathComponent("preview_\(key).mp4")
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

    /// 加载完整壁纸图片（用于已下载缓存，写入 getLocalPath 路径）
    func fetchImage(for url: URL) async -> NSImage? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        }
        let localPath = getLocalPath(for: url)
        if let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let data = try? Data(contentsOf: localPath) else { return nil }
            return NSImage(data: data)
        }.value {
            return image
        }
        do {
            let (data, _) = try await WallpaperCacheManager.session.data(from: url)
            return await Task.detached(priority: .utility) { () -> NSImage? in
                try? data.write(to: localPath)
                return NSImage(data: data)
            }.value
        } catch { return nil }
    }

    /// 加载缩略图（写入 thumb_ 前缀路径，绝不影响 isDownloaded 判断）
    func fetchThumbnail(for url: URL) async -> NSImage? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        }
        let localPath = getThumbnailPath(for: url)
        if let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let data = try? Data(contentsOf: localPath) else { return nil }
            return NSImage(data: data)
        }.value {
            return image
        }
        do {
            let (data, _) = try await WallpaperCacheManager.session.data(from: url)
            return await Task.detached(priority: .utility) { () -> NSImage? in
                try? data.write(to: localPath)
                return NSImage(data: data)
            }.value
        } catch { return nil }
    }
}
