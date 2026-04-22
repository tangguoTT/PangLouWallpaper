//
//  ContentView.swift
//  SimpleWallpaper
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WallpaperViewModel()
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("isSidebarVisible") private var isSidebarVisible: Bool = true
    @State private var showSettings = false

    private var sidebarToggleButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isSidebarVisible = true
            }
        }) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.6))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.07))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help("显示侧边栏")
        .transition(.opacity)
    }

    var body: some View {
        ZStack {
            // Background
            (isDarkMode
                ? Color(red: 0.07, green: 0.08, blue: 0.10)
                : Color(red: 0.94, green: 0.94, blue: 0.97)
            ).ignoresSafeArea()

            GeometryReader { geo in
                HStack(spacing: 0) {
                    // ── Left Sidebar ──
                    if isSidebarVisible {
                        SidebarView(
                            viewModel: viewModel,
                            isDarkMode: $isDarkMode,
                            showSettings: $showSettings,
                            isSidebarVisible: $isSidebarVisible
                        )
                        .transition(.move(edge: .leading))

                        // Thin separator
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 1)
                            .transition(.move(edge: .leading))
                    }

                    // ── Main Content Column ──
                    if showSettings {
                        SettingsView(viewModel: viewModel, isDarkMode: $isDarkMode)
                    } else {
                        let hideSearchBar = (viewModel.currentTab == .upload && viewModel.uploadMode == .pending)
                            || (viewModel.currentTab == .collection && viewModel.selectedCollectionId == nil)
                            || viewModel.currentTab == .steamWorkshop
                            || (viewModel.currentTab == .downloaded && viewModel.downloadedSubTab != .local)
                        let hideBottomBar = (viewModel.currentTab == .upload && viewModel.uploadMode == .pending)
                            || (viewModel.currentTab == .collection && viewModel.selectedCollectionId == nil)
                            || viewModel.currentTab == .steamWorkshop

                        VStack(spacing: 0) {
                            // Top bar row: sidebar toggle (when hidden) + search bar
                            if !hideSearchBar {
                                VStack(spacing: 0) {
                                    HStack(alignment: .center, spacing: 0) {
                                        if !isSidebarVisible {
                                            sidebarToggleButton
                                                .padding(.leading, 14)
                                                .padding(.top, 18)
                                                .padding(.bottom, 12)
                                        }
                                        SearchFilterBarView(viewModel: viewModel)
                                            .padding(.leading, isSidebarVisible ? 28 : 10)
                                            .padding(.trailing, 28)
                                            .padding(.top, 18)
                                            .padding(.bottom, 12)
                                    }
                                    Divider().opacity(0.5)
                                }
                                .background(.bar)
                                .zIndex(10)
                            } else {
                                // No search bar: show just the toggle button row when sidebar hidden
                                if !isSidebarVisible {
                                    HStack {
                                        sidebarToggleButton
                                        Spacer()
                                    }
                                    .padding(.leading, 14)
                                    .padding(.top, 14)
                                    .padding(.bottom, 4)
                                } else {
                                    Color.clear.frame(height: 18)
                                }
                            }

                            WallpaperGridView(viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .zIndex(1)

                            if viewModel.currentTab == .downloaded
                                && viewModel.downloadedSubTab == .local
                                && viewModel.isBatchSelectMode {
                                BatchActionBarView(viewModel: viewModel)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 14)
                                    .zIndex(1)
                            } else if !hideBottomBar {
                                PaginationBarView(viewModel: viewModel)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 14)
                                    .zIndex(1)
                            } else {
                                Color.clear.frame(height: 8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSidebarVisible)
                .disabled(
                    viewModel.showLoginSheet || viewModel.showAbout ||
                    viewModel.showUserSpace || viewModel.previewItem != nil ||
                    viewModel.editingWallpaper != nil || viewModel.addToCollectionTargetItem != nil ||
                    viewModel.deleteConfirmItem != nil
                )
            }

            // ── Modal Overlays ──

            if viewModel.showAbout {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.showAbout = false } }

                VStack {
                    Spacer()
                    AboutView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer()
                }
                .zIndex(98)
            }

            if viewModel.previewItem != nil {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.previewItem = nil } }

                VStack {
                    Spacer()
                    if let item = viewModel.previewItem {
                        WallpaperPreviewView(item: item, viewModel: viewModel)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    Spacer()
                }
                .zIndex(99)
            }

            if viewModel.addToCollectionTargetItem != nil {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.addToCollectionTargetItem = nil } }

                VStack {
                    Spacer()
                    AddToCollectionView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer()
                }
                .zIndex(99)
            }

            if viewModel.editingWallpaper != nil {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture { viewModel.cancelEdit() }

                VStack {
                    Spacer()
                    EditWallpaperPopupView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer()
                }
                .zIndex(100)
            }

            if let item = viewModel.deleteConfirmItem {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture { viewModel.deleteConfirmItem = nil }
                    .zIndex(100)

                VStack {
                    Spacer()
                    DeleteConfirmView(item: item, viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer()
                }
                .zIndex(101)
            }

            if viewModel.showUserSpace {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(102)

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
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture { viewModel.showEditProfile = false }
                    .zIndex(103.5)
                VStack {
                    Spacer()
                    EditProfileView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer()
                }
                .zIndex(104)
            }

            if viewModel.showChangePassword {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture { viewModel.showChangePassword = false }
                    .zIndex(103.5)
                VStack {
                    Spacer()
                    ChangePasswordView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer()
                }
                .zIndex(104)
            }

            if viewModel.showLoginSheet {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8).ignoresSafeArea()
                    .allowsHitTesting(true)
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.showLoginSheet = false } }

                VStack {
                    Spacer()
                    AuthView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer()
                }
                .zIndex(101)
            }
        }
        .sheet(item: $viewModel.periodPickerTargetPeriod) { period in
            PeriodWallpaperPickerView(period: period, viewModel: viewModel)
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
                            .padding(.trailing, 30).padding(.bottom, 30)
                    }
                }
            }
            .animation(.easeInOut, value: viewModel.statusMessage)
        )
    }
}
