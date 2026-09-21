import Foundation
import Observation

// 模块十四第 3 节演示：同模块（同 target）文件天然互通——
// ⚠️ 本文件没有任何「import Product」之类的写法（也不存在这个语法），
//    下面直接使用 Models/Product.swift 里的 Product，编译直接过
@Observable
final class CartService {
    private(set) var items: [Product] = []   // private(set)：外部只读，修改只走 add —— 访问控制管「可见面」

    func add(_ product: Product) {
        items.append(product)
    }

    var subtotal: Double {                   // reduce 求和（模块三）
        items.reduce(0) { $0 + $1.price }
    }
}
