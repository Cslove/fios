import SwiftUI
import WebKit

// MARK: - 共享：事件日志（把 WebView 生命周期全程可视化——学习期的「仪表盘」）

@Observable
final class WebEventLog {
    var events: [String] = []
    func log(_ text: String) { events.insert("\(Date.now.formatted(.dateTime.hour().minute().second()))  \(text)", at: 0) }
}

struct LogPanel: View {
    let title: String
    let log: WebEventLog
    var body: some View {
        Section(title) {
            if log.events.isEmpty {
                Text("（暂无事件——操作上面/网页里的按钮看日志）").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(log.events.prefix(30), id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        }
    }
}

// MARK: - 共享：WKWebView 桥（s11 第 1 节的完整版）

/// # UIViewRepresentable 桥——SwiftUI 与 UIKit 两个世界的翻译官
///
/// SwiftUI（声明式、值类型）没有 WebView 组件，必须借 UIKit（命令式、引用类型）的 WKWebView 用。
/// 心智模型 ≈ React 挂原生组件：makeCoordinator = 建 ref 存回调载体，makeUIView = mount（一次），
/// updateUIView = 收 props 同步（多次，必须防重入），Coordinator 的 delegate = 事件回流回调。
///
/// 调用顺序：
/// ```
/// makeCoordinator()  →  makeUIView(context:)  →  updateUIView(...)  →  状态变化 → updateUIView(...)
///     造管家               建 UIKit 视图(仅一次)     同步状态(可多次)         反复同步
/// ```
/// context 参数是穿针引线的信封：造的 Coordinator 藏在 context.coordinator 里，两个方法都从这取。
/// 三句纪律：一次性的进 make、会变的进 update、回调用 Coordinator 接。
struct WebViewBridge: UIViewRepresentable {
    enum Load {
        case remote(URL)                       // 远程页面
        case html(String)                     // 本地内嵌 HTML（≈ 离线包的最小形态）
    }
    let load: Load
    let log: WebEventLog
    var webViewBox: WeakWebViewBox? = nil               // 视图层「遥控器」：外面拿它调 evaluateJavaScript
    var onScriptMessage: ((WKScriptMessage) -> Void)? = nil

    /// 造管家（三个钩子里最早调用）。
/// 为什么需要：SwiftUI 视图是 struct，随 body 重算不断「重建」；UIKit 的 delegate 回调需要一个
/// 长期稳定的对象落脚——Coordinator 就是这个稳定锚点，同时存跨周期的东西（log / 业务回调 / weak webView）。
/// 用法：依赖在这里注入 init，Coordinator 就随身携带了。
    func makeCoordinator() -> Coordinator { Coordinator(log: log, onMessage: onScriptMessage) }

    /// 建 UIKit 视图——整个生命周期仅执行一次：无论 SwiftUI 刷新多少次，WKWebView 实例长存
/// （这就是「UIKit 视图不会随 body 重建」的落点）。所有一次性配置放这（通道注册、delegate 绑定）。
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // ① 注册 JS→原生通道：name "bridge" 对应网页里的 messageHandlers.bridge.postMessage(...)，
        //    回调人就是管家（⚠️ add() 会强持有 coordinator——deinit 必须拆环的原因）
        config.userContentController.add(context.coordinator, name: "bridge")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator   // ② 导航事件(didStart/didFinish/didFail)交给管家
        webView.uiDelegate = context.coordinator           // ③ 网页 alert 的呈现交给管家（不设=静默！）
        context.coordinator.webView = webView              // ④ 管家弱持有 webView（deinit 清理注册时要用）
        webViewBox?.webView = webView                      // ⑤ 填充「遥控器」——外面按钮才能调 evaluateJavaScript
        return webView
    }

    /// 同步状态——SwiftUI 状态变了、body 重算时被调（可高频）：UIKit 视图不会自己变，
/// 这个方法把 SwiftUI 世界的变化翻译成 UIKit 世界的方法调用。
/// load 写这不写 make 的原因：make 之后 SwiftUI 会立即调一次 update，首次加载自然发生在这里，
/// 「装载」统一走同步入口。
    func updateUIView(_ webView: WKWebView, context: Context) {
        // ⚠️ 防重入（关键）：父视图任何状态变化都可能触发本方法——不设防直接 load =
        // 界面每刷一次就重新加载网页 = 页面永远在白屏打转。url == nil 只在「还没加载过」时成立。
        guard webView.url == nil else { return }
        switch load {
        case .remote(let url):
            log.log("🚀 load 远程：\(url.absoluteString)")
            webView.load(URLRequest(url: url))
        case .html(let html):
            log.log("📦 load 本地 HTML（离线包雏形：无网络往返）")
            webView.loadHTMLString(html, baseURL: nil)    // 本地字符串即页面——首屏零网络
        }
    }

    /// 管家 = WebView 的「事件监听器对象」：一个装回调的稳定袋子（struct 视图存不住回调）。
    /// 声明遵守三个协议 ≈ implements 三个事件接口；里面每个方法都是协议预定义的事件入口，
    /// 不是我们发明的、我们也从不调用它们——WebKit 在对应时刻按签名回调：
    ///   webView(_:didStart/didFinish/didFail:)      = webView 喊「我开始请求了/加载完了/失败了」
    ///   webView(_:runJavaScriptAlertPanel…)         = webView 喊「网页要弹 alert，你来呈现」
    ///   userContentController(_:didReceive:)        = userContentController 喊「JS 消息到了」
    /// （方法名第一段 = 谁在喊你；签名一字不差才能被回调，写错 = 静默失效——用 Xcode 补全选协议方法）
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let log: WebEventLog
        var onMessage: ((WKScriptMessage) -> Void)?
        weak var webView: WKWebView?                      // weak：防 webView↔coordinator 互相强持有

        init(log: WebEventLog, onMessage: ((WKScriptMessage) -> Void)?) {
            self.log = log; self.onMessage = onMessage
        }
        /// 销毁钩子 = 拆环：makeUIView ①处的 add() 强持有了 coordinator——不移除注册，
        /// webView ↔ coordinator 互相引用谁也释放不了（内存泄漏，s11 坑 3）
        deinit {
            webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        }

        // MARK: 管家工作清单一：导航事件链（白屏排查看这条链断在哪一环）
        // 链路：didStart(发出请求) → didFinish(DOM ready) / didFail(加载失败)
        func webView(_ webView: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
            log.log("① didStart：开始请求（此刻页面还没解析）")
        }
        // didFinish 之后才能安全 evaluateJavaScript——之前调大概率扑空（页面还在解析）
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            log.log("② didFinish：DOM ready——现在才能安全 evaluateJavaScript")
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            log.log("❌ didFail：\(error.localizedDescription)")
        }

        // MARK: 管家工作清单二：JS→原生的收件箱
        // 网页里 window.webkit.messageHandlers.bridge.postMessage(...) 的内容到达这里；
        // message.name = 通道名，message.body = 传来的数据（只能 JSON 基本类型）
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            log.log("📩 JS→原生：\(message.name) = \(message.body)")
            onMessage?(message)
        }

        // MARK: 管家工作清单三：网页 alert 的呈现器
        // WKWebView 默认「丢弃」网页的 alert/confirm——不实现这个方法，网页弹窗彻底无声无息；
        // 实现 = 接管弹窗（这里选择记日志，也可以 present 系统弹窗）；
        // 调 completionHandler() 告诉网页「弹完了」（不调 = 网页 JS 永久卡住）
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            log.log("🔔 网页 alert：\(message)（不实现这个方法就完全不显示）")
            completionHandler()
        }
    }
}

// MARK: - Demo A：远程页面 + 导航事件链

struct RemoteWebDemo: View {
    @State private var urlString = "https://example.com"
    @State private var log = WebEventLog()
    @State private var reloadToken = 0                    // 换 URL 重建桥的开关

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("https://…", text: $urlString)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Go") {
                    guard let url = URL(string: urlString), url.scheme != nil else { log.log("❌ URL 不合法"); return }
                    log.log("—— 切换目标：\(url.absoluteString) ——")
                    reloadToken += 1                       // 变化触发桥重建（绕过防重入 guard）
                }
            }
            .padding(8)
            Divider()
            if let url = URL(string: urlString), url.scheme != nil {
                WebViewBridge(load: .remote(url), log: log).id(reloadToken)
            }
            Divider()
            List { LogPanel(title: "导航事件链（SwiftUI 侧）", log: log) }
                .frame(height: 180)
        }
        .navigationTitle("远程页面 + 事件链")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Demo B：内嵌测试页 + JS 双向通信闭环

/// 网页侧测试页：四个按钮覆盖「JS 调原生」全部姿势；onNativeEvent/computeSum 供原生调用
enum WebDemoPage {
    static let html = """
    <!DOCTYPE html><html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>body{font-family:-apple-system;padding:16px;background:#f5f5f5}
    button{display:block;width:100%;padding:12px;margin:8px 0;font-size:16px;border-radius:8px;border:1px solid #ccc;background:#fff}</style>
    </head><body>
    <h3 id="title">WebView 测试页</h3>
    <p id="status">等待指令…</p>
    <button onclick="send('pay')">postMessage：pay（模拟调起支付）</button>
    <button onclick="send('getUserInfo')">postMessage：getUserInfo（模拟拿登录态）</button>
    <button onclick="throwError()">throw 一个 JS 错误（看 Safari 调试器）</button>
    <button onclick="alert('网页 alert')">window.alert（原生不实现 uiDelegate 就静默）</button>
    <script>
      function send(action) {
        window.webkit.messageHandlers.bridge.postMessage({action: action, ts: Date.now()});
        document.getElementById('status').innerText = '已发送 → ' + action;
      }
      window.onNativeEvent = function(data) {           // 供原生调用的「事件入口」
        document.getElementById('status').innerText = '原生事件：' + JSON.stringify(data);
        return 'JS 已收到: ' + data.type;                // 返回值会被 evaluateJavaScript 的回调拿到
      }
      function computeSum(a, b) { return a + b; }        // 供原生调用拿返回值
      function throwError() { throw new Error('测试错误：请打开 Safari 调试器看 Console'); }
    </script></body></html>
    """
}

struct BridgeWebDemo: View {
    @State private var log = WebEventLog()
    @State private var jsResult = "（JS 返回值会显示在这）"
    @State private var webViewRef = WeakWebViewBox()      // 弱盒子：视图层拿到底层 WKWebView 的引用

    var body: some View {
        VStack(spacing: 0) {
            WebViewBridge(load: .html(WebDemoPage.html), log: log, webViewBox: webViewRef) { message in
                if let dict = message.body as? [String: Any], let action = dict["action"] as? String {
                    log.log("🎯 分发业务：action = \(action)（JSBridge 的 handler 注册表就是干这个）")
                }
            }
            Divider()
            List {
                Section("原生 → JS：evaluateJavaScript（必须等 didFinish——看上面日志到 ② 再点）") {
                    Button("调 window.onNativeEvent（无返回值关注）") {
                        callJS("window.onNativeEvent({type:'loginSuccess', user:'eleme'})")
                    }
                    Button("调 computeSum(3, 4) 拿返回值") { jsResult = "(计算中…)"
                        callJS("computeSum(3, 4)")
                    }
                    Button("调 throwError()——原生侧捕获 JS 异常") {
                        callJS("throwError()")
                    }
                    Text("JS 返回值/错误：\(jsResult)").font(.footnote).foregroundStyle(.secondary)
                }
                LogPanel(title: "事件日志（双向通信全程）", log: log)
            }
        }
        .navigationTitle("双向通信闭环")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func callJS(_ js: String) {
        // 弱盒子里的 webView 由 Coordinator 生命周期持有；这里取不到就说明桥还没建好
        guard let webView = webViewRef.webView else { log.log("⚠️ WebView 未就绪"); return }
        log.log("📤 原生→JS：\(js.prefix(40))…")
        webView.evaluateJavaScript(js) { result, error in       // 回调异步；result = JS 表达式的值
            DispatchQueue.main.async {
                if let error { self.jsResult = "❌ JS 抛错：\(error.localizedDescription)" }
                else if let result { self.jsResult = "✅ 返回 \(result)" }
                else { self.jsResult = "✅ 执行完成（无返回值）" }
            }
        }
    }
}

/// 弱引用盒子：SwiftUI 视图是值类型不能直接持有，Coordinator 塞进来、按钮取出用
final class WeakWebViewBox {
    weak var webView: WKWebView?
}

// MARK: - 入口

struct WebHybridDemoView: View {
    var body: some View {
        List {
            NavigationLink("A. 远程页面 + 导航事件链（didStart→didFinish→didFail）") { RemoteWebDemo() }
            NavigationLink("B. 双向通信闭环（postMessage ⇄ evaluateJavaScript）") { BridgeWebDemo() }
            Section("用 Safari 调试器看网页内部（白屏排查第一现场）") {
                Text("模拟器/真机：Safari → 开发(Develop) 菜单 → 选模拟器设备 → 选 fios 的 WebView 页面——Console/DOM/断点全套可用（真机需在 设置→Safari→高级 开 Web 检查器）")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("WebView Hybrid（s11）")
        .navigationBarTitleDisplayMode(.inline)
    }
}
