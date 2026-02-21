//
//  Models.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/21.
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
}
