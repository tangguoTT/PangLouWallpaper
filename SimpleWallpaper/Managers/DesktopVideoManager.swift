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

    func playVideoOnDesktop(url: URL) {
        clearVideoWallpaper()
        for screen in NSScreen.screens {
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
}
