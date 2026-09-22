import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {   // 三个 tab：商城 / 图片 / System Demo（system 系文档测试代码集合页）
                SystemDemoView().tabItem { Label("System", systemImage: "cube") }
                ShopView().tabItem { Label("商城", systemImage: "bag") }
                KingfisherDemoView().tabItem { Label("图片", systemImage: "photo") }
            }
        }
    }
}
