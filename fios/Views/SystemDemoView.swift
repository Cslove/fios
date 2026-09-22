import SwiftUI

// system demo 集合页——ios/system 系列文档的测试代码入口，一篇文档一行 item，
// 点进去 push 对应 demo。以后每学一篇（s5 通知、s6 后台……）就在这加一行。
struct SystemDemoView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("s1. App 生命周期（scenePhase 三态实测）") {
                    ContentView()   // 原「生命周期」tab 的内容（s1 第 3 节测试代码）
                }
                NavigationLink("sw3. 导航与路由（path 数组即导航栈）") {
                    NavDemoView()   // 自带独立 NavigationStack（嵌套栈：内层自己的 push/pop 内层消化）
                }
                NavigationLink("s11. WebView Hybrid（双向通信 + 事件链）") {
                    WebHybridDemoView()   // 远程页导航事件链 + 内嵌测试页 JS 双向通信闭环
                }
                NavigationLink("sw7. 自定义与样式（Shape/ButtonStyle/Canvas…）") {
                    StylesDemoView()      // 五个子 demo：画形/按压/卡片样式/图表时钟/特效五件套
                }
                NavigationLink("sw8. 实战专题（表单/键盘/无限滚动）") {
                    PracticeDemoView()    // 三个子 demo：注册校验/焦点跳格/分页列表
                }
            }
            .navigationTitle("System Demo")
        }
    }
}
