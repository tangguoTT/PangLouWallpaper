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

    /// Session for thumbnail images — larger cache, return cached data immediately
    static let thumbnailSession: URLSession = {
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024,
                             diskCapacity:  200 * 1024 * 1024)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// In-memory image cache (NSCache auto-evicts under memory pressure)
    static let imageMemCache = NSCache<NSString, NSImage>()

    // MARK: - Page result cache (5-min TTL)

    private struct PageCacheEntry {
        let items: [SteamWorkshopItem]
        let hasMore: Bool
        let date: Date
    }
    private var pageCache: [String: PageCacheEntry] = [:]
    private let pageCacheTTL: TimeInterval = 300

    // MARK: - Browse/Search (no key required)

    /// Fetches Workshop items by scraping Steam's public render endpoint.
    /// Returns hasMore=true when the page is full (can't know actual total from HTML).
    /// Results are cached in memory for 5 minutes to avoid redundant requests.
    func fetchViaRSS(query: String, page: Int, perPage: Int = 20) async throws -> (items: [SteamWorkshopItem], hasMore: Bool) {
        let cacheKey = "\(query)|\(page)"
        if let cached = pageCache[cacheKey], Date().timeIntervalSince(cached.date) < pageCacheTTL {
            return (cached.items, cached.hasMore)
        }

        var components = URLComponents(string: "https://steamcommunity.com/workshop/browse/render/")!
        var params: [URLQueryItem] = [
            URLQueryItem(name: "appid",    value: appId),
            URLQueryItem(name: "section",  value: "readytouseitems"),
            URLQueryItem(name: "p",        value: "\(page + 1)"),
        ]
        if query.isEmpty {
            params.append(URLQueryItem(name: "browsesort", value: "toprated"))
        } else {
            params.append(URLQueryItem(name: "browsesort", value: "textsearch"))
            params.append(URLQueryItem(name: "searchtext", value: query))
        }
        components.queryItems = params

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .useProtocolCachePolicy

        let (data, response) = try await Self.browseSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }

        let items = parseWorkshopHTML(html)
        // Steam doesn't expose a total count in the HTML — rely on whether the page is full
        let hasMore = items.count >= perPage
        pageCache[cacheKey] = PageCacheEntry(items: items, hasMore: hasMore, date: Date())
        return (items, hasMore)
    }

    // MARK: - HTML Parser
    //
    // Actual Steam Workshop HTML structure (from render endpoint):
    //   data-publishedfileid="ID"         → item ID
    //   class="workshopItemPreviewImage " src="URL"  → preview image
    //   class="workshopItemTitle ..."     → title text inside the div

    private func parseWorkshopHTML(_ html: String) -> [SteamWorkshopItem] {
        // Collect IDs (deduplicated, order-preserving — each item appears twice in the HTML)
        var seenIds = Set<String>()
        var orderedIds: [String] = []
        allCaptures(in: html, pattern: #"data-publishedfileid="(\d+)""#, groupCount: 1) { g in
            if let id = g[0], seenIds.insert(id).inserted { orderedIds.append(id) }
        }

        // Collect preview URLs in DOM order (one per item)
        // Steam CDN supports imw/imh resize params — bump to 440×248 (16:9) for sharp cards
        var previewURLs: [URL] = []
        allCaptures(in: html, pattern: #"class="workshopItemPreviewImage[^"]*"\s+src="([^"]+)""#, groupCount: 1) { g in
            if let src = g[0], let url = URL(string: src) {
                previewURLs.append(url.steamPreview(width: 440, height: 248))
            }
        }

        // Collect titles in DOM order (one per item)
        var titlesOrdered: [String] = []
        allCaptures(in: html, pattern: #"class="workshopItemTitle[^"]*">([^<]+)<"#, groupCount: 1) { g in
            if let t = g[0] {
                let clean = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { titlesOrdered.append(clean) }
            }
        }

        return orderedIds.enumerated().map { i, id in
            SteamWorkshopItem(
                id: id,
                title: i < titlesOrdered.count ? titlesOrdered[i] : "无标题",
                previewURL: i < previewURLs.count ? previewURLs[i] : nil,
                description: "",
                tags: [],
                fileSize: 0,
                timeUpdated: 0
            )
        }
    }

    private func allCaptures(in string: String, pattern: String, groupCount: Int,
                             handler: ([String?]) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsString = string as NSString
        regex.enumerateMatches(in: string, range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            guard let match else { return }
            var groups: [String?] = []
            for i in 1...groupCount {
                let r = match.range(at: i)
                groups.append(r.location != NSNotFound ? nsString.substring(with: r) : nil)
            }
            handler(groups)
        }
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

    private static let steamCMDDownloadURL = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz")!

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
        var isSupported: Bool { self == .video || self == .image }
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
        let supportedExts: Set<String> = ["mp4", "webm", "mov", "jpg", "jpeg", "png", "gif"]

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

    /// Returns the total bytes currently written in the item's download directories.
    /// Checks both the final content path and the in-progress downloading path.
    static func totalDownloadedBytes(itemId: String) -> Int64 {
        let dirs = [
            appSteamCMDDirectory.appendingPathComponent("steamapps/workshop/content/431960/\(itemId)"),
            appSteamCMDDirectory.appendingPathComponent("steamapps/downloading/431960/\(itemId)"),
        ]
        var total: Int64 = 0
        for dir in dirs {
            guard let enumerator = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
            ) else { continue }
            for case let url as URL in enumerator {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
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
        totalBytesHandler: ((Int64) -> Void)? = nil
    ) async -> LoginDownloadResult {
        let workingDir = URL(fileURLWithPath: steamcmdPath).deletingLastPathComponent()

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
                // - 已提供验证码时：不检测关键词（steamcmd 会在输出中回显验证码，
                //   若此时仍检测会误把回显当作新的验证码请求，导致循环弹出验证码界面）
                let alreadyHasCode = guardCode != nil && !(guardCode!.isEmpty)
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                    lock.lock(); outputBuffer += str; lock.unlock()

                    if !alreadyHasCode {
                        let low = str.lowercased()
                        if low.contains("two-factor code:") || low.contains("enter the current code from your steam guard mobile authenticator") {
                            resumeOnce(.needsTwoFactor); return
                        }
                        if low.contains("steam guard code:") || (low.contains("steam guard") && !low.contains("not required")) {
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
                    if output.count < 2000 { print(output) }

                    let dir = Self.workshopItemDirectory(itemId: itemId)
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
                        if low.contains("two-factor code:") || low.contains("enter the current code from your steam guard mobile authenticator") {
                            resumeOnce(.needsTwoFactor)
                        } else if low.contains("steam guard code:") || (low.contains("steam guard") && !low.contains("not required")) {
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
