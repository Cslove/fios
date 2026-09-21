import Foundation   // Foundation 是「另一个模块」（系统库）——照样要 import，且是文件级的

// 模块十四第 2/3 节演示：目录只是视觉分组；internal 是默认访问级别，fios target 内全可见
struct Product: Identifiable, Hashable {
    let id: Int
    let name: String
    let price: Double
}
