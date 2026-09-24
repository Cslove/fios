import SwiftUI

// 本文件把 9.现代Swift并发.md 的五大知识点串成一个可跑 demo：
// ① async/await 挂起  ② Task 从同步世界启动异步  ③ async let / TaskGroup 结构化并发
// ④ @MainActor 主线程守护  ⑤ actor 数据竞争编译期解药
// 运行时看控制台日志，观察「主线程 / 后台线程」切换与执行顺序。

struct ConcurrencyDemoView: View {
    @State private var userName = "未加载"
    @State private var parallelResult = ""
    @State private var groupResult = ""
    @State private var actorCount = 0
    @State private var mainActorLog = ""

    var body: some View {
        List {
            Section("① async/await：挂起而不是阻塞") {
                Text("当前用户：\(userName)")
                Button("模拟耗时加载") {
                    // Button 的 action 闭包在 iOS 26 SDK 标注了 @MainActor（View 的 body 也是），
                    // 从这里启动的 Task 继承主线程隔离，可直接改 @State；await 挂起期间不卡 UI
                    Task {
                        print("① Task 内线程：\(threadLabel())")   // 主线程
                        let name = await fetchUser()
                        userName = name
                    }
                }
            }

            Section("② Task：从同步世界启动异步") {
                Text("nonisolated 类里 Task { } 跑后台线程；MainActor 上下文启动的 Task 继承主线程。（本项目开了默认 MainActor 隔离，普通类须显式 nonisolated）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("普通类里 Task + MainActor.run") {
                    // 通过 nonisolated 类方法启动后台 Task，演示后台线程场景；
                    // 回调闭包跟随参数类型推断为 @MainActor，里面改 @State 是安全的
                    ProfileLoader().loadAsync { name in
                        userName = name
                    }
                }
                Button("Task { @MainActor in }") {
                    // 这里的 Task 已从 action（@MainActor）继承主线程，再标 @MainActor 属于冗余但明确；
                    // 在 nonisolated 上下文（比如下面的 ProfileLoader）想钉主线程就必须显式标
                    Task { @MainActor in
                        print("@MainActor Task 内线程：\(threadLabel())")
                        userName = "@MainActor 直接赋值"
                    }
                }
            }

            Section("③ 结构化并发：async let / TaskGroup") {
                Text("并行结果：\(parallelResult)")
                Button("async let 并发两个请求") {
                    Task {
                        async let a = fetchUser(id: 1)
                        async let b = fetchUser(id: 2)
                        let (first, second) = await (a, b)
                        parallelResult = "\(first) + \(second)"
                    }
                }

                Text("Group 结果：\(groupResult)")
                Button("TaskGroup 批量请求") {
                    Task {
                        groupResult = await loadMultiple()
                    }
                }
            }

            Section("④ @MainActor：UI 线程守护") {
                Text("日志：\(mainActorLog)")
                Button("@MainActor ViewModel 加载") {
                    Task {
                        let vm = ProfileViewModel()
                        await vm.load()
                        mainActorLog = "name=\(vm.name)，线程：\(threadLabel() == "主线程" ? "主" : "后")"
                    }
                }
                Button("后台干完活再切主线程") {
                    // 若用 Task { }：它从 action 继承 MainActor，await 恢复后已在主线程，
                    // 再写 MainActor.run 是多余的；
                    // Task.detached 不继承启动上下文：全程后台，摸 UI 前必须 MainActor.run 切回——
                    // 这才是 MainActor.run 真正必要的场景
                    Task.detached {
                        let thumbnail = await heavyWork()      // 后台干重活
                        await MainActor.run {
                            mainActorLog = "重活完成：\(thumbnail)，线程：\(threadLabel() == "主线程" ? "主" : "后")"   // 主
                        }
                    }
                }
            }

            Section("⑤ Actor：数据竞争编译期解药") {
                Text("计数：\(actorCount)")
                Button("多任务并发 +1（actor 保证安全）") {
                    Task {
                        let counter = Counter()
                        await withTaskGroup(of: Void.self) { group in
                            for _ in 1...10 {
                                group.addTask { await counter.increment() }
                            }
                        }
                        actorCount = await counter.snapshot()
                    }
                }
            }
        }
        .navigationTitle("并发 Demo")
    }
}

// MARK: - 线程标签辅助函数

// 非 actor 隔离的同步函数，专门用来在异步代码里判断当前线程
nonisolated func threadLabel() -> String {
    Thread.isMainThread ? "主线程" : "后台线程"
}

// MARK: - ① async/await 模拟网络请求

nonisolated func fetchUser(id: Int = 0) async -> String {
    // Task.sleep 模拟网络延迟，挂起不阻塞线程，期间当前线程可干别的；
    // 等价旧写法 Task.sleep(nanoseconds: 300_000_000)
    try? await Task.sleep(for: .seconds(0.3))
    return "User-\(id)"
}

// MARK: - ③ TaskGroup 批量请求

nonisolated func loadMultiple() async -> String {
    await withTaskGroup(of: String.self) { group in
        for i in 1...3 {
            group.addTask {
                await fetchUser(id: i)
            }
        }
        var results: [String] = []
        for await user in group {
            results.append(user)
        }
        return results.joined(separator: ", ")
    }
}

// MARK: - ② 普通类里启动后台 Task 的示例

// 非 MainActor 的普通类：本项目 Build Settings 开了 Default Actor Isolation = MainActor，
// 不显式标 nonisolated 的话整个类默认 @MainActor，Task 会跑主线程
nonisolated final class ProfileLoader {
    // 回调类型声明成 @MainActor @Sendable：@MainActor 保证调用时 hop 到主线程执行；
    // @Sendable 让闭包能被带进后台 Task（普通函数类型捕获进 @Sendable 闭包，
    // Swift 6 语言模式下会报 non-sendable 错误）
    func loadAsync(completion: @escaping @MainActor @Sendable (String) -> Void) {
        Task {
            print("普通类 Task 内线程：\(threadLabel())")   // 后台线程
            let name = await fetchUser()
            // ❌ 不带 await 直接 completion(name) 编译不过：从 nonisolated 上下文
            //    调 @MainActor 闭包是跨 actor 调用
            // 其实签名标了 @MainActor 后，直接 await completion(name) 也会自动 hop 主线程；
            // 这里保留 MainActor.run 是为了打印切换前后的线程对照
            await MainActor.run {
                print("MainActor.run 内线程：\(threadLabel())")   // 主线程
                completion(name)      // ✅ 回调类型已是 @MainActor，在主线程闭包里同步调用
            }
        }
    }
}

// MARK: - ④ @MainActor 示例

@MainActor
class ProfileViewModel {
    var name = "加载中"

    func load() async {
        name = "开始加载"
        let user = await fetchUser(id: 99)
        // await 挂起去后台请求，回来后编译器保证仍在主线程
        name = user
        print("ProfileViewModel.load 结束线程：\(threadLabel())")
    }
}

nonisolated func heavyWork() async -> String {
    // 模拟后台耗时计算（nonisolated async：函数体跑后台线程池）
    print("heavyWork：\(threadLabel())")
    try? await Task.sleep(for: .seconds(0.2))
    return "缩略图"
}

// MARK: - ⑤ Actor 示例

actor Counter {
    private var count = 0

    func increment() {
        count += 1
    }

    func snapshot() -> Int {
        count
    }
}
