//
//  SteamWorkshopService.swift
//  SimpleWallpaper
//

import Foundation
import AppKit

// MARK: - Service

class SteamWorkshopService: NSObject {
    static let shared = SteamWorkshopService()

    private let appId = "431960"

    // MARK: - Shared sessions

    /// Session for Workshop HTML pages — 5-minute disk cache
    private static let browseSession: URLSession = {
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024,
                             diskCapacity:   20 * 1024 * 1024)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Session for thumbnail images — NSImage 已有内存缓存，HTTP 层只保留磁盘缓存
    static let thumbnailSession: URLSession = {
        let cache = URLCache(memoryCapacity:   4 * 1024 * 1024,   // 4MB（压缩数据，仅临时）
                             diskCapacity:   200 * 1024 * 1024)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// In-memory image cache — 限制 100 张 / 80MB，防止长时间浏览导致内存暴涨
    static let imageMemCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 100
        c.totalCostLimit = 80 * 1024 * 1024   // 80 MB（cost 按解码像素字节数计）
        return c
    }()

    // MARK: - Worker base URL (read from Secrets.plist)

    private static let workerBaseURL: String = {
        guard let url  = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let host = dict["SteamWorkerURL"] as? String, !host.isEmpty else {
            fatalError("Secrets.plist 缺少 SteamWorkerURL，请参考 Secrets.plist.example")
        }
        return host
    }()

    // MARK: - Page result cache (5-min TTL)

    private struct PageCacheEntry {
        let items: [SteamWorkshopItem]
        let hasMore: Bool
        let nextCursor: String
        let total: Int
        let date: Date
    }
    private var pageCache: [String: PageCacheEntry] = [:]
    private let pageCacheTTL: TimeInterval = 300

    // MARK: - Browse/Search via Cloudflare Worker

    /// Fetches Workshop items through the Cloudflare Worker which proxies Steam's
    /// `IPublishedFileService/QueryFiles/v1/` API (no VPN required from China).
    /// Uses cursor-based pagination: pass "*" for the first page, then use the
    /// returned nextCursor for subsequent pages.
    func fetchViaWorker(query: String, cursor: String = "*", page: Int? = nil, filterTag: String? = nil, sortType: String = "0", perPage: Int = 20) async throws -> (items: [SteamWorkshopItem], hasMore: Bool, nextCursor: String, total: Int) {
        let tag = filterTag ?? ""
        let cacheKey = page != nil ? "\(query)|page\(page!)|\(sortType)|\(perPage)|\(tag)" : "\(query)|\(cursor)|\(sortType)|\(tag)"
        if let cached = pageCache[cacheKey], Date().timeIntervalSince(cached.date) < pageCacheTTL {
            return (cached.items, cached.hasMore, cached.nextCursor, cached.total)
        }

        var components = URLComponents(string: "\(Self.workerBaseURL)/workshop/query")!
        var queryItems = [
            URLQueryItem(name: "query",     value: query),
            URLQueryItem(name: "sort_type", value: sortType),
            URLQueryItem(name: "per_page",  value: "\(perPage)"),
        ]
        if let p = page {
            queryItems.append(URLQueryItem(name: "page", value: "\(p)"))
        } else {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let tag = filterTag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "filter_tag", value: tag))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await Self.browseSession.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            print("[Workshop] HTTP \(statusCode): \(body)")
            throw URLError(.badServerResponse)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outer = json["response"] as? [String: Any] else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            print("[Workshop] JSON parse failed: \(body)")
            throw URLError(.cannotParseResponse)
        }

        let nextCursorValue = outer["next_cursor"] as? String ?? ""
        let totalResults = outer["total"] as? Int ?? 0
        let details = outer["publishedfiledetails"] as? [[String: Any]] ?? []

        let items: [SteamWorkshopItem] = details.compactMap { d in
            guard let id    = d["publishedfileid"] as? String,
                  let title = d["title"] as? String,
                  !title.isEmpty else { return nil }

            let previewURL = (d["preview_url"] as? String).flatMap { URL(string: $0) }

            let fileSize: Int
            if let s = d["file_size"] as? String { fileSize = Int(s) ?? 0 }
            else { fileSize = d["file_size"] as? Int ?? 0 }

            // QueryFiles returns tags as {"tags": [{tag: "Video"}, ...]}
            // GetPublishedFileDetails returns tags as [{tag: "Video"}, ...]
            var tags: [String] = []
            if let tagsObj = d["tags"] as? [String: Any],
               let tagArr  = tagsObj["tags"] as? [[String: Any]] {
                tags = tagArr.compactMap { $0["tag"] as? String }
            } else if let tagArr = d["tags"] as? [[String: Any]] {
                tags = tagArr.compactMap { $0["tag"] as? String }
            }

            return SteamWorkshopItem(
                id: id,
                title: title,
                previewURL: previewURL,
                description: d["short_description"] as? String ?? "",
                tags: tags,
                fileSize: fileSize,
                timeUpdated: d["time_updated"] as? Int ?? 0
            )
        }

        // 满页说明大概率还有更多；next_cursor 为空/0 则明确没有更多
        let hasMore = details.count >= perPage || (!nextCursorValue.isEmpty && nextCursorValue != "0")
        pageCache[cacheKey] = PageCacheEntry(items: items, hasMore: hasMore, nextCursor: nextCursorValue, total: totalResults, date: Date())
        return (items, hasMore, nextCursorValue, totalResults)
    }

    // MARK: - Item Details (Steam API)

    /// Fetches tags and file size for up to 100 items at once using Steam's
    /// `GetPublishedFileDetails` endpoint (no API key required).
    /// Mutates `items` in-place and returns the enriched array.
    func fetchItemDetails(for items: [SteamWorkshopItem]) async -> [SteamWorkshopItem] {
        guard !items.isEmpty else { return items }

        // Build application/x-www-form-urlencoded body
        var parts = ["itemcount=\(items.count)"]
        for (i, item) in items.enumerated() {
            parts.append("publishedfileids[\(i)]=\(item.id)")
        }
        let body = parts.joined(separator: "&").data(using: .utf8)

        var request = URLRequest(url: URL(string: "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outer = json["response"] as? [String: Any],
              let details = outer["publishedfiledetails"] as? [[String: Any]] else {
            return items
        }

        // Build a lookup map by ID
        var detailMap: [String: [String: Any]] = [:]
        for d in details {
            if let fid = d["publishedfileid"] as? String { detailMap[fid] = d }
        }

        return items.map { item in
            guard let d = detailMap[item.id] else { return item }
            var updated = item

            // Tags: [{tag: "Video"}, {tag: "Scene"}] → ["Video", "Scene"]
            if let tagObjects = d["tags"] as? [[String: Any]] {
                updated.tags = tagObjects.compactMap { $0["tag"] as? String }
            }

            // file_size comes as a String in the Steam API
            if let sizeStr = d["file_size"] as? String, let size = Int(sizeStr), size > 0 {
                updated.fileSize = size
            } else if let sizeNum = d["file_size"] as? Int, sizeNum > 0 {
                updated.fileSize = sizeNum
            }

            return updated
        }
    }

    // MARK: - SteamCMD

    /// App-managed SteamCMD directory inside Application Support.
    static var appSteamCMDDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("PangLouWallpaperCache/steamcmd")
    }

    static var appSteamCMDPath: URL {
        appSteamCMDDirectory.appendingPathComponent("steamcmd.sh")
    }

    private static let steamCMDDownloadURL = URL(string: "\(workerBaseURL)/steamcmd/osx")!

    /// Returns the steamcmd executable path: prefers system install, falls back to app-bundled.
    static func findSteamCMD() -> String? {
        let systemPaths = ["/usr/local/bin/steamcmd", "/opt/homebrew/bin/steamcmd"]
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        let appPath = appSteamCMDPath
        if FileManager.default.fileExists(atPath: appPath.path) { return appPath.path }
        return nil
    }

    /// Downloads and extracts SteamCMD from Valve's CDN into the app support directory.
    static func installSteamCMD() async throws {
        let dir = appSteamCMDDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tarGzURL = dir.appendingPathComponent("steamcmd_osx.tar.gz")
        let (tmpURL, _) = try await URLSession.shared.download(from: steamCMDDownloadURL)
        try? FileManager.default.removeItem(at: tarGzURL)
        try FileManager.default.moveItem(at: tmpURL, to: tarGzURL)

        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extract.arguments = ["-xzf", tarGzURL.path, "-C", dir.path]
        try extract.run()
        extract.waitUntilExit()
        try? FileManager.default.removeItem(at: tarGzURL)

        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: appSteamCMDPath.path
        )

        // Run once so SteamCMD can self-update before first real use
        let update = Process()
        update.executableURL = URL(fileURLWithPath: appSteamCMDPath.path)
        update.currentDirectoryURL = dir
        update.arguments = ["+quit"]
        update.standardOutput = FileHandle.nullDevice
        update.standardError = FileHandle.nullDevice
        try update.run()
        update.waitUntilExit()
    }

    /// Local directory where SteamCMD stores downloaded workshop items.
    static func workshopItemDirectory(itemId: String) -> URL {
        let appManaged = appSteamCMDDirectory
            .appendingPathComponent("steamapps/workshop/content/431960/\(itemId)")
        if FileManager.default.fileExists(atPath: appManaged.path) { return appManaged }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/431960/\(itemId)")
    }

    enum WallpaperEngineType: String {
        case video, image, scene, web, preset, unknown
        var isSupported: Bool { self == .video || self == .image || self == .web }
    }

    /// Reads project.json and returns the wallpaper type (video/image/scene/web/…).
    static func detectWallpaperType(in directory: URL) -> WallpaperEngineType {
        let projectURL = directory.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: projectURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeStr = json["type"] as? String else { return .unknown }
        return WallpaperEngineType(rawValue: typeStr.lowercased()) ?? .unknown
    }

    /// Scans the item directory for the actual wallpaper file.
    ///
    /// Priority:
    ///   1. Read `project.json` → use the `"file"` key (exact match from developer).
    ///   2. Fallback: pick the largest supported file, **excluding** preview thumbnails.
    ///
    /// Returns `nil` if the wallpaper type is scene/web/preset (requires Wallpaper Engine to render).
    static func findWallpaperFile(in directory: URL) -> URL? {
        let supportedExts: Set<String> = ["mp4", "webm", "mov", "jpg", "jpeg", "png", "gif", "html", "htm"]

        // --- Step 1: parse project.json ---
        let projectURL = directory.appendingPathComponent("project.json")
        if let data = try? Data(contentsOf: projectURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            let typeStr = (json["type"] as? String ?? "").lowercased()
            let weType  = WallpaperEngineType(rawValue: typeStr) ?? .unknown

            // Scene / web / preset cannot be used without Wallpaper Engine
            if !weType.isSupported && weType != .unknown { return nil }

            // Use the exact filename the developer specified
            if let fileName = json["file"] as? String, !fileName.isEmpty {
                let candidate = directory.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        // --- Step 2: size-based fallback, excluding known thumbnail names ---
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        ) else { return nil }

        let thumbnailNames: Set<String> = ["preview.jpg", "preview.jpeg", "preview.png",
                                            "thumbnail.jpg", "thumbnail.png"]
        return contents
            .filter { url in
                guard supportedExts.contains(url.pathExtension.lowercased()) else { return false }
                return !thumbnailNames.contains(url.lastPathComponent.lowercased())
            }
            .sorted { a, b in
                let sizeA = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let sizeB = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sizeA > sizeB
            }
            .first
    }

    /// Returns bytes currently being written to the in-progress staging directory.
    static func totalDownloadedBytes(itemId: String, debugLog: Bool = false) -> Int64 {
        let steamBases: [URL] = [
            appSteamCMDDirectory,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Steam"),
        ]
        let downloadingSubdirs = [
            "steamapps/downloading/431960/\(itemId)",
            "steamapps/workshop/content/431960/\(itemId)",
        ]

        var total: Int64 = 0

        func sumDirectory(_ dir: URL) -> Int64 {
            guard let enumerator = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            ) else {
                if debugLog { print("[DiskScan]   \(dir.path) → NOT FOUND") }
                return 0
            }
            var dirTotal: Int64 = 0
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { continue }
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                dirTotal += size
                if debugLog { print("[DiskScan]     file: \(url.lastPathComponent) = \(size) bytes") }
            }
            if debugLog { print("[DiskScan]   \(dir.path) → \(dirTotal) bytes total") }
            return dirTotal
        }

        for base in steamBases {
            for subdir in downloadingSubdirs {
                let dir = base.appendingPathComponent(subdir)
                total += sumDirectory(dir)
            }
        }
        if debugLog { print("[DiskScan] itemId=\(itemId) grand total=\(total) bytes") }
        return total
    }

    /// Parses a percentage (0–1) from a SteamCMD output line.
    /// Supports:
    ///   "50.00%" — generic percent format
    ///   "progress: 50.00 (524288000 / 1048576000)" — steamcmd workshop format (no % sign)
    private static func parseProgressPercent(from text: String) -> Double? {
        // steamcmd workshop format: "progress: 50.00 (...)"
        let p1 = #"progress:\s*(\d+(?:\.\d+)?)"#
        if let r = try? NSRegularExpression(pattern: p1, options: .caseInsensitive),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(m.range(at: 1), in: text),
           let v = Double(text[range]), v >= 0, v <= 100 { return v / 100.0 }
        // generic "XX%" format
        let p2 = #"(\d{1,3}(?:\.\d+)?)\s*%"#
        if let r = try? NSRegularExpression(pattern: p2),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(m.range(at: 1), in: text),
           let v = Double(text[range]), v > 0, v <= 100 { return v / 100.0 }
        return nil
    }

    /// Parses total file size (bytes) from a steamcmd progress line.
    /// e.g. "progress: 50.00 (524288000 / 1048576000)" → 1048576000
    static func parseTotalBytes(from text: String) -> Int64? {
        let pattern = #"progress:.*?\(\s*\d+\s*/\s*(\d+)\s*\)"#
        guard let r = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range(at: 1), in: text),
              let total = Int64(text[range]), total > 0 else { return nil }
        return total
    }

    /// Downloads a Workshop item using SteamCMD (anonymous login).
    /// `progressHandler` is called on the main queue with values in [0, 1] as SteamCMD reports them.
    /// Respects Swift Task cancellation: cancelling the parent Task terminates the SteamCMD process.
    static func downloadWithSteamCMD(
        steamcmdPath: String,
        itemId: String,
        progressHandler: ((Double) -> Void)? = nil,
        totalBytesHandler: ((Int64) -> Void)? = nil
    ) async -> Bool {
        let workingDir = URL(fileURLWithPath: steamcmdPath).deletingLastPathComponent()
        print("[SteamCMD] downloadWithSteamCMD — path=\(steamcmdPath) workingDir=\(workingDir.path) itemId=\(itemId)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: steamcmdPath)
        process.currentDirectoryURL = workingDir
        process.arguments = ["+login", "anonymous", "+workshop_download_item", "431960", itemId, "+quit"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            for part in str.components(separatedBy: CharacterSet(charactersIn: "\r\n")) {
                if let pct = Self.parseProgressPercent(from: part) {
                    DispatchQueue.main.async { progressHandler?(pct) }
                }
                if let total = Self.parseTotalBytes(from: part) {
                    DispatchQueue.main.async { totalBytesHandler?(total) }
                }
            }
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let dir = workshopItemDirectory(itemId: itemId)
                    continuation.resume(returning: findWallpaperFile(in: dir) != nil)
                }
                do { try process.run() } catch { continuation.resume(returning: false) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    enum LoginDownloadResult {
        case success
        case needsSteamGuard   // Steam Guard 邮箱验证码
        case needsTwoFactor    // Steam Guard 移动端验证码
        case invalidCredentials
        case failed(String)
    }

    /// Downloads a Workshop item using SteamCMD with real Steam credentials.
    /// - Parameters:
    ///   - guardCode: Steam Guard code (email or mobile authenticator). Pass nil on first attempt.
    ///   - progressHandler: Called on the main queue with values in [0, 1].
    /// - Returns: Result indicating success, guard requirement, or failure.
    static func downloadWithCredentials(
        steamcmdPath: String,
        username: String,
        password: String,
        guardCode: String?,
        itemId: String,
        progressHandler: ((Double) -> Void)? = nil,
        totalBytesHandler: ((Int64) -> Void)? = nil,
        mobileConfirmHandler: (() -> Void)? = nil
    ) async -> LoginDownloadResult {
        let workingDir = URL(fileURLWithPath: steamcmdPath).deletingLastPathComponent()
        print("[SteamCMD] downloadWithCredentials — path=\(steamcmdPath) workingDir=\(workingDir.path) itemId=\(itemId) hasGuardCode=\(guardCode != nil && !(guardCode!.isEmpty))")

        var args = ["+login", username, password]
        if let code = guardCode, !code.isEmpty { args.append(code) }
        args += ["+workshop_download_item", "431960", itemId, "+quit"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: steamcmdPath)
        process.currentDirectoryURL = workingDir
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        var outputBuffer = ""
        let lock = NSLock()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<LoginDownloadResult, Never>) in
                // 只能 resume 一次，用 flag 保护
                var didResume = false
                var didCallMobileHandler = false  // prevent repeated mobileConfirmHandler calls
                func resumeOnce(_ result: LoginDownloadResult) {
                    lock.lock()
                    guard !didResume else { lock.unlock(); return }
                    didResume = true
                    lock.unlock()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning { process.terminate() }
                    continuation.resume(returning: result)
                }

                // 实时读取输出：
                // - 未提供验证码时：检测 Steam Guard 提示并立即返回，不等进程退出
                //   使用累积 buffer 检测，避免关键词跨 chunk 被切断漏检
                // - 已提供验证码时：不检测关键词（steamcmd 会在输出中回显验证码）
                let alreadyHasCode = guardCode != nil && !(guardCode!.isEmpty)
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                    lock.lock(); outputBuffer += str; let accumulated = outputBuffer; lock.unlock()

                    if !alreadyHasCode {
                        // Check accumulated buffer so keywords split across chunks are not missed
                        let low = accumulated.lowercased()

                        // Mobile app push-confirm: only call handler once even though chunks keep arriving
                        if !didCallMobileHandler && (
                            low.contains("please confirm the login")
                            || low.contains("steam mobile app on your phone")
                            || low.contains("confirm the login in the steam mobile")
                        ) {
                            lock.lock(); didCallMobileHandler = true; lock.unlock()
                            DispatchQueue.main.async { mobileConfirmHandler?() }
                            // Do NOT kill the process — SteamCMD keeps waiting for the user to approve
                            return
                        }
                        // Once mobile handler fired, skip re-checking confirm keywords on every chunk
                        if didCallMobileHandler { return }

                        // Two-factor code entry required
                        if low.contains("two-factor code:")
                            || low.contains("enter the current code from your steam guard mobile authenticator") {
                            resumeOnce(.needsTwoFactor); return
                        }

                        // Email Steam Guard code entry required
                        if low.contains("steam guard code:")
                            || low.contains("enter steam guard code")
                            || (low.contains("steam guard") && low.contains("code") && !low.contains("not required"))
                            || low.contains("guard code for") {
                            resumeOnce(.needsSteamGuard); return
                        }
                    }

                    for part in str.components(separatedBy: CharacterSet(charactersIn: "\r\n")) {
                        if let pct = Self.parseProgressPercent(from: part) {
                            DispatchQueue.main.async { progressHandler?(pct) }
                        }
                        if let total = Self.parseTotalBytes(from: part) {
                            DispatchQueue.main.async { totalBytesHandler?(total) }
                        }
                    }
                }

                process.terminationHandler = { _ in
                    lock.lock(); let output = outputBuffer; lock.unlock()

                    print("[SteamCMD] exit, output length=\(output.count)")
                    print("[SteamCMD output]:\n\(output.suffix(3000))")

                    // Print all scanned directories to identify where SteamCMD actually writes
                    print("[SteamCMD] scanning for downloaded files (itemId=\(itemId)):")
                    _ = Self.totalDownloadedBytes(itemId: itemId, debugLog: true)
                    let dir = Self.workshopItemDirectory(itemId: itemId)
                    print("[SteamCMD] workshopItemDirectory=\(dir.path) exists=\(FileManager.default.fileExists(atPath: dir.path))")
                    if Self.findWallpaperFile(in: dir) != nil {
                        resumeOnce(.success); return
                    }

                    let low = output.lowercased()

                    if alreadyHasCode {
                        // 已提供过验证码，output 里含有回显的验证码文本，不再用关键词判断是否需要验证码
                        // 只判断密码错误和成功，其余视为登录失败
                        if low.contains("invalid password") || low.contains("failed (invalid password)") {
                            resumeOnce(.invalidCredentials)
                        } else if low.contains("invalid steam guard code") || low.contains("invalid 2fa code") || low.contains("two-factor code mismatch") {
                            // 验证码本身填错了，让用户重新输入
                            resumeOnce(.needsSteamGuard)
                        } else if low.contains("success") {
                            resumeOnce(.success)
                        } else {
                            let snippet = String(output.suffix(300))
                            resumeOnce(.failed(snippet.isEmpty ? "SteamCMD 未返回可识别的输出" : snippet))
                        }
                    } else {
                        // 未提供验证码，正常检测 Steam Guard 请求
                        if low.contains("two-factor code:")
                            || low.contains("enter the current code from your steam guard mobile authenticator") {
                            resumeOnce(.needsTwoFactor)
                        } else if low.contains("steam guard code:")
                            || low.contains("enter steam guard code")
                            || (low.contains("steam guard") && low.contains("code") && !low.contains("not required"))
                            || low.contains("guard code for") {
                            resumeOnce(.needsSteamGuard)
                        } else if low.contains("invalid password") || low.contains("failed (invalid password)") {
                            resumeOnce(.invalidCredentials)
                        } else if low.contains("timeout") && low.contains("login") {
                            resumeOnce(.invalidCredentials)
                        } else if low.contains("success") {
                            resumeOnce(.success)
                        } else {
                            let snippet = String(output.suffix(300))
                            resumeOnce(.failed(snippet.isEmpty ? "SteamCMD 未返回可识别的输出" : snippet))
                        }
                    }
                }
                do { try process.run() } catch {
                    resumeOnce(.failed(error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
