//
//  DesktopWebManager.swift
//  SimpleWallpaper
//
//  把 WKWebView 铺满桌面，用于播放 Wallpaper Engine 的网页壁纸。
//  使用自定义 wpe:// scheme 绕过 file:// 跨域限制，使 JS fetch()/XHR 可访问本地资源。
//  必须返回 HTTPURLResponse(statusCode:200) 而非 URLResponse，否则 xhr.status = 0，
//  导致 Spine 等运行时误判为请求失败。

import AppKit
import WebKit

private let wpeScheme = "wpe"

// 拦截 wpe:// 请求，将其映射到本地目录下的同名文件（供桌面壁纸和预览 WKWebView 共用）
final class WallpaperFileSchemeHandler: NSObject, WKURLSchemeHandler {
    private let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        // wpe://localhost/relative/path -> rootDirectory/relative/path
        let relativePath = String(requestURL.path.drop(while: { $0 == "/" }))
        let fileURL = rootDirectory.appendingPathComponent(relativePath)

        // 防止路径穿越（如 wpe://localhost/../../etc/passwd）
        guard fileURL.standardized.path.hasPrefix(rootDirectory.standardized.path) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        // 解析 Range 请求头，支持视频 seek（HTTP 206 Partial Content）。
        // 没有 Accept-Ranges / 206 支持时，视频结束后重置 currentTime = 0 会失败，
        // play() 无法重新读取数据，导致 crossfade 类壁纸第一轮后变静态。
        let totalSize = data.count
        var responseData: Data = data
        var statusCode = 200
        var contentRangeHeader: String? = nil

        if let rangeHeader = urlSchemeTask.request.value(forHTTPHeaderField: "Range"),
           rangeHeader.hasPrefix("bytes=") {
            let rangeStr = String(rangeHeader.dropFirst(6))
            let parts = rangeStr.split(separator: "-", maxSplits: 1)
            if let startVal = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                let endVal: Int
                if parts.count > 1, let parsed = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    endVal = min(parsed, totalSize - 1)
                } else {
                    endVal = totalSize - 1
                }
                let lo = max(0, startVal)
                let hi = min(endVal, totalSize - 1)
                if lo <= hi {
                    responseData = data.subdata(in: lo..<(hi + 1))
                    statusCode = 206
                    contentRangeHeader = "bytes \(lo)-\(hi)/\(totalSize)"
                }
            }
        }

        var headers: [String: String] = [
            "Content-Type": mimeType(for: fileURL.pathExtension),
            "Content-Length": "\(responseData.count)",
            "Access-Control-Allow-Origin": "*",
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=3600"
        ]
        if let cr = contentRangeHeader { headers["Content-Range"] = cr }

        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            urlSchemeTask.didFailWithError(URLError(.unknown))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(responseData)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html":        return "text/html"
        case "js":          return "application/javascript"
        case "css":         return "text/css"
        case "json":        return "application/json"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "mp3":         return "audio/mpeg"
        case "ogg":         return "audio/ogg"
        case "wav":         return "audio/wav"
        case "mp4":         return "video/mp4"
        case "webm":        return "video/webm"
        case "atlas":       return "text/plain"
        default:            return "application/octet-stream"
        }
    }
}

class DesktopWebManager: NSObject, WKNavigationDelegate {
    static let shared = DesktopWebManager()

    private var windows: [NSWindow] = []
    private var currentURL: URL?
    private var currentAllowedDir: URL?
    private var currentScreenName: String = "全部"
    private weak var snapshotSourceWebView: WKWebView?
    private var currentSnapshotURL: URL?

    /// 网页壁纸音量 (0.0–1.0)，持久化到 UserDefaults。
    /// 默认 1.0（全音量）。设置后立即应用到所有运行中的 WKWebView，
    /// 并在 didFinish 时应用到新加载的页面（含 Web Audio API GainNode）。
    var webVolume: Double = {
        guard UserDefaults.standard.object(forKey: "webVolume") != nil else { return 1.0 }
        return UserDefaults.standard.double(forKey: "webVolume")
    }() {
        didSet {
            UserDefaults.standard.set(webVolume, forKey: "webVolume")
            let js = Self.volumeJS(webVolume)
            for window in windows {
                (window.contentView as? WKWebView)?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    /// JS snippet that applies volume via Web Audio API GainNode (if available) AND <video>/<audio>.
    static func volumeJS(_ vol: Double) -> String {
        "if(typeof window.__setWpVol==='function'){window.__setWpVol(\(vol));}else{" +
        "document.querySelectorAll('video,audio').forEach(function(e){e.volume=\(vol);});}"
    }

    /// WKUserScript injected at document start: controls Web Audio API volume via a master
    /// GainNode inserted into every AudioContext's audio graph.
    ///
    /// Design constraints:
    ///  • window.__setWpVol MUST be defined unconditionally — even if prototype patching throws
    ///    (non-configurable 'destination' in some WebKit builds), volumeJS() must have something
    ///    to call or audio stays at full volume forever.
    ///  • Prototype-level lazy override is tried first; falls back to constructor wrapping.
    ///  • MutationObserver enforces volume on dynamically created <audio>/<video> elements.
    static let audioMasterVolumeScript = WKUserScript(source: """
        (function(){
            var _gains=[];
            var _mediaEls=[];

            // ── 1. __setWpVol: always first, no matter what else throws ──────────────────────
            window.__setWpVol=function(v){
                window.__wpVol=v;
                for(var i=0;i<_gains.length;i++){try{if(_gains[i]&&_gains[i].gain)_gains[i].gain.value=v;}catch(e){}}
                for(var i=0;i<_mediaEls.length;i++){try{_mediaEls[i].volume=v;}catch(e){}}
                try{document.querySelectorAll('video,audio').forEach(function(el){try{el.volume=v;}catch(e){}});}catch(e){}
            };

            // ── 2. setInterval: continuously enforce volume every 200 ms ─────────────────────
            // Catches audio that initialises or resets volume after didFinish fires.
            // Only active when __wpVol < 1 (i.e. user asked for mute/quiet).
            setInterval(function(){
                var v=window.__wpVol;
                if(typeof v==='undefined'||v>=1)return;
                for(var i=0;i<_gains.length;i++){try{if(_gains[i]&&_gains[i].gain)_gains[i].gain.value=v;}catch(e){}}
                try{document.querySelectorAll('video,audio').forEach(function(el){try{if(el.volume!==v)el.volume=v;}catch(e){}});}catch(e){}
            },200);

            // ── 3. Track <audio>/<video> created by any mechanism ────────────────────────────
            function _trackMedia(el){
                if(!el||el.__wpT)return;el.__wpT=true;
                var v=typeof window.__wpVol!=='undefined'?window.__wpVol:1;
                try{el.volume=v;}catch(e){}
                _mediaEls.push(el);
            }
            // new Audio(src) — often never appended to DOM, so querySelectorAll misses it
            try{
                var _OA=window.Audio;
                if(_OA){
                    window.Audio=function(s){
                        var e=arguments.length>0?new _OA(s):new _OA();
                        _trackMedia(e);return e;
                    };
                    try{window.Audio.prototype=_OA.prototype;}catch(e){}
                }
            }catch(e){}
            // document.createElement('audio') — also never appended in some wallpapers
            try{
                var _OCE=Document.prototype.createElement;
                Document.prototype.createElement=function(t){
                    var el=_OCE.apply(this,arguments);
                    if(t){var tl=t.toLowerCase();if(tl==='audio'||tl==='video')_trackMedia(el);}
                    return el;
                };
            }catch(e){}
            // MutationObserver — elements added to DOM
            try{
                new MutationObserver(function(ms){
                    if(typeof window.__wpVol==='undefined'||window.__wpVol>=1)return;
                    ms.forEach(function(m){m.addedNodes.forEach(function(n){
                        try{if(n.tagName==='AUDIO'||n.tagName==='VIDEO')_trackMedia(n);}catch(e){}
                        try{if(n.querySelectorAll)n.querySelectorAll('audio,video').forEach(_trackMedia);}catch(e){}
                    });});
                }).observe(document,{childList:true,subtree:true});
            }catch(e){}

            // ── 4. Web Audio API: intercept AudioContext.destination ─────────────────────────
            var AC=window.AudioContext||window.webkitAudioContext;
            if(!AC)return;
            var _proto=null,_origDest=null;
            for(var p=AC.prototype;p;p=Object.getPrototypeOf(p)){
                var d=Object.getOwnPropertyDescriptor(p,'destination');
                if(d){_proto=p;_origDest=d;break;}
            }
            if(!_proto||!_origDest)return;

            function _patchCtx(ctx){
                if(ctx.__wpCtxP)return;ctx.__wpCtxP=true;
                try{
                    var realFn=_origDest.get||function(){return _origDest.value;};
                    var real=realFn.call(ctx);
                    var g=ctx.createGain();
                    g.gain.value=typeof window.__wpVol!=='undefined'?window.__wpVol:1;
                    g.connect(real);
                    _gains.push(g);
                    Object.defineProperty(ctx,'destination',{get:function(){return g;},configurable:true});
                }catch(e){}
            }

            // Method A: prototype-level lazy override
            try{
                Object.defineProperty(_proto,'destination',{
                    get:function(){
                        _patchCtx(this);
                        var own=Object.getOwnPropertyDescriptor(this,'destination');
                        return own?own.get.call(this):(_origDest.get?_origDest.get.call(this):_origDest.value);
                    },
                    configurable:true
                });
            }catch(e){}

            // Method B: constructor wrapping — always enabled (redundant with A but adds safety)
            var _Orig=AC;
            var _Wrapped=function(o){
                var c=o!==undefined?new _Orig(o):new _Orig();
                _patchCtx(c);return c;
            };
            try{_Wrapped.prototype=_Orig.prototype;}catch(e){}
            try{Object.setPrototypeOf(_Wrapped,_Orig);}catch(e){}
            if(window.AudioContext)try{window.AudioContext=_Wrapped;}catch(e){}
            if(window.webkitAudioContext)try{window.webkitAudioContext=_Wrapped;}catch(e){}
        })();
    """, injectionTime: .atDocumentStart, forMainFrameOnly: true)

    // MARK: - Init

    override init() {
        super.init()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleScreenWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenWake),
                       name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        // 屏幕/系统休眠时卸载 WebGL 内容，释放帧缓冲和纹理内存（~500MB+）
        nc.addObserver(self, selector: #selector(handleScreenSleep),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleScreenSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - 屏幕唤醒 / 休眠处理

    @objc private func handleScreenSleep() {
        guard !windows.isEmpty else { return }
        // 加载空白页：销毁 JS 引擎、WebGL context、全部纹理，让 WebContent 进程内存回落到约 50MB
        for window in windows {
            (window.contentView as? WKWebView)?.loadHTMLString("", baseURL: nil)
        }
    }

    @objc private func handleScreenWake() {
        guard !windows.isEmpty,
              let url = currentURL,
              let allowedDir = currentAllowedDir,
              let wpeURL = makeWpeURL(for: url, relativeTo: allowedDir) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            for window in self.windows {
                window.orderFront(nil)
                (window.contentView as? WKWebView)?.load(URLRequest(url: wpeURL))
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Always apply volume (including 0 = mute) after every page load.
        // Covers both Web Audio API (via __setWpVol) and <video>/<audio> elements.
        webView.evaluateJavaScript(DesktopWebManager.volumeJS(webVolume), completionHandler: nil)
        guard webView === snapshotSourceWebView, isActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak webView] in
            guard let self = self, self.isActive, let wv = webView else { return }
            let cfg = WKSnapshotConfiguration()
            cfg.rect = wv.bounds
            wv.takeSnapshot(with: cfg) { [weak self] image, _ in
                guard let self = self, let image = image else { return }
                self.applySnapshotAsSystemWallpaper(image)
            }
        }
    }

    // MARK: - Public API

    /// 在目标屏幕上显示网页壁纸（HTML 文件 URL）。
    func showWebWallpaper(url: URL, screenName: String = "全部") {
        clearWebWallpaper()
        currentURL = url
        let allowedDir = url.deletingLastPathComponent()
        currentAllowedDir = allowedDir
        currentScreenName = screenName

        guard let wpeURL = makeWpeURL(for: url, relativeTo: allowedDir) else { return }

        let targetScreens: [NSScreen]
        if screenName == "全部" {
            targetScreens = NSScreen.screens
        } else {
            let filtered = NSScreen.screens.filter { $0.localizedName == screenName }
            targetScreens = filtered.isEmpty ? NSScreen.screens : filtered
        }

        for (index, screen) in targetScreens.enumerated() {
            let window = makeWindow(frame: screen.frame)
            let webView = makeWebView(frame: screen.frame, rootDirectory: allowedDir)
            webView.navigationDelegate = self   // all screens: apply volume in didFinish
            if index == 0 { snapshotSourceWebView = webView }
            window.contentView = webView
            window.orderFront(nil)
            webView.load(URLRequest(url: wpeURL))
            windows.append(window)
        }
    }

    /// 清除所有网页壁纸窗口。
    func clearWebWallpaper() {
        currentURL = nil
        currentAllowedDir = nil
        snapshotSourceWebView = nil
        for window in windows {
            (window.contentView as? WKWebView)?.stopLoading()
            window.contentView = nil   // 断开强引用，让 WKWebView（含 JS 引擎和 WebGL context）立即释放
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    var isActive: Bool { !windows.isEmpty }

    // MARK: - 锁屏同步

    private func applySnapshotAsSystemWallpaper(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }

        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        // Use a unique filename each time — macOS caches the wallpaper by URL,
        // so reusing the same path causes the old image to persist after switching wallpapers.
        let newURL = cacheDir.appendingPathComponent("webwallpaper_\(UUID().uuidString).jpg")
        guard (try? jpeg.write(to: newURL)) != nil else { return }

        let oldURL = currentSnapshotURL
        currentSnapshotURL = newURL

        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(newURL, for: screen, options: [:])
        }

        if let old = oldURL {
            try? FileManager.default.removeItem(at: old)
        }
    }

    // MARK: - Private helpers

    private func makeWpeURL(for fileURL: URL, relativeTo rootDir: URL) -> URL? {
        let rootPath = rootDir.standardized.path
        let filePath = fileURL.standardized.path
        guard filePath.hasPrefix(rootPath) else { return nil }
        let relative = String(filePath.dropFirst(rootPath.count))
        var comps = URLComponents()
        comps.scheme = wpeScheme
        comps.host = "localhost"
        comps.path = relative.hasPrefix("/") ? relative : "/\(relative)"
        return comps.url
    }

    private func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // desktopIconWindow 层级：在系统壁纸之上、所有 App 窗口之下，WebGL 合成正常
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.backgroundColor = .black
        window.isOpaque = true
        window.isRestorable = false
        return window
    }

    private func makeWebView(frame: NSRect, rootDirectory: URL) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(WallpaperFileSchemeHandler(rootDirectory: rootDirectory),
                                   forURLScheme: wpeScheme)
        // 桌面模式渲染，确保 requestAnimationFrame 以全速运行
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // 允许视频在 JS 中以 video.play() 重新启动，而无需用户手势。
        // 不设此项时，已结束的视频调用 play() 会被 WKWebView 静默阻止，
        // 导致依赖手动循环（crossfade）的壁纸动画在第一轮后停止。
        config.mediaTypesRequiringUserActionForPlayback = []

        // 强制 devicePixelRatio = 1，阻止 WebGL 壁纸创建 Retina 分辨率画布。
        // 对于使用 `canvas.width = innerWidth * devicePixelRatio` 的壁纸，
        // 帧缓冲面积缩小 4 倍（2x Retina），显存和内存均显著降低。
        // 壁纸作为背景图案，1x 精度肉眼不可分辨。
        let dprScript = WKUserScript(
            source: "Object.defineProperty(window,'devicePixelRatio',{get:function(){return 1;},configurable:true});",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(dprScript)
        // Set __wpVol BEFORE audioMasterVolumeScript so the lazy destination getter picks up the
        // correct initial volume when the wallpaper first creates an AudioContext.
        let initVolScript = WKUserScript(
            source: "window.__wpVol=\(webVolume);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(initVolScript)
        config.userContentController.addUserScript(DesktopWebManager.audioMasterVolumeScript)

        // 注入 cover-fit 脚本：轮询等待 canvas 创建完成，然后用 transform scale
        // 把固定像素尺寸的 canvas 缩放到铺满整个视口（类似 background-size: cover）。
        // 若 canvas 的 CSS 渲染尺寸已铺满视口（如 Spine 角色壁纸通过 CSS 100%×100% 自管理），
        // 则跳过变换，避免把 1080×1920 的竖向 canvas 错误放大 2× 覆盖背景图片。
        let coverScript = WKUserScript(source: """
            (function() {
                var attempts = 0;
                function coverFit() {
                    var canvas = document.querySelector('canvas');
                    if (!canvas || canvas.width < 2 || canvas.height < 2) {
                        if (++attempts < 40) { setTimeout(coverFit, 250); }
                        return;
                    }
                    var sw = window.innerWidth, sh = window.innerHeight;
                    // 用 CSS 渲染尺寸（getBoundingClientRect）而非 WebGL 帧缓冲尺寸判断。
                    // 若 canvas 已通过 CSS（如 width:100%;height:100%）铺满视口，
                    // 壁纸自行管理布局，无需额外变换。
                    var rect = canvas.getBoundingClientRect();
                    if (rect.width >= sw * 0.9 && rect.height >= sh * 0.9) {
                        document.documentElement.style.overflow = 'hidden';
                        document.body.style.overflow = 'hidden';
                        return;
                    }
                    var scale = Math.max(sw / canvas.width, sh / canvas.height);
                    canvas.style.setProperty('position', 'fixed', 'important');
                    canvas.style.setProperty('top',    '50%', 'important');
                    canvas.style.setProperty('left',   '50%', 'important');
                    canvas.style.setProperty('width',  canvas.width  + 'px', 'important');
                    canvas.style.setProperty('height', canvas.height + 'px', 'important');
                    canvas.style.setProperty('transform',
                        'translate(-50%,-50%) scale(' + scale + ')', 'important');
                    canvas.style.setProperty('transform-origin', 'center center', 'important');
                    canvas.style.setProperty('margin', '0', 'important');
                    document.documentElement.style.overflow = 'hidden';
                    document.body.style.overflow = 'hidden';
                    // 用 backgroundColor（而非 background shorthand）设置兜底底色，
                    // 避免清除壁纸通过 JS/CSS 设置的 backgroundImage。
                    document.body.style.backgroundColor = '#000';
                }
                setTimeout(coverFit, 200);
            })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(coverScript)

        // 模拟 Wallpaper Engine 在启动时调用 applyUserProperties({})。
        // 许多 WE 壁纸（如 Spine 角色壁纸）仅在此回调中初始化背景图片、颜色等属性；
        // 不调用则背景保持 CSS 默认值（通常为黑色或引用不存在的文件）。
        let weInitScript = WKUserScript(source: """
            (function() {
                function tryApplyProperties() {
                    if (window.wallpaperPropertyListener &&
                        typeof window.wallpaperPropertyListener.applyUserProperties === 'function') {
                        window.wallpaperPropertyListener.applyUserProperties({});
                    }
                }
                // 立即尝试一次（若脚本已同步执行完毕）
                setTimeout(tryApplyProperties, 0);
                // 再延迟执行，给异步加载的脚本留出初始化时间
                setTimeout(tryApplyProperties, 500);
                setTimeout(tryApplyProperties, 1500);
            })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(weInitScript)

        // WKWebView 对已结束（ended）视频的 play() 调用会静默失败，
        // 导致依赖手动 crossfade 循环的壁纸在第一轮后变为静态。
        //
        // 根本解法：在页面脚本的 window.load 回调（init）执行前，
        // 将所有 video 元素的 loop 属性设为 true，令视频永不进入 ended 状态。
        // 视频到达末尾时自动衔接到开头（loop 行为由浏览器原生保证，无 ended 触发），
        // 此后对这些视频调用的任何 play() 都在"已播放"状态下执行，必然成功。
        //
        // 时机保证：atDocumentEnd 在 HTML 解析完成后、window.load 前注入，
        // 先于 init() 对视频调用 load()/play()；
        // loop 属性不受 load() 重置，在整个页面生命周期中持续有效。
        let videoLoopScript = WKUserScript(source: """
            (function() {
                function setLoop(v) {
                    if (v._wpeLoop) return;
                    v._wpeLoop = true;
                    v.loop = true;
                }
                document.querySelectorAll('video').forEach(setLoop);
                new MutationObserver(function(mutations) {
                    mutations.forEach(function(m) {
                        m.addedNodes.forEach(function(n) {
                            if (n.nodeName === 'VIDEO') setLoop(n);
                            if (n.querySelectorAll) n.querySelectorAll('video').forEach(setLoop);
                        });
                    });
                }).observe(document.documentElement, { childList: true, subtree: true });
            })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(videoLoopScript)

        let webView = WKWebView(frame: frame, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        return webView
    }
}
