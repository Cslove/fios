import SwiftUI
import Playgrounds

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase   // 前后台状态的订阅入口（系统自动注入当前状态）

    var body: some View {
        VStack(spacing: 20) {
                    Text("Hello iOS")
                        .font(.largeTitle)

                    Button("点我") {
                        print("按钮被点击了")
                    }
                    .buttonStyle(.borderedProminent)

                    // 界面直接显示当前状态——不用盯控制台也能看三态切换
                    Text("当前状态：\(String(describing: scenePhase))")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: scenePhase) { old, new in
                    switch new {
                    case .active:     print("active：用户正在用")
                    case .inactive:   print("inactive：前台但被打断——下拉通知栏/多任务界面就是这态")
                    case .background: print("background：即将退后台，只剩几秒能干活！")
                    @unknown default: break   // 苹果预留：未来加新状态不崩
                    }
                }
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
