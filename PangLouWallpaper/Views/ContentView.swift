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
                    
                    let hideBottomBar = (viewModel.currentTab == .upload && viewModel.uploadMode == .pending)
                        || (viewModel.currentTab == .collection && viewModel.selectedCollectionId == nil)
                    if !hideBottomBar {
                        BottomFloatingBarView(viewModel: viewModel)
                            .padding(.top, 10)
                            .padding(.bottom, 25)
                    }
                }
                // 🌟 强制规定：VStack 尺寸绝对不能超过当前可用空间！
                .frame(width: geo.size.width, height: geo.size.height)
                .disabled(viewModel.showLoginSheet || viewModel.showAbout || viewModel.showUserSpace || viewModel.previewItem != nil || viewModel.editingWallpaper != nil || viewModel.addToCollectionTargetItem != nil)
            }
            
            if viewModel.showAbout {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .allowsHitTesting(viewModel.showAbout)
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
                    .allowsHitTesting(viewModel.previewItem != nil)
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
                    .allowsHitTesting(viewModel.addToCollectionTargetItem != nil)
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
                Color.black.opacity(0.5).ignoresSafeArea()
                    .allowsHitTesting(viewModel.editingWallpaper != nil)
                    .onTapGesture { viewModel.cancelEdit() }
                // 保证弹窗永远在屏幕正中间
                VStack {
                    Spacer()
                    EditWallpaperPopupView(viewModel: viewModel)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(100)
            }

            if viewModel.showUserSpace {
                // 遮罩：纯视觉，不拦截事件（allowsHitTesting false）
                // 点击空白由 HStack 内的 Spacer 手势处理，避免 HStack 吞掉事件后无人消费
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(102)

                // 抽屉：从右侧滑入
                // Spacer 区域直接绑定 onTapGesture 关闭抽屉，
                // 确保左侧空白点击被正确处理而不是被 HStack 吞掉
                HStack(spacing: 0) {
                    Spacer()
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.showUserSpace = false }
                    UserSpaceView(viewModel: viewModel)
                }
                .transition(.move(edge: .trailing))
                .zIndex(103)
            }

            if viewModel.showEditProfile {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .allowsHitTesting(viewModel.showEditProfile)
                    .onTapGesture { viewModel.showEditProfile = false }
                    .zIndex(103.5)
                VStack {
                    Spacer()
                    EditProfileView(viewModel: viewModel)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(104)
            }

            if viewModel.showChangePassword {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .allowsHitTesting(viewModel.showChangePassword)
                    .onTapGesture { viewModel.showChangePassword = false }
                    .zIndex(103.5)
                VStack {
                    Spacer()
                    ChangePasswordView(viewModel: viewModel)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(104)
            }

            if viewModel.showLoginSheet {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .allowsHitTesting(viewModel.showLoginSheet)
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.showLoginSheet = false } }
                VStack {
                    Spacer()
                    AuthView(viewModel: viewModel)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(101)
            }

        }
        .animation(.easeInOut(duration: 0.28), value: viewModel.showUserSpace)
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
    }
}
