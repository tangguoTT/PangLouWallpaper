//
//  ImageFeatureExtractor.swift
//  PangLouWallpaper
//
//  从图片或视频提取 VNFeaturePrint 向量，用于以图搜图。
//

import Vision
import AppKit
import AVFoundation

struct ImageFeatureExtractor {

    /// 从图片或视频 URL 提取 VNFeaturePrint 浮点向量
    static func extract(from url: URL) async throws -> [Float] {
        let imageURL: URL
        var tempFile: URL? = nil

        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v"].contains(ext) {
            // 视频：先提取首帧缩略图写入临时文件
            let cgImage = try await videoThumbnail(from: url)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                try data.write(to: tmp)
            }
            imageURL = tmp
            tempFile = tmp
        } else {
            imageURL = url
        }

        defer { tempFile.map { try? FileManager.default.removeItem(at: $0) } }

        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        try handler.perform([request])

        guard let obs = request.results?.first as? VNFeaturePrintObservation else {
            throw NSError(domain: "ImageFeatureExtractor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法提取图像特征"])
        }
        return obs.floatArray()
    }

    private static func videoThumbnail(from url: URL) async throws -> CGImage {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 512, height: 512)
        return try gen.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 1), actualTime: nil)
    }
}

private extension VNFeaturePrintObservation {
    func floatArray() -> [Float] {
        var out = [Float](repeating: 0, count: elementCount)
        data.withUnsafeBytes { raw in
            switch elementType {
            case .float:
                let buf = raw.bindMemory(to: Float.self)
                for i in 0..<elementCount { out[i] = buf[i] }
            case .double:
                let buf = raw.bindMemory(to: Double.self)
                for i in 0..<elementCount { out[i] = Float(buf[i]) }
            @unknown default: break
            }
        }
        return out
    }
}
