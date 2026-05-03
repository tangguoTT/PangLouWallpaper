//
//  DownloadedDetailView.swift
//  SimpleWallpaper
//
//  已下载壁纸详情页：点击卡片后整页替换网格，左侧预览，右侧设置面板。

import SwiftUI
import Combine
import AVKit
import WebKit
import AppKit

// MARK: - Media Kind

enum DetailMediaKind {
    case image, videoMP4, videoWebM, html
}

private func resolveLocalURL(_ item: WallpaperItem) -> URL? {
    if item.fullURL.isFileURL && FileManager.default.fileExists(atPath: item.fullURL.path) {
        return item.fullURL
    }
    let cached = WallpaperCacheManager.shared.getLocalPath(for: item.fullURL)
    return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
}

private func detectKind(_ item: WallpaperItem, url: URL?) -> DetailMediaKind {
    let ext = url?.pathExtension.lowercased() ?? ""
    if ext == "html" || ext == "htm" { return .html }
    if ext == "webm"                 { return .videoWebM }
    if item.isVideo                  { return .videoMP4 }
    return .image
}

// MARK: - Shared Media Controller

final class DetailMediaController: ObservableObject {
    @Published var volume: Double = 0
    @Published var playbackRate: Double = 1.0
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1

    // AVPlayer state
    private(set) var avPlayer: AVPlayer?
    private var timeObserver: Any?

    // WKWebView state
    private weak var webView: WKWebView?
    private var pollTimer: Timer?

    // MARK: - AVPlayer

    func connectAVPlayer(_ player: AVPlayer) {
        disconnectAVPlayer()
        avPlayer = player
        player.volume = Float(volume)
        player.play()
        isPlaying = true

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            guard let self, let player else { return }
            self.currentTime = max(0, time.seconds)
            if let d = player.currentItem?.duration, d.isNumeric {
                self.duration = max(1, d.seconds)
            }
            self.isPlaying = player.timeControlStatus == .playing
        }

        // Loop automatically
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    func disconnectAVPlayer() {
        if let o = timeObserver, let p = avPlayer { p.removeTimeObserver(o) }
        avPlayer?.pause()
        avPlayer = nil
        timeObserver = nil
    }

    // MARK: - WKWebView

    func connectWebView(_ wv: WKWebView) {
        disconnectWebView()
        webView = wv
        applyVolumeWeb(volume)

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let wv = self.webView else { return }
            wv.evaluateJavaScript(
                "(function(){var v=document.querySelector('video');if(!v)return null;" +
                "return [v.currentTime, isNaN(v.duration)?0:v.duration, !v.paused]})()"
            ) { [weak self] result, _ in
                guard let self else { return }
                if let arr = result as? [Any], arr.count == 3 {
                    self.currentTime = (arr[0] as? Double) ?? 0
                    let d = (arr[1] as? Double) ?? 0
                    self.duration = d > 0 ? d : 1
                    self.isPlaying = (arr[2] as? Bool) ?? false
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    func disconnectWebView() {
        pollTimer?.invalidate()
        pollTimer = nil
        webView = nil
    }

    // MARK: - Playback actions

    func togglePlay() {
        if let p = avPlayer {
            if p.timeControlStatus == .playing { p.pause() } else { p.play() }
        } else {
            webView?.evaluateJavaScript(
                "(function(){var v=document.querySelector('video');" +
                "if(v){if(v.paused)v.play();else v.pause()}})()", completionHandler: nil)
        }
    }

    func seek(to seconds: Double) {
        if let p = avPlayer {
            p.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        } else {
            webView?.evaluateJavaScript(
                "(function(){var v=document.querySelector('video');if(v)v.currentTime=\(seconds)})()",
                completionHandler: nil)
        }
    }

    func setRate(_ rate: Double) {
        playbackRate = rate
        if let p = avPlayer {
            if p.timeControlStatus == .playing { p.rate = Float(rate) }
        } else {
            webView?.evaluateJavaScript(
                "document.querySelectorAll('video').forEach(function(v){v.playbackRate=\(rate)})",
                completionHandler: nil)
        }
    }

    func setVolume(_ v: Double) {
        volume = v
        avPlayer?.volume = Float(v)
        applyVolumeWeb(v)
    }

    private func applyVolumeWeb(_ v: Double) {
        webView?.evaluateJavaScript(DesktopWebManager.volumeJS(v), completionHandler: nil)
    }

    func cleanup() {
        disconnectAVPlayer()
        disconnectWebView()
    }

    deinit { cleanup() }
}

// MARK: - Root View

struct DownloadedDetailView: View {
    let item: WallpaperItem
    @ObservedObject var viewModel: WallpaperViewModel
    @StateObject private var controller = DetailMediaController()

    private var localURL: URL? { resolveLocalURL(item) }
    private var mediaKind: DetailMediaKind { detectKind(item, url: localURL) }

    var body: some View {
        HStack(spacing: 0) {
            // Left: preview
            DetailPreviewPane(localURL: localURL, mediaKind: mediaKind, controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            // Right: settings
            DetailSettingsPane(item: item, viewModel: viewModel,
                               mediaKind: mediaKind, controller: controller)
                .frame(width: 280)
        }
        .onAppear {
            // Initialise volume slider from current desktop playback volume
            switch mediaKind {
            case .videoWebM, .videoMP4:
                controller.volume = Double(DesktopVideoManager.shared.videoVolume)
            case .html:
                controller.volume = DesktopWebManager.shared.webVolume
            case .image:
                break
            }
        }
        .onDisappear { controller.cleanup() }
    }
}

// MARK: - Preview Pane

private struct DetailPreviewPane: View {
    let localURL: URL?
    let mediaKind: DetailMediaKind
    let controller: DetailMediaController

    var body: some View {
        ZStack {
            Color.black

            if let url = localURL {
                switch mediaKind {
                case .image:
                    StaticImagePreview(url: url)
                case .videoMP4:
                    AVPlayerPreview(url: url, controller: controller)
                case .videoWebM, .html:
                    WebPreview(url: url, isHTML: mediaKind == .html, controller: controller)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36)).foregroundColor(.secondary)
                    Text("文件未找到").font(.system(size: 14)).foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Static Image

private struct StaticImagePreview: View {
    let url: URL
    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                    .tint(.white)
            }
        }
        .task {
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            image = loaded
        }
    }
}

// MARK: - AVPlayer Preview (mp4 / mov)

private struct AVPlayerPreview: NSViewRepresentable {
    let url: URL
    let controller: DetailMediaController

    func makeNSView(context: Context) -> AVPlayerView {
        let player = AVPlayer(url: url)
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        controller.connectAVPlayer(player)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

// MARK: - WebView Preview (webm video / html wallpaper)

private struct WebPreview: NSViewRepresentable {
    let url: URL
    let isHTML: Bool
    let controller: DetailMediaController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, url: url, isHTML: isHTML)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        if isHTML {
            // Use wpe:// custom scheme so JS fetch()/XHR can load local assets.
            // With plain file://, WKWebView returns xhr.status=0 which Spine treats as failure.
            config.setURLSchemeHandler(
                WallpaperFileSchemeHandler(rootDirectory: url.deletingLastPathComponent()),
                forURLScheme: "wpe"
            )
            // Desktop content mode: requestAnimationFrame runs at full speed
            config.defaultWebpagePreferences.preferredContentMode = .desktop

            // Fix devicePixelRatio to avoid upscaled blur on Retina
            let dpr = WKUserScript(
                source: "Object.defineProperty(window,'devicePixelRatio',{get:function(){return 1;},configurable:true});",
                injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(dpr)
            // Same Web Audio API master volume interception as the desktop web view
            config.userContentController.addUserScript(DesktopWebManager.audioMasterVolumeScript)

            // Black background + canvas cover-fit (mirrors DesktopWebManager behaviour)
            let coverScript = WKUserScript(source: """
                (function(){
                    document.documentElement.style.background='#000';
                    document.body && (document.body.style.backgroundColor='#000');
                    var attempts=0;
                    function coverFit(){
                        var canvas=document.querySelector('canvas');
                        if(!canvas||canvas.width<2||canvas.height<2){
                            if(++attempts<40){setTimeout(coverFit,250);}return;
                        }
                        var sw=window.innerWidth,sh=window.innerHeight;
                        var rect=canvas.getBoundingClientRect();
                        if(rect.width>=sw*0.9&&rect.height>=sh*0.9){
                            document.documentElement.style.overflow='hidden';
                            document.body.style.overflow='hidden';return;
                        }
                        var scale=Math.max(sw/canvas.width,sh/canvas.height);
                        canvas.style.setProperty('position','fixed','important');
                        canvas.style.setProperty('top','50%','important');
                        canvas.style.setProperty('left','50%','important');
                        canvas.style.setProperty('width',canvas.width+'px','important');
                        canvas.style.setProperty('height',canvas.height+'px','important');
                        canvas.style.setProperty('transform','translate(-50%,-50%) scale('+scale+')','important');
                        canvas.style.setProperty('transform-origin','center center','important');
                        canvas.style.setProperty('margin','0','important');
                        document.documentElement.style.overflow='hidden';
                        document.body.style.overflow='hidden';
                        document.body.style.backgroundColor='#000';
                    }
                    setTimeout(coverFit,200);
                })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(coverScript)

            // Trigger WE wallpaperPropertyListener.applyUserProperties so wallpapers initialize correctly
            let weInit = WKUserScript(source: """
                (function(){
                    function t(){if(window.wallpaperPropertyListener&&
                        typeof window.wallpaperPropertyListener.applyUserProperties==='function')
                        window.wallpaperPropertyListener.applyUserProperties({});}
                    setTimeout(t,0);setTimeout(t,500);setTimeout(t,1500);
                })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(weInit)
        } else {
            // WebM: inject autoplay + loop via MutationObserver in case <video> is created dynamically
            let autoplay = WKUserScript(source: """
                (function(){
                    function setupVideo(v){if(v._wpSetup)return;v._wpSetup=true;v.loop=true;v.autoplay=true;}
                    document.querySelectorAll('video').forEach(setupVideo);
                    new MutationObserver(function(ms){ms.forEach(function(m){
                        m.addedNodes.forEach(function(n){
                            if(n.nodeName==='VIDEO')setupVideo(n);
                            if(n.querySelectorAll)n.querySelectorAll('video').forEach(setupVideo);
                        });
                    });}).observe(document.documentElement,{childList:true,subtree:true});
                })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(autoplay)
        }

        // HTML wallpapers (Spine/WebGL) read window.innerWidth/Height at init time to size the
        // canvas. A zero frame gives a 0×0 viewport and the canvas is never created.
        // Use the screen frame so the JS initialises at full resolution; SwiftUI resizes the
        // view afterwards and the coverScript re-scales the canvas.
        let initFrame = isHTML
            ? (NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080))
            : .zero
        let wv = WKWebView(frame: initFrame, configuration: config)
        wv.navigationDelegate = context.coordinator
        context.coordinator.load(into: wv)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: DetailMediaController
        let url: URL
        let isHTML: Bool

        init(controller: DetailMediaController, url: URL, isHTML: Bool) {
            self.controller = controller
            self.url = url
            self.isHTML = isHTML
        }

        func load(into wv: WKWebView) {
            if isHTML {
                // Load via wpe:// so JS fetch()/XHR resolves assets as HTTP 200.
                // file:// XHR returns status 0, which Spine treats as a load failure.
                let filename = url.lastPathComponent
                if let wpeURL = URL(string: "wpe://localhost/\(filename)") {
                    wv.load(URLRequest(url: wpeURL))
                    return
                }
            }
            // WebM: plain file access is sufficient (no XHR needed to load video)
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            controller.connectWebView(webView)
        }
    }
}

// MARK: - Settings Pane

struct DetailSettingsPane: View {
    let item: WallpaperItem
    @ObservedObject var viewModel: WallpaperViewModel
    let mediaKind: DetailMediaKind
    @ObservedObject var controller: DetailMediaController

    // Only webm needs custom playback controls; mp4 gets native AVPlayerView controls
    private var showWebControls: Bool { mediaKind == .videoWebM }
    // Show volume slider for webm and html (mp4 volume is in AVPlayerView)
    private var showVolume: Bool { mediaKind == .videoWebM || mediaKind == .html }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Back button ──
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { viewModel.closeDetail() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text("返回列表").font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.brandPurple)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            .keyboardShortcut(.escape, modifiers: [])

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Title & badges ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title.isEmpty ? "无标题" : item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        HStack(spacing: 5) {
                            switch mediaKind {
                            case .videoMP4, .videoWebM:
                                kindBadge("动态", color: Color(hex: "#7C6BF5"))
                            case .html:
                                kindBadge("网页", color: Color(hex: "#3792EF"))
                            case .image:
                                kindBadge("静态", color: Color.secondary.opacity(0.45))
                            }
                            if !item.resolution.isEmpty && item.resolution != "其他" {
                                kindBadge(item.resolution, color: Color.secondary.opacity(0.3))
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)

                    // ── Wallpaper settings ──
                    sectionLabel("壁纸设置")

                    settingRow("适配方式") {
                        Picker("", selection: $viewModel.wallpaperFit) {
                            ForEach(WallpaperFit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 90)
                    }

                    settingRow("目标显示器") {
                        Picker("", selection: $viewModel.targetScreenName) {
                            ForEach(viewModel.availableScreenNames, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 110)
                    }

                    // ── Playlist & Collection ──
                    sectionDivider()
                    sectionLabel("列表与合集")

                    settingRow("加入轮播") {
                        Toggle("", isOn: Binding(
                            get: { viewModel.playlistIds.contains(item.id) },
                            set: { _ in viewModel.toggleInPlaylist(item: item) }
                        ))
                        .labelsHidden()
                        .toggleStyle(BrandSwitchStyle())
                    }

                    Divider().padding(.leading, 20)

                    settingRow("加入合集") {
                        Button(action: {
                            if viewModel.isLoggedIn { viewModel.addToCollectionTargetItem = item }
                            else { viewModel.showLoginSheet = true }
                        }) {
                            Text(viewModel.isItemInAnyCollection(item) ? "已加入" : "+ 添加")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(
                                    viewModel.isItemInAnyCollection(item) ? .secondary : Color.brandPurple
                                )
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(
                                    viewModel.isItemInAnyCollection(item)
                                        ? Color.secondary.opacity(0.1)
                                        : Color.brandPurple.opacity(0.1)
                                )
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }

                    // ── Audio ──
                    if showVolume {
                        sectionDivider()
                        sectionLabel("音频")

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("音量").font(.system(size: 13)).foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(controller.volume * 100))%")
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            Slider(
                                value: Binding(get: { controller.volume },
                                               set: { controller.setVolume($0) }),
                                in: 0...1
                            ).tint(Color.brandPurple)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                    }

                    // ── Playback controls (WebM only) ──
                    if showWebControls {
                        sectionDivider()
                        sectionLabel("播放控制")

                        // Play/pause + speed
                        HStack(spacing: 10) {
                            Button(action: { controller.togglePlay() }) {
                                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.brandPurple)
                                    .clipShape(Circle())
                            }.buttonStyle(.plain)

                            Spacer()

                            HStack(spacing: 4) {
                                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { r in
                                    Button(action: { controller.setRate(r) }) {
                                        Text(r == 1.0 ? "1×" : String(format: "%.1g×", r))
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(controller.playbackRate == r ? .white : .primary.opacity(0.55))
                                            .padding(.horizontal, 7).padding(.vertical, 4)
                                            .background(
                                                controller.playbackRate == r
                                                    ? AnyShapeStyle(Color.brandPurple)
                                                    : AnyShapeStyle(Color.primary.opacity(0.08))
                                            )
                                            .clipShape(Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 8)

                        // Progress + time
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { controller.duration > 1 ? controller.currentTime / controller.duration : 0 },
                                    set: { controller.seek(to: $0 * controller.duration) }
                                ),
                                in: 0...1
                            ).tint(Color.brandPurple)

                            HStack {
                                Text(formatTime(controller.currentTime))
                                Spacer()
                                Text(formatTime(controller.duration))
                            }
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 10)
                    }

                    sectionDivider()

                    // ── Apply button ──
                    Button(action: {
                        // Set volume BEFORE setWallpaper so makeWebView reads the correct
                        // webVolume (via initVolScript injection) when creating the new WKWebView.
                        // Also mutes the currently-playing desktop wallpaper immediately via didSet.
                        let vol = controller.volume
                        switch mediaKind {
                        case .videoWebM, .videoMP4:
                            DesktopVideoManager.shared.videoVolume = Float(vol)
                        case .html:
                            DesktopWebManager.shared.webVolume = vol
                        case .image:
                            break
                        }
                        viewModel.setWallpaper(item: item)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: mediaKind == .image ? "photo.fill" : "play.rectangle.fill")
                                .font(.system(size: 13))
                            Text(mediaKind == .image ? "设为壁纸" : "设为动态壁纸")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(LinearGradient.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Color.brandPurple.opacity(0.4), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20).padding(.bottom, 4).padding(.top, 2)
    }

    @ViewBuilder
    private func sectionDivider() -> some View {
        Divider().padding(.vertical, 10).padding(.horizontal, 20)
    }

    @ViewBuilder
    private func settingRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(.primary)
            Spacer()
            content()
        }
        .padding(.horizontal, 20).padding(.vertical, 7)
    }

    @ViewBuilder
    private func kindBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func formatTime(_ s: Double) -> String {
        let t = max(0, Int(s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
