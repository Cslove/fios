import SwiftUI
import CoreLocation

// s3. 权限与隐私——定位权限全流程 demo。
// 前置：target → Info → Custom iOS Target Properties 已加
// Privacy - Location Always and When In Use Usage Description（否则直接崩溃，
// 这是权限体系的头号铁律：先声明后调用，漏声明的报错不是编译错误而是运行时致命）
// ⚠️ 配对坑（实测）：requestWhenInUseAuthorization() 查的是
// Privacy - Location When In Use Usage Description——只声明 Always key 时
// 请求静默失败、弹窗不出现、状态停在未决定，控制台报 missing required usage key

// MARK: - Demo 页

struct LocationDemoView: View {
    // CLLocationManager：系统定位服务入口（CoreLocation 框架的核心管理器，
    // 权限请求、经纬度获取都从它走）；不能用 @State 包——它是引用类型，
    // @State 面向值类型（模块五讲过），这里用普通 let 持有即可
    private let manager = CLLocationManager()
    @State private var logs: [LogLine] = []

    var body: some View {
        // MARK: 页面主体
        List {
            Section("操作") {
                Button("① 请求定位权限") { requestAuth() }
                Button("② 拿一次当前位置") { requestOneShotLocation() }
            }
            Section("权限状态") {
                Text(statusText())    // 随时可查：不弹窗，纯读取当前授权状态
            }
            Section("日志") {
                ForEach(logs) { log in Text(log.text).font(.footnote) }
            }
        }
        .navigationTitle("定位权限")
        .onAppear(perform: setup)
    }

    // MARK: 生命周期与回调接线

    // @State 持有的桥接对象：View 是 struct 随刷新重建，delegate 必须落在稳定的
    // 引用类型上（模块十 LifecycleMonitor 同款模式）——@State 初始化一次、跨刷新存活
    @State private var coordinator = LocationDelegate()

    private func setup() {
        // delegate 是「系统 → 我们」的回话通道（模块十讲过代理模式）：
        // 权限弹窗被用户点掉、定位成功/失败，结果都异步走 delegate 方法回来
        manager.delegate = coordinator
        // 反向接线：回调结果注回页面日志（闭包捕获的 @State 底层是引用盒子，跨刷新有效）
        coordinator.onLog = { log($0) }
    }

    private func requestAuth() {
        // iOS 14+ 的标准两问式：先问「使用期间」（弹窗），状态里含「始终」档位
        manager.requestWhenInUseAuthorization()
        log("已发起权限请求——看模拟器弹窗；结果会异步回来（下方状态区刷新）")
    }

    private func requestOneShotLocation() {
        // 只想要一次位置：requestLocation() 走「成功 or 失败一次回调」；
        // 连续追踪才用 startUpdatingLocation()（s6 后台机制详讲，会显著耗电）
        manager.requestLocation()
        log("已请求一次定位——未授权/模拟器无位置数据时走失败分支")
    }

    private func statusText() -> String {
        // authorizationStatus：.notDetermined（还没问过）/.denied（拒绝）/
        // .restricted（家长控制等系统限制）/.authorizedWhenInUse/.authorizedAlways
        switch manager.authorizationStatus {
        case .notDetermined: return "未决定（还没弹过窗）"
        case .denied: return "已被拒绝（去 设置 → 隐私 → 定位服务 开）"
        case .restricted: return "受限（系统级限制）"
        case .authorizedAlways: return "始终允许"
        case .authorizedWhenInUse: return "使用期间允许"
        @unknown default: return "未知状态"
        }
    }

    private func log(_ text: String) {
        logs.append(LogLine(text: text))    // 同模块十：UUID 作 ID，避免 ForEach 重复 ID 警告
    }
}

// MARK: - 桥接对象：CLLocationManagerDelegate → SwiftUI

// CLLocationManagerDelegate：定位系统的回调协议；NSObject 是接 ObjC delegate 的
// 必经基类（Xcode 27 新工程默认全模块 MainActor 隔离，CLLocationManager 在主线程
// 创建时回调也回主线程，隔离天然对齐）
final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLog: ((String) -> Void)?    // 反向注回页面的日志闭包（View 在 onAppear 里接上）

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 权限状态一变就回调：弹窗被点掉、设置里改权限，都会走这
        onLog?("权限状态变化 → \(describe(manager.authorizationStatus))")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // requestLocation()/startUpdatingLocation() 成功：locations 数组一般取 last
        guard let loc = locations.last else { return }
        onLog?("定位成功：纬度 \(loc.coordinate.latitude)，经度 \(loc.coordinate.longitude)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 模拟器默认无定位数据（Features → Location 可改模拟位置），常见走这
        onLog?("定位失败：\(error.localizedDescription)")
    }

    private func describe(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "未决定"
        case .denied: return "拒绝"
        case .restricted: return "受限"
        case .authorizedAlways: return "始终允许"
        case .authorizedWhenInUse: return "使用期间允许"
        @unknown default: return "未知"
        }
    }
}

// MARK: - 日志行模型

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
}
