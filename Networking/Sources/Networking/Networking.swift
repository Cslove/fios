public enum API {
    public static func format(_ price: Double) -> String { "¥\(Int(price))" }
}
struct Reachability {}   // 故意 internal：留着下一步测模块边界
