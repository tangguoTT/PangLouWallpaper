//
//  ContentView.swift
//  SimpleWallpaper
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WallpaperViewModel()
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    var body: some View {
        ZStack {
            (isDarkMode ? Color(red: 0.08, green: 0.09, blue: 0.10) : Color(red: 0.95, green: 0.95, blue: 0.97))
                .ignoresSafeArea()
            
            // 🌟 核心修复 1：利用 GeometryReader 拿到真实窗口尺寸，死死锁住边框
            GeometryReader { geo in
                VStack(spacing: 0) {
                    TopNavigationBarView(viewModel: viewModel, isDarkMode: $isDarkMode)
                        .padding(.top, 20)
                        .padding(.horizontal, 30)
                    
                    WallpaperGridView(viewModel: viewModel)
                        .padding(.top, 15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    let hideBottomBar = (viewModel.currentTab == .upload && viewModel.uploadMode != .manage)
                        || (viewModel.currentTab == .collection && viewModel.selectedCollectionId == nil)
                    if !hideBottomBar {
                        BottomFloatingBarView(viewModel: viewModel)
                            .padding(.top, 10)
                            .padding(.bottom, 25)
                    }
                }
                // 🌟 强制规定：VStack 尺寸绝对不能超过当前可用空间！
                .frame(width: geo.size.width, height: geo.size.height)
            }
            
            if viewModel.showAbout {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.showAbout = false } }
                VStack {
                    Spacer()
                    AboutView(viewModel: viewModel)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(98)
            }

            if viewModel.previewItem != nil {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil } }
                VStack {
                    Spacer()
                    if let item = viewModel.previewItem {
                        WallpaperPreviewView(item: item, viewModel: viewModel)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    Spacer()
                }
                .zIndex(99)
            }

            if viewModel.addToCollectionTargetItem != nil {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.addToCollectionTargetItem = nil } }
                VStack {
                    Spacer()
                    AddToCollectionView(viewModel: viewModel)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(99)
            }

            if viewModel.editingWallpaper != nil {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { viewModel.cancelEdit() }
                // 保证弹窗永远在屏幕正中间
                VStack {
                    Spacer()
                    EditWallpaperPopupView(viewModel: viewModel)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(100)
            }

        }
        .frame(minWidth: 1100, minHeight: 750)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear {
            viewModel.fetchCloudData()
            viewModel.restoreLastWallpaper()
        }
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundColor(isDarkMode ? .white : .black)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.trailing, 30).padding(.bottom, 100)
                    }
                }
            }
            .animation(.easeInOut, value: viewModel.statusMessage)
        )
        .onTapGesture {
            if viewModel.showTypeMenu || viewModel.showCategoryMenu || viewModel.showResolutionMenu || viewModel.showColorMenu {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.showTypeMenu = false; viewModel.showCategoryMenu = false; viewModel.showResolutionMenu = false; viewModel.showColorMenu = false
                }
            }
        }
    }
}
