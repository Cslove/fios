import SwiftUI
import Networking

// 模块十四第 2/3 节演示：跨三个文件协作（Models/Product + Services/CartService + 本视图），
// 全程没有一行 fios 内部 import——它们同属 fios 这一个模块（编译 target）
struct ShopView: View {
    @State private var cart = CartService()   // @Observable 实例用 @State 持有（模块十二）
    private let products = [
        Product(id: 1, name: "机械键盘", price: 399),
        Product(id: 2, name: "蓝牙耳机", price: 899),
        Product(id: 3, name: "显示器支架", price: 199),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(products) { product in       // Product: Identifiable → 不用写 id: \.self
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                            Text(API.format(product.price))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("加购") { cart.add(product) }
                    }
                }
                Divider()
                Text("购物车 \(cart.items.count) 件 · 小计 ¥\(cart.subtotal, specifier: "%.0f")")
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.bar)
            }
            .navigationTitle("商城（跨文件协作）")
        }
    }
}
