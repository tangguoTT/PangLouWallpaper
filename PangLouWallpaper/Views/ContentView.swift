import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WallpaperViewModel()
    @State private var isDarkMode: Bool = true

    var body: some View {
        ZStack {
            (isDarkMode ? Color(red: 0.08, green: 0.09, blue: 0.10) : Color(red: 0.95, green: 0.95, blue: 0.97))
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                TopNavigationBarView(viewModel: viewModel, isDarkMode: $isDarkMode)
                    .padding(.top, 20)
                    .padding(.horizontal, 30)
                
                WallpaperGridView(viewModel: viewModel)
                    .padding(.top, 15)
                
                BottomFloatingBarView(viewModel: viewModel)
                    .padding(.bottom, 25)
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
        // 💡 修改点：只要点击界面的其他地方，任何弹开的菜单都会自动收起
        .onTapGesture {
            if viewModel.showTypeMenu || viewModel.showCategoryMenu || viewModel.showResolutionMenu || viewModel.showColorMenu {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.showTypeMenu = false
                    viewModel.showCategoryMenu = false
                    viewModel.showResolutionMenu = false
                    viewModel.showColorMenu = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
