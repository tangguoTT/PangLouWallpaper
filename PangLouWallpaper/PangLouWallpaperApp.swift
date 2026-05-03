//
//  SimpleWallpaperApp.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/20.
//

import SwiftUI
import AppKit

// -----------------------------------------------------------
// MARK: - 1. 程序生命周期管家 (AppDelegate)
// -----------------------------------------------------------
// 这个类会在程序刚启动的瞬间，抢先一步执行一些底层设置
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 🌟 核心魔法 1：设置为 .accessory（附件模式）
        // 这行代码会彻底隐藏程序在底部 Dock 栏的图标，把它变成一个纯粹的后台/状态栏软件！
        NSApp.setActivationPolicy(.accessory)
        
        // 确保程序刚启动时，主界面能立刻跳到所有窗口的最前面
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "panglouwallpaper" {
            Task { await AuthService.shared.handleAuthCallback(url: url) }
        }
    }
}

// -----------------------------------------------------------
// MARK: - 2. 软件的启动大门
// -----------------------------------------------------------
@main
struct PangLouWallpaperApp: App {
    // 告诉 SwiftUI：请使用上面我写的那个“管家”来接管程序的启动
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // SwiftUI 提供的专属工具：用来在状态栏里强行召唤窗口
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Window（非 WindowGroup）确保全局唯一实例，不会重复创建窗口
        Window("胖楼壁纸", id: "mainWindow") {
            ContentView()
        }
        .defaultSize(width: 1200, height: 820)

        MenuBarExtra("胖楼壁纸", systemImage: "camera.aperture") {

            Button("打开主界面") {
                // 优先复用已有窗口：最小化则恢复，否则直接前置
                if let win = NSApp.windows.first(where: { $0.identifier?.rawValue == "mainWindow" })
                    ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
                    if win.isMiniaturized { win.deminiaturize(nil) }
                    win.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "mainWindow")
                }
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("随机换一张壁纸") {
                NotificationCenter.default.post(name: .randomWallpaperTrigger, object: nil)
            }

            Divider()

            Button("退出胖楼壁纸") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
