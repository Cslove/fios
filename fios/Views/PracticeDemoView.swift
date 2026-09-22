import SwiftUI

// sw8. 实战专题 的实操集合——三个子 demo 对应文档三节：
// 1 注册表单（模型收拢校验/canSubmit 聚合）/ 2 键盘焦点流（@FocusState 跳格+避让）/
// 3 无限滚动（isLoading+hasMore 双保险分页）
// 文档代码即完整可跑版，此处照搬 + 一处补完：数字键盘工具条跳格（文档说「要自己加」的真场景）

// MARK: - 1. 注册表单（模型层收拢校验，视图零业务）

@Observable
class RegisterForm {
    var username = ""                // 4~12 位字母数字
    var password = ""                // 至少 8 位
    var confirm = ""                 // 必须与 password 一致
    var phone = ""                   // 11 位手机号
    var agreed = false               // 协议勾选

    // 每个字段一个校验函数：返回 nil = 通过，返回 String = 错误文案
    //（「Optional 当错误通道」：sw8 文档第 1 节的核心手法）
    func usernameError() -> String? {
        if username.isEmpty { return nil }                       // 空着先不报——没开始填就弹红字是坏体验
        return username.count < 4 ? "用户名至少 4 位" : nil
    }
    func passwordError() -> String? {
        password.count < 8 ? "密码至少 8 位" : nil
    }
    func confirmError() -> String? {
        (confirm != password) ? "两次密码不一致" : nil
    }
    func phoneError() -> String? {
        if phone.isEmpty { return nil }
        // range(of:options:.regularExpression)：字符串自带正则整串匹配
        return phone.range(of: #"^1\d{10}$"#, options: .regularExpression) == nil
            ? "手机号格式不对" : nil
    }

    // 聚合校验：全过 + 勾了协议才能提交（计算属性——任何字段变化自动重算，按钮状态跟着变）
    var canSubmit: Bool {
        username.count >= 4 && password.count >= 8
        && confirm == password && phone.range(of: #"^1\d{10}$"#, options: .regularExpression) != nil
        && agreed
    }
}

// 单字段视图：label + 输入框 + 错误行，一个组件四处复用
struct FormField: View {
    let title: String
    @Binding var text: String
    var error: String?               // 当前错误（nil 不显示）
    var secure = false               // 密码框走 secure
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Group {                  // Group：批量套修饰符的容器（不产生额外布局层级）
                if secure { SecureField("请输入\(title)", text: $text) }
                else { TextField("请输入\(title)", text: $text) }
            }
            .textFieldStyle(.roundedBorder)
            if let error {           // 错误行：有错才出现（高度跳动被下面 animation 抚平）
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .transition(.opacity)                 // 出现/消失淡入淡出（sw2 transition）
            }
        }
        .animation(.smooth, value: error)
    }
}

struct RegisterView: View {
    @State private var form = RegisterForm()
    @State private var submitted = false

    var body: some View {
        Form {                       // Form：系统表单容器——自动分组样式/键盘避让/滚动
            Section("账号信息") {
                FormField(title: "用户名", text: $form.username, error: form.usernameError())
                FormField(title: "密码", text: $form.password, error: form.passwordError(), secure: true)
                FormField(title: "确认密码", text: $form.confirm, error: form.confirmError(), secure: true)
                FormField(title: "手机号", text: $form.phone, error: form.phoneError())
            }
            Section {
                Toggle(isOn: $form.agreed) {
                    Text("已阅读并同意《用户协议》")
                }
            }
            Section {
                Button("注册") { submitted = true }
                    .disabled(!form.canSubmit)             // disabled：不可用时系统自动置灰+禁点
                if submitted {
                    Label("注册成功（此处接真实提交请求）", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } footer: {
                Text("按钮亮起条件：4 项校验全过 + 勾选协议——试着只填一半看按钮状态")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("注册")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 2. 键盘焦点流（回车跳格 + 数字键盘工具条补完）

struct KeyboardFlowDemo: View {
    @State private var username = ""
    @State private var phone = ""
    @State private var address = ""

    // @FocusState：受控焦点——「哪个字段被聚焦」是框架状态，改值就能移焦点（≈ ref.focus() 但无 DOM）
    enum Field { case username, phone, address }      // 小 enum 当焦点的「名字」
    @FocusState var focused: Field?

    var body: some View {
        Form {
            TextField("用户名", text: $username)
                .focused($focused, equals: .username)  // 绑定：这框聚焦时 focused == .username
                .submitLabel(.next)                    // 键盘回车键显示「下一项」
                .onSubmit { focused = .phone }         // 按回车 → 焦点状态改到 phone → 自动跳格
            TextField("手机号", text: $phone)
                .focused($focused, equals: .phone)
                .keyboardType(.numberPad)              // 数字键盘
                // ⚠️ numberPad 没有回车键——submitLabel/onSubmit 对它无效，
                // 「下一格」要自己加工具条（下面 toolbar 就是补完这一幕）：
            TextField("地址", text: $address)
                .focused($focused, equals: .address)
                .submitLabel(.done)
                .onSubmit { focused = nil }            // nil = 收起键盘
            Button("提交") { print(username, phone, address) }
        }
        // 数字键盘的「下一格」补完：placement: .keyboard = 键盘上方工具条，
        // 只有 numberPad 聚焦时才有意义——这里简化为常驻（真实项目可按 focused == .phone 显隐）
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(focused == .phone ? "下一格" : "收起键盘") {
                    if focused == .phone { focused = .address }   // 数字键盘跳格的正解在这
                    else { focused = nil }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .scrollDismissesKeyboard(.interactively)       // 滚动时跟手收起键盘
        .navigationTitle("键盘体验")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 3. 无限滚动（分页 + 防重入 + 到底止损）

struct FeedItem: Identifiable { let id = UUID(); var title: String }

@Observable
class FeedModel {
    var items: [FeedItem] = []
    var isLoading = false            // 防重入锁：请求进行中不再触发下一次
    var hasMore = true               // 到底标记：没有下一页就停

    init() { loadMore() }            // 首屏先拉第一页

    func loadMore() {
        guard !isLoading, hasMore else { return }     // 双保险：正在加载/已到底直接返回
        isLoading = true
        Task {                                        // Task：起异步任务（结构化并发）
            try? await Task.sleep(for: .seconds(1))   // 模拟网络延迟——1 秒后交付下一页
            let page = (0..<20).map { FeedItem(title: "第 \(items.count + $0 + 1) 条内容") }
            items += page                             // 追加（不是替换）——append 语义即分页
            isLoading = false
            if items.count >= 100 { hasMore = false } // 演示 5 页后到底（真实项目由接口决定）
        }
    }

    func refresh() async {           // 下拉刷新：清空重拉第一页
        items = []
        hasMore = true
        loadMore()
    }
}

struct InfiniteFeedView: View {
    @State private var model = FeedModel()

    var body: some View {
        List {
            ForEach(model.items) { item in
                Text(item.title)
                    // 无限滚动触发器：最后一行出现时加载下一页
                    .onAppear {
                        if item.id == model.items.last?.id {
                            model.loadMore()
                        }
                    }
            }
            // 底部状态行：三态三张脸（加载中转圈 / 到底提示 / 平时没有）
            if model.isLoading {
                HStack(spacing: 8) {
                    ProgressView()                     // 系统菊花加载指示器
                    Text("加载中…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if !model.hasMore {
                Text("— 到底啦 —")
                    .font(.footnote).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .refreshable { await model.refresh() }        // 下拉刷新：系统手势 + 顶部菊花
        .navigationTitle("无限滚动")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 入口（外层 SystemDemoView 已有 NavigationStack，子页直接 push——不另包避免嵌套栈坑）

struct PracticeDemoView: View {
    var body: some View {
        List {
            NavigationLink("1. 注册表单（校验聚合 + 即时反馈）") { RegisterView() }
            NavigationLink("2. 键盘焦点流（回车跳格 + 工具条 + 避让）") { KeyboardFlowDemo() }
            NavigationLink("3. 无限滚动（分页 + 防重入 + 下拉刷新）") { InfiniteFeedView() }
            Section {
                Text("对应文档：ios/sw/sw8.实战专题.md——验证顺序：注册页只填一半看按钮置灰 → 键盘页试「下一项」跳格（数字键盘用工具条） → 信息流快速滚到底看 isLoading 期间只有一朵菊花")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("实战专题（sw8）")
        .navigationBarTitleDisplayMode(.inline)
    }
}
