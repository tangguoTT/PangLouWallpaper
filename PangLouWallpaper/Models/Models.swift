//
//  Models.swift
//  SimpleWallpaper
//

import Foundation

struct WallpaperItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let wallpaperDescription: String
    let tags: [String]
    let category: String
    let resolution: String
    let color: String
    let isVideo: Bool
    let fullURL: URL
    let uploadedAt: Int
    let uploadedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, title, isVideo, fullURL
        case wallpaperDescription = "description"
        case tags, category, resolution, color, uploadedAt
        case uploadedBy = "uploaded_by"
    }

    init(
        id: String,
        title: String,
        wallpaperDescription: String = "",
        tags: [String] = [],
        category: String = "",
        resolution: String = "",
        color: String = "",
        isVideo: Bool,
        fullURL: URL,
        uploadedAt: Int = 0,
        uploadedBy: String? = nil
    ) {
        self.id = id
        self.title = title
        self.wallpaperDescription = wallpaperDescription
        self.tags = tags
        self.category = category
        self.resolution = resolution
        self.color = color
        self.isVideo = isVideo
        self.fullURL = fullURL
        self.uploadedAt = uploadedAt
        self.uploadedBy = uploadedBy
    }

    // 兼容旧格式 JSON（缺失字段给默认值）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isVideo = try c.decode(Bool.self, forKey: .isVideo)
        fullURL = try c.decode(URL.self, forKey: .fullURL)
        wallpaperDescription = (try? c.decodeIfPresent(String.self, forKey: .wallpaperDescription)) ?? ""
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? ""
        resolution = (try? c.decodeIfPresent(String.self, forKey: .resolution)) ?? ""
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? ""
        uploadedAt = (try? c.decodeIfPresent(Int.self, forKey: .uploadedAt)) ?? 0
        uploadedBy = (try? c.decodeIfPresent(String.self, forKey: .uploadedBy)) ?? nil
    }
}

// MARK: - User Profile

struct UserProfile: Codable {
    let id: String
    var username: String
    var avatarURL: String

    enum CodingKeys: String, CodingKey {
        case id, username
        case avatarURL = "avatar_url"
    }
}

enum AppTab: String {
    case pc = "电脑壁纸"
    case downloaded = "已下载壁纸"
    case slideshow = "轮播壁纸"
    case collection = "我的合集"
    case upload = "上传壁纸"
}

struct WallpaperCollection: Identifiable, Codable {
    let id: String
    var name: String
    var coverWallpaperId: String
    var wallpaperIds: [String]
    let createdAt: Int

    init(id: String = UUID().uuidString, name: String, wallpaperIds: [String] = []) {
        self.id = id
        self.name = name
        self.wallpaperIds = wallpaperIds
        self.coverWallpaperId = wallpaperIds.first ?? ""
        self.createdAt = Int(Date().timeIntervalSince1970)
    }
}

enum DownloadedSubTab {
    case local         // 已下载到本地缓存
    case localImports  // 本地导入
}

enum WallpaperFit: String, CaseIterable {
    case fill    = "填充"
    case fit     = "适应"
    case stretch = "拉伸"
    case center  = "居中"
}

struct PendingUploadItem: Identifiable {
    let id = UUID()
    let url: URL
    var title: String = ""
    var wallpaperDescription: String = ""
    var tags: String = ""           // 逗号分隔，如 "动漫, 夜晚, 城市"
    var category: String = ""
    var resolution: String = ""
    var color: String = ""
}
