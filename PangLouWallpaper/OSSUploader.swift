//
//  OSSUploader.swift
//  SimpleWallpaper
//
//  Cloudflare R2 uploader (S3-compatible API, AWS Signature V4).

import Foundation
import CryptoKit
import AVFoundation
import AppKit

class OSSUploader {
    static let shared = OSSUploader()

    private let accessKeyId: String
    private let accessKeySecret: String
    private let accountId: String
    private let bucketName: String
    private let customDomain: String
    // 静态壁纸 → images/，动态壁纸 → videos/
    private func folder(isVideo: Bool) -> String { isVideo ? "videos" : "images" }

    private init() {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url) as? [String: String],
            let keyId     = dict["R2AccessKeyId"],
            let keySecret = dict["R2AccessKeySecret"],
            let acctId    = dict["R2AccountId"],
            let bucket    = dict["R2BucketName"],
            let domain    = dict["R2CustomDomain"]
        else {
            fatalError("Secrets.plist 未找到或缺少 R2 相关字段，请参考 Secrets.plist.example 创建该文件")
        }
        self.accessKeyId    = keyId
        self.accessKeySecret = keySecret
        self.accountId      = acctId
        self.bucketName     = bucket
        var d = domain.hasSuffix("/") ? String(domain.dropLast()) : domain
        if !d.hasPrefix("http://") && !d.hasPrefix("https://") { d = "https://" + d }
        self.customDomain   = d
    }

    /// 上传文件到 Cloudflare R2，返回填好 fullURL 的 WallpaperItem。
    /// onProgress: 0.0 ~ 1.0，在主线程之外回调，调用方自行切换线程。
    func uploadFile(
        fileURL: URL,
        fileData: Data,
        draft: WallpaperItem,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> WallpaperItem {
        let ext = fileURL.pathExtension.lowercased()
        let fileName   = draft.id + "." + ext
        let objectKey  = folder(isVideo: draft.isVideo) + "/" + fileName

        try await putObject(objectKey: objectKey, data: fileData, fileExtension: ext, onProgress: onProgress)

        let publicURL = "\(customDomain)/\(objectKey)"
        return WallpaperItem(
            id: draft.id,
            title: draft.title,
            wallpaperDescription: draft.wallpaperDescription,
            tags: draft.tags,
            category: draft.category,
            resolution: draft.resolution,
            color: draft.color,
            isVideo: draft.isVideo,
            fullURL: URL(string: publicURL)!,
            uploadedAt: draft.uploadedAt
        )
    }

    /// 上传视频首帧缩略图到 thumbnails/{itemId}.jpg
    func uploadVideoThumbnail(videoURL: URL, itemId: String) async throws {
        let asset     = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 500)

        let (cgImage, _) = try await generator.image(at: .zero)
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        guard let tiff    = nsImage.tiffRepresentation,
              let rep     = NSBitmapImageRep(data: tiff),
              let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { throw URLError(.cannotDecodeContentData) }

        try await putObject(objectKey: "thumbnails/\(itemId).jpg",
                            data: jpegData, fileExtension: "jpg", onProgress: nil)
    }

    /// 删除视频对应的缩略图 thumbnails/{itemId}.jpg
    func deleteThumbnail(itemId: String) async throws {
        try await sendRequest(method: "DELETE", objectKey: "thumbnails/\(itemId).jpg", data: Data())
    }

    /// 从 R2 删除文件。objectKey 从 fullURL 去掉 customDomain 前缀得到。
    func deleteObject(for item: WallpaperItem) async throws {
        let base = item.fullURL.absoluteString
        guard base.hasPrefix(customDomain) else { return }
        let objectKey = String(base.dropFirst(customDomain.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        try await sendRequest(method: "DELETE", objectKey: objectKey, data: Data())
    }

    // MARK: - AWS Signature V4

    private func putObject(
        objectKey: String,
        data: Data,
        fileExtension: String,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        let region  = "auto"
        let service = "s3"
        let host    = "\(accountId).r2.cloudflarestorage.com"
        let path    = "/\(bucketName)/\(objectKey)"
        let uploadURL = URL(string: "https://\(host)\(path)")!

        let contentType = mimeType(for: fileExtension)
        let now        = Date()
        let amzDate    = iso8601Full.string(from: now)
        let dateStamp  = iso8601Date.string(from: now)

        let payloadHash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }.joined()

        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let canonicalHeaders =
            "content-type:\(contentType)\n" +
            "host:\(host)\n" +
            "x-amz-content-sha256:\(payloadHash)\n" +
            "x-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = ["PUT", encodedPath, "", canonicalHeaders, signedHeaders, payloadHash]
            .joined(separator: "\n")

        let credentialScope  = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalHash    = SHA256.hash(data: Data(canonicalRequest.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let stringToSign     = ["AWS4-HMAC-SHA256", amzDate, credentialScope, canonicalHash]
            .joined(separator: "\n")

        let signingKey = deriveSigningKey(secret: accessKeySecret, date: dateStamp,
                                          region: region, service: service)
        let signature  = hmac(key: signingKey, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }.joined()

        let authorization =
            "AWS4-HMAC-SHA256 " +
            "Credential=\(accessKeyId)/\(credentialScope), " +
            "SignedHeaders=\(signedHeaders), " +
            "Signature=\(signature)"

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType,   forHTTPHeaderField: "Content-Type")
        request.setValue(amzDate,       forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash,   forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        if let onProgress {
            // 用 delegate 跟踪上传字节数
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let delegate = UploadProgressDelegate(onProgress: onProgress) { result in
                    continuation.resume(with: result)
                }
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                session.uploadTask(with: request, from: data).resume()
            }
        } else {
            let (_, response) = try await URLSession.shared.upload(for: request, from: data)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
        }
    }

    /// DELETE / 无 body 请求（不含 Content-Type）
    private func sendRequest(method: String, objectKey: String, data: Data) async throws {
        let region  = "auto"
        let service = "s3"
        let host    = "\(accountId).r2.cloudflarestorage.com"
        let path    = "/\(bucketName)/\(objectKey)"
        let url     = URL(string: "https://\(host)\(path)")!

        let now       = Date()
        let amzDate   = iso8601Full.string(from: now)
        let dateStamp = iso8601Date.string(from: now)

        // SHA256("") for empty body
        let payloadHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path

        let canonicalHeaders = "host:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
        let signedHeaders    = "host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = [method, encodedPath, "", canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalHash   = SHA256.hash(data: Data(canonicalRequest.utf8)).map { String(format: "%02x", $0) }.joined()
        let stringToSign    = ["AWS4-HMAC-SHA256", amzDate, credentialScope, canonicalHash].joined(separator: "\n")

        let signingKey  = deriveSigningKey(secret: accessKeySecret, date: dateStamp, region: region, service: service)
        let signature   = hmac(key: signingKey, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(amzDate,       forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash,   forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode / 100 != 2 {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Helpers

    private func deriveSigningKey(secret: String, date: String, region: String, service: String) -> Data {
        let kDate    = hmac(key: Data(("AWS4" + secret).utf8), data: Data(date.utf8))
        let kRegion  = hmac(key: kDate,    data: Data(region.utf8))
        let kService = hmac(key: kRegion,  data: Data(service.utf8))
        return         hmac(key: kService, data: Data("aws4_request".utf8))
    }

    private func hmac(key: Data, data: Data) -> Data {
        let symKey = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: symKey))
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "mp4":         return "video/mp4"
        case "json":        return "application/json"
        default:            return "application/octet-stream"
        }
    }

    private lazy var iso8601Full: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(abbreviation: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; return f
    }()
    private lazy var iso8601Date: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(abbreviation: "UTC"); f.dateFormat = "yyyyMMdd"; return f
    }()
}

// MARK: - Upload progress delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let completion: (Result<Void, Error>) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void,
         completion: @escaping (Result<Void, Error>) -> Void) {
        self.onProgress = onProgress
        self.completion = completion
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completion(.failure(error))
        } else if let httpResp = task.response as? HTTPURLResponse, httpResp.statusCode != 200 {
            completion(.failure(URLError(.badServerResponse)))
        } else {
            completion(.success(()))
        }
    }
}
