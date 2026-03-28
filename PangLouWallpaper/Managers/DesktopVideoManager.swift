//
//  DesktopVideoManager.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/21.
//

// 负责在 Mac 桌面底层画视频。

import AppKit
import AVKit

class DesktopVideoManager: NSObject {
    static let shared = DesktopVideoManager()
    private var videoWindows: [NSWindow] = []
    private var videoPlayers: [AVPlayer] = []
    private var playerLooperObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let nc = NSWorkspace.shared.notificationCenter
        // 屏幕亮起 / 电脑从深度休眠恢复 → 继续播放
        nc.addObserver(self, selector: #selector(wakeUpAndPlay), name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(wakeUpAndPlay), name: NSWorkspace.didWakeNotification, object: nil)
        // 会话解锁（锁屏解开）→ 继续播放
        nc.addObserver(self, selector: #selector(wakeUpAndPlay), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        // 屏幕进入睡眠 → 暂停，节省性能
        nc.addObserver(self, selector: #selector(pauseForSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        // 会话锁定（锁屏激活）→ 暂停，节省性能
        nc.addObserver(self, selector: #selector(pauseForSleep), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }

    @objc private func wakeUpAndPlay() {
        for player in videoPlayers { player.play() }
    }

    @objc private func pauseForSleep() {
        for player in videoPlayers { player.pause() }
    }

    func clearVideoWallpaper() {
        for player in videoPlayers {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        for window in videoWindows {
            window.contentView = nil
            window.orderOut(nil)
        }
        for observer in playerLooperObservers { NotificationCenter.default.removeObserver(observer) }
        videoWindows.removeAll()
        videoPlayers.removeAll()
        playerLooperObservers.removeAll()
    }

    func playVideoOnDesktop(url: URL, screenName: String = "全部") {
        clearVideoWallpaper()
        let targetScreens: [NSScreen]
        if screenName == "全部" {
            targetScreens = NSScreen.screens
        } else {
            let filtered = NSScreen.screens.filter { $0.localizedName == screenName }
            targetScreens = filtered.isEmpty ? NSScreen.screens : filtered
        }
        for screen in targetScreens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
            window.backgroundColor = .black
            
            let player = AVPlayer(url: url)
            player.actionAtItemEnd = .none
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            
            let observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                player.seek(to: .zero); player.play()
            }
            playerLooperObservers.append(observer)
            
            let playerView = AVPlayerView()
            playerView.player = player
            playerView.controlsStyle = .none
            playerView.videoGravity = .resizeAspectFill
            window.contentView = playerView
            window.makeKeyAndOrderFront(nil)
            player.play()
            videoWindows.append(window)
            videoPlayers.append(player)
        }
    }
    
    // 清理机制：当这个管家被销毁时，记得把监听器也拆掉（虽然单例一般不会被销毁，但这是个好习惯）
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
