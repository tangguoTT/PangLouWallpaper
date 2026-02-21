//
//  URLExtension.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/21.
//

// 专门处理阿里云 OSS 的图片/视频缩略图逻辑。

import Foundation

extension URL {
    func ossThumb(isVideo: Bool) -> URL {
        let base = self.absoluteString
        if isVideo {
            return URL(string: base + "?x-oss-process=video/snapshot,t_1000,f_jpg,w_400,m_fast") ?? self
        } else {
            return URL(string: base + "?x-oss-process=image/resize,m_fill,h_250,w_400") ?? self
        }
    }
}
