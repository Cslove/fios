import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {   // 三个 demo 并存：商城 + 生命周期 + Kingfisher（模块十四 SPM 实物）
                ShopView().tabItem { Label("商城", systemImage: "bag") }
                ContentView().tabItem { Label("生命周期", systemImage: "clock") }
                KingfisherDemoView().tabItem { Label("图片", systemImage: "photo") }
            }
        }
    }
}
