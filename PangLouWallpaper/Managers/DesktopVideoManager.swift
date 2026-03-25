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

    // 🌟 新增核心代码：在初始化时，注册“系统唤醒”监听器
    override init() {
        super.init()
        
        // 监听系统通知：屏幕重新亮起时
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(wakeUpAndPlay),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        // 监听系统通知：电脑从深度休眠中恢复时
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(wakeUpAndPlay),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    // 🌟 新增核心代码：当收到唤醒通知时，强制所有视频重新播放
    @objc private func wakeUpAndPlay() {
        for player in videoPlayers {
            player.play()
        }
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
