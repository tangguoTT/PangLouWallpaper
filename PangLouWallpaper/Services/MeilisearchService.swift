//
//  MeilisearchService.swift
//  SimpleWallpaper
//

import Foundation

// MARK: - Response Types

struct MeilisearchSearchResponse: Codable {
    let hits: [WallpaperItem]
    let totalHits: Int
    let page: Int
    let totalPages: Int
    let hitsPerPage: Int
}

// MARK: - Service

class MeilisearchService {
    static let shared = MeilisearchService()

    private let host: String
    private let apiKey: String
    private let indexName = "wallpapers"

    private init() {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url) as? [String: String],
            let host = dict["MeilisearchHost"],
            let apiKey = dict["MeilisearchApiKey"]
        else {
            fatalError("Secrets.plist 缺少 MeilisearchHost 或 MeilisearchApiKey，请参考 Secrets.plist.example")
        }
        self.host = host.hasSuffix("/") ? String(host.dropLast()) : host
        self.apiKey = apiKey
    }

    // MARK: - Search

    /// 搜索壁纸，支持全文搜索 + 多维度过滤 + 分页
    func search(
        query: String,
        filters: [String] = [],
        page: Int = 0,
        hitsPerPage: Int = 12
    ) async throws -> MeilisearchSearchResponse {
        var body: [String: Any] = [
            "q": query,
            "page": page + 1,            // Meilisearch 从 1 开始
            "hitsPerPage": hitsPerPage,
            "attributesToSearchOn": ["title", "description", "tags"]
        ]
        if !filters.isEmpty {
            body["filter"] = filters.joined(separator: " AND ")
        }

        let request = try makeRequest(method: "POST", path: "/indexes/\(indexName)/search", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data: data)

        let decoder = JSONDecoder()
        return try decoder.decode(MeilisearchSearchResponse.self, from: data)
    }

    // MARK: - Documents

    /// 批量新增或替换文档（幂等）
    func addDocuments(_ items: [WallpaperItem]) async throws {
        let data = try JSONEncoder().encode(items)
        let request = makeRawRequest(method: "POST", path: "/indexes/\(indexName)/documents", body: data)
        let (respData, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data: respData)
    }

    /// 批量更新文档（只更新提供的字段，主键必须存在）
    func updateDocuments(_ items: [WallpaperItem]) async throws {
        let data = try JSONEncoder().encode(items)
        let request = makeRawRequest(method: "PUT", path: "/indexes/\(indexName)/documents", body: data)
        let (respData, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data: respData)
    }

    /// 删除单个文档
    func deleteDocument(id: String) async throws {
        let request = makeRawRequest(method: "DELETE", path: "/indexes/\(indexName)/documents/\(id)")
        let (respData, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data: respData)
    }

    /// 获取索引中全部文档（分页循环直到取完）
    func getAllDocuments() async throws -> [WallpaperItem] {
        struct GetDocsResponse: Codable { let results: [WallpaperItem]; let total: Int }
        var all: [WallpaperItem] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let request = makeRawRequest(method: "GET",
                path: "/indexes/\(indexName)/documents?limit=\(pageSize)&offset=\(offset)")
            let (data, response) = try await URLSession.shared.data(for: request)
            try checkHTTP(response, data: data)
            let decoded = try JSONDecoder().decode(GetDocsResponse.self, from: data)
            all.append(contentsOf: decoded.results)
            offset += decoded.results.count
            if offset >= decoded.total || decoded.results.isEmpty { break }
        }
        return all
    }

    // MARK: - Index Settings（首次迁移时调用一次）

    func configureIndex() async throws {
        let settings: [String: Any] = [
            "searchableAttributes": ["title", "description", "tags"],
            "filterableAttributes": ["category", "resolution", "color", "isVideo"],
            "sortableAttributes": ["uploadedAt"],
            "displayedAttributes": [
                "id", "title", "description", "tags",
                "category", "resolution", "color",
                "isVideo", "fullURL", "uploadedAt"
            ]
        ]
        let request = try makeRequest(method: "PATCH", path: "/indexes/\(indexName)/settings", body: settings)
        let (respData, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data: respData)
    }

    // MARK: - Helpers

    private func makeRequest(method: String, path: String, body: [String: Any]) throws -> URLRequest {
        let data = try JSONSerialization.data(withJSONObject: body)
        return makeRawRequest(method: method, path: path, body: data)
    }

    private func makeRawRequest(method: String, path: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(host)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            print("❌ Meilisearch error \(http.statusCode): \(body)")
            throw URLError(.badServerResponse)
        }
    }
}
