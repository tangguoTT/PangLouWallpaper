//
//  DesktopWebManager.swift
//  SimpleWallpaper
//
//  把 WKWebView 铺满桌面，用于播放 Wallpaper Engine 的网页壁纸。
//  窗口层级与 DesktopVideoManager 相同（desktopWindow 级），鼠标穿透。

import AppKit
import WebKit

class DesktopWebManager: NSObject {
    static let shared = DesktopWebManager()

    private var windows: [NSWindow] = []

    // MARK: - Public API

    /// 在目标屏幕上显示网页壁纸（HTML 文件 URL）。
    /// - Parameters:
    ///   - url: 本地 HTML 文件路径。
    ///   - screenName: 目标屏幕名称，传 "全部" 则铺全部屏幕。
    func showWebWallpaper(url: URL, screenName: String = "全部") {
        clearWebWallpaper()

        let targetScreens: [NSScreen]
        if screenName == "全部" {
            targetScreens = NSScreen.screens
        } else {
            let filtered = NSScreen.screens.filter { $0.localizedName == screenName }
            targetScreens = filtered.isEmpty ? NSScreen.screens : filtered
        }

        // HTML 所在目录，WKWebView 需要访问权限才能加载相对资源
        let allowedDir = url.deletingLastPathComponent()

        for screen in targetScreens {
            let window = makeWindow(frame: screen.frame)
            let webView = makeWebView(frame: screen.frame)
            window.contentView = webView
            window.orderFront(nil)
            webView.loadFileURL(url, allowingReadAccessTo: allowedDir)
            windows.append(window)
        }
    }

    /// 清除所有网页壁纸窗口。
    func clearWebWallpaper() {
        for window in windows {
            (window.contentView as? WKWebView)?.stopLoading()
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    var isActive: Bool { !windows.isEmpty }

    // MARK: - Private helpers

    private func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        window.backgroundColor = .black
        window.isOpaque = true
        return window
    }

    private func makeWebView(frame: NSRect) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 允许本地文件访问
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: frame, configuration: config)
        // 透明背景，让 HTML 的 background 自己控制颜色
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        return webView
    }
}
