import SwiftUI

// sw3.导航与路由 全示例合集——对照 ios/sw/sw3.导航与路由.md 边玩边读：
// ①值导航 ②path 编程式操纵 ③deep link（配 scheme 后）⑥sheet 分工
// （④TabView 就是本 App 的 tab 结构本身——切 tab 验证状态互不干扰；
//   ⑤@SceneStorage 状态恢复见 sw3 第 5 节，需序列化 path，此处不展开）
struct NavDemoView: View {
    @State private var path: [Product] = []      // 第 2 节：栈的本体就是这个数组（界面只是它的投影）
    @State private var showingEditor = false     // 第 6 节：sheet 模态的开关（@State 布尔）

    var body: some View {
        NavigationStack(path: $path) {           // 绑定给栈：数组变→界面变；界面返回→数组也变
            List {
                Section("① 值导航：NavigationLink(value:) + 类型路由表") {
                    ForEach(NavDemoData.products) { product in
                        NavigationLink(value: product) {       // 点行 = 往栈里 push 这个 Product 值
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.name)
                                Text("¥\(product.price, specifier: "%.0f")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("② 编程式导航：直接操纵 path 数组") {
                    Button("压三层：直达商品 3") {
                        path = [NavDemoData.products[0],
                                NavDemoData.products[1],
                                NavDemoData.products[2]]       // 一次性压三层（sw3 第 2 节）
                    }
                    Button("pop 返回一层") {
                        guard !path.isEmpty else { return }    // 空数组 removeLast 会崩——数组操作直接暴露
                        path.removeLast()
                    }
                    Button("回根（弹回首页）") { path.removeAll() }
                    Text("当前栈深：\(path.count) 层")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("⑥ sheet 模态：办一件事就回来") {
                    Button("弹出编辑页（半屏 sheet）") { showingEditor = true }
                }
            }
            .navigationDestination(for: Product.self) { product in   // 类型路由表：Product → 详情页
                ProductDetailNav(product: product, path: $path)      // （挂在 List 内容上，别挂到行上——sw3 坑 1）
            }
            .navigationTitle("导航 demo（sw3）")
            .onOpenURL { url in                  // ③ deep link 三步：URL → 解析 → 改 path
                // 前置：target → Info → URL Types 加 scheme（如 fiosdemo），然后模拟器跑：
                //   xcrun simctl openurl booted "fiosdemo://product/7"
                if url.host == "product", let id = Int(url.lastPathComponent) {
                    path.append(Product(id: id, name: "Deep Link 商品 #\(id)", price: 0))
                }
            }
            .sheet(isPresented: $showingEditor) {    // 模态 ≈ Drawer/Modal（sw3 第 6 节的分工口诀）
                Text("编辑页（sheet 模态）")
                    .font(.title2)
                    .presentationDetents([.medium])   // 半屏——现代 iOS 模态标配
            }
        }
    }
}

// 详情页：展示当前商品 + 「下一个」手动 push（sw3 练习 1）+ 栈内容实时可视
struct ProductDetailNav: View {
    let product: Product
    @Binding var path: [Product]                 // 拿到栈的读写通道：详情页里也能操纵导航

    var body: some View {
        VStack(spacing: 20) {
            Text(product.name).font(.largeTitle)
            Text("¥\(product.price, specifier: "%.0f")").foregroundStyle(.secondary)

            Button("push 下一个（path.append）") {
                if let next = NavDemoData.products.randomElement() {
                    path.append(next)             // 和点 NavigationLink 等价：都是往数组加元素
                }
            }
            .buttonStyle(.borderedProminent)

            Text("栈内路径：\(path.map(\.name).joined(separator: " → "))")
                .font(.footnote).foregroundStyle(.secondary)
                // path.map(\.name)——模块七第 4 节 KeyPath 实战：传「name 的路径」当取值器
        }
        .navigationTitle("详情 #\(product.id)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum NavDemoData {                               // enum 当命名空间装静态数据（模块十一讲过此模式）
    static let products = [
        Product(id: 1, name: "机械键盘", price: 399),
        Product(id: 2, name: "蓝牙耳机", price: 899),
        Product(id: 3, name: "显示器支架", price: 199),
    ]
}
