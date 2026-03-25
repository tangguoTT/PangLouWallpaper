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
        // 1. 你的主界面（原封不动）
        // 🌟 我们只给它加了一个身份证号 id: "mainWindow"，方便我们以后呼唤它
        WindowGroup(id: "mainWindow") {
            ContentView()
        }
        
        // 2. 🌟 核心魔法 2：在屏幕右上角状态栏生成图标
        // "camera.aperture" 是那个光圈图标，和你在导航栏用的一样
        MenuBarExtra("胖楼壁纸", systemImage: "camera.aperture") {
            
            // 下拉菜单按钮一：打开界面
            Button("打开主界面") {
                // 根据身份证号，把主窗口叫出来
                openWindow(id: "mainWindow")
                // 并把它强行按在屏幕最上面，防止被浏览器等其他软件挡住
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
