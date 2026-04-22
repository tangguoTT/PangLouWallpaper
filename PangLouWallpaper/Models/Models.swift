//
//  Models.swift
//  SimpleWallpaper
//

import Foundation

/// 审核状态：nil 表示旧数据（视为 approved）
enum ApprovalStatus: String, Codable {
    case pending  = "pending"   // 待审核
    case approved = "approved"  // 已通过
    case rejected = "rejected"  // 已拒绝
}

struct WallpaperItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let wallpaperDescription: String
    let tags: [String]
    let category: String
    let resolution: String
    let color: String
    let isVideo: Bool
    var fullURL: URL
    /// 轻量预览片段（上传时截取前4秒压缩生成），用于卡片悬停动态预览
    var previewURL: URL?
    let uploadedAt: Int
    let uploadedBy: String?
    /// nil = 旧数据，等同于 approved
    var approvalStatus: ApprovalStatus?
    var rejectionReason: String?

    enum CodingKeys: String, CodingKey {
        case id, title, isVideo, fullURL, previewURL
        case wallpaperDescription = "description"
        case tags, category, resolution, color, uploadedAt
        case uploadedBy      = "uploaded_by"
        case approvalStatus  = "approval_status"
        case rejectionReason = "rejection_reason"
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
        previewURL: URL? = nil,
        uploadedAt: Int = 0,
        uploadedBy: String? = nil,
        approvalStatus: ApprovalStatus? = nil,
        rejectionReason: String? = nil
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
        self.previewURL = previewURL
        self.uploadedAt = uploadedAt
        self.uploadedBy = uploadedBy
        self.approvalStatus = approvalStatus
        self.rejectionReason = rejectionReason
    }

    // 兼容旧格式 JSON（缺失字段给默认值）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isVideo = try c.decode(Bool.self, forKey: .isVideo)
        fullURL = try c.decode(URL.self, forKey: .fullURL)
        previewURL = try? c.decodeIfPresent(URL.self, forKey: .previewURL)
        wallpaperDescription = (try? c.decodeIfPresent(String.self, forKey: .wallpaperDescription)) ?? ""
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? ""
        resolution = (try? c.decodeIfPresent(String.self, forKey: .resolution)) ?? ""
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? ""
        uploadedAt = (try? c.decodeIfPresent(Int.self, forKey: .uploadedAt)) ?? 0
        uploadedBy = try? c.decodeIfPresent(String.self, forKey: .uploadedBy)
        approvalStatus = try? c.decodeIfPresent(ApprovalStatus.self, forKey: .approvalStatus)
        rejectionReason = try? c.decodeIfPresent(String.self, forKey: .rejectionReason)
    }

    /// 是否对所有用户可见（通过审核或旧数据）
    var isPubliclyVisible: Bool {
        approvalStatus == nil || approvalStatus == .approved
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
    case steamWorkshop = "Steam Workshop"
}

// MARK: - Steam Workshop

struct SteamWorkshopItem: Identifiable, Equatable {
    let id: String           // publishedfileid
    let title: String
    let previewURL: URL?
    var description: String
    var tags: [String]
    var fileSize: Int        // bytes, 0 = not yet fetched
    let timeUpdated: Int

    var isVideo: Bool {
        tags.contains(where: { $0.lowercased() == "video" })
    }

    /// Wallpaper Engine type derived from tags
    var weType: WEType {
        let low = tags.map { $0.lowercased() }
        if low.contains("video")   { return .video }
        if low.contains("scene")   { return .scene }
        if low.contains("web")     { return .web }
        if low.contains("preset")  { return .preset }
        if low.contains("image")   { return .image }
        return .unknown
    }

    /// macOS 可直接使用（无需 Wallpaper Engine）
    var isMacOSCompatible: Bool { weType == .video || weType == .image || weType == .web }

    enum WEType {
        case video, image, scene, web, preset, unknown

        var displayName: String {
            switch self {
            case .video:   return "视频"
            case .image:   return "图片"
            case .scene:   return "场景"
            case .web:     return "网页"
            case .preset:  return "预设"
            case .unknown: return "未知"
            }
        }
        var needsWE: Bool { self == .scene || self == .preset }
        var systemImage: String {
            switch self {
            case .video:  return "play.circle.fill"
            case .image:  return "photo.fill"
            case .scene:  return "cube.fill"
            case .web:    return "globe"
            case .preset: return "slider.horizontal.3"
            case .unknown: return "questionmark.circle"
            }
        }
    }
}

enum WorkshopDownloadState {
    case downloading
    case done(URL)
    case failed(String)
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
    case local         // 云端下载到本地缓存
    case workshop      // Steam Workshop 下载
    case localImports  // 手动导入
}

// MARK: - 定时换壁纸时间段

enum DayPeriod: String, CaseIterable, Codable, Identifiable {
    case morning   = "早晨"   // 06:00–12:00
    case afternoon = "下午"   // 12:00–18:00
    case night     = "夜晚"   // 18:00–06:00

    var id: String { rawValue }

    var timeRange: String {
        switch self {
        case .morning:   return "06:00 – 12:00"
        case .afternoon: return "12:00 – 18:00"
        case .night:     return "18:00 – 06:00"
        }
    }

    static func current() -> DayPeriod {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12:  return .morning
        case 12..<18: return .afternoon
        default:      return .night
        }
    }
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
