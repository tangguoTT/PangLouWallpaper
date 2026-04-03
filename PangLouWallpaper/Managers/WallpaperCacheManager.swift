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
    
    lazy var cacheDirectory: URL = {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let path = urls[0].appendingPathComponent("PangLouWallpaperCache")
        try? fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }()
    
    private func stableHash(for string: String) -> String {
        let data = Data(string.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func getLocalPath(for url: URL) -> URL {
        let key = stableHash(for: url.absoluteString)
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return cacheDirectory.appendingPathComponent("\(key).\(ext)")
    }
    
    func fetchImage(for url: URL) async -> NSImage? {
        // 本地文件直接读取，无需缓存
        if url.isFileURL {
            return await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        }
        let localPath = getLocalPath(for: url)
        // 磁盘 I/O 放到后台线程，避免阻塞主线程
        if let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let data = try? Data(contentsOf: localPath) else { return nil }
            return NSImage(data: data)
        }.value {
            return image
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // 写盘也在后台完成，同时解码图片
            return await Task.detached(priority: .utility) { () -> NSImage? in
                try? data.write(to: localPath)
                return NSImage(data: data)
            }.value
        } catch { return nil }
    }
}
