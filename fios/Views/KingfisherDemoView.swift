import SwiftUI
import Kingfisher   // ← 模块十四第 5 节 SPM 六步链路的终点：
                    //   拉源码 → 解析锁版本 → 独立编译成 Kingfisher 模块 → 链接给 fios target
                    //   → 本文件 import 放行。⚠️ import 文件级：其他文件要用得各写各的

// Kingfisher 是干啥的：iOS 最主流的图片加载缓存库（业界标配，≈ 前端图片组件 +
// 图片缓存策略合体）——把「远程图 URL → 屏幕上的图」的脏活全包：下载/解码/占位/
// 渐显/失败兜底/内存+磁盘双缓存/列表防错位/内存警告清缓存。没有它这些全得手写。
// 本文件四个 Section 挨个摸一遍这些能力：① 占位→渐显→兜底三件套 ② 降采样省内存
// ③ 失败重试 ④ 查询/清除缓存——亲眼看「内存 → 磁盘 → 网络」三级缓存逐层命中

struct KingfisherDemoView: View {
    // picsum.photos：免费稳定图床（每个 id 固定一张图），教学网络图首选
    private func url(_ id: Int) -> URL {
        URL(string: "https://picsum.photos/id/\(id)/400/300")!
    }

    var body: some View {
        List {
            Section("① 基础加载：占位 → 渐显 → 失败兜底") {
                KFImage(url(237))                       // 远程图加载的 SwiftUI 形态
                    .placeholder {                      // 加载中转圈（≈ img 未加载完占位区）
                        ProgressView().frame(maxWidth: .infinity, minHeight: 150)
                    }
                    .fade(duration: 0.25)               // 加载完成 0.25s 渐显——网络图标配体验
                    .onFailureView {                              // 失败兜底：Kingfisher 8+ 的 SwiftUI API
                        Image(systemName: "photo.badge.exclamationmark")   // （闭包是 ViewBuilder，能放任意视图
                            .foregroundStyle(.red)                     //   旧版等价 API 是 onFailureImage(UIImage)，已弃用）
                    }
                    .onFailure { _ in print("加载失败：适合打日志/埋点") }   // onFailure 是纯回调（Void），
                    // 不能在里面返回视图——在这里写 Text(...) 会报「result unused」警告
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Section("② 处理器：大图降采样解码（列表省内存利器）") {
                KFImage(url(1084))
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 200, height: 150)))
                    // 400×300 原图按目标框解码位图——「解码即缩小」，而非解出大图再缩放；
                    // 列表几十张图时内存差距可达几十倍
                    .cacheOriginalImage()               // 原图也缓存：换尺寸时直接从缓存走，不再下载
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Section("③ 失败与重试（演示：不存在的图 id）") {
                KFImage(URL(string: "https://picsum.photos/id/99999999/400/300")!)   // 必失败
                    .retry(maxCount: 2, interval: .seconds(1))     // 失败自动重试 2 次、间隔 1 秒
                    .placeholder { ProgressView() }
                    .onFailureView { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.red) }
                    .onFailure { error in print("最终失败：\(error.localizedDescription)") }   // 错误信息看控制台
                    .frame(height: 60)
            }

            Section("④ 缓存验证：Kingfisher 的核心价值（看控制台）") {
                Button("查 237 号图的缓存状态") {
                    let type = ImageCache.default.imageCachedType(forKey: url(237).absoluteString)
                    print("缓存状态：\(type)")   // none=还没加载过｜memory=刚看过（内存缓存）
                                                   // disk=看过但内存已滚走——再加载秒出、不走网络
                }
                Button("清内存缓存") {
                    KingfisherManager.shared.cache.clearMemoryCache()   // 收到内存警告时的标准动作
                    print("内存缓存已清（磁盘还在，再加载走磁盘、不走网络）")
                }
                Button("清磁盘缓存") {
                    KingfisherManager.shared.cache.clearDiskCache {    // 异步清：磁盘 IO 不卡主线程
                        print("磁盘缓存已清——下次加载要重新下载")
                    }
                }
            }

            Section("说明") {
                Text("UIKit 里等价一行：imageView.kf.setImage(with: url)——给 UIImageView 加 .kf 前缀能力，就是模块八 Extension 的实战威力：库给系统类型扩展方法")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
