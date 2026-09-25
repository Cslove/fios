import Foundation

// MARK: - 统一错误（模块十一第 3 节）

// 四类失败统一收编：调用侧 do-catch 只需分支一次，不用散落各处判断
// httpFailed 携带状态码——URLSession 不管 404/500，全靠这层自己查（模块十一第 1 节的坑）
public enum ApiError: Error {
    case invalidURL
    case invalidResponse
    case httpFailed(Int)                     // 非 2xx，携带状态码
    case decodingFailed                      // JSON → 模型解码失败
}

// MARK: - HTTP 方法（URLRequest 定制用）

// 小而全：get/post 已覆盖 Demo；真实项目可加 put/delete/patch
public enum HttpMethod: String {
    case get = "GET"
    case post = "POST"
}

// MARK: - 泛型请求封装（模块十一第 2/3 节合体）

// APIClient ≈ 前端 axios 实例：baseURL 一次配置，get/post 通吃所有模型
// 放在 Networking 包而不是 App 里：主 App / Widget / 测试都能 import 复用（模块十四第 4 节）
public struct APIClient {
    public let baseURL: String
    public let session: URLSession            // 注入而非写死 URLSession.shared：测试可换 mock session

    public init(baseURL: String = "https://jsonplaceholder.typicode.com",
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // GET：模块十一第 3 节的泛型 get——泛型由调用侧左侧类型注解确定
    public func get<T: Decodable>(_ path: String) async throws -> T {
        // URL 构造可能失败（路径含非法字符），模块四 guard let 收编成 ApiError
        guard let url = URL(string: baseURL + path) else {
            throw ApiError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        return try Self.validateAndDecode(data: data, response: response)
    }

    // POST：模块十一第 2 节的 URLRequest 定制——httpMethod/请求头/请求体三件套
    // ⚠️ httpMethod 默认 GET，忘写就是 GET；Content-Type 不写后端解析不了 body
    public func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw ApiError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = HttpMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)      // 模块十：模型 → JSON Data

        let (data, response) = try await session.data(for: request)   // data(for:) 吃 URLRequest
        return try Self.validateAndDecode(data: data, response: response)
    }

    // URL 查询参数拼装（模块十一第 2 节）：URLComponents 自动百分号编码，
    // 手动拼字符串中文/空格/& 全是坑；URL(string:) 直接构造会因非法字符返回 nil
    public static func url(base: String, path: String,
                           query: [URLQueryItem] = []) -> URL? {
        var comps = URLComponents(string: base + path)
        if !query.isEmpty { comps?.queryItems = query }
        return comps?.url
    }

    // 校验 + 解码共用收尾：状态码 2xx 才放行，再泛型解码
    // httpFailed 让 404/500 在这一层变成明确错误，而不是把错误页 JSON 硬解成模型
    static func validateAndDecode<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {   // 模块八 as? 向下转型
            throw ApiError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {     // 模块二区间
            throw ApiError.httpFailed(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)   // 模块十解码；T.self 元类型
        } catch {
            throw ApiError.decodingFailed
        }
    }
}
