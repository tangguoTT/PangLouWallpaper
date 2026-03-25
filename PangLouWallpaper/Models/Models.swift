//
//  Models.swift
//  SimpleWallpaper
//

import Foundation

struct WallpaperItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let fullURL: URL
    let isVideo: Bool
}

enum AppTab: String {
    case pc = "电脑壁纸"
    case downloaded = "已下载壁纸"
    case slideshow = "轮播壁纸"
    case upload = "上传壁纸" // 🌟 新增：独立的上传专属频道
}

enum WallpaperFit: String, CaseIterable {
    case fill   = "填充"
    case fit    = "适应"
    case stretch = "拉伸"
    case center = "居中"
}

// 🌟 新增：代表"待上传列表"里每一张图片的数据模型
struct PendingUploadItem: Identifiable {
    let id = UUID()
    let url: URL
    var category: String = "全部"
    var resolution: String = "全部"
    var color: String = "全部"
}
