//
//  URLExtension.swift
//  SimpleWallpaper
//
//  缩略图 URL 生成规则：
//  - 静态图片：Cloudflare Image Resizing（需在 Dashboard → Speed → Optimization 开启）
//  - 动态视频：约定路径 thumbnails/{id}.jpg（上传视频时同步截首帧上传）

import Foundation

extension URL {
    func ossThumb(isVideo: Bool) -> URL {
        let base = self.absoluteString
        guard let hostRange = base.range(of: "://"),
              let slash = base[hostRange.upperBound...].firstIndex(of: "/") else { return self }
        let scheme = String(base[base.startIndex ..< hostRange.lowerBound])
        let host   = String(base[hostRange.upperBound ..< slash])
        let path   = String(base[slash...])

        if isVideo {
            // 约定：视频 ID（文件名去掉扩展名）对应缩略图在 thumbnails/{id}.jpg
            let stem = self.deletingPathExtension().lastPathComponent
            return URL(string: "\(scheme)://\(host)/thumbnails/\(stem).jpg") ?? self
        } else {
            // Cloudflare Image Resizing
            return URL(string: "\(scheme)://\(host)/cdn-cgi/image/width=400,height=250,fit=cover\(path)") ?? self
        }
    }

    /// Steam CDN 图片尺寸参数替换（images.steamusercontent.com 支持 imw/imh 缩放）
    func steamPreview(width: Int, height: Int) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var items = (comps.queryItems ?? []).filter {
            !["imw", "imh", "ima", "impolicy", "imcolor", "letterbox"].contains($0.name)
        }
        items += [
            URLQueryItem(name: "imw", value: "\(width)"),
            URLQueryItem(name: "imh", value: "\(height)"),
            URLQueryItem(name: "ima", value: "fit"),
        ]
        comps.queryItems = items
        return comps.url ?? self
    }

    /// 轻量预览片段路径：previews/{id}.mp4
    func ossPreview() -> URL {
        let base = self.absoluteString
        guard let hostRange = base.range(of: "://"),
              let slash = base[hostRange.upperBound...].firstIndex(of: "/") else { return self }
        let scheme = String(base[base.startIndex ..< hostRange.lowerBound])
        let host   = String(base[hostRange.upperBound ..< slash])
        let stem   = self.deletingPathExtension().lastPathComponent
        return URL(string: "\(scheme)://\(host)/previews/\(stem).mp4") ?? self
    }
}
