//
//  AuthService.swift
//  PangLouWallpaper
//

import Foundation

// MARK: - User model

struct AuthUser: Codable {
    let id: String
    let email: String
    var accessToken: String
    var refreshToken: String
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case notLoggedIn
    case serverError(String)
    case confirmationRequired   // 注册成功但需要验证邮件

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:           return "请先登录"
        case .serverError(let msg):  return msg
        case .confirmationRequired:  return "注册成功！请查收验证邮件，点击链接确认后再登录"
        }
    }
}

// MARK: - Service

class AuthService {
    static let shared = AuthService()

    private let supabaseURL: String
    private let anonKey: String

    private(set) var currentUser: AuthUser? {
        didSet { persistSession() }
    }

    var isLoggedIn: Bool { currentUser != nil }

    private init() {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url) as? [String: String],
            let supabaseURL = dict["SupabaseURL"],
            let anonKey = dict["SupabaseAnonKey"],
            !supabaseURL.isEmpty, !anonKey.isEmpty
        else {
            fatalError("Secrets.plist 缺少 SupabaseURL 或 SupabaseAnonKey，请参考 Secrets.plist.example")
        }
        self.supabaseURL = supabaseURL.hasSuffix("/") ? String(supabaseURL.dropLast()) : supabaseURL
        self.anonKey = anonKey
        self.currentUser = loadPersistedSession()
    }

    // MARK: - Session persistence

    private func persistSession() {
        if let user = currentUser, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "supabaseSession")
        } else {
            UserDefaults.standard.removeObject(forKey: "supabaseSession")
        }
    }

    private func loadPersistedSession() -> AuthUser? {
        guard
            let data = UserDefaults.standard.data(forKey: "supabaseSession"),
            let user = try? JSONDecoder().decode(AuthUser.self, from: data)
        else { return nil }
        return user
    }

    // MARK: - Auth

    func signUp(email: String, password: String) async throws {
        var request = makeRequest(path: "/auth/v1/signup", method: "POST")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode(SupabaseErrorBody.self, from: data))?.message ?? "注册失败，请稍后重试"
            throw AuthError.serverError(msg)
        }
        // 若有 access_token 则直接登录；否则说明需要邮件验证
        if let auth = try? JSONDecoder().decode(SupabaseAuthResponse.self, from: data),
           !auth.accessToken.isEmpty {
            await MainActor.run {
                self.currentUser = AuthUser(id: auth.user.id, email: auth.user.email,
                                            accessToken: auth.accessToken, refreshToken: auth.refreshToken)
            }
        } else {
            throw AuthError.confirmationRequired
        }
    }

    func signIn(email: String, password: String) async throws {
        var request = makeRequest(path: "/auth/v1/token?grant_type=password", method: "POST")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode(SupabaseErrorBody.self, from: data))?.message ?? "邮箱或密码错误"
            throw AuthError.serverError(msg)
        }
        let auth = try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        await MainActor.run {
            self.currentUser = AuthUser(id: auth.user.id, email: auth.user.email,
                                        accessToken: auth.accessToken, refreshToken: auth.refreshToken)
        }
    }

    // 处理 Supabase 邮件验证回调（panglouwallpaper://login-callback#access_token=...）
    func handleAuthCallback(url: URL) async {
        guard let fragment = url.fragment else { return }
        var params: [String: String] = [:]
        for pair in fragment.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 { params[kv[0]] = kv[1] }
        }
        guard let accessToken = params["access_token"],
              let refreshToken = params["refresh_token"],
              let (id, email) = decodeJWT(accessToken) else { return }
        await MainActor.run {
            self.currentUser = AuthUser(id: id, email: email,
                                        accessToken: accessToken, refreshToken: refreshToken)
        }
        NotificationCenter.default.post(name: .authCallbackCompleted, object: nil)
    }

    private func decodeJWT(_ token: String) -> (id: String, email: String)? {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: data)
        else { return nil }
        return (id: payload.sub, email: payload.email ?? "")
    }

    func signOut() async {
        guard let user = currentUser else { return }
        var request = makeRequest(path: "/auth/v1/logout", method: "POST", token: user.accessToken)
        try? await URLSession.shared.data(for: request)
        await MainActor.run { self.currentUser = nil }
    }

    // MARK: - Profile

    func fetchProfile(userId: String) async throws -> UserProfile? {
        guard let user = currentUser else { throw AuthError.notLoggedIn }
        let request = makeRequest(
            path: "/rest/v1/profiles?id=eq.\(userId)&select=*",
            method: "GET", token: user.accessToken
        )
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([UserProfile].self, from: data).first
    }

    func upsertProfile(_ profile: UserProfile) async throws {
        try await upsertProfileRequest(profile, isRetry: false)
    }

    private func upsertProfileRequest(_ profile: UserProfile, isRetry: Bool) async throws {
        guard let user = currentUser else { throw AuthError.notLoggedIn }
        var request = makeRequest(path: "/rest/v1/profiles", method: "POST", token: user.accessToken)
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(profile)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 && !isRetry {
                try await refreshSession()
                try await upsertProfileRequest(profile, isRetry: true)
                return
            }
            if !(200...299).contains(http.statusCode) {
                let msg = (try? JSONDecoder().decode(SupabaseErrorBody.self, from: data))?.message ?? "保存失败（HTTP \(http.statusCode)）"
                throw AuthError.serverError(msg)
            }
        }
    }

    func refreshSession() async throws {
        guard let user = currentUser else { throw AuthError.notLoggedIn }
        var request = makeRequest(path: "/auth/v1/token?grant_type=refresh_token", method: "POST")
        request.httpBody = try JSONEncoder().encode(["refresh_token": user.refreshToken])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            await MainActor.run { self.currentUser = nil }
            throw AuthError.serverError("登录已过期，请重新登录")
        }
        let auth = try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        await MainActor.run {
            self.currentUser = AuthUser(id: user.id, email: user.email,
                                        accessToken: auth.accessToken, refreshToken: auth.refreshToken)
        }
    }

    func changePassword(newPassword: String) async throws {
        guard let user = currentUser else { throw AuthError.notLoggedIn }
        var request = makeRequest(path: "/auth/v1/user", method: "PUT", token: user.accessToken)
        request.httpBody = try JSONEncoder().encode(["password": newPassword])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode(SupabaseErrorBody.self, from: data))?.message ?? "修改密码失败"
            throw AuthError.serverError(msg)
        }
    }

    // MARK: - Collections CRUD

    func fetchCollections(userId: String) async throws -> [WallpaperCollection] {
        guard let user = currentUser else { throw AuthError.notLoggedIn }
        let request = makeRequest(
            path: "/rest/v1/collections?user_id=eq.\(userId)&select=*&order=created_at.asc",
            method: "GET", token: user.accessToken
        )
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([SupabaseCollectionRow].self, from: data).map { $0.toCollection() }
    }

    func upsertCollection(_ collection: WallpaperCollection) async throws {
        guard let user = currentUser else { throw AuthError.notLoggedIn }
        var request = makeRequest(path: "/rest/v1/collections", method: "POST", token: user.accessToken)
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(SupabaseCollectionInsert(collection: collection, userId: user.id))
        try? await URLSession.shared.data(for: request)
    }

    func deleteCloudCollection(id: String) async throws {
        guard let user = currentUser else { throw AuthError.notLoggedIn }
        let request = makeRequest(
            path: "/rest/v1/collections?id=eq.\(id)&user_id=eq.\(user.id)",
            method: "DELETE", token: user.accessToken
        )
        try? await URLSession.shared.data(for: request)
    }

    // MARK: - Request builder

    private func makeRequest(path: String, method: String, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: supabaseURL + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }
}

// MARK: - Private Supabase response types

private struct SupabaseAuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: SupabaseUser
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

private struct SupabaseUser: Decodable {
    let id: String
    let email: String
}

private struct SupabaseErrorBody: Decodable {
    let message: String?
    let errorDescription: String?
    enum CodingKeys: String, CodingKey {
        case message = "msg"
        case errorDescription = "error_description"
    }
}

private struct SupabaseCollectionRow: Decodable {
    let id: String
    let name: String
    let wallpaperIds: [String]
    enum CodingKeys: String, CodingKey {
        case id, name
        case wallpaperIds = "wallpaper_ids"
    }
    func toCollection() -> WallpaperCollection {
        WallpaperCollection(id: id, name: name, wallpaperIds: wallpaperIds)
    }
}

private struct SupabaseCollectionInsert: Encodable {
    let id: String
    let userId: String
    let name: String
    let wallpaperIds: [String]
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case wallpaperIds = "wallpaper_ids"
    }
    init(collection: WallpaperCollection, userId: String) {
        self.id = collection.id
        self.userId = userId
        self.name = collection.name
        self.wallpaperIds = collection.wallpaperIds
    }
}

private struct JWTPayload: Decodable {
    let sub: String
    let email: String?
}

extension Notification.Name {
    static let authCallbackCompleted = Notification.Name("authCallbackCompleted")
}
