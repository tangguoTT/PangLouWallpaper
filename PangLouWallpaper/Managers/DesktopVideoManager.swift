//
//  DesktopVideoManager.swift
//  SimpleWallpaper
//

// 负责在 Mac 桌面底层画视频。
// 循环引擎：AVPlayerLooper（Apple 官方无缝循环方案），彻底消除播完黑屏问题。
// 淡入淡出：NSWindow.alphaValue 动画，切换/退出时平滑过渡。

import AppKit
import AVFoundation
import AVKit

class DesktopVideoManager: NSObject {
    static let shared = DesktopVideoManager()

    // MARK: - 单屏播放容器

    private struct ScreenPlayer {
        let window: NSWindow
        let player: AVQueuePlayer
        let looper: AVPlayerLooper   // 必须持有，否则循环停止

        /// 完整清理：停止循环、停止播放、销毁窗口
        func teardown() {
            looper.disableLooping()
            player.pause()
            player.removeAllItems()
            window.contentView = nil
            window.orderOut(nil)
        }
    }

    private var screenPlayers: [ScreenPlayer] = []

    // MARK: - 系统状态

    private var isSleeping = false
    private var isPausedByEnergySaving = false

    var isEnergySavingEnabled: Bool = UserDefaults.standard.bool(forKey: "energySavingEnabled") {
        didSet {
            UserDefaults.standard.set(isEnergySavingEnabled, forKey: "energySavingEnabled")
            if isEnergySavingEnabled {
                scheduleEnergySavingCheck(after: 0)
            } else if isPausedByEnergySaving {
                isPausedByEnergySaving = false
                if !isSleeping { resumeAll() }
            }
        }
    }

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
        nc.addObserver(self, selector: #selector(handleScreenSleep),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenSleep),
                       name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleAppSwitch),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleSpaceChange),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - 系统事件处理

    @objc private func handleScreenWake() {
        isSleeping = false
        isPausedByEnergySaving = false
        if isEnergySavingEnabled {
            scheduleEnergySavingCheck(after: 1.0)
        } else {
            resumeAll()
        }
    }

    @objc private func handleScreenSleep() {
        isSleeping = true
        isPausedByEnergySaving = false
        pauseAll()
    }

    @objc private func handleAppSwitch() {
        guard isEnergySavingEnabled, !isSleeping else { return }
        scheduleEnergySavingCheck(after: 0.4)
    }

    @objc private func handleSpaceChange() {
        guard isEnergySavingEnabled, !isSleeping else { return }
        scheduleEnergySavingCheck(after: 0.5)
    }

    // MARK: - 节能逻辑

    private func scheduleEnergySavingCheck(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.applyEnergySavingIfNeeded()
        }
    }

    private func applyEnergySavingIfNeeded() {
        guard isEnergySavingEnabled, !isSleeping else { return }
        let covered = isDesktopCovered()
        if covered && !isPausedByEnergySaving {
            isPausedByEnergySaving = true
            pauseAll()
        } else if !covered && isPausedByEnergySaving {
            isPausedByEnergySaving = false
            resumeAll()
        }
    }

    private func isDesktopCovered() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return false }
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let owner = info[kCGWindowOwnerName as String] as? String {
                let systemNames: Set<String> = ["WindowServer", "Window Server", "Dock", "Finder"]
                if systemNames.contains(owner) { continue }
            }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let ww = bounds["Width"] ?? 0, wh = bounds["Height"] ?? 0
            for screen in NSScreen.screens where ww >= screen.frame.width - 2 && wh >= screen.frame.height - 2 {
                return true
            }
        }
        return false
    }

    // MARK: - 播放控制

    private func resumeAll() {
        for sp in screenPlayers { sp.player.play() }
    }

    private func pauseAll() {
        for sp in screenPlayers { sp.player.pause() }
    }

    // MARK: - 构建单屏播放器（AVPlayerLooper 无缝循环）

    private func buildScreenPlayer(url: URL, screen: NSScreen) -> ScreenPlayer {
        // ── 窗口 ──
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        window.backgroundColor = .black
        window.isOpaque = false   // 允许 alphaValue 动画

        // ── 资源 & 播放器 ──
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        let templateItem = AVPlayerItem(asset: asset)
        templateItem.seekingWaitsForVideoCompositionRendering = false

        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false

        // AVPlayerLooper 负责无缝循环，不再需要手动监听播完通知
        let looper = AVPlayerLooper(player: player, templateItem: templateItem)

        // ── 播放视图 ──
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill
        window.contentView = playerView

        return ScreenPlayer(window: window, player: player, looper: looper)
    }

    // MARK: - 公开接口

    /// 清除动态壁纸（淡出后移除）
    func clearVideoWallpaper() {
        let old = screenPlayers
        screenPlayers = []
        isSleeping = false
        isPausedByEnergySaving = false
        guard !old.isEmpty else { return }

        fadeOut(old, duration: 0.35) {
            for sp in old { sp.teardown() }
        }
    }

    /// 设置动态壁纸（淡入新窗口，淡出旧窗口，交叉过渡）
    func playVideoOnDesktop(url: URL, screenName: String = "全部") {
        let oldPlayers = screenPlayers

        // 确定目标屏幕
        let targetScreens: [NSScreen]
        if screenName == "全部" {
            targetScreens = NSScreen.screens
        } else {
            let filtered = NSScreen.screens.filter { $0.localizedName == screenName }
            targetScreens = filtered.isEmpty ? NSScreen.screens : filtered
        }

        // 构建新的 ScreenPlayer（alpha = 0，不可见）
        var newPlayers: [ScreenPlayer] = []
        for screen in targetScreens {
            let sp = buildScreenPlayer(url: url, screen: screen)
            sp.window.alphaValue = 0
            sp.window.orderFront(nil)
            newPlayers.append(sp)
        }
        screenPlayers = newPlayers

        // 判断是否应暂停（节能 / 睡眠）
        let shouldStartPaused = isSleeping || (isEnergySavingEnabled && isDesktopCovered())
        if shouldStartPaused {
            isPausedByEnergySaving = isEnergySavingEnabled && !isSleeping
        } else {
            for sp in screenPlayers { sp.player.play() }
        }

        // ── 交叉淡入淡出 ──
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for sp in screenPlayers { sp.window.animator().alphaValue = 1 }
            for sp in oldPlayers    { sp.window.animator().alphaValue = 0 }
        }, completionHandler: {
            for sp in oldPlayers { sp.teardown() }
        })
    }

    // MARK: - 辅助

    private func fadeOut(_ players: [ScreenPlayer], duration: TimeInterval, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for sp in players { sp.window.animator().alphaValue = 0 }
        }, completionHandler: completion)
    }
}
