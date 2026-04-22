//
//  DesktopWebManager.swift
//  SimpleWallpaper
//
//  把 WKWebView 铺满桌面，用于播放 Wallpaper Engine 的网页壁纸。
//  窗口层级与 DesktopVideoManager 相同（desktopWindow 级），鼠标穿透。

import AppKit
import WebKit

class DesktopWebManager: NSObject, WKNavigationDelegate {
    static let shared = DesktopWebManager()

    private var windows: [NSWindow] = []
    private var currentURL: URL?
    private var currentScreenName: String = "全部"
    // 只对第一个 webView 截图（截一个即可同步给所有屏幕的锁屏）
    private weak var snapshotSourceWebView: WKWebView?

    // MARK: - Init

    override init() {
        super.init()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleScreenWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenWake),
                       name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - 屏幕唤醒处理

    @objc private func handleScreenWake() {
        guard !windows.isEmpty, let url = currentURL else { return }
        // 唤醒后重新显示窗口并重新加载，防止 WKWebView 在低层级窗口里渲染中断
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            let allowedDir = url.deletingLastPathComponent()
            for window in self.windows {
                window.orderFront(nil)
                (window.contentView as? WKWebView)?.loadFileURL(url, allowingReadAccessTo: allowedDir)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === snapshotSourceWebView, isActive else { return }
        // 等页面动画稍微运行后再截图，让锁屏画面更贴近实际效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak webView] in
            guard let self = self, self.isActive, let wv = webView else { return }
            let cfg = WKSnapshotConfiguration()
            cfg.rect = wv.bounds
            wv.takeSnapshot(with: cfg) { [weak self] image, _ in
                guard let self = self, let image = image else { return }
                self.applySnapshotAsSystemWallpaper(image)
            }
        }
    }

    // MARK: - Public API

    /// 在目标屏幕上显示网页壁纸（HTML 文件 URL）。
    /// - Parameters:
    ///   - url: 本地 HTML 文件路径。
    ///   - screenName: 目标屏幕名称，传 "全部" 则铺全部屏幕。
    func showWebWallpaper(url: URL, screenName: String = "全部") {
        currentURL = url
        currentScreenName = screenName
        clearWebWallpaper()

        let targetScreens: [NSScreen]
        if screenName == "全部" {
            targetScreens = NSScreen.screens
        } else {
            let filtered = NSScreen.screens.filter { $0.localizedName == screenName }
            targetScreens = filtered.isEmpty ? NSScreen.screens : filtered
        }

        let allowedDir = url.deletingLastPathComponent()

        for (index, screen) in targetScreens.enumerated() {
            let window = makeWindow(frame: screen.frame)
            let webView = makeWebView(frame: screen.frame)
            if index == 0 {
                // 只监听第一个 webView 的加载完成，用于截图同步锁屏
                webView.navigationDelegate = self
                snapshotSourceWebView = webView
            }
            window.contentView = webView
            window.orderFront(nil)
            webView.loadFileURL(url, allowingReadAccessTo: allowedDir)
            windows.append(window)
        }
    }

    /// 清除所有网页壁纸窗口。
    func clearWebWallpaper() {
        currentURL = nil
        snapshotSourceWebView = nil
        for window in windows {
            (window.contentView as? WKWebView)?.stopLoading()
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    var isActive: Bool { !windows.isEmpty }

    // MARK: - 锁屏同步

    private func applySnapshotAsSystemWallpaper(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let snapURL = cacheDir.appendingPathComponent("webwallpaper_lockscreen.jpg")
        guard (try? jpeg.write(to: snapURL)) != nil else { return }

        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(snapURL, for: screen, options: [:])
        }
    }

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
        window.isRestorable = false
        return window
    }

    private func makeWebView(frame: NSRect) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: frame, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        return webView
    }
}
