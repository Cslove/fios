import SwiftUI
import Networking   // 模块十四第 4 节的本地包：APIClient / ApiError / HttpMethod 都在这

// 本文件是 11.网络请求与数据流.md 的完整可跑 demo，六个 Section 对应文档六节：
// ① URLSession 基础（原始 data + 状态码不抛错的坑）  ② URLRequest 定制 POST + URLComponents 拼参
// ③ 泛型封装（Networking 包里的 APIClient）          ④ 错误分支实测（404 / 解码失败 / 域名错误）
// ⑤ 调试手法（原始 JSON 打印）                        ⑥ 完整列表页（.task 加载 + .refreshable 刷新 + 导航详情）
// 分层原则：网络层（APIClient）在 Networking 包，页面只管「调 API → 改 @State → 渲染」

// MARK: - 数据模型（Codable，模块十）

// Identifiable：List 要求 id 做复用标识（模块十二）
struct Todo: Identifiable, Codable {
    let id: Int
    let title: String
    let completed: Bool
    var isLong: Bool { title.count > 40 }     // 计算属性：演示详情页按数据派生 UI
}

// POST 的请求体模型：Encodable 方向（模型 → JSON）
struct NewPost: Encodable {
    let title: String
    let body: String
    let userId: Int
}

// POST 的响应模型：Decodable 方向（JSON → 模型）；JSONPlaceholder 回包带 id
struct CreatedPost: Decodable {
    let id: Int
    let title: String
}

// 故意缺字段的模型：演示 decodingFailed 分支——JSON 里没有 price，解码必失败
struct BrokenTodo: Decodable {
    let id: Int
    let price: Double     // ❌ /todos 接口没这个字段
}

// MARK: - Demo 页

struct NetworkingDemoView: View {
    // APIClient 是 struct（无状态），@State 持有即可；真实项目常用单例或环境注入
    @State private var client = APIClient()
    @State private var todos: [Todo] = []
    @State private var logs: [LogLine] = []
    @State private var rawJSON = "（未请求）"
    @State private var loadingSection6 = false
    @State private var postResult = "（未发请求）"

    // UUID 当 ID：日志文本会重复（两次点同一按钮），id: \.self 会报 occurs multiple times
    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        List {
            section1RawURLSession
            section2URLRequest
            section3GenericClient
            section4ErrorBranches
            section5Debug
            section6FullList
            section7SSE
            logSection
        }
        .navigationTitle("网络请求 Demo")
    }

    // MARK: ① URLSession 基础：async 版 fetch（文档第 1 节）

    // 不走封装、直接 URLSession.shared：看清「原始返回」长什么样——
    // data 是字节，response 里有状态码，但 404/500 不会 throw，必须自己查
    private var section1RawURLSession: some View {
        Section("① URLSession 基础：data 元组 + 状态码不抛错的坑") {
            Text("原始 JSON 预览：\(rawJSON)")
                .font(.footnote.monospaced())
                .lineLimit(4)
            Button("直接请求 /todos/1，看原始 data") {
                Task {
                    do {
                        let url = URL(string: "https://jsonplaceholder.typicode.com/todos/1")!
                        let (data, response) = try await URLSession.shared.data(from: url)
                        // 调试第一招：先肉眼看原始 JSON（模块十一第 4 节）
                        if let text = String(data: data, encoding: .utf8) {
                            rawJSON = String(text.prefix(150))
                            log("① 原始 JSON 前 150 字符已显示")
                        }
                        // ⚠️ 坑的实证：请求一个 404 路径，这行照样打印 200 OK——
                        // URLSession 把 404 的错误页当正常 data 返回，不 throw
                        let http = response as! HTTPURLResponse
                        log("① 状态码 \(http.statusCode)——URLSession 不替你抛 404/500")
                    } catch {
                        log("① 网络层错误：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: ② URLRequest：定制 POST + URLComponents（文档第 2 节）

    private var section2URLRequest: some View {
        Section("② URLRequest：POST 三件套 + 查询参数编码") {
            Text("POST /posts 结果：\(postResult)")
                .font(.footnote)
            Button("POST 新文章（走 Networking 包的 client.post）") {
                Task {
                    do {
                        // 请求体：Encodable 模型 → JSONEncoder → Data（模块十）
                        let created: CreatedPost = try await client.post(
                            "/posts",
                            body: NewPost(title: "fios demo", body: "来自 NetworkingDemoView", userId: 1)
                        )
                        postResult = "✅ 创建成功，服务端返回 id=\(created.id)"
                        log("② POST 成功：id=\(created.id)")
                    } catch let ApiError.httpFailed(code) {
                        postResult = "❌ HTTP \(code)"
                        log("② POST 失败：HTTP \(code)")
                    } catch {
                        postResult = "❌ \(error.localizedDescription)"
                        log("② POST 失败：\(error.localizedDescription)")
                    }
                }
            }
            Button("URLComponents 拼中文参数（看编码后的 URL）") {
                // 查询参数拼装：手动拼字符串中文/空格/& 全是坑，
                // URLComponents 自动百分号编码（Networking 包里的静态工具方法）
                if let url = APIClient.url(base: "https://jsonplaceholder.typicode.com",
                                           path: "/comments",
                                           query: [URLQueryItem(name: "q", value: "swift 中文")]) {
                    log("② 编码后 URL：\(url.absoluteString)")
                } else {
                    log("② URL 构造失败（invalidURL 分支）")
                }
            }
        }
    }

    // MARK: ③ 泛型封装：一个函数通吃所有模型（文档第 3 节）

    private var section3GenericClient: some View {
        Section("③ 泛型封装：client.get 通吃所有模型") {
            Text("同一个 get，传 Todo 得 Todo、传 [Todo] 得数组——泛型由左侧类型注解确定")
                .font(.caption).foregroundStyle(.secondary)
            Button("请求单个 Todo（泛型 T = Todo）") {
                Task {
                    do {
                        let todo: Todo = try await client.get("/todos/5")
                        log("③ 单个：#\(todo.id) \(todo.title)")
                    } catch { log("③ 失败：\(describe(error))") }
                }
            }
            Button("请求用户列表（泛型 T = [Todo]）") {
                Task {
                    do {
                        let list: [Todo] = try await client.get("/todos?_limit=3")
                        log("③ 数组 \(list.count) 条：\(list.map(\.title).joined(separator: " / "))")
                    } catch { log("③ 失败：\(describe(error))") }
                }
            }
        }
    }

    // MARK: ④ 错误分支实测：四类 ApiError 各自命中（文档第 3 节 + 亲测清单）

    private var section4ErrorBranches: some View {
        Section("④ 错误分支实测：一个 do-catch 收编所有失败") {
            Button("触发 httpFailed(404)（URLSession 不会替你抛）") {
                Task {
                    do {
                        // /xxx 不存在 → JSONPlaceholder 返回 404 页面
                        // 封装层查状态码收编成 httpFailed——体会「不封装这层就静默拿到错误页」
                        let _: [Todo] = try await client.get("/xxx")
                        log("④ 意外成功？不该走到这")
                    } catch { log("④ 命中：\(describe(error))") }
                }
            }
            Button("触发 decodingFailed（模型字段对不上）") {
                Task {
                    do {
                        // BrokenTodo 要 price 字段，接口没有 → 解码必失败
                        let _: [BrokenTodo] = try await client.get("/todos?_limit=1")
                        log("④ 意外成功？不该走到这")
                    } catch { log("④ 命中：\(describe(error))") }
                }
            }
            Button("触发网络错误（不存在的域名）") {
                Task {
                    do {
                        // 换 baseURL 到不存在的域名：走 URLSession 原生网络错误（非 ApiError）
                        let bad = APIClient(baseURL: "https://nonexistent.example.invalid")
                        let _: [Todo] = try await bad.get("/todos")
                        log("④ 意外成功？不该走到这")
                    } catch { log("④ 命中：\(describe(error))") }
                }
            }
        }
    }

    // MARK: ⑤ 调试手法（文档第 4 节）

    private var section5Debug: some View {
        Section("⑤ 调试手法速查") {
            Text("""
            ① 打印原始 JSON：String(data:encoding:)——先看后端给了什么再查解析
            ② Xcode 异常断点：断点面板 + → Swift Error Breakpoint，throw 瞬间断住
            ③ 抓包：Charles / Proxyman（模拟器走系统代理，装证书即抓）
            ④ ATS：iOS 默认只允许 https，http 明文被系统拦（Info.plist 配例外）
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: ⑥ 完整列表页：.task + .refreshable + 导航（文档第 6 节）

    private var section6FullList: some View {
        Section("⑥ 完整页：加载 / 下拉刷新 / 导航详情") {
            if todos.isEmpty {
                HStack {
                    Text(loadingSection6 ? "加载中…" : "点按钮加载 200 条待办")
                    if loadingSection6 { Spacer(); ProgressView() }
                }
            } else {
                // 导航去详情页（模块十二 NavigationLink）
                NavigationLink {
                    TodoDetailView(todo: todos[0])
                } label: {
                    Text("查看第一条详情：\(todos[0].title)")
                        .lineLimit(1)
                }
                Text("已加载 \(todos.count) 条（下拉本 Section 可整页刷新）")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("加载全部待办") { Task { await loadAll() } }
        }
    }

    private func loadAll() async {
        loadingSection6 = true
        defer { loadingSection6 = false }        // defer：无论成功失败都收尾（模块八）
        do {
            todos = try await client.get("/todos")   // 200 条
            log("⑥ 加载成功：\(todos.count) 条")
        } catch let ApiError.httpFailed(code) {
            log("⑥ HTTP 错误 \(code)")
        } catch {
            log("⑥ 其他错误：\(error.localizedDescription)")
        }
    }

    // MARK: ⑦ SSE 流式输出（AI 打字机效果；SSEClient 在 Networking 包）

    // 真实 AI 接口要 key，Demo 用本地 Mock 服务：一秒推一个词，模拟服务端持续发 event
    @State private var sseText = "（未开始）"
    @State private var sseRunning = false
    @State private var sseTask: Task<Void, Never>?

    private var section7SSE: some View {
        Section("⑦ SSE 流式输出：AI 打字机效果") {
            Text("模型输出：\(sseText)")
                .font(.body.monospaced())
                .lineLimit(3)
            if sseRunning {
                HStack { Text("生成中…"); Spacer(); ProgressView() }
            }
            Button(sseRunning ? "停止生成" : "开始生成（Mock SSE 流）") {
                if sseRunning {
                    sseTask?.cancel()          // 手动停：模拟用户点「停止生成」按钮
                    log("⑦ 已手动停止——SSEClient 的 onTermination 会断开底层连接")
                } else {
                    startSSE()
                }
            }
            Text("消费侧就是 for await：每来一个 chunk 追加到 @State，UI 自动刷新")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func startSSE() {
        sseText = ""
        sseRunning = true
        // Task 存起来供「停止生成」取消；整段逻辑 = 真实 AI 接口调用，只换 MockSSEServer.url
        sseTask = Task {
            defer { sseRunning = false }       // 无论正常结束/取消/失败都收尾
            let sse = SSEClient(session: MockSSEServer.session)   // Mock 拦截 session：换 .shared 即真实接口
            // MockSSEServer：本地 SSE 服务（URLProtocol 拦截，无需真后端）
            let request = URLRequest(url: MockSSEServer.url)
            for await event in sse.stream(request: request) {
                switch event {
                case .chunk(let token):
                    sseText += token            // 打字机核心：增量拼接，每 chunk 刷一次 UI
                case .done:
                    log("⑦ 流结束 [DONE]，共 \(sseText.count) 字")
                case .failed(let error):
                    log("⑦ 流失败：\(error.localizedDescription)")
                }
            }
            // 真实接口（OpenAI 兼容）写法：
            // let req = try SSEClient.jsonPOST(url: URL(string: "https://api.deepseek.com/chat/completions")!,
            //                                 body: ChatRequest(model: "deepseek-chat",
            //                                                   messages: [.init(role: "user", content: "讲个笑话")],
            //                                                   stream: true))
            // for await event in sse.stream(request: req) { …同上… }
        }
    }

    // MARK: 工具

    // 错误描述统一出口：四类 ApiError + URLSession 原生错误各说人话
    private func describe(_ error: Error) -> String {
        switch error {
        case ApiError.invalidURL:     return "invalidURL：URL 构造失败"
        case ApiError.invalidResponse: return "invalidResponse：响应不是 HTTPURLResponse"
        case ApiError.httpFailed(let code): return "httpFailed(\(code))：状态码非 2xx"
        case ApiError.decodingFailed: return "decodingFailed：JSON 解不进模型"
        default:                      return "网络层错误：\(error.localizedDescription)"
        }
    }

    private func log(_ line: String) {
        logs.insert(LogLine(text: line), at: 0)
        if logs.count > 15 { logs.removeLast(logs.count - 15) }
    }

    private var logSection: some View {
        Section("事件日志") {
            ForEach(logs) { line in
                Text(line.text).font(.footnote.monospaced())
            }
        }
    }
}

// MARK: - 详情页（模块十二：目标页接收单个模型渲染）

struct TodoDetailView: View {
    let todo: Todo

    var body: some View {
        List {
            LabeledContent("ID", value: "\(todo.id)")
            LabeledContent("状态", value: todo.completed ? "已完成" : "进行中")
            LabeledContent("标题长度", value: "\(todo.title.count) 字符（\(todo.isLong ? "长" : "短")）")
            Section("标题全文") {
                Text(todo.title)
            }
        }
        .navigationTitle("待办 #\(todo.id)")
    }
}

// MARK: - Mock SSE 服务（URLProtocol 拦截，无需真后端/真 key）

// 原理：URLProtocol 是 URLSession 的底层拦截点（模块十一第 4 节提过的日志/Mock 手法）——
// 拦下指定 URL 的请求，不上网，直接喂本地造的 SSE 字节流。拦截器只装进专用 session，
// 不碰全局 URLSession.shared，别处请求零影响。
enum MockSSEServer {
    // 专用 session：APIClient 没动，只服务本 Demo 的 SSE 请求
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [MockSSEProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }()

    // 用假域名标记「这条请求归 Mock 管」；首帧小词、后期长句，模拟真实 AI 越写越长的节奏
    static let url = URL(string: "https://mock.ai.local/chat/completions")!

    static let reply: [String] = [
        "你好",
        "，我是",
        "一个",
        "本地 Mock 的",
        "流式输出",
        "演示：",
        "SSE 每", "秒", "推", "一", "个",
        "增量 token，",
        "客户端用",
        "AsyncStream",
        "逐个消费，",
        "拼出打字机效果。",
    ]
}

final class MockSSEProtocol: URLProtocol {
    // canInit：所有请求先过这里，返回 true = 这条请求归我接管
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "mock.ai.local"      // 只拦假域名，其他请求照常走网络
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Task {
            // 模拟响应头（SSE 响应的 Content-Type 是 text/event-stream）
            let response = HTTPURLResponse(url: MockSSEServer.url,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            for word in MockSSEServer.reply {
                // 逐条喂事件：data: 一行 + 空行 = 一条完整 SSE 事件（协议边界）
                let event = "data: \(word)\n\n"
                client?.urlProtocol(self, didLoad: event.data(using: .utf8)!)
                try? await Task.sleep(for: .seconds(0.5))   // 模拟生成耗时
            }
            client?.urlProtocol(self, didLoad: "data: [DONE]\n\n".data(using: .utf8)!)   // 结束标记
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}    // 被取消时无需清理（Mock 无真实连接）
}

// 让 Mock session 和 SSEClient 串起来：消费侧 startSSE() 里换成这个即可（已内联）
// let sse = SSEClient(session: MockSSEServer.session)
