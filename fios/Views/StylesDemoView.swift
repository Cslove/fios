import SwiftUI

// sw7. 自定义与样式系统 的实操集合——五个子 demo 对应文档五节：
// 1 Shape（聊天气泡 + 进度环）/ 2 ButtonStyle / 3 ViewModifier 卡片样式 /
// 4 Canvas + TimelineView 图表时钟 / 5 视觉特效五件套

// MARK: - 1. Shape：Path 画笔 + trim 进度环

// 聊天气泡的「小尾巴」——系统 RoundedRectangle 画不出来的形状，用 Path 命令式画
struct ChatBubble: Shape {
    var cornerRadius: CGFloat = 12
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height),  // 主体：圆角矩形
                          cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        p.move(to: CGPoint(x: 14, y: rect.maxY - 0.5))   // 提笔到左下角
        p.addLine(to: CGPoint(x: 4, y: rect.maxY + 8))   // 往左下斜出——小尾巴的尖
        p.addLine(to: CGPoint(x: 24, y: rect.maxY - 0.5))// 收回来——三角凸起
        p.closeSubpath()
        return p
    }
}

struct ShapeDemoView: View {
    @State private var progress = 0.35
    var body: some View {
        VStack(spacing: 32) {
            // 气泡：fill 填充色，文字叠在上面（overlay 默认居中）
            ChatBubble()
                .fill(.blue.opacity(0.8))
                .frame(width: 200, height: 60)
                .overlay {
                    Text("自定义形状!").font(.subheadline).foregroundStyle(.white)
                }

            // 进度环：trim 截取圆弧 + 旋转到 12 点起点
            ZStack {
                Circle().stroke(.gray.opacity(0.25), lineWidth: 10)   // 轨道
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: progress)              // progress 变化平滑过渡
                Text("\(Int(progress * 100))%").font(.headline).monospacedDigit()
            }
            .frame(width: 120, height: 120)

            Button("加载更多") { progress = min(progress + 0.2, 1) }
                .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("1. Shape 画形")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 2. ButtonStyle：按压行为

// 通用按压反馈：按下缩小变暗、松手弹回
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label                     // label = 按钮原有内容
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// 组件库风格：颜色/圆角从外面注入
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .orange
    var cornerRadius: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color, in: .rect(cornerRadius: cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

struct ButtonStyleDemoView: View {
    @State private var count = 0
    var body: some View {
        VStack(spacing: 20) {
            Button("加购（\(count)）") { count += 1 }
                .buttonStyle(PrimaryButtonStyle())
            Button("自定义颜色") { }
                .buttonStyle(PrimaryButtonStyle(color: .teal))
                .padding(.horizontal)
            Button("系统样式 .bordered") { }
                .buttonStyle(.bordered)
            Button("按下试试缩放") { }
                .buttonStyle(ScaleButtonStyle())
                .buttonBorderShape(.capsule)
        }
        .padding()
        .navigationTitle("2. ButtonStyle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 3. ViewModifier：封装可复用样式

// 全 App 卡片样式：白底/圆角/阴影一次封装
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background, in: .rect(cornerRadius: 16))
            .clipShape(.rect(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

// 配套扩展：变成顺手的 .cardStyle()（和系统 API 一个手感）
extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct CardStyleDemoView: View {
    struct Order: Identifiable { let id = UUID(); var title: String; var price: Double }
    let orders = [Order(title: "拿铁", price: 28), Order(title: "可颂", price: 15)]
    var body: some View {
        VStack(spacing: 12) {
            ForEach(orders) { order in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(order.title).font(.headline)
                        Text("¥\(order.price, specifier: "%.1f")")   // specifier：printf 式格式化
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("详情").foregroundStyle(.orange)
                }
                .cardStyle()
            }
            Text("这行没挂 cardStyle（对照组）")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("3. ViewModifier")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 4. Canvas + TimelineView：像素级画布 + 时间驱动

// Canvas：逐元素绘制柱状图（≈ <canvas> 2D 上下文）
struct BarChart: View {
    let data: [Double]
    var body: some View {
        Canvas { context, size in
            let barWidth = size.width / CGFloat(data.count) * 0.6
            for (i, value) in data.enumerated() {
                let h = CGFloat(value) * size.height
                let x = CGFloat(i) * (size.width / CGFloat(data.count)) + barWidth * 0.25
                let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 4),
                    with: .color(.orange.opacity(0.85)))
                context.draw(
                    Text("\(Int(value * 100))").font(.caption2),
                    at: CGPoint(x: rect.midX, y: rect.minY - 8))
            }
        }
        .frame(height: 160)
        .padding(.horizontal)
    }
}

struct CanvasClockDemoView: View {
    var body: some View {
        // TimelineView：每秒重建一次内容——和 Canvas 组合就是轻量动画引擎
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let seconds = Calendar.current.component(.second, from: timeline.date)
            VStack(spacing: 20) {
                Text("秒：\(seconds)")
                    .font(.system(size: 48, weight: .bold).monospacedDigit())
                BarChart(data: [0.3, 0.7, Double(seconds) / 60, 0.5])  // 第三根柱每秒长一点
                    .animation(.smooth, value: seconds)
                Text("第三根柱 = 当前秒数/60（Canvas 重绘，不是动画插值）")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("4. Canvas + TimelineView")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 5. 视觉特效五件套

struct EffectsDemoView: View {
    var body: some View {
        VStack(spacing: 24) {
            // ① 渐变文字
            Text("渐变标题")
                .font(.largeTitle.bold())
                .foregroundStyle(LinearGradient(colors: [.orange, .pink],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))

            // ② mask：形状当镂空模板
            Image(systemName: "camera.fill").font(.system(size: 60))
                .mask(Circle())

            // ③ Material 毛玻璃
            Rectangle().fill(.orange.gradient)
                .frame(width: 220, height: 90)
                .overlay {
                    Capsule().fill(.ultraThinMaterial)
                        .frame(width: 160, height: 40)
                        .overlay(Text("毛玻璃").font(.headline))
                }

            // ④ drawingGroup：多层视图合成一张位图上屏（动画掉帧时的救命开关）
            HStack {
                ForEach(0..<8, id: \.self) { i in
                    Circle().fill(.teal.gradient).frame(width: 14)
                        .offset(y: CGFloat(i % 2 * 10))
                }
            }
            .drawingGroup()

            // ⑤ contentShape：扩大点击热区（透明 padding 区域也可点）
            Text("点我（热区 = 整个浅色矩形，含透明边距）")
                .padding(20).background(.orange.opacity(0.15))
                .contentShape(.rect)
                .onTapGesture { print("hit!") }
        }
        .padding()
        .navigationTitle("5. 特效五件套")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 入口（外层 SystemDemoView 已有 NavigationStack，这里不另包——避免嵌套栈回退坑）

struct StylesDemoView: View {
    var body: some View {
        List {
            NavigationLink("1. Shape：聊天气泡 + 进度环（Path 画笔 / trim 截弧）") { ShapeDemoView() }
            NavigationLink("2. ButtonStyle：按压缩放（isPressed 按压状态）") { ButtonStyleDemoView() }
            NavigationLink("3. ViewModifier：卡片样式复用（.cardStyle()）") { CardStyleDemoView() }
            NavigationLink("4. Canvas + TimelineView：图表与时钟（每秒重绘）") { CanvasClockDemoView() }
            NavigationLink("5. 视觉特效五件套（渐变/mask/毛玻璃/合成/热区）") { EffectsDemoView() }
            Section {
                Text("对应文档：ios/sw/sw7.自定义与样式系统.md——每个子页代码即文档示例的完整可跑版")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("自定义与样式（sw7）")
        .navigationBarTitleDisplayMode(.inline)
    }
}
