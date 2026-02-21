//
//  AppSections.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/21.
//

// 包含顶部栏、瀑布流照片墙、卡片、底部悬浮栏四个核心组件。

//
//  AppSections.swift
//  SimpleWallpaper
//

import SwiftUI

struct TopNavigationBarView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Binding var isDarkMode: Bool
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "camera.aperture").font(.system(size: 22))
                Text("胖楼壁纸").font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(capsuleBgColor).clipShape(Capsule())
            .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 4) {
                NavPillButtonView(title: AppTab.pc.rawValue, icon: "desktopcomputer", isSelected: viewModel.currentTab == .pc) { viewModel.currentTab = .pc }
                NavPillButtonView(title: AppTab.downloaded.rawValue, icon: "square.and.arrow.down", isSelected: viewModel.currentTab == .downloaded) { viewModel.currentTab = .downloaded }
            }
            .padding(4).background(capsuleBgColor).clipShape(Capsule())
            
            Spacer()
            
            HStack(spacing: 15) {
                CustomThemeToggleView(isDarkMode: $isDarkMode)
                Image(systemName: "bell").font(.system(size: 16)).foregroundColor(.primary)
                
                Menu {
                    Toggle("开机自动启动", isOn: Binding(
                        get: { viewModel.isAutoStartEnabled },
                        set: { viewModel.toggleAutoStart(enable: $0) }
                    ))
                    Divider()
                    Button(role: .destructive, action: { viewModel.clearCache() }) {
                        Text("清除全部缓存 (\(viewModel.cacheSizeString))")
                        Image(systemName: "trash")
                    }
                } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 16)).foregroundColor(.primary).frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                
                Image(systemName: "person.circle.fill").resizable().frame(width: 36, height: 36)
                    .foregroundColor(.gray).overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
    }
}

struct WallpaperGridView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    let columns = Array(repeating: GridItem(.flexible(), spacing: 15), count: 4)
    var body: some View {
        if viewModel.displayWallpapers.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "tray").font(.system(size: 48)).foregroundColor(.primary.opacity(0.3))
                Text(viewModel.currentTab == .downloaded ? "暂无下载缓存" : "未找到相关壁纸")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary.opacity(0.5))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 120)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(viewModel.paginatedImages) { item in
                        WallpaperCardView(item: item, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 30).padding(.bottom, 120)
            }
        }
    }
}

struct BottomFloatingBarView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var searchText = ""
    
    let types = ["全部", "静态壁纸", "动态壁纸"]
    let categories = ["全部", "魅力 | 迷人", "自制 | 艺术", "安逸 | 自由", "科幻 | 星云", "动漫 | 二次元", "自然 | 风景", "游戏 | 玩具"]
    let resolutions = ["全部", "1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K"]
    let colors: [(String, Color?)] = [
        ("全部", nil), ("偏蓝", Color(hex: "#28A7D0")), ("偏绿", Color(hex: "#449B3E")),
        ("偏红", Color(hex: "#873229")), ("灰/白", Color.gray.opacity(0.6)),
        ("紫/粉", Color(hex: "#A030C8")), ("暗色", Color(hex: "#333333")),
        ("偏黄", Color(hex: "#C6AC2C")), ("其他颜色", nil)
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                HStack { TextField("插画、简单、动漫...", text: $searchText).textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.primary) }
                .padding(.horizontal, 16).padding(.vertical, 10).frame(width: 180).background(capsuleBgColor).clipShape(Capsule())
                
                HStack(spacing: 6) {
                    FilterTagView(title: "昨日热门", isSelected: true)
                    
                    // 1. 种类
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.showTypeMenu.toggle()
                            if viewModel.showTypeMenu { closeOtherMenus(except: "Type") }
                        }
                    }) {
                        FilterTagView(title: viewModel.selectedType == "全部" ? "种类" : viewModel.selectedType, icon: "square.grid.2x2", isSelected: viewModel.showTypeMenu || viewModel.selectedType != "全部")
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if viewModel.showTypeMenu {
                            MenuPopoverView(options: types, selected: $viewModel.selectedType) { viewModel.showTypeMenu = false }.offset(y: -46)
                        }
                    }
                    
                    // 2. 分类
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.showCategoryMenu.toggle()
                            if viewModel.showCategoryMenu { closeOtherMenus(except: "Category") }
                        }
                    }) {
                        let displayTitle = viewModel.selectedCategory == "全部" ? "分类" : (viewModel.selectedCategory.components(separatedBy: " | ").first ?? "分类")
                        FilterTagView(title: displayTitle, icon: "tag", isSelected: viewModel.showCategoryMenu || viewModel.selectedCategory != "全部")
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if viewModel.showCategoryMenu {
                            MenuPopoverView(options: categories, selected: $viewModel.selectedCategory) { viewModel.showCategoryMenu = false }.offset(y: -46)
                        }
                    }
                    
                    // 3. 💡 分辨率
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.showResolutionMenu.toggle()
                            if viewModel.showResolutionMenu { closeOtherMenus(except: "Resolution") }
                        }
                    }) {
                        FilterTagView(title: viewModel.selectedResolution == "全部" ? "分辨率" : viewModel.selectedResolution, icon: "tv", isSelected: viewModel.showResolutionMenu || viewModel.selectedResolution != "全部")
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if viewModel.showResolutionMenu {
                            ResolutionPopoverView(viewModel: viewModel, options: resolutions)
                                .offset(y: -46)
                        }
                    }
                    
                    // 4. 💡 色系
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.showColorMenu.toggle()
                            if viewModel.showColorMenu { closeOtherMenus(except: "Color") }
                        }
                    }) {
                        FilterTagView(title: viewModel.selectedColor == "全部" ? "色系" : viewModel.selectedColor, icon: "paintpalette", isSelected: viewModel.showColorMenu || viewModel.selectedColor != "全部")
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if viewModel.showColorMenu {
                            ColorPopoverView(options: colors, selected: $viewModel.selectedColor) { viewModel.showColorMenu = false }
                                .offset(y: -46)
                        }
                    }
                }
                HStack(spacing: 8) { Button(action:{}) { Image(systemName: "viewfinder").font(.system(size: 14)).padding(10).background(capsuleBgColor).clipShape(Circle()) }.buttonStyle(.plain) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)).shadow(color: Color.black.opacity(0.1), radius: 15, y: 8)
            
            HStack(spacing: 16) {
                Button(action: { viewModel.currentPage -= 1 }) { Image(systemName: "arrow.left").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(.plain).disabled(viewModel.currentPage == 0).foregroundColor(viewModel.currentPage == 0 ? Color.primary.opacity(0.3) : Color.primary)
                
                HStack(spacing: 10) {
                    ForEach(0..<min(viewModel.totalPages, 3), id: \.self) { index in
                        PageNumberCircleView(number: index + 1, isCurrent: viewModel.currentPage == index) { viewModel.currentPage = index }
                    }
                    if viewModel.totalPages > 3 {
                        Text("...").foregroundColor(.primary.opacity(0.6)).font(.system(size: 12, weight: .bold))
                        PageNumberCircleView(number: viewModel.totalPages, isCurrent: viewModel.currentPage == viewModel.totalPages - 1) { viewModel.currentPage = viewModel.totalPages - 1 }
                    }
                }
                
                Text("Go").font(.system(size: 13, weight: .bold)).foregroundColor(.accentColor).padding(.leading, 10)
                Button(action: { viewModel.currentPage += 1 }) { Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(.plain).disabled(viewModel.currentPage >= viewModel.totalPages - 1).foregroundColor(viewModel.currentPage >= viewModel.totalPages - 1 ? Color.primary.opacity(0.3) : Color.primary)
            }
        }
    }
    
    // 菜单互斥排他
    private func closeOtherMenus(except name: String) {
        if name != "Type" { viewModel.showTypeMenu = false }
        if name != "Category" { viewModel.showCategoryMenu = false }
        if name != "Resolution" { viewModel.showResolutionMenu = false }
        if name != "Color" { viewModel.showColorMenu = false }
    }
}

// ----------------------------------------------------
// MARK: 💡 高级重用弹窗组件
// ----------------------------------------------------

struct MenuPopoverView: View {
    let options: [String]
    @Binding var selected: String
    let closeAction: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            ForEach(options, id: \.self) { option in
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = option; closeAction() } }) {
                    Text(option).font(.system(size: 15, weight: selected == option ? .bold : .medium)).foregroundColor(selected == option ? .white : .white.opacity(0.8))
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 20).padding(.horizontal, 24).fixedSize()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.4), radius: 15, y: 5).transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }
}

// 💡 色系专属弹窗 (修复圆角过大，还原纯正毛玻璃)
struct ColorPopoverView: View {
    let options: [(String, Color?)]
    @Binding var selected: String
    let closeAction: () -> Void
    
    var body: some View {
        // 动态计算精确高度 (保持不变)
        let contentHeight = CGFloat(options.count) * 36.0 + 24.0
        let finalHeight = min(contentHeight, 280.0)
        
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ForEach(options, id: \.0) { option in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selected = option.0
                            closeAction()
                        }
                    }) {
                        HStack(spacing: 0) {
                            Text(option.0)
                                .font(.system(size: 14, weight: selected == option.0 ? .bold : .medium))
                                .foregroundColor(selected == option.0 ? .white : .white.opacity(0.8))
                            
                            Spacer()
                            
                            if let color = option.1 {
                                Circle().fill(color).frame(width: 14, height: 14)
                            } else if option.0 == "其他颜色" {
                                Circle().fill(AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .red]), center: .center)).frame(width: 14, height: 14)
                            } else {
                                Spacer().frame(width: 14)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .frame(width: 140, height: finalHeight)
        // 🌟 核心修改区 🌟
        .background(
            // 1. 使用更精致的 12 号圆角
            // 2. 直接应用 ultraThinMaterial 材质作为填充，确保毛玻璃通透感
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
            // 3. 强制深色环境，让毛玻璃呈现暗色调
                .environment(\.colorScheme, .dark)
        )
        // 描边圆角也要同步改成 12
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 15, y: 5)
        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
    }
}

// 💡 分辨率专属弹窗 (带底部虚线自定义区域)
struct ResolutionPopoverView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    let options: [String]
    var body: some View {
        VStack(spacing: 0) {
            // 上方列表
            VStack(spacing: 18) {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.selectedResolution = option
                            viewModel.showResolutionMenu = false
                        }
                    }) {
                        Text(option).font(.system(size: 15, weight: viewModel.selectedResolution == option ? .bold : .medium)).foregroundColor(viewModel.selectedResolution == option ? .white : .white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }.padding(.all, 20)
            
            Divider().background(Color.white.opacity(0.1))
            
            // 底部自定义虚线框区域
            VStack(alignment: .leading, spacing: 12) {
                Text("自定义：").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                HStack(spacing: 10) {
                    CustomDashedTextField(placeholder: "例: 1920", text: $viewModel.customWidth)
                    Text("×").foregroundColor(.gray)
                    CustomDashedTextField(placeholder: "例: 1080", text: $viewModel.customHeight)
                }
                Text("提示：【可单项查询】 【点击空白处触发搜索】").font(.system(size: 10)).foregroundColor(.gray.opacity(0.8))
            }.padding(.all, 20)
        }
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.4), radius: 15, y: 5).transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }
}

// 专门为分辨率打造的虚线边框输入框
struct CustomDashedTextField: View {
    var placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
    }
}

// Hex Color Extension 用于色系支持
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
}
