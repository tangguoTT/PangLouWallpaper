//
//  UIComponents.swift
//  SimpleWallpaper
//
//  Created by 唐潇 on 2026/2/21.
//

// 存放了在各个地方复用的小零件（开关、胶囊按钮、页码等）。

import SwiftUI

let capsuleBgColor = Color.primary.opacity(0.05)

struct AsyncThumbnailView: View {
    let item: WallpaperItem
    @State private var thumbnail: NSImage?
    var body: some View {
        ZStack {
            if let img = thumbnail {
                Image(nsImage: img).resizable().aspectRatio(16/10, contentMode: .fill)
            } else {
                Color.primary.opacity(0.05).overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: item.fullURL) {
            let thumbURL = item.fullURL.ossThumb(isVideo: item.isVideo)
            if let img = await WallpaperCacheManager.shared.fetchImage(for: thumbURL) { self.thumbnail = img }
        }
    }
}

struct WallpaperCardView: View {
    let item: WallpaperItem
    @ObservedObject var viewModel: WallpaperViewModel
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            AsyncThumbnailView(item: item).cornerRadius(12).clipped()
            if item.isVideo { VStack { HStack { Spacer(); Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundColor(.white.opacity(0.9)).padding(10) }; Spacer() } }
            
            if isHovered {
                (colorScheme == .dark ? Color.black : Color.white).opacity(0.3).cornerRadius(12)
                    .overlay(
                        ZStack {
                            Button(action: { viewModel.setWallpaper(item: item) }) {
                                Text(item.isVideo ? "设为动态壁纸" : "设为壁纸").font(.system(size: 13, weight: .bold)).foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(.vertical, 8).padding(.horizontal, 20).background(.ultraThinMaterial).clipShape(Capsule()).overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                            }.buttonStyle(.plain)
                            
                            if viewModel.currentTab == .downloaded {
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button(action: { viewModel.deleteSingleCache(for: item) }) {
                                            Image(systemName: "trash.fill").font(.system(size: 12)).foregroundColor(.white).padding(8).background(Color.red.opacity(0.8)).clipShape(Circle()).shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                                        }
                                        .buttonStyle(.plain).padding(8)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    )
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .shadow(color: Color.primary.opacity(isHovered ? 0.2 : 0.05), radius: isHovered ? 10 : 4, y: isHovered ? 5 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered).onHover { isHovered = $0 }
    }
}

struct CustomThemeToggleView: View {
    @Binding var isDarkMode: Bool

    var body: some View {
        ZStack {
            Capsule().fill(isDarkMode ? Color(white: 0.25) : Color(white: 0.8))
                .frame(width: 54, height: 28).overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 1))
            HStack {
                if isDarkMode { Spacer(minLength: 0) }
                ZStack {
                    Circle().fill(Color(white: 0.75)).shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    if isDarkMode {
                        ZStack {
                            Circle().stroke(Color.black, lineWidth: 1.5).frame(width: 14, height: 14)
                            Image(systemName: "moon.fill").resizable().scaledToFit().frame(width: 8, height: 8).foregroundColor(.black).offset(x: -0.5, y: -0.5)
                        }.transition(.scale.combined(with: .opacity))
                    } else {
                        ZStack {
                            Group { Rectangle().fill(Color.black).frame(width: 16, height: 16); Rectangle().fill(Color.black).frame(width: 16, height: 16).rotationEffect(.degrees(45)) }
                            Group { Rectangle().fill(Color(red: 0.98, green: 0.86, blue: 0.45)).frame(width: 13, height: 13); Rectangle().fill(Color(red: 0.98, green: 0.86, blue: 0.45)).frame(width: 13, height: 13).rotationEffect(.degrees(45)) }
                            Circle().stroke(Color.black, lineWidth: 1).frame(width: 7, height: 7).background(Circle().fill(Color(red: 0.98, green: 0.86, blue: 0.45)))
                        }.transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 24, height: 24).padding(2)
                if !isDarkMode { Spacer(minLength: 0) }
            }
        }
        .frame(width: 54, height: 28)
        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isDarkMode.toggle() } }
    }
}

struct NavPillButtonView: View {
    let title: String; let icon: String; let isSelected: Bool; var showBadge: Bool = false
    let action: () -> Void
    var bgColor: Color { isSelected ? Color.accentColor.opacity(0.15) : Color.clear }
    var fgColor: Color { isSelected ? Color.accentColor : Color.primary.opacity(0.6) }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 12)); Text(title).font(.system(size: 13, weight: isSelected ? .bold : .regular)) }
            .foregroundColor(fgColor).padding(.vertical, 8).padding(.horizontal, 16).background(bgColor).clipShape(Capsule())
            .overlay(ZStack { if showBadge { Text("N").font(.system(size: 8, weight: .bold)).foregroundColor(.white).padding(4).background(Color.red).clipShape(Circle()).offset(x: 10, y: -10) } }, alignment: .topTrailing)
        }.buttonStyle(.plain)
    }
}

struct FilterTagView: View {
    let title: String; var icon: String? = nil; let isSelected: Bool
    var fgColor: Color { isSelected ? Color.accentColor : Color.primary.opacity(0.7) }
    var bgColor: Color { isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05) }
    var body: some View { HStack(spacing: 4) { if let icon = icon { Image(systemName: icon).font(.system(size: 11)) }; Text(title).font(.system(size: 13)) }.foregroundColor(fgColor).padding(.vertical, 8).padding(.horizontal, 16).background(bgColor).clipShape(Capsule()) }
}

struct PageNumberCircleView: View {
    let number: Int; let isCurrent: Bool; let action: () -> Void
    var fgColor: Color { isCurrent ? Color.accentColor : Color.primary.opacity(0.7) }
    var bgColor: Color { isCurrent ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05) }
    var body: some View {
        Button(action: action) {
            Text("\(number)").font(.system(size: 13, weight: isCurrent ? .bold : .medium)).foregroundColor(fgColor).frame(width: 32, height: 32).background(bgColor).clipShape(Circle())
        }.buttonStyle(.plain)
    }
}
