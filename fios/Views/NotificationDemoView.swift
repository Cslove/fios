import SwiftUI
import UIKit   // 用到 UIApplication 的系统通知名

// 本文件是 10.日常开发高频实战模式.md 第 6 节（NotificationCenter 一对多广播）的可跑 demo。
// 场景：一次「登录成功」广播，三个互不相识的订阅者各自响应（角标 / VIP 权益 / 收件箱）。
// 心智模型：NotificationCenter ≈ 前端 mitt / EventBus——emit 是 post，订阅是 addObserver，
// event.detail 是 userInfo；区别是订阅者的注销（removeObserver）全靠你自己管生命周期。

// ============ 通知名定义 ============

// MARK: - 通知名定义

extension Notification.Name {
    // 自定义通知名：用扩展挂 static 属性（模块八讲过扩展），字符串只在这出现一次，
    // 调用侧全用 .userDidLogin 自动补全——写错编译不过，比硬编码字符串安全
    static let userDidLogin = Notification.Name("userDidLogin")
}

// ============ 发送方：模拟登录服务 ============

// MARK: - 发送方（LoginService：post 广播）

// 项目默认隔离 = MainActor，这里不标也是主线程；登录要刷 UI，放主线程正合适
final class LoginService {
    static let shared = LoginService()   // 单例（模块十第 2 节）：全局唯一登录入口
    private var nextUserId = 100
    private init() {}                    // private init：堵死外部再 new，配合 static shared 保住单例

    func login() async {
        nextUserId += 1
        try? await Task.sleep(for: .seconds(0.5))    // 模拟网络请求耗时（模块九）
        let isVip = nextUserId % 2 == 0               // 偶数 userId 模拟抽中 VIP
        // post 三件套：
        // name     通知名（这条广播的唯一标识，订阅方按它过滤）
        // object   发送者是谁——订阅方可指定「只收某个对象发的通知」，不关心就 nil
        // userInfo 携带数据 ≈ event.detail；类型是 [AnyHashable: Any]，收方要 as? 拆箱
        // ⚠️ post 本身不返回任何结果，纯单向广播——发送方不知道谁在听、听到没有
        NotificationCenter.default.post(
            name: .userDidLogin,
            object: self,
            userInfo: ["userId": nextUserId, "vip": isVip]
        )
    }
}

// ============ 订阅者 1：角标管理（永久存活，App 级订阅）============

// MARK: - 订阅者 1（BadgeManager：角标，App 级永久订阅）

final class BadgeManager {
    // NSObjectProtocol：addObserver 返回的「观察者令牌」（opaque 类型），
    // 注销 removeObserver 时全凭它——令牌丢了就永远无法注销，等于泄漏
    private var observer: NSObjectProtocol?
    private(set) var badgeCount = 0      // private(set)：外部只读，只有本类内部能改
    var onUpdate: (() -> Void)?          // 状态变化后通知 View 刷新的回调

    init() {
        // addObserver 四件套：
        // forName 监听哪条通知；object 只收某发送者的通知（nil = 谁发都收）
        // queue   回调跑哪个队列：.main = 主线程（闭包里要刷 UI 就必须主线程）
        //         ⚠️ 传 nil 则回调在「发通知的线程」上同步执行——后台 post + nil 队列 = 后台刷 UI 崩溃
        // using   收到通知执行的闭包（逃逸闭包，模块七）；[weak self] 防循环引用（NotificationCenter 会持有闭包）
        observer = NotificationCenter.default.addObserver(
            forName: .userDidLogin, object: nil, queue: .main
        ) { [weak self] note in
            // userInfo 取值拆箱两连：note.userInfo?["userId"] 出来是 Any?，as? Int 才能当数字用（模块八）
            let userId = note.userInfo?["userId"] as? Int ?? 0
            self?.badgeCount += userId
            self?.onUpdate?()
        }
    }

    deinit {
        // deinit：引用计数归零时自动调用（模块七）。观察者必须在这里注销——
        // 不注销的话通知中心还持着闭包、闭包里 self 已是 nil，通知照发但永远无人响应，白耗性能
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            print("🧹 BadgeManager deinit：已注销观察者")
        }
    }
}

// ============ 订阅者 2：VIP 权益页（临时订阅，演示销毁/重建生命周期）============

// MARK: - 订阅者 2（VipManager：VIP 权益，临时订阅，可销毁/重建）

final class VipManager {
    private var observer: NSObjectProtocol?
    private(set) var lastWelcome = "未登录"
    var onUpdate: (() -> Void)?

    init() {
        // object: LoginService.shared——只收登录服务发的通知，别处同名广播一概不理（发送者过滤）
        observer = NotificationCenter.default.addObserver(
            forName: .userDidLogin, object: LoginService.shared, queue: .main
        ) { [weak self] note in
            let userId = note.userInfo?["userId"] as? Int ?? 0
            let vip = note.userInfo?["vip"] as? Bool ?? false
            self?.lastWelcome = vip ? "欢迎回来，VIP 用户 #\(userId)（享 9 折）" : "普通用户 #\(userId)"
            self?.onUpdate?()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            print("🧹 VipManager deinit：已注销观察者——之后再登录，VIP 行不再更新")
        }
    }
}

// ============ 订阅者 3：收件箱（永久存活，演示一次广播多处同时收到）============

// MARK: - 订阅者 3（InboxManager：收件箱，永久存活）

final class InboxManager {
    private var observer: NSObjectProtocol?
    private(set) var unreadCount = 0
    var onUpdate: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .userDidLogin, object: nil, queue: .main
        ) { [weak self] _ in
            self?.unreadCount += 1       // 每次登录推一条新消息
            self?.onUpdate?()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            print("🧹 InboxManager deinit：已注销观察者")
        }
    }
}

// ============ 订阅者 4：系统通知——App 生命周期监听 ============

// MARK: - 订阅者 4（LifecycleMonitor：系统生命周期通知）

final class LifecycleMonitor {
    private var observers: [NSObjectProtocol] = []   // 多条订阅就攒令牌数组，deinit 统一注销
    private(set) var backgroundCount = 0
    // 统一事件回调：带出消息文本，后台/前台两类事件走同一个出口，View 侧好统一记日志
    // （若用无参 onUpdate，两类事件无法区分，只能记同一条文案）
    var onEvent: ((String) -> Void)?

    init() {
        let center = NotificationCenter.default
        // 系统通知：UIApplication 自带一大堆现成通知名，不用自己定义——
        // 进后台 / 回前台 / 键盘弹收 / 截屏，系统事件全走同一套 NotificationCenter 机制
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,   // 进入后台那一刻
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.backgroundCount += 1
            self.onEvent?("App 进入后台（第 \(self.backgroundCount) 次）")
        })
        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,  // 即将回前台
            object: nil, queue: .main
        ) { [weak self] _ in
            // 之前这里是 print：只进 Xcode 控制台，页面 UI 看不到——改走 onEvent 进页面日志
            self?.onEvent?("App 将回前台")
        })
    }

    deinit {
        // forEach + 函数引用：令牌数组逐个注销（removeObserver 恰好收一个参数，可整函数传入）
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

// ============ Demo 页 ============

// MARK: - Demo 页（NotificationDemoView）

struct NotificationDemoView: View {
    // @State 持有 class 实例：View 是 struct 重建无损（模块十二），manager 们在 App 生命周期内常驻
    @State private var badgeManager = BadgeManager()
    @State private var inboxManager = InboxManager()
    @State private var lifecycle = LifecycleMonitor()
    @State private var vipManager: VipManager? = VipManager()   // Optional：随时销毁，演示 deinit 注销
    @State private var loggingIn = false
    // 日志结构体：id 用 UUID 保证唯一——纯文本内容会重复（两次点「模拟登录」日志相同），
    // ForEach id: \.self 遇重复 ID 会报 occurs multiple times 并产生未定义行为
    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
    }
    @State private var logs: [LogLine] = [LogLine(text: "点「模拟登录」看一次广播三处响应")]

    var body: some View {
        List {
            Section("一对多：一次登录广播，三处同时响应") {
                Text("角标：\(badgeManager.badgeCount)")
                Text("VIP 权益：\(vipManager?.lastWelcome ?? "（订阅者已销毁）")")
                    .foregroundStyle(vipManager == nil ? .secondary : .primary)
                Text("收件箱：\(inboxManager.unreadCount) 条未读")
                Button {
                    loggingIn = true
                    log("→ LoginService.login() 发起（0.5s 模拟网络）")
                    Task {
                        await LoginService.shared.login()   // post 一声，广播全网
                        loggingIn = false
                        log("← 广播完毕：角标 / VIP / 收件箱 各自收到并更新")
                    }
                } label: {
                    HStack {
                        Text("模拟登录并广播")
                        if loggingIn { Spacer(); ProgressView() }
                    }
                }
            }

            Section("订阅者生命周期（EventBus 没有的责任）") {
                Text("VIP 订阅者状态：\(vipManager == nil ? "已销毁（注销，不再收通知）" : "存活中")")
                if vipManager != nil {
                    Button("销毁 VIP 订阅者（触发 deinit 注销）", role: .destructive) {
                        vipManager = nil   // 引用归零 → deinit 立即执行 → removeObserver
                        log("VipManager 已销毁，观察者已注销——再登录只有两处响应")
                    }
                } else {
                    Button("重建 VIP 订阅者") {
                        let m = VipManager()
                        bind(m)                       // 新实例要重绑刷新回调
                        vipManager = m
                        log("VipManager 已重建，重新订阅 userDidLogin")
                    }
                }
            }

            Section("系统通知也是同一套机制") {
                Text("进入后台次数：\(lifecycle.backgroundCount)")
                Text("真机/模拟器按 Home 或 Cmd+Shift+H 切后台，回来数字 +1")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("事件日志") {
                ForEach(logs) { line in
                    Text(line.text).font(.footnote.monospaced())
                }
            }
        }
        .navigationTitle("通知中心 Demo")
        .onAppear(perform: bindAll)
    }

    // 三个常驻 manager 只需绑一次；绑定内容 = 把 manager 的状态变化搬进 @State 世界来刷新 UI
    // MARK: 绑定回调（manager → 页面日志）

    private func bindAll() {
        bind(badgeManager)
        bind(inboxManager)
        if let m = vipManager { bind(m) }
        lifecycle.onEvent = { log("🔔 系统广播：\($0)") }
    }

    private func bind(_ m: VipManager) {
        m.onUpdate = { log("  VIP 权益收到广播：\(m.lastWelcome)") }
    }
    private func bind(_ m: BadgeManager) {
        m.onUpdate = { log("  角标收到广播：badgeCount = \(m.badgeCount)") }
    }
    private func bind(_ m: InboxManager) {
        m.onUpdate = { log("  收件箱收到广播：unread = \(m.unreadCount)") }
    }

    // MARK: 页面日志工具

    private func log(_ line: String) {
        logs.insert(LogLine(text: line), at: 0)
        print("\(line)")
        if logs.count > 15 { logs.removeLast(logs.count - 15) }   // 只留最近 15 条
    }
}
