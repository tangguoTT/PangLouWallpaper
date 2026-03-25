//
//  OSSUploader.swift
//  SimpleWallpaper
//

import Foundation
import CryptoKit
import AppKit

class OSSUploader {
    static let shared = OSSUploader()
    
    private let accessKeyId: String
    private let accessKeySecret: String
    private let endpoint = "oss-cn-beijing.aliyuncs.com"

    private init() {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String],
              let keyId = dict["OSSAccessKeyId"],
              let keySecret = dict["OSSAccessKeySecret"] else {
            fatalError("Secrets.plist 未找到或格式错误，请参考 Secrets.plist.example 创建该文件")
        }
        self.accessKeyId = keyId
        self.accessKeySecret = keySecret
    }
    private let bucketName = "wallpapers-pl"
    private let remotePath = "wallpapers/"
    
    // 🌟 核心修改：接收 customTitle 参数
    func uploadFile(fileURL: URL, fileData: Data, hashString: String, customTitle: String) async throws -> WallpaperItem {
        let ext = fileURL.pathExtension.lowercased()
        let fileName = hashString + "." + ext
        let objectKey = remotePath + fileName
        
        try await putObject(objectKey: objectKey, data: fileData, fileExtension: ext)
        
        let fileUrlString = "https://\(bucketName).\(endpoint)/\(objectKey)"
        
        return WallpaperItem(
            id: hashString,
            title: customTitle, // 🌟 使用带标签的新名字
            fullURL: URL(string: fileUrlString)!,
            isVideo: (ext == "mp4" || ext == "mov")
        )
    }
    
    func uploadJSON(items: [WallpaperItem]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(items)
        try await putObject(objectKey: remotePath + "wallpapers.json", data: jsonData, fileExtension: "json")
    }
    
    private func putObject(objectKey: String, data: Data, fileExtension: String) async throws {
        let url = URL(string: "https://\(bucketName).\(endpoint)/\(objectKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let dateString = formatter.string(from: Date())
        
        let contentType: String
        switch fileExtension {
        case "jpg", "jpeg": contentType = "image/jpeg"
        case "png": contentType = "image/png"
        case "mp4": contentType = "video/mp4"
        case "json": contentType = "application/json"
        default: contentType = "application/octet-stream"
        }
        
        request.setValue(dateString, forHTTPHeaderField: "Date")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let stringToSign = "PUT\n\n\(contentType)\n\(dateString)\n/\(bucketName)/\(objectKey)"
        let key = SymmetricKey(data: accessKeySecret.data(using: .utf8)!)
        let signature = HMAC<Insecure.SHA1>.authenticationCode(for: stringToSign.data(using: .utf8)!, using: key)
        let base64Auth = Data(signature).base64EncodedString()
        
        request.setValue("OSS \(accessKeyId):\(base64Auth)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
    }
}
